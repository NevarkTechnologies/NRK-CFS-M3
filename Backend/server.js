const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const crypto = require('crypto');
const helmet = require('helmet');
const { rateLimit, ipKeyGenerator } = require('express-rate-limit');
const { RedisStore } = require('rate-limit-redis');
const Redis = require('ioredis');
const Razorpay = require('razorpay');
const admin = require('firebase-admin');
require('dotenv').config();

const Cafe = require('./models/cafe');
const MenuItem = require('./models/menuitems');
const Order = require('./models/order');
const User = require('./models/user');
const Notification = require('./models/notification');
const CafeCounter = require('./models/cafeCounter');
const PaymentSession = require('./models/paymentSession');
const AuditLog = require('./models/auditLog');
// CODEX EDITS: Durable webhook receipts and notification outbox are shared by
// every PM2 worker through MongoDB.
const PaymentWebhookEvent = require('./models/paymentWebhookEvent');
const NotificationOutbox = require('./models/notificationOutbox');

const app = express();
// Trust the first proxy hop (AWS ALB / nginx) so express-rate-limit reads the real
// client IP from X-Forwarded-For instead of the proxy's internal address.
app.set('trust proxy', 1);
const allowedStatuses = ['Pending', 'Preparing', 'Ready', 'Completed', 'Rejected'];
let razorpayClient;
// CODEX EDITS: Processing leases allow another worker to safely resume work
// after a crash without deleting the payment cart.
const PAYMENT_PROCESSING_LEASE_MS = 30 * 1000;
const WEBHOOK_PROCESSING_LEASE_MS = 60 * 1000;
const OUTBOX_PROCESSING_LEASE_MS = 60 * 1000;
const PAYMENT_SESSION_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;
let notificationOutboxTimer;

const redisClient = new Redis(process.env.REDIS_URL || 'redis://127.0.0.1:6379');
redisClient.on('error', (err) => console.warn('Redis error:', err.message));
let firebaseInitialized = false;

// ── Security middleware ───────────────────────────────────────────────────────
app.use(helmet());

// CORS: require explicit CLIENT_ORIGIN — never default to wildcard in prod.
const allowedOrigins = (process.env.CLIENT_ORIGIN || '')
  .split(',')
  .map(o => o.trim())
  .filter(Boolean);

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, Postman in dev)
    if (!origin) return callback(null, true);
    if (allowedOrigins.length === 0 && process.env.NODE_ENV !== 'production') {
      // Dev-only fallback: allow all origins only when explicitly not in production
      return callback(null, true);
    }
    if (allowedOrigins.includes(origin)) return callback(null, true);
    callback(new Error(`CORS: origin ${origin} not allowed`));
  },
  credentials: true,
}));

app.use(express.json({
  limit: '5mb',
  // Keep the raw request bytes — Razorpay webhook signatures are computed over
  // the exact body, so verification must not use the re-serialized JSON.
  verify: (req, res, buf) => { req.rawBody = buf; },
}));

// express-mongo-sanitize is incompatible with Express 5 (req.query is read-only).
// Inline sanitizer: strips keys starting with $ or containing . from body and query.
function stripMongo(obj) {
  if (!obj || typeof obj !== 'object') return;
  for (const key of Object.keys(obj)) {
    if (key.startsWith('$') || key.includes('.')) {
      delete obj[key];
    } else {
      stripMongo(obj[key]);
    }
  }
}
app.use((req, res, next) => {
  stripMongo(req.body);
  // req.query is read-only in Express 5 — sanitize values in-place without reassigning
  if (req.query && typeof req.query === 'object') {
    for (const key of Object.keys(req.query)) {
      if (key.startsWith('$') || key.includes('.')) {
        delete req.query[key];
      }
    }
  }
  next();
});

// ── Rate limiting ─────────────────────────────────────────────────────────────
// Each limiter gets its own Redis store with a distinct prefix so their counters
// never collide. All workers share the same Redis counter — limits are global.
const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 min
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Too many requests, please try again later.' },
  store: new RedisStore({ sendCommand: (...args) => redisClient.call(...args), prefix: 'rl:general:' }),
  // CODEX EDITS: Razorpay deliveries use a dedicated, higher-capacity limiter;
  // sharing the public API bucket could reject valid captures during bursts.
  skip: req => req.path === '/razorpay/webhook',
});

// Strict limit for order writes (place/confirm/status) — 10 per minute
const orderLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  message: { message: 'Too many order requests, please slow down.' },
  store: new RedisStore({ sendCommand: (...args) => redisClient.call(...args), prefix: 'rl:order:' }),
  // CODEX EDITS: Reconciliation has its own authenticated read-style limiter.
  skip: req => req.path === '/reconcile',
});
// Generous limit for order reads — per Firebase UID so accounts don't share a bucket
const orderReadLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 120,
  keyGenerator: (req) => req.firebaseUser?.uid || ipKeyGenerator(req),
  message: { message: 'Too many requests, please slow down.' },
  store: new RedisStore({ sendCommand: (...args) => redisClient.call(...args), prefix: 'rl:orderread:' }),
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  message: { message: 'Too many auth requests, please try again later.' },
  store: new RedisStore({ sendCommand: (...args) => redisClient.call(...args), prefix: 'rl:auth:' }),
});

// CODEX EDITS: Supports bounded foreground polling without weakening write
// limits on payment initiation or order confirmation.
const paymentReconcileLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60,
  keyGenerator: req => req.firebaseUser?.uid || ipKeyGenerator(req),
  message: { message: 'Too many payment status checks, please slow down.' },
  store: new RedisStore({ sendCommand: (...args) => redisClient.call(...args), prefix: 'rl:reconcile:' }),
});

// CODEX EDITS: Dedicated webhook limiter protects the public signed endpoint
// without coupling all merchants to Razorpay's shared source IP bucket.
const webhookLimiter = rateLimit({
  windowMs: 5 * 60 * 1000,
  max: 2000,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Too many webhook requests.' },
  store: new RedisStore({ sendCommand: (...args) => redisClient.call(...args), prefix: 'rl:webhook:' }),
});

app.use('/api/', generalLimiter);
app.use('/api/payment', orderLimiter);
app.use('/api/auth', authLimiter);

// ── Helpers ───────────────────────────────────────────────────────────────────
function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

// CODEX EDITS: Structured, correlation-friendly payment logs intentionally omit
// signatures, UPI IDs, tokens, and other secrets/PII.
function paymentLog(event, fields = {}, level = 'info') {
  const safeFields = Object.fromEntries(
    Object.entries(fields).filter(([, value]) => value !== undefined && value !== null && value !== '')
  );
  const record = JSON.stringify({
    timestamp: new Date().toISOString(),
    service: 'nevark-food-backend',
    workerId: process.env.NODE_APP_INSTANCE || '0',
    event,
    ...safeFields,
  });
  (console[level] || console.log)(record);
}

// CODEX EDITS: Bound persisted/logged error text so external SDK responses
// cannot inflate Mongo documents or logs.
function safeErrorMessage(error) {
  return String(error?.message || error || 'Unknown error').slice(0, 500);
}

function makeOrderId() {
  return `NRK${Date.now()}${Math.floor(Math.random() * 900 + 100)}`;
}

function toMoney(value) {
  return Math.round(Number(value || 0) * 100) / 100;
}

async function generateTokenNumber(cafeId, mongoSession = null) {
  const ist = new Date(Date.now() + 330 * 60 * 1000);
  const today = ist.toISOString().slice(0, 10);
  const key = `${cafeId}:${today}`;
  const options = { returnDocument: 'after', upsert: true };
  // CODEX EDITS: Participate in the order transaction when MongoDB supports it.
  if (mongoSession) options.session = mongoSession;
  const doc = await CafeCounter.findOneAndUpdate(
    { key },
    { $inc: { seq: 1 } },
    options
  );
  return String(doc.seq).padStart(4, '0');
}

function audit(action, actorId, targetType, targetId, meta = {}) {
  AuditLog.create({ action, actorId, targetType, targetId, meta }).catch(() => {});
}

function toPaise(value) {
  return Math.round(toMoney(value) * 100);
}

function getRazorpayClient() {
  if (razorpayClient) return razorpayClient;
  const keyId = process.env.RAZORPAY_KEY_ID;
  const keySecret = process.env.RAZORPAY_KEY_SECRET;
  if (!keyId || !keySecret) {
    const error = new Error('Razorpay credentials are not configured');
    error.statusCode = 503;
    throw error;
  }
  razorpayClient = new Razorpay({ key_id: keyId, key_secret: keySecret });
  return razorpayClient;
}

function initializeFirebaseAdmin() {
  if (firebaseInitialized || admin.apps.length) {
    firebaseInitialized = true;
    return admin;
  }
  const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (serviceAccount) {
    admin.initializeApp({ credential: admin.credential.cert(JSON.parse(serviceAccount)) });
  } else {
    admin.initializeApp();
  }
  firebaseInitialized = true;
  return admin;
}

async function verifyFirebaseIdentity(idToken) {
  if (!idToken) return null;
  const firebase = initializeFirebaseAdmin();
  return await firebase.auth().verifyIdToken(idToken);
}

function isOnlinePayment(payment) {
  return payment?.provider === 'Razorpay' || payment?.method === 'Online';
}

async function createRazorpayOrder(orderId, amount) {
  const client = getRazorpayClient();
  return client.orders.create({
    amount: toPaise(amount),
    currency: 'INR',
    receipt: orderId,
    notes: { orderId },
  });
}

async function sendPushNotification(userIds, title, message, data = {}) {
  try {
    const users = await User.find({ _id: { $in: userIds } }).select('fcmTokens');
    const tokens = users.flatMap(user => user.fcmTokens || []).filter(Boolean);
    if (tokens.length === 0) return true;
    const firebase = initializeFirebaseAdmin();
    await firebase.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body: message },
      android: {
        priority: 'high',
        notification: { channelId: 'orders', sound: 'default', priority: 'high', defaultVibrateTimings: true },
      },
      apns: {
        headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
        payload: { aps: { sound: 'default', badge: 1, contentAvailable: true } },
      },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
    });
    return true;
  } catch (err) {
    console.warn('Push notification failed:', err.message);
    return false;
  }
}

function verifyRazorpaySignature({ razorpay_order_id, razorpay_payment_id, razorpay_signature }) {
  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) return false;
  if (!process.env.RAZORPAY_KEY_SECRET) {
    const error = new Error('Razorpay credentials are not configured');
    error.statusCode = 503;
    throw error;
  }
  const expected = crypto
    .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
    .update(`${razorpay_order_id}|${razorpay_payment_id}`)
    .digest('hex');
  // Use timing-safe comparison without prior length check to prevent timing attacks
  try {
    return crypto.timingSafeEqual(
      Buffer.from(expected.padEnd(64, '0')),
      Buffer.from(String(razorpay_signature).padEnd(64, '0'))
    ) && expected.length === String(razorpay_signature).length;
  } catch {
    return false;
  }
}

// ── Auth middleware ───────────────────────────────────────────────────────────
// Always enforced — no dev bypass. Ensures every protected route is authenticated.
async function requireFirebaseAuth(req, res, next) {
  try {
    const authHeader = req.get('Authorization') || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
    if (!token) {
      return res.status(401).json({ message: 'Firebase auth token is required' });
    }
    req.firebaseUser = await verifyFirebaseIdentity(token);
    if (!req.firebaseUser) {
      return res.status(401).json({ message: 'Invalid Firebase auth token' });
    }
    return next();
  } catch (err) {
    return res.status(401).json({ message: 'Invalid Firebase auth token' });
  }
}

// ── Ownership helpers ─────────────────────────────────────────────────────────

// Verify the authenticated user is the vendor who owns this cafe.
async function requireCafeOwner(req, res, next) {
  try {
    const cafeId = req.params.id || req.params.cafeId || req.body?.cafeId;
    if (!mongoose.Types.ObjectId.isValid(cafeId)) {
      return res.status(400).json({ message: 'Invalid cafe ID' });
    }
    const cafe = await Cafe.findById(cafeId).select('vendorId');
    if (!cafe) return res.status(404).json({ message: 'Cafe not found' });
    if (cafe.vendorId !== req.firebaseUser.uid) {
      return res.status(403).json({ message: 'Forbidden: you do not own this cafe' });
    }
    req.cafe = cafe;
    next();
  } catch (err) {
    next(err);
  }
}

// Verify the authenticated user is the vendor who owns the menu item's cafe.
async function requireMenuItemOwner(req, res, next) {
  try {
    const itemId = req.params.id;
    if (!mongoose.Types.ObjectId.isValid(itemId)) {
      return res.status(400).json({ message: 'Invalid menu item ID' });
    }
    const item = await MenuItem.findById(itemId).select('cafeId');
    if (!item) return res.status(404).json({ message: 'Menu item not found' });
    const cafe = await Cafe.findById(item.cafeId).select('vendorId');
    if (!cafe || cafe.vendorId !== req.firebaseUser.uid) {
      return res.status(403).json({ message: 'Forbidden: you do not own this menu item' });
    }
    req.menuItem = item;
    next();
  } catch (err) {
    next(err);
  }
}

// Verify the authenticated user is the vendor who owns the order's cafe.
async function requireOrderCafeOwner(req, res, next) {
  try {
    const order = await Order.findOne({ orderId: req.params.orderId }).select('cafeId');
    if (!order) return res.status(404).json({ message: 'Order not found' });
    const cafe = await Cafe.findById(order.cafeId).select('vendorId');
    if (!cafe || cafe.vendorId !== req.firebaseUser.uid) {
      return res.status(403).json({ message: 'Forbidden: you do not own this order' });
    }
    next();
  } catch (err) {
    next(err);
  }
}

// Validate an ObjectId param to prevent NoSQL injection.
function validateObjectId(paramName) {
  return (req, res, next) => {
    const val = req.params[paramName] || req.query[paramName];
    if (val && !mongoose.Types.ObjectId.isValid(val)) {
      return res.status(400).json({ message: `Invalid ${paramName}` });
    }
    next();
  };
}

function buildCafeQuery(req) {
  const query = {};
  if (req.query.search) query.$text = { $search: req.query.search };
  if (req.query.category) query.category = req.query.category;
  return query;
}

// Legacy direct order creation has been disabled for security: it created orders
// marked 'Paid' from client-supplied payment data with no verification (and trusted a
// client-supplied discount). All orders must now go through the verified payment flow:
//   POST /api/payment/initiate  ->  POST /api/orders/confirm
async function createOrder(req, res) {
  return res.status(410).json({
    message: 'Direct order creation is disabled. Use POST /api/payment/initiate then POST /api/orders/confirm.',
  });
}

function getMongoOptions() {
  const uri = process.env.MONGO_URI;
  const dbName = process.env.MONGO_DB_NAME || (() => {
    const uriNoQuery = uri.split('?')[0];
    const lastSegment = uriNoQuery.substring(uriNoQuery.lastIndexOf('/') + 1);
    return lastSegment && !lastSegment.includes('@') ? lastSegment : undefined;
  })();
  if (!dbName) throw new Error('MONGO_DB_NAME is missing and MONGO_URI does not include a database name');
  return { dbName };
}

async function connectDatabase() {
  if (!process.env.MONGO_URI) throw new Error('MONGO_URI is missing. Add it to Backend/.env');
  await mongoose.connect(process.env.MONGO_URI, getMongoOptions());
  // CODEX EDITS: Migrate the former 30-minute createdAt TTL online. Dropping
  // the old TTL first prevents it racing the seven-day backfill.
  await migratePaymentSessionIndexes();
  // CODEX EDITS: Fail startup before accepting traffic if payment-critical
  // idempotency indexes cannot be created or validated.
  await Promise.all([
    PaymentSession.init(),
    PaymentWebhookEvent.init(),
    NotificationOutbox.init(),
    Notification.init(),
    Order.init(),
  ]);
  console.log('MongoDB connected');
}

// CODEX EDITS: Backward-compatible online migration for sessions created by
// previous releases. Existing sessions receive defaults without rewriting carts.
async function migratePaymentSessionIndexes() {
  try {
    const indexes = await PaymentSession.collection.indexes();
    const oldTtl = indexes.find(index =>
      index.key?.createdAt === 1 && index.expireAfterSeconds !== undefined
    );
    if (oldTtl) {
      await PaymentSession.collection.dropIndex(oldTtl.name);
      paymentLog('payment_session.old_ttl_removed', { indexName: oldTtl.name });
    }
  } catch (error) {
    // NamespaceNotFound means this is a clean deployment with no collection yet.
    if (error?.code !== 26 && error?.codeName !== 'NamespaceNotFound') throw error;
  }

  const defaultExpiry = new Date(Date.now() + PAYMENT_SESSION_RETENTION_MS);
  await PaymentSession.updateMany(
    { status: { $exists: false } },
    { $set: { status: 'pending' } }
  );
  await PaymentSession.updateMany(
    { expiresAt: { $exists: false } },
    { $set: { expiresAt: defaultExpiry } }
  );
  await PaymentSession.collection.createIndex(
    { expiresAt: 1 },
    { expireAfterSeconds: 0, name: 'expiresAt_1' }
  );
}

// CODEX EDITS: The outbox insert is idempotent and can participate in the same
// transaction as order creation, leaving notification delivery off the request path.
async function enqueueOrderNotifications(order, mongoSession = null) {
  const options = { upsert: true };
  if (mongoSession) options.session = mongoSession;
  await NotificationOutbox.updateOne(
    { dedupeKey: `order:${order._id}:created` },
    {
      $setOnInsert: {
        dedupeKey: `order:${order._id}:created`,
        orderId: order._id,
        status: 'pending',
        nextAttemptAt: new Date(),
      },
    },
    options
  );
}

// CODEX EDITS: One PM2 worker atomically leases each outbox job. Failed jobs
// use bounded exponential backoff and can be resumed after worker termination.
async function processNotificationOutboxOnce() {
  const now = new Date();
  const staleBefore = new Date(Date.now() - OUTBOX_PROCESSING_LEASE_MS);
  const job = await NotificationOutbox.findOneAndUpdate(
    {
      $or: [
        { status: { $in: ['pending', 'failed'] }, nextAttemptAt: { $lte: now } },
        { status: 'processing', processingStartedAt: { $lt: staleBefore } },
      ],
    },
    {
      $set: { status: 'processing', processingStartedAt: now, lastError: '' },
      $inc: { attempts: 1 },
    },
    { sort: { nextAttemptAt: 1 }, returnDocument: 'after' }
  );
  if (!job) return;

  try {
    const order = await Order.findById(job.orderId);
    if (!order) throw new Error('Outbox order no longer exists');

    if (order.userId && !job.customerNotificationSentAt) {
      await Notification.updateOne(
        { dedupeKey: `order:${order._id}:placed` },
        {
          $setOnInsert: {
            userId: order.userId,
            title: 'Order Placed 🎉',
            message: `Token #${order.tokenNumber} confirmed — payment received.`,
            type: 'order',
            orderId: order._id,
            items: order.items.map(item => item.name),
            dedupeKey: `order:${order._id}:placed`,
          },
        },
        { upsert: true }
      );
      await NotificationOutbox.updateOne(
        { _id: job._id },
        { $set: { customerNotificationSentAt: new Date() } }
      );
    }

    if (order.userId && !job.customerPushSentAt) {
      const sent = await sendPushNotification(
        [order.userId],
        'Order Placed 🎉',
        `Token #${order.tokenNumber} confirmed — payment received.`,
        { type: 'order', orderId: order.orderId, status: 'Pending' }
      );
      if (!sent) throw new Error('Customer FCM delivery failed');
      await NotificationOutbox.updateOne(
        { _id: job._id },
        { $set: { customerPushSentAt: new Date() } }
      );
    }

    if (order.cafeId && !job.vendorPushSentAt) {
      const vendorUser = await User.findOne({ cafeId: order.cafeId, role: 'vendor' }).select('_id').lean();
      if (vendorUser) {
        const sent = await sendPushNotification(
          [vendorUser._id],
          'New Order 🛎️',
          `Token #${order.tokenNumber} — new order from ${order.customerName || 'a customer'}`,
          { type: 'vendor_order', orderId: order.orderId, status: 'Pending' }
        );
        if (!sent) throw new Error('Vendor FCM delivery failed');
      }
      await NotificationOutbox.updateOne(
        { _id: job._id },
        { $set: { vendorPushSentAt: new Date() } }
      );
    }

    await NotificationOutbox.updateOne(
      { _id: job._id },
      {
        $set: {
          status: 'sent',
          sentAt: new Date(),
          processingStartedAt: null,
          lastError: '',
        },
      }
    );
    paymentLog('notification_outbox.sent', { orderId: order.orderId, attempts: job.attempts });
  } catch (error) {
    const delayMs = Math.min(5 * 60 * 1000, 1000 * (2 ** Math.min(job.attempts, 8)));
    await NotificationOutbox.updateOne(
      { _id: job._id },
      {
        $set: {
          status: 'failed',
          processingStartedAt: null,
          nextAttemptAt: new Date(Date.now() + delayMs),
          lastError: safeErrorMessage(error),
        },
      }
    );
    paymentLog('notification_outbox.failed', {
      orderObjectId: String(job.orderId),
      attempts: job.attempts,
      error: safeErrorMessage(error),
    }, 'warn');
  }
}

// CODEX EDITS: Timer is unref'd so graceful PM2 shutdown is never held open.
function startNotificationOutboxWorker() {
  if (notificationOutboxTimer) return;
  setImmediate(() => processNotificationOutboxOnce().catch(error =>
    paymentLog('notification_outbox.worker_error', { error: safeErrorMessage(error) }, 'error')
  ));
  notificationOutboxTimer = setInterval(() => {
    processNotificationOutboxOnce().catch(error =>
      paymentLog('notification_outbox.worker_error', { error: safeErrorMessage(error) }, 'error')
    );
  }, 5000);
  notificationOutboxTimer.unref?.();
}

// ── Routes ────────────────────────────────────────────────────────────────────

app.get('/api/health', (req, res) => {
  res.json({ ok: true, service: 'nevark-food-backend', mongoState: mongoose.connection.readyState });
});

// Auth — rate-limited above
app.post('/api/auth/google', asyncHandler(async (req, res) => {
  const { name, email, avatar, idToken, fcmToken } = req.body;
  if (!name || !email) return res.status(400).json({ message: 'name and email are required' });

  const normalizedEmail = email.toLowerCase();

  // Always verify the Firebase token — reject unverified logins
  const decodedToken = await verifyFirebaseIdentity(idToken);
  if (!decodedToken) return res.status(401).json({ message: 'Valid Firebase ID token is required' });
  if (decodedToken.email?.toLowerCase() !== normalizedEmail) {
    return res.status(403).json({ message: 'Firebase token email does not match request email' });
  }

  // Resolve role from a trusted source — never from the client-supplied request body.
  // Priority: Firestore (authoritative) -> existing DB user's role -> default 'customer'.
  // The lookup mirrors the client's data model: a 'users' doc whose 'email' array
  // contains this address (matched with the verified token email's original casing).
  const existingUser = await User.findOne({ email: normalizedEmail }).select('role').lean();
  let resolvedRole = existingUser?.role || 'customer';
  try {
    const firebase = initializeFirebaseAdmin();
    const snapshot = await firebase.firestore()
      .collection('users')
      .where('email', 'array-contains', decodedToken.email)
      .limit(1)
      .get();
    if (!snapshot.empty) resolvedRole = snapshot.docs[0].data().role || resolvedRole;
  } catch (err) {
    console.warn('Firebase role lookup failed:', err.message);
  }

  let user = await User.findOneAndUpdate(
    { email: normalizedEmail },
    {
      $set: { googleId: decodedToken.uid, avatar, role: resolvedRole },
      $setOnInsert: { name },
      ...(fcmToken && /^[A-Za-z0-9_:%-]{20,300}$/.test(fcmToken)
        ? { $addToSet: { fcmTokens: fcmToken } } : {}),
    },
    { returnDocument: 'after', upsert: true, runValidators: true }
  ).populate('cafeId');

  if (user.role === 'vendor') {
    const vendorId = decodedToken.uid; // Always use Firebase UID as vendorId
    if (!user.vendorId || user.vendorId !== vendorId) {
      user = await User.findByIdAndUpdate(user._id, { vendorId }, { returnDocument: 'after' }).populate('cafeId');
    }
    if (!user.cafeId) {
      let cafe = await Cafe.findOne({ vendorId });
      if (!cafe) {
        const baseSlug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '').slice(0, 40) || `vendor-${Date.now()}`;
        const slug = `${baseSlug}-${crypto.randomBytes(3).toString('hex')}`; // Collision-safe
        cafe = await Cafe.create({ name: `${name}'s Cafe`, slug, cuisine: 'General', description: '', location: '', city: '', pin: '', vendorId, active: true });
      }
      user = await User.findByIdAndUpdate(user._id, { cafeId: cafe._id, vendorId }, { returnDocument: 'after' }).populate('cafeId');
    }
  }

  res.status(200).json(user);
}));

// User can only update their own profile
app.patch('/api/users/:id', requireFirebaseAuth, asyncHandler(async (req, res) => {
  // Verify the authenticated user is modifying their own record
  const targetUser = await User.findById(req.params.id).select('googleId');
  if (!targetUser) return res.status(404).json({ message: 'User not found' });
  if (targetUser.googleId !== req.firebaseUser.uid) {
    return res.status(403).json({ message: 'Forbidden: you can only update your own profile' });
  }

  const allowed = {};
  for (const key of ['name', 'email', 'avatar', 'phone', 'paymentLabel']) {
    if (req.body[key] !== undefined) allowed[key] = req.body[key];
  }
  const user = await User.findByIdAndUpdate(req.params.id, allowed, { returnDocument: 'after', runValidators: true }).populate('cafeId');
  res.json(user);
}));

app.post('/api/users/:id/fcm-token', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const { token } = req.body;
  if (!token || typeof token !== 'string') return res.status(400).json({ message: 'token is required' });

  // Validate FCM token format to prevent junk data in fcmTokens array
  if (!/^[A-Za-z0-9_:%-]{20,300}$/.test(token)) {
    return res.status(400).json({ message: 'Invalid FCM token format' });
  }

  // Only allow user to register their own FCM token
  const targetUser = await User.findById(req.params.id).select('googleId');
  if (!targetUser) return res.status(404).json({ message: 'User not found' });
  if (targetUser.googleId !== req.firebaseUser.uid) {
    return res.status(403).json({ message: 'Forbidden' });
  }

  await User.findByIdAndUpdate(req.params.id, { $addToSet: { fcmTokens: token.trim() } });
  res.status(204).send();
}));

// Public: cafe listing (customers don't need auth to browse)
app.get('/api/cafes', asyncHandler(async (req, res) => {
  const cafes = await Cafe.find(buildCafeQuery(req))
    .select('-vendorId -ratings') // Don't expose vendorId or raw ratings array
    .sort({ rating: -1, name: 1 });
  res.json(cafes);
}));

app.get('/api/cafes/:id', validateObjectId('id'), asyncHandler(async (req, res) => {
  const cafe = await Cafe.findById(req.params.id).select('-vendorId -ratings');
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });
  res.json(cafe);
}));

app.post('/api/cafes', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const user = await User.findOne({ googleId: req.firebaseUser.uid }).select('role').lean();
  if (!user || (user.role !== 'vendor' && user.role !== 'admin')) {
    return res.status(403).json({ message: 'Forbidden: only vendors can create cafes' });
  }
  const cafe = await Cafe.create(req.body);
  audit('cafe.created', req.firebaseUser.uid, 'cafe', cafe._id.toString(), { name: cafe.name });
  res.status(201).json(cafe);
}));

// Vendor can only update their own cafe
app.patch('/api/cafes/:id', requireFirebaseAuth, validateObjectId('id'), requireCafeOwner, asyncHandler(async (req, res) => {
  // Strip fields that vendors must not self-set
  const { vendorId, ratings, ...safeBody } = req.body;
  const cafe = await Cafe.findByIdAndUpdate(req.params.id, safeBody, { returnDocument: 'after', runValidators: true });
  audit('cafe.updated', req.firebaseUser.uid, 'cafe', req.params.id, { fields: Object.keys(safeBody) });
  res.json(cafe);
}));

// Public: batch availability check for cart items (called pre-payment)
app.post('/api/menu/availability-check', asyncHandler(async (req, res) => {
  const { itemIds } = req.body;
  if (!Array.isArray(itemIds) || itemIds.length === 0) {
    return res.status(400).json({ message: 'itemIds array is required' });
  }
  const valid = itemIds.filter(id => mongoose.Types.ObjectId.isValid(id));
  const items = await MenuItem.find({ _id: { $in: valid } }).select('_id available name').lean();
  const result = {};
  for (const item of items) {
    result[item._id.toString()] = { available: item.available, name: item.name };
  }
  res.json(result);
}));

// Public: menu listing
app.get('/api/menu', asyncHandler(async (req, res) => {
  const query = {};
  if (req.query.cafeId) {
    if (!mongoose.Types.ObjectId.isValid(req.query.cafeId)) return res.status(400).json({ message: 'Invalid cafeId' });
    query.cafeId = req.query.cafeId;
  }
  if (req.query.vendorId) {
    // vendorId is an opaque string — sanitize but allow any string (already protected by mongoSanitize)
    query.vendorId = String(req.query.vendorId);
  }
  if (req.query.available !== undefined) query.available = req.query.available === 'true';
  if (req.query.search) query.$text = { $search: String(req.query.search).slice(0, 200) };
  const items = await MenuItem.find(query).populate('cafeId', 'name slug').sort({ category: 1, name: 1 });
  res.json(items);
}));

app.get('/api/cafes/:id/menu', validateObjectId('id'), asyncHandler(async (req, res) => {
  const items = await MenuItem.find({ cafeId: req.params.id, available: true }).sort({ category: 1, name: 1 });
  res.json(items);
}));

// Rating — userId always from auth token, never from client
app.post('/api/cafes/:id/review', requireFirebaseAuth, validateObjectId('id'), asyncHandler(async (req, res) => {
  const { stars } = req.body;
  const userId = req.firebaseUser.uid; // Never trust client-provided userId
  if (!stars || stars < 1 || stars > 5) {
    return res.status(400).json({ message: 'stars (1-5) is required' });
  }
  // Pull any existing rating for this user (returns pre-update doc to check if it existed).
  // Then push the new rating and recompute aggregate in a single pipeline update.
  // Replaces the read-modify-write pattern (findById → modify → save) which would let
  // two concurrent workers silently clobber each other's rating changes.
  const beforePull = await Cafe.findByIdAndUpdate(req.params.id, { $pull: { ratings: { userId } } });
  if (!beforePull) return res.status(404).json({ message: 'Cafe not found' });
  const cafe = await Cafe.findOneAndUpdate(
    { _id: req.params.id },
    [
      { $set: { ratings: { $concatArrays: ['$ratings', [{ userId, stars: Number(stars) }]] } } },
      { $set: {
        reviews: { $size: '$ratings' },
        rating: { $round: [{ $divide: [{ $sum: '$ratings.stars' }, { $size: '$ratings' }] }, 1] },
      } },
    ],
    { returnDocument: 'after' }
  );
  audit('rating.submitted', userId, 'cafe', req.params.id, { stars, updated: beforePull.ratings.some(r => r.userId === userId) });
  res.json({ rating: cafe.rating, reviews: cafe.reviews });
}));

app.delete('/api/cafes/:id/review', requireFirebaseAuth, validateObjectId('id'), asyncHandler(async (req, res) => {
  const userId = req.firebaseUser.uid;
  // Single atomic pipeline update: filter out the user's rating and recompute the
  // aggregate in one findOneAndUpdate — no read-modify-write race possible.
  const cafe = await Cafe.findOneAndUpdate(
    { _id: req.params.id },
    [
      { $set: { ratings: { $filter: { input: '$ratings', as: 'r', cond: { $ne: ['$$r.userId', userId] } } } } },
      { $set: {
        reviews: { $size: '$ratings' },
        rating: {
          $cond: [
            { $gt: [{ $size: '$ratings' }, 0] },
            { $round: [{ $divide: [{ $sum: '$ratings.stars' }, { $size: '$ratings' }] }, 1] },
            4,
          ],
        },
      } },
    ],
    { returnDocument: 'after' }
  );
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });
  audit('rating.deleted', userId, 'cafe', req.params.id);
  res.json({ rating: cafe.rating, reviews: cafe.reviews });
}));

// User can only read their own ratings
app.get('/api/users/:userId/ratings', requireFirebaseAuth, asyncHandler(async (req, res) => {
  if (req.params.userId !== req.firebaseUser.uid) {
    return res.status(403).json({ message: 'Forbidden' });
  }
  const userId = req.firebaseUser.uid;
  const cafes  = await Cafe.find({ 'ratings.userId': userId }, { ratings: 1 });
  const result = {};
  cafes.forEach(cafe => {
    const r = cafe.ratings.find(r => r.userId === userId);
    if (r) result[cafe._id.toString()] = r.stars;
  });
  res.json(result);
}));

// Menu — vendor must own the cafe they're adding to
app.post('/api/menu', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const { cafeId } = req.body;
  if (!cafeId || !mongoose.Types.ObjectId.isValid(cafeId)) {
    return res.status(400).json({ message: 'Valid cafeId is required' });
  }
  const cafe = await Cafe.findById(cafeId).select('vendorId');
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });
  if (cafe.vendorId !== req.firebaseUser.uid) {
    return res.status(403).json({ message: 'Forbidden: you do not own this cafe' });
  }
  const item = await MenuItem.create(req.body);
  res.status(201).json(item);
}));

app.post('/api/menu/add', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const { cafeId } = req.body;
  if (!cafeId || !mongoose.Types.ObjectId.isValid(cafeId)) {
    return res.status(400).json({ message: 'Valid cafeId is required' });
  }
  const cafe = await Cafe.findById(cafeId).select('vendorId');
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });
  if (cafe.vendorId !== req.firebaseUser.uid) {
    return res.status(403).json({ message: 'Forbidden: you do not own this cafe' });
  }
  const item = await MenuItem.create(req.body);
  res.status(201).json(item);
}));

app.patch('/api/menu/:id', requireFirebaseAuth, validateObjectId('id'), requireMenuItemOwner, asyncHandler(async (req, res) => {
  const { cafeId, ...safeBody } = req.body; // Prevent moving item to another cafe
  const item = await MenuItem.findByIdAndUpdate(req.params.id, safeBody, { returnDocument: 'after', runValidators: true });
  if (!item) return res.status(404).json({ message: 'Menu item not found' });
  res.json(item);
}));

app.delete('/api/menu/:id', requireFirebaseAuth, validateObjectId('id'), requireMenuItemOwner, asyncHandler(async (req, res) => {
  await MenuItem.findByIdAndDelete(req.params.id);
  res.status(204).send();
}));

// ── Payment ───────────────────────────────────────────────────────────────────

// Step 1: compute totals server-side, create Razorpay order, persist cart to DB.
app.post('/api/payment/initiate', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const {
    customerName, customerEmail, cafeId, cafeteriaName,
    items, location, pickupTime, notes,
  } = req.body;

  if (!customerName || !cafeteriaName || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ message: 'customerName, cafeteriaName, and items are required' });
  }

  // userId always from verified Firebase token
  const userRecord = await User.findOne({ googleId: req.firebaseUser.uid }).select('_id').lean();
  const resolvedUserId = userRecord?._id || null;

  const normalizedItems = items.map(item => ({
    menuItemId: mongoose.Types.ObjectId.isValid(item.menuItemId || item.id)
      ? (item.menuItemId || item.id) : undefined,
    name:  String(item.name  || '').trim(),
    qty:   Number(item.qty   || item.quantity || 1),
    price: Number(item.price || 0),
    image: item.image || '',
  }));

  if (normalizedItems.some(i => !i.name || i.qty < 1 || i.price < 0)) {
    return res.status(400).json({ message: 'Each item needs name, qty ≥ 1, and price ≥ 0' });
  }

  let resolvedCafeId = cafeId;
  if (!resolvedCafeId && cafeteriaName) {
    const cafe = await Cafe.findOne({ name: cafeteriaName }).select('_id');
    resolvedCafeId = cafe?._id;
  }

  // Reject if cafe is currently closed
  if (resolvedCafeId) {
    const cafe = await Cafe.findById(resolvedCafeId).select('active').lean();
    if (cafe && cafe.active === false) {
      return res.status(409).json({ message: 'This cafe is currently closed and not accepting orders.' });
    }
  }

  // Reject if any item is currently disabled by the vendor
  const menuItemIds = normalizedItems.map(i => i.menuItemId).filter(id => id && mongoose.Types.ObjectId.isValid(String(id)));
  if (menuItemIds.length > 0) {
    const unavailable = await MenuItem.find({ _id: { $in: menuItemIds }, available: false }).select('name').lean();
    if (unavailable.length > 0) {
      const names = unavailable.map(i => i.name).join(', ');
      return res.status(409).json({ message: `Some items are no longer available: ${names}. Please update your cart.` });
    }
  }

  const itemTotal      = toMoney(normalizedItems.reduce((s, i) => s + i.price * i.qty, 0));
  const platformFee    = toMoney(itemTotal * 0.03);
  const convenienceFee = 1.5;
  // Discounts are not accepted from the client — there is no server-validated coupon
  // system yet. Forcing 0 prevents price manipulation via an arbitrary discount value.
  const discountAmt    = 0;
  const total          = toMoney(itemTotal + platformFee + convenienceFee);
  if (total <= 0) return res.status(400).json({ message: 'Order total must be greater than zero' });

  const receipt      = `init_${makeOrderId()}`;
  const razorpayOrder = await createRazorpayOrder(receipt, total);

  // Persist cart to MongoDB — survives crashes and multi-instance deployments.
  await PaymentSession.create({
    razorpayOrderId: razorpayOrder.id,
    // CODEX EDITS: Explicit state/expiry keeps old and new workers compatible
    // during a rolling PM2 reload.
    status: 'pending',
    expiresAt: new Date(Date.now() + PAYMENT_SESSION_RETENTION_MS),
    cart: {
      // CODEX EDITS: Bind the payment owner to the verified Firebase identity;
      // never trust a client-supplied email for reconciliation access control.
      userId: resolvedUserId,
      customerName,
      customerEmail: (req.firebaseUser.email || customerEmail || '').toLowerCase(),
      cafeId: resolvedCafeId, cafeteriaName,
      items: normalizedItems,
      itemTotal, platformFee, convenienceFee, discount: discountAmt, total,
      location: location || 'Pickup counter',
      pickupTime: pickupTime || '',
      notes: notes || '',
    },
  });

  // CODEX EDITS: Correlate initiation without logging cart contents or PII.
  paymentLog('payment.initiated', {
    razorpayOrderId: razorpayOrder.id,
    amountPaise: razorpayOrder.amount,
    cafeId: resolvedCafeId ? String(resolvedCafeId) : '',
  });

  // Return key ID so the Flutter client doesn't need to hardcode it.
  res.json({ razorpayOrder, razorpayKeyId: process.env.RAZORPAY_KEY_ID });
}));

// Create the DB order for a paid Razorpay order — shared by the client confirm
// endpoint and the Razorpay webhook, whichever arrives first. Idempotent on
// razorpay_order_id: if the order already exists it is returned untouched, so
// the two paths can never double-create or double-notify. Returns null only
// when no order exists and the PaymentSession is gone (expired/never created).
// CODEX EDITS: Create the DB order through a leased, durable state machine.
// Client confirmation and webhook delivery can safely race across PM2 workers.
async function createOrderFromPaymentSession(razorpay_order_id, razorpay_payment_id, source = 'unknown') {
  const existing = await Order.findOne({ 'payment.providerOrderId': razorpay_order_id });
  if (existing) {
    await markPaymentSessionCompleted(razorpay_order_id, razorpay_payment_id, existing._id);
    await enqueueOrderNotifications(existing);
    return existing;
  }

  const staleBefore = new Date(Date.now() - PAYMENT_PROCESSING_LEASE_MS);
  const claimedSession = await PaymentSession.findOneAndUpdate(
    {
      razorpayOrderId: razorpay_order_id,
      $or: [
        { status: { $in: ['pending', 'failed'] } },
        { status: { $exists: false } },
        { status: 'processing', processingStartedAt: { $lt: staleBefore } },
      ],
    },
    {
      $set: {
        status: 'processing',
        processingStartedAt: new Date(),
        lastPaymentId: razorpay_payment_id,
        lastError: null,
      },
    },
    { returnDocument: 'after' }
  );

  if (!claimedSession) {
    // CODEX EDITS: A peer worker may own the live lease. Poll only the shared
    // order result; never consume or mutate its payment session.
    for (let attempt = 0; attempt < 10; attempt++) {
      await new Promise(resolve => setTimeout(resolve, 300));
      const concurrentOrder = await Order.findOne({ 'payment.providerOrderId': razorpay_order_id });
      if (concurrentOrder) return concurrentOrder;
    }
    return null;
  }

  const cart = claimedSession.cart;
  let order;
  try {
    order = await persistPaidOrderWithTransaction(
      claimedSession,
      razorpay_order_id,
      razorpay_payment_id
    );
  } catch (error) {
    // CODEX EDITS: A commit may have succeeded just before a connection loss.
    // Resolve by the unique provider order ID before resetting the lease.
    const committedOrder = await Order.findOne({ 'payment.providerOrderId': razorpay_order_id });
    if (committedOrder) {
      await markPaymentSessionCompleted(razorpay_order_id, razorpay_payment_id, committedOrder._id);
      await enqueueOrderNotifications(committedOrder);
      return committedOrder;
    }

    await PaymentSession.updateOne(
      { _id: claimedSession._id, status: 'processing' },
      {
        $set: {
          status: 'pending',
          processingStartedAt: null,
          lastError: { message: safeErrorMessage(error), at: new Date(), source },
        },
      }
    );
    paymentLog('payment.order_creation_failed', {
      razorpayOrderId: razorpay_order_id,
      razorpayPaymentId: razorpay_payment_id,
      source,
      error: safeErrorMessage(error),
    }, 'error');
    throw error;
  }

  audit('payment.confirmed', cart.userId, 'payment', order.orderId, {
    amount: cart.total,
    razorpayPaymentId: razorpay_payment_id,
    cafeId: cart.cafeId,
    source,
  });
  paymentLog('payment.order_created', {
    razorpayOrderId: razorpay_order_id,
    razorpayPaymentId: razorpay_payment_id,
    orderId: order.orderId,
    source,
  });
  return order;
}

// CODEX EDITS: Keep the session result repairable and queryable after completion.
async function markPaymentSessionCompleted(razorpayOrderId, razorpayPaymentId, orderObjectId, mongoSession = null) {
  const options = mongoSession ? { session: mongoSession } : {};
  await PaymentSession.updateOne(
    { razorpayOrderId },
    {
      $set: {
        status: 'completed',
        processingStartedAt: null,
        completedAt: new Date(),
        completedOrderId: orderObjectId,
        lastPaymentId: razorpayPaymentId,
        lastError: null,
      },
    },
    options
  );
}

// CODEX EDITS: Transactionally commit counter, order, session state, and outbox.
// A standalone-Mongo fallback preserves local development without weakening the
// crash-recovery state machine used in production replica sets.
async function persistPaidOrderWithTransaction(paymentSession, razorpayOrderId, razorpayPaymentId) {
  const mongoSession = await mongoose.startSession();
  let createdOrder;
  try {
    await mongoSession.withTransaction(async () => {
      createdOrder = await persistPaidOrder(
        paymentSession,
        razorpayOrderId,
        razorpayPaymentId,
        mongoSession
      );
    }, {
      readConcern: { level: 'snapshot' },
      writeConcern: { w: 'majority' },
      readPreference: 'primary',
    });
    return createdOrder;
  } catch (error) {
    const unsupported = error?.code === 20 ||
      error?.code === 263 ||
      /transaction numbers are only allowed|replica set|mongos/i.test(safeErrorMessage(error));
    if (!unsupported) throw error;
    paymentLog('payment.transaction_fallback', {
      razorpayOrderId,
      reason: safeErrorMessage(error),
    }, 'warn');
    return persistPaidOrder(paymentSession, razorpayOrderId, razorpayPaymentId, null);
  } finally {
    await mongoSession.endSession();
  }
}

// CODEX EDITS: Shared write unit for transactional production and safe local fallback.
async function persistPaidOrder(paymentSession, razorpayOrderId, razorpayPaymentId, mongoSession) {
  const cart = paymentSession.cart;
  const tokenNumber = await generateTokenNumber(cart.cafeId, mongoSession);
  const payload = {
    orderId: makeOrderId(),
    tokenNumber,
    userId: cart.userId,
    customerName: cart.customerName,
    customerEmail: cart.customerEmail,
    cafeId: cart.cafeId,
    cafeteriaName: cart.cafeteriaName,
    items: cart.items,
    itemTotal: cart.itemTotal,
    platformFee: cart.platformFee,
    convenienceFee: cart.convenienceFee,
    discount: cart.discount,
    total: cart.total,
    status: 'Pending',
    payment: {
      method: 'Online',
      provider: 'Razorpay',
      providerOrderId: razorpayOrderId,
      transactionId: razorpayPaymentId,
      status: 'Paid',
    },
    location: cart.location,
    pickupTime: cart.pickupTime,
    notes: cart.notes,
  };

  let order;
  if (mongoSession) {
    [order] = await Order.create([payload], { session: mongoSession });
  } else {
    order = await Order.create(payload);
  }
  await markPaymentSessionCompleted(razorpayOrderId, razorpayPaymentId, order._id, mongoSession);
  await enqueueOrderNotifications(order, mongoSession);
  return order;
}

// Step 2: verify HMAC, retrieve cart from DB, create order.
app.post('/api/orders/confirm', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;
  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    return res.status(400).json({ message: 'razorpay_order_id, razorpay_payment_id, and razorpay_signature are required' });
  }

  // Cryptographic verification first.
  if (!verifyRazorpaySignature({ razorpay_order_id, razorpay_payment_id, razorpay_signature })) {
    return res.status(400).json({ message: 'Payment verification failed — invalid signature' });
  }

  // CODEX EDITS: Tag the source for production correlation and state repair.
  const order = await createOrderFromPaymentSession(
    razorpay_order_id,
    razorpay_payment_id,
    'client_confirm'
  );
  if (!order) {
    return res.status(409).json({ message: 'Payment confirmation is already being processed' });
  }

  res.status(201).json(order);
}));

// CODEX EDITS: Ownership helper supports both current verified-email sessions
// and older sessions that may only contain the Mongo user reference.
async function paymentBelongsToRequester(req, customerEmail, userId) {
  const verifiedEmail = String(req.firebaseUser?.email || '').toLowerCase();
  if (verifiedEmail && String(customerEmail || '').toLowerCase() === verifiedEmail) return true;
  if (!userId) return false;
  const requester = await User.findOne({ googleId: req.firebaseUser.uid }).select('_id').lean();
  return !!requester && String(requester._id) === String(userId);
}

// CODEX EDITS: Persist only bounded, non-sensitive SDK diagnostics.
function sanitizeSdkError(value) {
  if (!value || typeof value !== 'object') return null;
  const nested = value.error && typeof value.error === 'object' ? value.error : {};
  return {
    code: String(value.code ?? '').slice(0, 50),
    message: String(value.message ?? '').slice(0, 300),
    reason: String(nested.reason ?? nested.error_reason ?? '').slice(0, 100),
    source: String(nested.source ?? nested.error_source ?? '').slice(0, 100),
    step: String(nested.step ?? nested.error_step ?? '').slice(0, 100),
  };
}

// CODEX EDITS: Never fulfil from a captured webhook/API object unless its
// immutable amount, currency, and provider order ID match the server-side cart.
function assertCapturedPaymentIntegrity(paymentSession, razorpayOrder, payment) {
  const expectedAmount = toPaise(paymentSession.cart.total);
  const orderAmount = Number(razorpayOrder?.amount);
  const paymentAmount = Number(payment?.amount);
  const currency = String(payment?.currency || razorpayOrder?.currency || '').toUpperCase();
  const orderMatches = String(payment?.order_id || '') === paymentSession.razorpayOrderId;
  if (
    orderAmount !== expectedAmount ||
    paymentAmount !== expectedAmount ||
    currency !== 'INR' ||
    !orderMatches
  ) {
    const error = new Error('Captured payment does not match the initiated order');
    error.statusCode = 409;
    throw error;
  }
}

// CODEX EDITS: Authoritative reconciliation is used for SDK errors, lifecycle
// resumes, cold starts, and safe retries of the same Razorpay order.
app.post(
  '/api/payment/reconcile',
  requireFirebaseAuth,
  paymentReconcileLimiter,
  asyncHandler(async (req, res) => {
    const razorpayOrderId = String(req.body?.razorpay_order_id || '').trim();
    if (!/^order_[A-Za-z0-9]+$/.test(razorpayOrderId)) {
      return res.status(400).json({ message: 'A valid razorpay_order_id is required' });
    }

    const existingOrder = await Order.findOne({ 'payment.providerOrderId': razorpayOrderId });
    if (existingOrder) {
      const ownsOrder = await paymentBelongsToRequester(
        req,
        existingOrder.customerEmail,
        existingOrder.userId
      );
      if (!ownsOrder) return res.status(403).json({ message: 'Forbidden' });
      paymentLog('payment.reconciled_existing', {
        razorpayOrderId,
        orderId: existingOrder.orderId,
      });
      return res.json({ state: 'captured', order: existingOrder });
    }

    const paymentSession = await PaymentSession.findOne({ razorpayOrderId });
    if (!paymentSession) {
      paymentLog('payment.reconcile_expired', { razorpayOrderId }, 'warn');
      return res.json({ state: 'expired', message: 'Payment session is no longer available' });
    }

    const ownsSession = await paymentBelongsToRequester(
      req,
      paymentSession.cart?.customerEmail,
      paymentSession.cart?.userId
    );
    if (!ownsSession) return res.status(403).json({ message: 'Forbidden' });

    const sdkError = sanitizeSdkError(req.body?.sdk_error);
    if (sdkError) {
      await PaymentSession.updateOne(
        { _id: paymentSession._id },
        { $set: { lastError: { ...sdkError, at: new Date(), source: 'mobile_sdk' } } }
      );
    }

    let razorpayOrder;
    let paymentCollection;
    try {
      const client = getRazorpayClient();
      [razorpayOrder, paymentCollection] = await Promise.all([
        client.orders.fetch(razorpayOrderId),
        client.orders.fetchPayments(razorpayOrderId),
      ]);
    } catch (error) {
      // A gateway/network outage is indeterminate, never a customer-facing failure.
      paymentLog('payment.reconcile_gateway_unavailable', {
        razorpayOrderId,
        sdkErrorCode: sdkError?.code,
        error: safeErrorMessage(error),
      }, 'warn');
      return res.json({
        state: 'pending',
        gatewayStatus: 'unavailable',
        retryable: true,
        message: 'Payment status is temporarily unavailable',
      });
    }

    const payments = Array.isArray(paymentCollection)
      ? paymentCollection
      : (Array.isArray(paymentCollection?.items) ? paymentCollection.items : []);
    const capturedPayment = payments
      .filter(payment => payment?.status === 'captured' || payment?.captured === true)
      .sort((a, b) => Number(b.created_at || 0) - Number(a.created_at || 0))[0];

    if (capturedPayment) {
      assertCapturedPaymentIntegrity(paymentSession, razorpayOrder, capturedPayment);
      const order = await createOrderFromPaymentSession(
        razorpayOrderId,
        capturedPayment.id,
        'server_reconcile'
      );
      if (order) return res.json({ state: 'captured', order });
    }

    const gatewayStatus = capturedPayment
      ? 'captured_processing'
      : String(razorpayOrder?.status || 'created');
    paymentLog('payment.reconcile_pending', {
      razorpayOrderId,
      gatewayStatus,
      paymentAttempts: payments.length,
      sdkErrorCode: sdkError?.code,
    });
    return res.json({
      state: 'pending',
      gatewayStatus,
      retryable: true,
      checkoutOrder: {
        id: razorpayOrderId,
        amount: Number(razorpayOrder?.amount || toPaise(paymentSession.cart.total)),
        currency: String(razorpayOrder?.currency || 'INR'),
        status: gatewayStatus,
      },
      razorpayKeyId: process.env.RAZORPAY_KEY_ID,
      message: 'Payment is awaiting final confirmation',
    });
  })
);

// Razorpay webhook — authoritative fallback for order creation. If the app is
// killed or loses the checkout success callback during a UPI redirect and never
// calls /api/orders/confirm, this still creates the order once the payment is
// captured. Configure in the Razorpay dashboard with the same secret as
// RAZORPAY_WEBHOOK_SECRET, subscribed to payment.captured and order.paid.
// No Firebase auth — authenticated by the webhook HMAC signature instead.
app.post('/api/razorpay/webhook', webhookLimiter, asyncHandler(async (req, res) => {
  const secret = process.env.RAZORPAY_WEBHOOK_SECRET;
  if (!secret) return res.status(503).json({ message: 'Webhook secret not configured' });

  const signature = req.headers['x-razorpay-signature'];
  if (!signature || !req.rawBody) {
    return res.status(400).json({ message: 'Missing webhook signature' });
  }

  const expected = crypto.createHmac('sha256', secret).update(req.rawBody).digest('hex');
  let valid = false;
  try {
    valid = expected.length === String(signature).length &&
      crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(String(signature)));
  } catch {
    valid = false;
  }
  if (!valid) return res.status(400).json({ message: 'Invalid webhook signature' });

  // CODEX EDITS: Persist and lease every verified delivery before processing;
  // the raw-body hash is a stable fallback when Razorpay omits an event ID.
  const event = String(req.body?.event || 'unknown');
  const paymentEntity = req.body?.payload?.payment?.entity;
  const orderEntity = req.body?.payload?.order?.entity;
  let razorpayOrderId = String(paymentEntity?.order_id || orderEntity?.id || '');
  let razorpayPaymentId = String(paymentEntity?.id || '');
  const eventKey = String(req.body?.id || crypto.createHash('sha256').update(req.rawBody).digest('hex'));
  try {
    await PaymentWebhookEvent.updateOne(
      { eventKey },
      {
        $setOnInsert: {
          eventKey,
          eventType: event,
          razorpayOrderId,
          razorpayPaymentId,
          status: 'received',
        },
      },
      { upsert: true }
    );
  } catch (error) {
    // CODEX EDITS: PM2 workers can receive the same webhook simultaneously.
    // A duplicate insert race is safe because the next lease query is idempotent.
    if (error?.code !== 11000) throw error;
  }

  if ((event === 'payment.captured' || event === 'order.paid') && razorpayOrderId && !razorpayPaymentId) {
    // CODEX EDITS: Some order.paid deliveries are order-centric and omit the
    // payment entity. Fetching the captured payment keeps order.paid useful
    // without trusting a partial webhook payload to fulfil an order.
    const paymentCollection = await getRazorpayClient().orders.fetchPayments(razorpayOrderId);
    const payments = Array.isArray(paymentCollection)
      ? paymentCollection
      : (Array.isArray(paymentCollection?.items) ? paymentCollection.items : []);
    const capturedPayment = payments
      .filter(payment => payment?.status === 'captured' || payment?.captured === true)
      .sort((a, b) => Number(b.created_at || 0) - Number(a.created_at || 0))[0];
    if (capturedPayment) {
      razorpayPaymentId = String(capturedPayment.id || '');
      await PaymentWebhookEvent.updateOne(
        { eventKey },
        {
          $set: {
            razorpayOrderId,
            razorpayPaymentId,
          },
        }
      );
    }
  }

  const receipt = await PaymentWebhookEvent.findOneAndUpdate(
    {
      eventKey,
      $or: [
        { status: { $in: ['received', 'failed'] } },
        {
          status: 'processing',
          processingStartedAt: { $lt: new Date(Date.now() - WEBHOOK_PROCESSING_LEASE_MS) },
        },
      ],
    },
    {
      $set: { status: 'processing', processingStartedAt: new Date(), lastError: '' },
      $inc: { attempts: 1 },
    },
    { returnDocument: 'after' }
  );

  if (!receipt) {
    paymentLog('payment.webhook_duplicate', { eventKey, event, razorpayOrderId });
    return res.json({ ok: true, duplicate: true });
  }

  try {
    if (event === 'payment.captured' || event === 'order.paid') {
      if (!razorpayOrderId || !razorpayPaymentId) {
        throw new Error('Captured webhook is missing payment or order ID');
      }

      const existingOrder = await Order.findOne({ 'payment.providerOrderId': razorpayOrderId });
      if (!existingOrder) {
        const paymentSession = await PaymentSession.findOne({ razorpayOrderId });
        if (!paymentSession) throw new Error('Payment session not found for captured webhook');
        // CODEX EDITS: Use the signed payment entity when present; otherwise
        // fetch the captured payment for order.paid payloads that omit it.
        let capturedPaymentEntity = paymentEntity;
        if (!capturedPaymentEntity || String(capturedPaymentEntity.id || '') !== razorpayPaymentId) {
          const paymentCollection = await getRazorpayClient().orders.fetchPayments(razorpayOrderId);
          const payments = Array.isArray(paymentCollection)
            ? paymentCollection
            : (Array.isArray(paymentCollection?.items) ? paymentCollection.items : []);
          capturedPaymentEntity = payments.find(payment => String(payment?.id || '') === razorpayPaymentId);
        }
        if (!capturedPaymentEntity) throw new Error('Captured payment entity could not be resolved');
        assertCapturedPaymentIntegrity(
          paymentSession,
          orderEntity || { amount: capturedPaymentEntity?.amount, currency: capturedPaymentEntity?.currency },
          capturedPaymentEntity
        );
        const order = await createOrderFromPaymentSession(
          razorpayOrderId,
          razorpayPaymentId,
          'razorpay_webhook'
        );
        if (!order) throw new Error('Paid order is still unavailable after processing lease');
      }
    }

    await PaymentWebhookEvent.updateOne(
      { _id: receipt._id },
      {
        $set: {
          status: 'processed',
          processedAt: new Date(),
          processingStartedAt: null,
          lastError: '',
        },
      }
    );
    paymentLog('payment.webhook_processed', {
      eventKey,
      event,
      razorpayOrderId,
      razorpayPaymentId,
      attempts: receipt.attempts,
    });
  } catch (error) {
    await PaymentWebhookEvent.updateOne(
      { _id: receipt._id },
      {
        $set: {
          status: 'failed',
          processingStartedAt: null,
          lastError: safeErrorMessage(error),
        },
      }
    );
    paymentLog('payment.webhook_failed', {
      eventKey,
      event,
      razorpayOrderId,
      razorpayPaymentId,
      error: safeErrorMessage(error),
    }, 'error');
    throw error;
  }

  // CODEX EDITS: Only successfully persisted/processed events return 200;
  // failures reach the error handler so Razorpay retries them.
  res.json({ ok: true });
}));

// Recovery lookup: after a lost success callback the app polls this with the
// Razorpay order id to find the order the webhook created, instead of showing
// the customer a false "payment declined".
app.get('/api/orders/by-payment/:razorpayOrderId', requireFirebaseAuth, orderReadLimiter, asyncHandler(async (req, res) => {
  const order = await Order.findOne({ 'payment.providerOrderId': req.params.razorpayOrderId });
  if (!order) return res.status(404).json({ message: 'Order not found' });

  // Access control: only the customer who placed the order may recover it.
  const requesterEmail = (req.firebaseUser.email || '').toLowerCase();
  if (!order.customerEmail || order.customerEmail.toLowerCase() !== requesterEmail) {
    return res.status(403).json({ message: 'Forbidden' });
  }
  res.json(order);
}));

app.post('/api/orders', orderLimiter, requireFirebaseAuth, asyncHandler(createOrder));
app.post('/api/orders/place', orderLimiter, requireFirebaseAuth, asyncHandler(createOrder));

app.get('/api/orders', requireFirebaseAuth, orderReadLimiter, asyncHandler(async (req, res) => {
  const query = { 'payment.status': { $ne: 'Pending' } };

  // Access control: scope results to what the requester is allowed to see.
  // Vendors see only orders for cafes they own; customers see only their own orders.
  if (req.query.cafeId && !mongoose.Types.ObjectId.isValid(req.query.cafeId)) {
    return res.status(400).json({ message: 'Invalid cafeId' });
  }
  const ownedCafes = await Cafe.find({ vendorId: req.firebaseUser.uid }).select('_id').lean();
  const ownedCafeIds = ownedCafes.map(c => c._id.toString());

  if (req.query.cafeId) {
    // Explicit cafe requested — only allowed if the requester owns it.
    if (!ownedCafeIds.includes(req.query.cafeId)) {
      return res.status(403).json({ message: 'Forbidden: you do not own this cafe' });
    }
    query.cafeId = req.query.cafeId;
  } else if (ownedCafeIds.length > 0) {
    // Vendor with no explicit cafe — restrict to all cafes they own.
    query.cafeId = { $in: ownedCafeIds };
  } else {
    // Customer — always restrict to their own verified email, ignoring any client value.
    const email = (req.firebaseUser.email || '').toLowerCase();
    if (!email) return res.status(403).json({ message: 'Forbidden' });
    query.customerEmail = email;
  }

  if (req.query.status) {
    if (!allowedStatuses.includes(req.query.status)) return res.status(400).json({ message: 'Invalid status' });
    query.status = req.query.status;
  }
  if (req.query.date) {
    // date param is YYYY-MM-DD in IST; convert to UTC range for the query
    const dateStr = req.query.date;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) return res.status(400).json({ message: 'Invalid date format, expected YYYY-MM-DD' });
    const istOffsetMs = 330 * 60 * 1000;
    const startIst = new Date(`${dateStr}T00:00:00.000Z`);
    const startUtc = new Date(startIst.getTime() - istOffsetMs);
    const endUtc = new Date(startUtc.getTime() + 24 * 60 * 60 * 1000);
    query.createdAt = { $gte: startUtc, $lt: endUtc };
  }
  const orders = await Order.find(query).populate('cafeId', 'name image imageType').sort({ createdAt: -1 });
  res.json(orders);
}));

app.get('/api/orders/:orderId', requireFirebaseAuth, orderReadLimiter, asyncHandler(async (req, res) => {
  const order = await Order.findOne({ orderId: req.params.orderId });
  if (!order) return res.status(404).json({ message: 'Order not found' });

  // Access control: only the customer who placed the order, or the vendor who
  // owns the order's cafe, may read it.
  const requesterEmail = (req.firebaseUser.email || '').toLowerCase();
  const isCustomerOwner = !!order.customerEmail && order.customerEmail.toLowerCase() === requesterEmail;
  let isVendorOwner = false;
  if (!isCustomerOwner && order.cafeId) {
    const cafe = await Cafe.findById(order.cafeId).select('vendorId').lean();
    isVendorOwner = !!cafe && cafe.vendorId === req.firebaseUser.uid;
  }
  if (!isCustomerOwner && !isVendorOwner) {
    return res.status(403).json({ message: 'Forbidden' });
  }
  res.json(order);
}));

// Only the vendor who owns the cafe can update order status
app.patch('/api/orders/:orderId/status', requireFirebaseAuth, requireOrderCafeOwner, asyncHandler(async (req, res) => {
  const { status } = req.body;
  if (!allowedStatuses.includes(status)) {
    return res.status(400).json({ message: `status must be one of: ${allowedStatuses.join(', ')}` });
  }

  const order = await Order.findOneAndUpdate(
    { orderId: req.params.orderId },
    { status },
    { returnDocument: 'after', runValidators: true }
  );
  if (!order) return res.status(404).json({ message: 'Order not found' });
  audit('order.status_changed', req.firebaseUser.uid, 'order', order.orderId, { status, cafeId: order.cafeId?.toString() });

  if (order.userId) {
    // Don't notify the vendor if they are also the customer (same Firebase account — test scenario)
    const orderUser = await User.findById(order.userId).select('googleId').lean();
    const isVendorAlsoCustomer = orderUser?.googleId === req.firebaseUser.uid;

    const t = `Token #${order.tokenNumber}`;
    const statusContent = {
      Pending:   { title: 'Order Received 📋',   body: `${t} is pending confirmation.` },
      Preparing: { title: 'Being Prepared 👨‍🍳',   body: `${t} — the kitchen is on it!` },
      Ready:     { title: 'Ready for Pickup! 🎉', body: `${t} — come collect your order now!` },
      Completed: { title: 'Order Completed ✅',    body: `${t} — enjoy your meal!` },
      Rejected:  { title: 'Order Rejected ❌',     body: `${t} was rejected. Please contact support.` },
    };
    const { title, body } = statusContent[order.status] ?? { title: 'Order Update', body: `${t} is now ${order.status}.` };
    await Notification.create({ userId: order.userId, title, message: body, type: 'order', orderId: order._id, items: order.items.map(i => i.name) });
    if (!isVendorAlsoCustomer) {
      await sendPushNotification([order.userId], title, body, { type: 'order', orderId: order.orderId, status: order.status });
    }
  }
  res.json(order);
}));

app.post('/api/payment/verify', requireFirebaseAuth, asyncHandler(async (req, res) => {
  if (!verifyRazorpaySignature(req.body)) {
    return res.status(400).json({ message: 'Invalid Razorpay signature' });
  }
  res.json({ ok: true });
}));

app.patch('/api/orders/:orderId/payment', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const { transactionId, status, providerOrderId, razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;
  const allowedPaymentStatuses = ['Pending', 'Paid', 'Failed', 'Refunded'];
  if (status && !allowedPaymentStatuses.includes(status)) {
    return res.status(400).json({ message: `status must be one of: ${allowedPaymentStatuses.join(', ')}` });
  }

  const existingOrder = await Order.findOne({ orderId: req.params.orderId });
  if (!existingOrder) return res.status(404).json({ message: 'Order not found' });

  // Ownership check: only the customer who placed the order may update payment status.
  const requesterEmail = (req.firebaseUser.email || '').toLowerCase();
  if (!existingOrder.customerEmail || existingOrder.customerEmail.toLowerCase() !== requesterEmail) {
    return res.status(403).json({ message: 'Forbidden' });
  }

  // Always verify Razorpay signature when setting Paid — regardless of current status
  if (status === 'Paid') {
    const signedOrderId   = razorpay_order_id  || existingOrder.payment.providerOrderId;
    const signedPaymentId = razorpay_payment_id || transactionId;
    if (signedOrderId !== existingOrder.payment.providerOrderId) {
      return res.status(400).json({ message: 'Razorpay order id does not match this order' });
    }
    if (!verifyRazorpaySignature({ razorpay_order_id: signedOrderId, razorpay_payment_id: signedPaymentId, razorpay_signature })) {
      return res.status(400).json({ message: 'Invalid Razorpay signature' });
    }
  }

  const update = {};
  if (transactionId   !== undefined) update['payment.transactionId']   = transactionId;
  if (providerOrderId !== undefined) update['payment.providerOrderId'] = providerOrderId;
  if (status          !== undefined) update['payment.status']          = status;

  const order = await Order.findOneAndUpdate({ orderId: req.params.orderId }, { $set: update }, { returnDocument: 'after', runValidators: true });
  if (!order) return res.status(404).json({ message: 'Order not found' });
  res.json(order);
}));

// User can only read their own notifications
app.get('/api/notifications/:userId', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const requestingUser = await User.findOne({ googleId: req.firebaseUser.uid }).select('_id').lean();
  if (!requestingUser || requestingUser._id.toString() !== req.params.userId) {
    return res.status(403).json({ message: 'Forbidden' });
  }
  const notifications = await Notification.find({ userId: req.params.userId })
    .sort({ createdAt: -1 }).limit(100);
  res.json(notifications);
}));

// Broadcast notifications — admin only
app.post('/api/notifications/send', requireFirebaseAuth, asyncHandler(async (req, res) => {
  // Only admins can broadcast — check Firestore role
  const firebase = initializeFirebaseAdmin();
  const snapshot = await firebase.firestore().collection('users')
    .where('email', '==', req.firebaseUser.email)
    .limit(1)
    .get();
  const firestoreRole = snapshot.empty ? null : snapshot.docs[0].data().role;
  if (firestoreRole !== 'admin') {
    return res.status(403).json({ message: 'Forbidden: admin only' });
  }

  const { title, message, targetUserIds } = req.body;
  if (!title || !message) return res.status(400).json({ message: 'title and message are required' });

  const users = Array.isArray(targetUserIds) && targetUserIds.length > 0
    ? await User.find({ _id: { $in: targetUserIds } }).select('_id')
    : await User.find({ role: 'customer' }).select('_id');
  const userIds = users.map(u => u._id);

  const notifications = await Notification.insertMany(userIds.map(userId => ({ userId, title, message, type: 'promotion' })));
  await sendPushNotification(userIds, title, message, { type: 'promotion' });
  res.status(201).json({ sent: notifications.length });
}));

app.patch('/api/notifications/:notificationId/read', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const requestingUser = await User.findOne({ googleId: req.firebaseUser.uid }).select('_id').lean();
  if (!requestingUser) return res.status(403).json({ message: 'Forbidden' });
  const notification = await Notification.findOneAndUpdate(
    { _id: req.params.notificationId, userId: requestingUser._id },
    { isRead: true },
    { returnDocument: 'after' }
  );
  if (!notification) return res.status(404).json({ message: 'Notification not found' });
  res.json(notification);
}));

app.delete('/api/notifications/:notificationId', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const requestingUser = await User.findOne({ googleId: req.firebaseUser.uid }).select('_id').lean();
  if (!requestingUser) return res.status(403).json({ message: 'Forbidden' });
  const notification = await Notification.findOneAndDelete({ _id: req.params.notificationId, userId: requestingUser._id });
  if (!notification) return res.status(404).json({ message: 'Notification not found' });
  res.status(204).send();
}));

// Vendor can only access their own dashboard
app.get('/api/vendor/:vendorId/dashboard', requireFirebaseAuth, asyncHandler(async (req, res) => {
  if (req.firebaseUser.uid !== req.params.vendorId) {
    return res.status(403).json({ message: 'Forbidden: you can only access your own dashboard' });
  }

  const cafes   = await Cafe.find({ vendorId: req.params.vendorId }).select('_id');
  const cafeIds = cafes.map(c => c._id);
  const orderQuery = cafeIds.length ? { cafeId: { $in: cafeIds } } : {};

  const [summary] = await Order.aggregate([
    { $match: orderQuery },
    { $group: {
      _id: null,
      totalOrders:  { $sum: 1 },
      revenue:      { $sum: '$itemTotal' },
      activeOrders: { $sum: { $cond: [{ $in: ['$status', ['Pending', 'Preparing', 'Ready']] }, 1, 0] } },
      completed:    { $sum: { $cond: [{ $eq: ['$status', 'Completed'] }, 1, 0] } },
    }},
  ]);

  const recentOrders = await Order.find(orderQuery).sort({ createdAt: -1 }).limit(6);
  res.json({
    totalOrders:  summary?.totalOrders  || 0,
    revenue:      summary?.revenue      || 0,
    activeOrders: summary?.activeOrders || 0,
    completed:    summary?.completed    || 0,
    recentOrders,
  });
}));

// ── Error handlers ────────────────────────────────────────────────────────────
app.use((req, res) => res.status(404).json({ message: 'Route not found' }));

app.use((err, req, res, next) => {
  // Never leak internal details to clients
  console.error(`[${new Date().toISOString()}] ${req.method} ${req.path} —`, err.message);
  if (err.name === 'ValidationError') return res.status(400).json({ message: err.message });
  if (err.code === 11000)             return res.status(409).json({ message: 'Duplicate value' });
  if (err.statusCode)                 return res.status(err.statusCode).json({ message: err.message });
  if (err.message?.startsWith('CORS')) return res.status(403).json({ message: err.message });
  res.status(500).json({ message: 'Internal server error' });
});

const PORT = process.env.PORT || 5000;
let httpServer;
connectDatabase()
  .then(() => {
    httpServer = app.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
      // CODEX EDITS: Start background delivery only after Mongo and HTTP are ready.
      startNotificationOutboxWorker();
      if (typeof process.send === 'function') process.send('ready');
    });
  })
  .catch(err => { console.error('Failed to start server:', err.message); process.exit(1); });

// CODEX EDITS: Graceful PM2 reload stops new traffic, lets active requests
// finish, and closes shared clients without abandoning payment work mid-write.
async function gracefulShutdown(signal) {
  paymentLog('process.shutdown_started', { signal });
  if (notificationOutboxTimer) clearInterval(notificationOutboxTimer);
  const forceTimer = setTimeout(() => process.exit(1), 30 * 1000);
  forceTimer.unref?.();
  const closeResources = async () => {
    try {
      await mongoose.connection.close(false);
      await redisClient.quit();
      clearTimeout(forceTimer);
      process.exit(0);
    } catch (error) {
      paymentLog('process.shutdown_failed', { error: safeErrorMessage(error) }, 'error');
      process.exit(1);
    }
  };
  if (httpServer) httpServer.close(closeResources);
  else await closeResources();
}

process.once('SIGINT', () => gracefulShutdown('SIGINT'));
process.once('SIGTERM', () => gracefulShutdown('SIGTERM'));
