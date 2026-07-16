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
// Per-gateway fee structure, editable directly in MongoDB (see models/feeConfig).
const FeeConfig = require('./models/feeConfig');
// Operational settings (pickup window, ...) editable directly in MongoDB.
const AppConfig = require('./models/appConfig');
// Official Paytm checksum implementation (vendored, lib/paytmChecksum.js).
const PaytmChecksum = require('./lib/paytmChecksum');
// CODEX EDITS: Durable webhook receipts and notification outbox are shared by
// every PM2 worker through MongoDB.
const PaymentWebhookEvent = require('./models/paymentWebhookEvent');
const NotificationOutbox = require('./models/notificationOutbox');

const app = express();
console.log('Co-owner Bug Fixed');
// Trust the first proxy hop (AWS ALB / nginx) so express-rate-limit reads the real
// client IP from X-Forwarded-For instead of the proxy's internal address.
app.set('trust proxy', 1);
const allowedStatuses = ['Pending', 'Preparing', 'Ready', 'Completed', 'Rejected'];
let razorpayClient;
// Supported payment gateways. Paytm is the preferred option shown first and
// auto-selected in the app; Razorpay remains fully supported.
const PAYMENT_GATEWAYS = ['razorpay', 'paytm'];
const PREFERRED_GATEWAY = 'paytm';
// Seed values for the fee_configs collection and fallback if a document is
// ever deleted — matches the previously hardcoded 3% + ₹1.5 structure.
const FEE_DEFAULTS = {
  razorpay: { platformFeePercent: 3, platformFeeFlat: 0, convenienceFee: 1.5, active: true },
  paytm: { platformFeePercent: 3, platformFeeFlat: 0, convenienceFee: 1.5, active: true },
};
// Same-day pickup window, enforced server-side so no client (old builds
// included) can place an order outside it. Defaults to 11:00–13:30 IST; the
// live values come from the app_configs document {key: 'pickup_window'} and
// can be edited directly in MongoDB (reflects immediately, no restart):
//   db.app_configs.updateOne({key:'pickup_window'},
//     {$set:{'value.start':'11:00','value.end':'13:30'}})
const PICKUP_WINDOW_DEFAULTS = { start: '11:00', end: '13:30' };
// CODEX EDITS: Processing leases allow another worker to safely resume work
// after a crash without deleting the payment cart.
const PAYMENT_PROCESSING_LEASE_MS = 30 * 1000;
const WEBHOOK_PROCESSING_LEASE_MS = 60 * 1000;
const OUTBOX_PROCESSING_LEASE_MS = 60 * 1000;
// CODEX EDITS 2026-07-09 11:22:21 IST: A Razorpay checkout can be safely
// resumed only for 15 minutes; the Mongo document still remains for audit.
const PAYMENT_SESSION_ACTIVE_MS = 15 * 60 * 1000;
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

// Paytm posts its payment callback as application/x-www-form-urlencoded.
app.use(express.urlencoded({
  extended: false,
  limit: '1mb',
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
  // Paytm's payment callback gets the same treatment.
  skip: req => req.path === '/razorpay/webhook' || req.path === '/paytm/callback',
});

// Strict limit for order writes (place/confirm/status) — 10 per minute
const orderLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  message: { message: 'Too many order requests, please slow down.' },
  store: new RedisStore({ sendCommand: (...args) => redisClient.call(...args), prefix: 'rl:order:' }),
  // CODEX EDITS: Reconciliation has its own authenticated read-style limiter.
  // /fees is a public read hit on every cart/checkout open — never write-limited.
  skip: req => req.path === '/reconcile' || req.path === '/fees',
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

// ── Paytm gateway helpers ─────────────────────────────────────────────────────

function getPaytmConfig() {
  const mid = process.env.PAYTM_MID;
  const key = process.env.PAYTM_MERCHANT_KEY;
  if (!mid || !key) {
    const error = new Error('Paytm credentials are not configured');
    error.statusCode = 503;
    throw error;
  }
  const baseUrl = (process.env.PAYTM_BASE_URL || 'https://securestage.paytmpayments.com')
    .replace(/\/+$/, '');
  return {
    mid,
    key,
    website: process.env.PAYTM_WEBSITE || 'WEBSTAGING',
    baseUrl,
    // Staging hosts drive the SDK's isStaging flag and webview-only checkout.
    isStaging: /securestage\.|securegw-stage\./.test(baseUrl),
  };
}

function makePaytmOrderId() {
  return `PTM${Date.now()}${Math.floor(Math.random() * 900 + 100)}`;
}

async function paytmApiPost(url, payload, timeoutMs = 20000) {
  if (typeof fetch !== 'function') {
    const error = new Error('Paytm integration requires Node 18+ (global fetch)');
    error.statusCode = 503;
    throw error;
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    const data = await response.json().catch(() => null);
    if (!response.ok || !data) {
      throw new Error(`Paytm API responded with HTTP ${response.status}`);
    }
    return data;
  } finally {
    clearTimeout(timer);
  }
}

// Creates the Paytm transaction token that opens checkout. The signature is
// computed over the exact JSON body with the merchant key (official checksum).
async function createPaytmTransactionToken(orderId, amount, { custId, email, callbackUrl }) {
  const cfg = getPaytmConfig();
  const body = {
    requestType: 'Payment',
    mid: cfg.mid,
    websiteName: cfg.website,
    orderId,
    callbackUrl,
    txnAmount: { value: toMoney(amount).toFixed(2), currency: 'INR' },
    userInfo: {
      custId: String(custId || 'guest').slice(0, 64),
      ...(email ? { email: String(email).slice(0, 100) } : {}),
    },
  };
  const signature = await PaytmChecksum.generateSignature(JSON.stringify(body), cfg.key);
  const data = await paytmApiPost(
    `${cfg.baseUrl}/theia/api/v1/initiateTransaction?mid=${encodeURIComponent(cfg.mid)}&orderId=${encodeURIComponent(orderId)}`,
    { body, head: { signature } }
  );
  const resultStatus = data?.body?.resultInfo?.resultStatus;
  const txnToken = data?.body?.txnToken;
  if (resultStatus !== 'S' || !txnToken) {
    paymentLog('payment.paytm_initiate_failed', {
      paytmOrderId: orderId,
      resultCode: data?.body?.resultInfo?.resultCode,
      resultMsg: data?.body?.resultInfo?.resultMsg,
    }, 'error');
    const error = new Error(
      data?.body?.resultInfo?.resultMsg || 'Paytm transaction could not be initiated'
    );
    error.statusCode = 502;
    throw error;
  }
  return { txnToken, config: cfg };
}

// Authoritative payment truth for Paytm — the Transaction Status API. Client
// results and callback params are never trusted without this check.
async function fetchPaytmTransactionStatus(orderId) {
  const cfg = getPaytmConfig();
  const body = { mid: cfg.mid, orderId };
  const signature = await PaytmChecksum.generateSignature(JSON.stringify(body), cfg.key);
  const data = await paytmApiPost(`${cfg.baseUrl}/v3/order/status`, { body, head: { signature } });
  const info = data?.body?.resultInfo || {};
  return {
    resultStatus: String(info.resultStatus || 'UNKNOWN'),
    resultCode: String(info.resultCode || ''),
    resultMsg: String(info.resultMsg || ''),
    txnId: String(data?.body?.txnId || ''),
    txnAmount: data?.body?.txnAmount,
    orderId: String(data?.body?.orderId || orderId),
  };
}

// Mirror of assertCapturedPaymentIntegrity for Paytm: fulfil only when the
// gateway-confirmed amount and order id match the server-side cart exactly.
function assertPaytmCapturedIntegrity(paymentSession, statusResult) {
  const expected = toMoney(paymentSession.cart.total);
  const paid = toMoney(statusResult.txnAmount);
  if (paid !== expected || statusResult.orderId !== paymentSession.razorpayOrderId) {
    const error = new Error('Captured Paytm payment does not match the initiated order');
    error.statusCode = 409;
    throw error;
  }
}

// ── Fee configuration (DB-driven, real-time) ─────────────────────────────────

// Insert default fee documents once; existing documents are never overwritten,
// so direct DB edits survive every deploy/restart.
async function seedFeeConfigs() {
  for (const [gateway, defaults] of Object.entries(FEE_DEFAULTS)) {
    await FeeConfig.updateOne(
      { gateway },
      { $setOnInsert: { gateway, ...defaults } },
      { upsert: true }
    );
  }
  // Pickup window document — inserted once, then owned by direct DB edits.
  await AppConfig.updateOne(
    { key: 'pickup_window' },
    { $setOnInsert: { key: 'pickup_window', value: { ...PICKUP_WINDOW_DEFAULTS } } },
    { upsert: true }
  );
}

// Read live on every request — a direct MongoDB edit reflects immediately in
// both the fees endpoint and the amounts actually charged at initiation.
async function getFeeConfig(gateway) {
  const doc = await FeeConfig.findOne({ gateway }).lean();
  if (doc) return doc;
  return { gateway, ...(FEE_DEFAULTS[gateway] || FEE_DEFAULTS.razorpay) };
}

function computeOrderFees(itemTotal, feeConfig) {
  const percent = Number(feeConfig.platformFeePercent) || 0;
  const flat = Number(feeConfig.platformFeeFlat) || 0;
  const platformFee = toMoney(itemTotal * (percent / 100) + flat);
  const convenienceFee = toMoney(
    feeConfig.convenienceFee === undefined ? 1.5 : feeConfig.convenienceFee
  );
  return { platformFee, convenienceFee };
}

// ── Pickup window validation ──────────────────────────────────────────────────

function parseHHMM(value) {
  const match = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(String(value || '').trim());
  if (!match) return null;
  return Number(match[1]) * 60 + Number(match[2]);
}

function formatMinutes12h(minutes) {
  const h24 = Math.floor(minutes / 60);
  const m = minutes % 60;
  const period = h24 < 12 ? 'AM' : 'PM';
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  return `${h12}:${String(m).padStart(2, '0')} ${period}`;
}

// Live-read the pickup window from app_configs; malformed or missing values
// fall back to the defaults so ordering is never bricked by a bad edit.
async function getPickupWindow() {
  let start = PICKUP_WINDOW_DEFAULTS.start;
  let end = PICKUP_WINDOW_DEFAULTS.end;
  try {
    const doc = await AppConfig.findOne({ key: 'pickup_window' }).lean();
    if (doc?.value?.start !== undefined) start = doc.value.start;
    if (doc?.value?.end !== undefined) end = doc.value.end;
  } catch {
    // Fall through to defaults.
  }
  let startMinutes = parseHHMM(start);
  let endMinutes = parseHHMM(end);
  if (startMinutes === null || endMinutes === null || startMinutes > endMinutes) {
    startMinutes = parseHHMM(PICKUP_WINDOW_DEFAULTS.start);
    endMinutes = parseHHMM(PICKUP_WINDOW_DEFAULTS.end);
  }
  return {
    start: formatMinutes12h(startMinutes),
    end: formatMinutes12h(endMinutes),
    startMinutes,
    endMinutes,
  };
}

// pickupTime arrives as the device's local wall-clock ISO string
// (YYYY-MM-DDTHH:mm:ss). Components are compared against IST "today" directly —
// never via Date parsing — so the server's own timezone cannot skew the rule.
async function validatePickupWindow(pickupTime) {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(String(pickupTime || ''));
  if (!match) return 'A valid pickup time is required.';
  const [, year, month, day, hour, minute] = match;
  const istToday = new Date(Date.now() + 330 * 60 * 1000).toISOString().slice(0, 10);
  if (`${year}-${month}-${day}` !== istToday) {
    return 'Pickup must be scheduled for today.';
  }
  const window = await getPickupWindow();
  const minutes = Number(hour) * 60 + Number(minute);
  if (minutes < window.startMinutes || minutes > window.endMinutes) {
    return `Pickup time must be between ${window.start} and ${window.end}.`;
  }
  return null;
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

// Minimal co-owner fix: a vendor may manage a cafe either as the primary
// Cafe.vendorId Firebase UID or as a vendor user whose assigned cafeId matches.
async function canManageCafe(firebaseUser, cafe) {
  if (!firebaseUser || !cafe) return false;
  if (cafe.vendorId === firebaseUser.uid) return true;
  const user = await User.findOne({ googleId: firebaseUser.uid })
    .select('role cafeId')
    .lean();
  return user?.role === 'vendor' &&
    user.cafeId &&
    String(user.cafeId) === String(cafe._id);
}

async function manageableCafeIds(firebaseUser, explicitVendorId = null) {
  const user = await User.findOne({ googleId: firebaseUser.uid })
    .select('role cafeId vendorId')
    .lean();
  const vendorIds = [firebaseUser.uid];
  if (
    explicitVendorId &&
    explicitVendorId !== firebaseUser.uid &&
    user?.vendorId === explicitVendorId
  ) {
    vendorIds.push(explicitVendorId);
  }
  const cafes = await Cafe.find({
    $or: [
      { vendorId: { $in: vendorIds } },
      ...(user?.role === 'vendor' && user.cafeId ? [{ _id: user.cafeId }] : []),
    ],
  }).select('_id').lean();
  return cafes.map(c => c._id.toString());
}

// Verify the authenticated user is allowed to manage this cafe.
async function requireCafeOwner(req, res, next) {
  try {
    const cafeId = req.params.id || req.params.cafeId || req.body?.cafeId;
    if (!mongoose.Types.ObjectId.isValid(cafeId)) {
      return res.status(400).json({ message: 'Invalid cafe ID' });
    }
    const cafe = await Cafe.findById(cafeId).select('vendorId');
    if (!cafe) return res.status(404).json({ message: 'Cafe not found' });
    if (!await canManageCafe(req.firebaseUser, cafe)) {
      return res.status(403).json({ message: 'Forbidden: you do not own this cafe' });
    }
    req.cafe = cafe;
    next();
  } catch (err) {
    next(err);
  }
}

// Verify the authenticated user can manage the menu item's cafe.
async function requireMenuItemOwner(req, res, next) {
  try {
    const itemId = req.params.id;
    if (!mongoose.Types.ObjectId.isValid(itemId)) {
      return res.status(400).json({ message: 'Invalid menu item ID' });
    }
    const item = await MenuItem.findById(itemId).select('cafeId');
    if (!item) return res.status(404).json({ message: 'Menu item not found' });
    const cafe = await Cafe.findById(item.cafeId).select('vendorId');
    if (!cafe || !await canManageCafe(req.firebaseUser, cafe)) {
      return res.status(403).json({ message: 'Forbidden: you do not own this menu item' });
    }
    req.menuItem = item;
    next();
  } catch (err) {
    next(err);
  }
}

// Verify the authenticated user can manage the order's cafe.
async function requireOrderCafeOwner(req, res, next) {
  try {
    const order = await Order.findOne({ orderId: req.params.orderId }).select('cafeId');
    if (!order) return res.status(404).json({ message: 'Order not found' });
    const cafe = await Cafe.findById(order.cafeId).select('vendorId');
    if (!cafe || !await canManageCafe(req.firebaseUser, cafe)) {
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
    FeeConfig.init(),
    AppConfig.init(),
  ]);
  // Seed per-gateway fee documents (no-op when they already exist).
  await seedFeeConfigs();
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
  // CODEX EDITS 2026-07-09 11:22:21 IST: Backfill the 15-minute active
  // checkout window from each session's original creation time. This makes
  // old cancelled sessions stop blocking new carts immediately after deploy.
  const sessionsWithoutActiveUntil = await PaymentSession.find(
    { activeUntil: { $exists: false } },
    { _id: 1, createdAt: 1 }
  ).lean();
  if (sessionsWithoutActiveUntil.length > 0) {
    await PaymentSession.bulkWrite(
      sessionsWithoutActiveUntil.map(session => {
        const createdAt = session.createdAt instanceof Date
          ? session.createdAt
          : new Date();
        return {
          updateOne: {
            filter: { _id: session._id },
            update: {
              $set: {
                activeUntil: new Date(createdAt.getTime() + PAYMENT_SESSION_ACTIVE_MS),
              },
            },
          },
        };
      }),
      { ordered: false }
    );
  }
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
    const vendorId = user.cafeId && user.vendorId ? user.vendorId : decodedToken.uid;
    if (!user.vendorId) {
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
    { returnDocument: 'after', updatePipeline: true }
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
    { returnDocument: 'after', updatePipeline: true }
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
  if (!await canManageCafe(req.firebaseUser, cafe)) {
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
  if (!await canManageCafe(req.firebaseUser, cafe)) {
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

// Public, read live from MongoDB: the app fetches this on cart/checkout open so
// direct fee_configs edits reflect in real time without a deploy.
app.get('/api/payment/fees', asyncHandler(async (req, res) => {
  const [configs, pickupWindow] = await Promise.all([
    Promise.all(PAYMENT_GATEWAYS.map(gateway => getFeeConfig(gateway))),
    getPickupWindow(),
  ]);
  res.json({
    preferredGateway: PREFERRED_GATEWAY,
    gateways: configs.map(config => ({
      gateway: config.gateway,
      active: config.active !== false,
      platformFeePercent: Number(config.platformFeePercent) || 0,
      platformFeeFlat: Number(config.platformFeeFlat) || 0,
      convenienceFee: Number(config.convenienceFee) || 0,
    })),
    // Same-day pickup window (minutes since midnight + display labels) — the
    // app builds its slot picker from this instead of hardcoded values.
    pickupWindow: {
      startMinutes: pickupWindow.startMinutes,
      endMinutes: pickupWindow.endMinutes,
      startLabel: pickupWindow.start,
      endLabel: pickupWindow.end,
    },
  });
}));

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

  // Gateway selection — Paytm is the preferred default in the app; requests
  // from older builds that omit it keep the original Razorpay behaviour.
  const gateway = String(req.body.gateway || 'razorpay').toLowerCase();
  if (!PAYMENT_GATEWAYS.includes(gateway)) {
    return res.status(400).json({ message: `gateway must be one of: ${PAYMENT_GATEWAYS.join(', ')}` });
  }

  // Same-day pickup window (DB-configurable), enforced regardless of client version.
  const pickupError = await validatePickupWindow(pickupTime);
  if (pickupError) return res.status(400).json({ message: pickupError });

  const itemTotal = toMoney(normalizedItems.reduce((s, i) => s + i.price * i.qty, 0));
  // Fees come from the fee_configs collection (live read) — see models/feeConfig.
  const feeConfig = await getFeeConfig(gateway);
  if (feeConfig.active === false) {
    return res.status(409).json({ message: 'This payment method is currently unavailable. Please choose another.' });
  }
  const { platformFee, convenienceFee } = computeOrderFees(itemTotal, feeConfig);
  // Discounts are not accepted from the client — there is no server-validated coupon
  // system yet. Forcing 0 prevents price manipulation via an arbitrary discount value.
  const discountAmt    = 0;
  const total          = toMoney(itemTotal + platformFee + convenienceFee);
  if (total <= 0) return res.status(400).json({ message: 'Order total must be greater than zero' });

  // Server-side cart persisted with the session — survives crashes and
  // multi-instance deployments. Shared by both gateways.
  const cart = {
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
  };
  // Authoritative fee breakdown echoed to the client so the summary it renders
  // always matches the amount actually charged.
  const fees = { gateway, itemTotal, platformFee, convenienceFee, discount: discountAmt, total };

  if (gateway === 'paytm') {
    const paytmConfig = getPaytmConfig();
    const paytmOrderId = makePaytmOrderId();
    const channel = req.body.channel === 'web' ? 'web' : 'app';
    let callbackUrl;
    if (channel === 'web') {
      // Web checkout is a full-page redirect: Paytm must return the browser to
      // our callback page, which finalises the order and links back to the app.
      const publicBase = (process.env.PUBLIC_BASE_URL || '').replace(/\/+$/, '');
      if (!publicBase) {
        return res.status(503).json({ message: 'Paytm web payments are not configured (PUBLIC_BASE_URL missing)' });
      }
      callbackUrl = `${publicBase}/api/paytm/callback`;
    } else {
      // All-in-One SDK flow: Paytm's own callback returns the result to the app;
      // the Transaction Status API remains the only source of truth server-side.
      callbackUrl = `${paytmConfig.baseUrl}/theia/paytmCallback?ORDER_ID=${paytmOrderId}`;
    }

    const { txnToken } = await createPaytmTransactionToken(paytmOrderId, total, {
      custId: req.firebaseUser.uid,
      email: cart.customerEmail,
      callbackUrl,
    });

    await PaymentSession.create({
      razorpayOrderId: paytmOrderId,
      provider: 'paytm',
      status: 'pending',
      activeUntil: new Date(Date.now() + PAYMENT_SESSION_ACTIVE_MS),
      expiresAt: new Date(Date.now() + PAYMENT_SESSION_RETENTION_MS),
      paytm: { txnToken, callbackUrl, channel },
      cart,
    });

    paymentLog('payment.initiated', {
      gateway: 'paytm',
      providerOrderId: paytmOrderId,
      amountPaise: toPaise(total),
      cafeId: resolvedCafeId ? String(resolvedCafeId) : '',
    });

    return res.json({
      gateway: 'paytm',
      fees,
      paytmOrder: {
        orderId: paytmOrderId,
        txnToken,
        amount: total.toFixed(2),
        currency: 'INR',
        mid: paytmConfig.mid,
        callbackUrl,
        isStaging: paytmConfig.isStaging,
        showPaymentPageUrl: `${paytmConfig.baseUrl}/theia/api/v1/showPaymentPage`,
      },
    });
  }

  const receipt      = `init_${makeOrderId()}`;
  const razorpayOrder = await createRazorpayOrder(receipt, total);

  // Persist cart to MongoDB — survives crashes and multi-instance deployments.
  await PaymentSession.create({
    razorpayOrderId: razorpayOrder.id,
    provider: 'razorpay',
    // CODEX EDITS: Explicit state/expiry keeps old and new workers compatible
    // during a rolling PM2 reload.
    status: 'pending',
    // CODEX EDITS 2026-07-09 11:22:21 IST: This order can be resumed/retried
    // for 15 minutes only; after that a changed cart may start a new payment.
    activeUntil: new Date(Date.now() + PAYMENT_SESSION_ACTIVE_MS),
    expiresAt: new Date(Date.now() + PAYMENT_SESSION_RETENTION_MS),
    cart,
  });

  // CODEX EDITS: Correlate initiation without logging cart contents or PII.
  paymentLog('payment.initiated', {
    gateway: 'razorpay',
    razorpayOrderId: razorpayOrder.id,
    amountPaise: razorpayOrder.amount,
    cafeId: resolvedCafeId ? String(resolvedCafeId) : '',
  });

  // Return key ID so the Flutter client doesn't need to hardcode it.
  res.json({ gateway: 'razorpay', fees, razorpayOrder, razorpayKeyId: process.env.RAZORPAY_KEY_ID });
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
      provider: paymentSession.provider === 'paytm' ? 'Paytm' : 'Razorpay',
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

// CODEX EDITS 2026-07-09 11:22:21 IST: Compute the operational payment
// window even for pre-migration sessions that may not have activeUntil stored.
function paymentSessionActiveUntil(paymentSession) {
  if (paymentSession?.activeUntil instanceof Date) return paymentSession.activeUntil;
  const createdAt = paymentSession?.createdAt instanceof Date
    ? paymentSession.createdAt
    : new Date();
  return new Date(createdAt.getTime() + PAYMENT_SESSION_ACTIVE_MS);
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

// Paytm counterpart of the Razorpay reconcile flow below. Same response
// contract (captured/pending/expired) so the app's recovery machinery is
// shared. Differences: Paytm truth comes from the Transaction Status API, and
// a TXN_FAILURE order id is terminal — it can never be retried, so the client
// must start a fresh payment.
async function reconcilePaytmSession(res, paymentSession, sdkError) {
  const paytmOrderId = paymentSession.razorpayOrderId;
  let statusResult;
  try {
    statusResult = await fetchPaytmTransactionStatus(paytmOrderId);
  } catch (error) {
    // A gateway/network outage is indeterminate, never a customer-facing failure.
    paymentLog('payment.reconcile_gateway_unavailable', {
      gateway: 'paytm',
      providerOrderId: paytmOrderId,
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

  if (statusResult.resultStatus === 'TXN_SUCCESS') {
    assertPaytmCapturedIntegrity(paymentSession, statusResult);
    const order = await createOrderFromPaymentSession(
      paytmOrderId,
      statusResult.txnId,
      'server_reconcile'
    );
    if (order) return res.json({ state: 'captured', order });
    // A peer worker holds the processing lease — report pending, never failure.
    return res.json({
      state: 'pending',
      gatewayStatus: 'captured_processing',
      retryable: true,
      message: 'Payment is awaiting final confirmation',
    });
  }

  const activeUntil = paymentSessionActiveUntil(paymentSession);
  const failed = statusResult.resultStatus === 'TXN_FAILURE';
  if (failed || activeUntil <= new Date()) {
    await PaymentSession.updateOne(
      { _id: paymentSession._id, status: { $ne: 'completed' } },
      {
        $set: {
          status: 'failed',
          activeUntil,
          lastError: {
            code: failed ? statusResult.resultCode || 'txn_failure' : 'session_expired',
            message: failed
              ? statusResult.resultMsg || 'Paytm reported the transaction as failed'
              : 'Payment session expired with no successful Paytm transaction',
            at: new Date(),
            source: 'server_reconcile',
          },
        },
      }
    );
    paymentLog('payment.reconcile_terminal', {
      gateway: 'paytm',
      providerOrderId: paytmOrderId,
      gatewayStatus: statusResult.resultStatus,
      resultCode: statusResult.resultCode,
    }, 'warn');
    return res.json({
      state: 'expired',
      retryable: false,
      message: failed
        ? 'Payment failed. No amount was captured — please start a new payment.'
        : 'Payment session expired. Please start a new payment.',
    });
  }

  // PENDING / NO_RECORD_FOUND inside the active window: the same order can be
  // resumed with its original txnToken (valid for the same 15 minutes).
  const paytmConfig = getPaytmConfig();
  paymentLog('payment.reconcile_pending', {
    gateway: 'paytm',
    providerOrderId: paytmOrderId,
    gatewayStatus: statusResult.resultStatus,
    sdkErrorCode: sdkError?.code,
  });
  return res.json({
    state: 'pending',
    gatewayStatus: statusResult.resultStatus.toLowerCase(),
    retryable: true,
    paytmCheckout: {
      orderId: paytmOrderId,
      txnToken: paymentSession.paytm?.txnToken || '',
      amount: toMoney(paymentSession.cart.total).toFixed(2),
      currency: 'INR',
      mid: paytmConfig.mid,
      callbackUrl: paymentSession.paytm?.callbackUrl || '',
      isStaging: paytmConfig.isStaging,
      showPaymentPageUrl: `${paytmConfig.baseUrl}/theia/api/v1/showPaymentPage`,
    },
    message: 'Payment is awaiting final confirmation',
  });
}

// CODEX EDITS: Authoritative reconciliation is used for SDK errors, lifecycle
// resumes, cold starts, and safe retries of the same Razorpay order.
app.post(
  '/api/payment/reconcile',
  requireFirebaseAuth,
  paymentReconcileLimiter,
  asyncHandler(async (req, res) => {
    // Accepts either a Razorpay order id (order_...) or a Paytm merchant order
    // id (PTM...). The client keeps sending it under the historical param name.
    const razorpayOrderId = String(
      req.body?.razorpay_order_id || req.body?.provider_order_id || ''
    ).trim();
    if (!/^(order_[A-Za-z0-9]+|PTM[0-9]+)$/.test(razorpayOrderId)) {
      return res.status(400).json({ message: 'A valid payment order id is required' });
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

    // Paytm sessions reconcile against the Transaction Status API.
    if (paymentSession.provider === 'paytm') {
      return reconcilePaytmSession(res, paymentSession, sdkError);
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

    const activeUntil = paymentSessionActiveUntil(paymentSession);
    if (activeUntil <= new Date()) {
      // CODEX EDITS 2026-07-09 11:22:21 IST: If Razorpay has no captured
      // payment after 15 minutes, expire this checkout so the app can clear
      // the local pending pointer and create a fresh order for the current cart.
      await PaymentSession.updateOne(
        { _id: paymentSession._id, status: { $ne: 'completed' } },
        {
          $set: {
            status: 'failed',
            activeUntil,
            lastError: {
              code: 'session_expired',
              message: 'Payment session expired after 15 minutes with no captured payment',
              at: new Date(),
              source: 'server_reconcile',
            },
          },
        }
      );
      paymentLog('payment.reconcile_expired_active_window', {
        razorpayOrderId,
        gatewayStatus: String(razorpayOrder?.status || 'created'),
        paymentAttempts: payments.length,
        activeUntil: activeUntil.toISOString(),
      }, 'warn');
      return res.json({
        state: 'expired',
        retryable: false,
        message: 'Payment session expired. Please start a new payment.',
      });
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

// Minimal HTML page returned by the Paytm callback. In the web flow the user's
// browser lands here after Paytm's redirect; app-flow server notifications
// simply ignore the body. Links (and auto-redirects) back to the web app.
function paytmCallbackPage(outcome, orderId) {
  const appUrl = (process.env.CLIENT_ORIGIN || '').split(',').map(o => o.trim()).filter(Boolean)[0] || '';
  const copy = {
    success: ['Payment received 🎉', 'Your payment was successful. Return to BenchBites to see your order token.'],
    pending: ['Payment processing…', 'Your payment is being verified. Return to BenchBites — your order will appear once it is confirmed.'],
    failed: ['Payment failed', 'No amount was captured. Return to BenchBites and try the payment again.'],
    invalid: ['Invalid request', 'This payment callback could not be verified.'],
  }[outcome] || ['Payment update', 'Return to BenchBites to continue.'];
  const safeOrder = String(orderId || '').replace(/[^A-Za-z0-9_-]/g, '');
  return `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${copy[0]} — BenchBites</title>
<style>body{font-family:system-ui,sans-serif;background:#f4f6f9;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.card{background:#fff;border-radius:16px;padding:32px;max-width:360px;text-align:center;box-shadow:0 4px 20px rgba(0,0,0,.08)}
h1{font-size:20px;color:#0f172a;margin:0 0 8px}p{font-size:14px;color:#475569;line-height:1.5}
a{display:inline-block;margin-top:16px;background:#0F4CFF;color:#fff;text-decoration:none;padding:10px 24px;border-radius:10px;font-weight:600}
.oid{font-size:12px;color:#94a3b8;margin-top:14px}</style>
${appUrl ? `<script>setTimeout(function(){window.location.replace(${JSON.stringify(appUrl)});},2500);</script>` : ''}
</head><body><div class="card"><h1>${copy[0]}</h1><p>${copy[1]}</p>
${appUrl ? `<a href="${appUrl}">Return to app</a>` : ''}
${safeOrder ? `<div class="oid">Ref: ${safeOrder}</div>` : ''}
</div></body></html>`;
}

// Paytm payment callback — the web-flow browser redirect and any dashboard-
// configured server notification both land here as a form POST with a
// CHECKSUMHASH. Signature is verified with the merchant key, the event is
// leased through PaymentWebhookEvent exactly like Razorpay webhooks, and the
// order is only ever fulfilled from the Transaction Status API — callback
// params alone are never trusted. No Firebase auth: checksum authenticates.
app.post('/api/paytm/callback', webhookLimiter, asyncHandler(async (req, res) => {
  const params = { ...(req.body || {}) };
  const checksum = String(params.CHECKSUMHASH || '');
  const paytmOrderId = String(params.ORDERID || '');
  res.set('Content-Type', 'text/html; charset=utf-8');

  if (!paytmOrderId || !checksum) {
    return res.status(400).send(paytmCallbackPage('invalid', paytmOrderId));
  }

  let paytmConfig;
  try {
    paytmConfig = getPaytmConfig();
  } catch {
    return res.status(503).send(paytmCallbackPage('invalid', paytmOrderId));
  }

  let signatureValid = false;
  try {
    // verifySignature strips CHECKSUMHASH from the params object itself.
    signatureValid = await PaytmChecksum.verifySignature(params, paytmConfig.key, checksum);
  } catch {
    signatureValid = false;
  }
  if (!signatureValid) {
    paymentLog('payment.paytm_callback_invalid_signature', { providerOrderId: paytmOrderId }, 'warn');
    return res.status(400).send(paytmCallbackPage('invalid', paytmOrderId));
  }

  const callbackStatus = String(params.STATUS || 'UNKNOWN');
  const callbackTxnId = String(params.TXNID || '');
  const eventKey = `paytm:${crypto.createHash('sha256').update(req.rawBody || Buffer.from(paytmOrderId)).digest('hex')}`;
  try {
    await PaymentWebhookEvent.updateOne(
      { eventKey },
      {
        $setOnInsert: {
          eventKey,
          eventType: `paytm.${callbackStatus}`,
          razorpayOrderId: paytmOrderId,
          razorpayPaymentId: callbackTxnId,
          status: 'received',
        },
      },
      { upsert: true }
    );
  } catch (error) {
    if (error?.code !== 11000) throw error;
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
    paymentLog('payment.webhook_duplicate', { eventKey, event: `paytm.${callbackStatus}`, providerOrderId: paytmOrderId });
    return res.send(paytmCallbackPage(callbackStatus === 'TXN_SUCCESS' ? 'success' : 'pending', paytmOrderId));
  }

  let outcome = 'pending';
  try {
    // Authoritative check — never fulfil from the posted params.
    const statusResult = await fetchPaytmTransactionStatus(paytmOrderId);
    if (statusResult.resultStatus === 'TXN_SUCCESS') {
      const existingOrder = await Order.findOne({ 'payment.providerOrderId': paytmOrderId });
      if (!existingOrder) {
        const paymentSession = await PaymentSession.findOne({ razorpayOrderId: paytmOrderId });
        if (!paymentSession) throw new Error('Payment session not found for Paytm callback');
        assertPaytmCapturedIntegrity(paymentSession, statusResult);
        const order = await createOrderFromPaymentSession(
          paytmOrderId,
          statusResult.txnId,
          'paytm_callback'
        );
        if (!order) throw new Error('Paid order is still unavailable after processing lease');
      }
      outcome = 'success';
    } else if (statusResult.resultStatus === 'TXN_FAILURE') {
      outcome = 'failed';
    }

    await PaymentWebhookEvent.updateOne(
      { _id: receipt._id },
      { $set: { status: 'processed', processedAt: new Date(), processingStartedAt: null, lastError: '' } }
    );
    paymentLog('payment.webhook_processed', {
      eventKey,
      event: `paytm.${callbackStatus}`,
      providerOrderId: paytmOrderId,
      gatewayStatus: statusResult.resultStatus,
      attempts: receipt.attempts,
    });
  } catch (error) {
    await PaymentWebhookEvent.updateOne(
      { _id: receipt._id },
      { $set: { status: 'failed', processingStartedAt: null, lastError: safeErrorMessage(error) } }
    );
    paymentLog('payment.webhook_failed', {
      eventKey,
      event: `paytm.${callbackStatus}`,
      providerOrderId: paytmOrderId,
      error: safeErrorMessage(error),
    }, 'error');
    // Unlike Razorpay's webhook there is no retrying caller behind this POST —
    // the browser is. Reconciliation from the app completes the recovery, so
    // always show the neutral pending page instead of an error dump.
    outcome = 'pending';
  }

  res.send(paytmCallbackPage(outcome, paytmOrderId));
}));

// Users occasionally refresh or revisit the callback URL — show the neutral
// page instead of a 404.
app.get('/api/paytm/callback', webhookLimiter, (req, res) => {
  res.set('Content-Type', 'text/html; charset=utf-8');
  res.send(paytmCallbackPage('pending', String(req.query?.ORDERID || '')));
});

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
  const ownedCafeIds = await manageableCafeIds(req.firebaseUser);

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
    const cafe = await Cafe.findById(order.cafeId).select('vendorId');
    isVendorOwner = !!cafe && await canManageCafe(req.firebaseUser, cafe);
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
  const cafeIds = (await manageableCafeIds(req.firebaseUser, req.params.vendorId))
    .map(id => new mongoose.Types.ObjectId(id));
  if (req.firebaseUser.uid !== req.params.vendorId && cafeIds.length === 0) {
    return res.status(403).json({ message: 'Forbidden: you can only access your own dashboard' });
  }

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
