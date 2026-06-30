const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const crypto = require('crypto');
const helmet = require('helmet');
const { rateLimit, ipKeyGenerator } = require('express-rate-limit');
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

const app = express();
const allowedStatuses = ['Pending', 'Preparing', 'Ready', 'Completed', 'Rejected'];
let razorpayClient;
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

app.use(express.json({ limit: '5mb' }));

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
const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 min
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Too many requests, please try again later.' },
});

// Strict limit for order writes (place/confirm/status) — 10 per minute
const orderLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  message: { message: 'Too many order requests, please slow down.' },
});
// Generous limit for order reads — per Firebase UID so accounts don't share a bucket
const orderReadLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 120,
  keyGenerator: (req) => req.firebaseUser?.uid || ipKeyGenerator(req),
  message: { message: 'Too many requests, please slow down.' },
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  message: { message: 'Too many auth requests, please try again later.' },
});

app.use('/api/', generalLimiter);
app.use('/api/payment', orderLimiter);
app.use('/api/auth', authLimiter);

// ── Helpers ───────────────────────────────────────────────────────────────────
function asyncHandler(fn) {
  return (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
}

function makeOrderId() {
  return `NRK${Date.now()}${Math.floor(Math.random() * 900 + 100)}`;
}

function toMoney(value) {
  return Math.round(Number(value || 0) * 100) / 100;
}

async function generateTokenNumber(cafeId) {
  const ist = new Date(Date.now() + 330 * 60 * 1000);
  const today = ist.toISOString().slice(0, 10);
  const key = `${cafeId}:${today}`;
  const doc = await CafeCounter.findOneAndUpdate(
    { key },
    { $inc: { seq: 1 } },
    { new: true, upsert: true }
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
    if (tokens.length === 0) return;
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
  } catch (err) {
    console.warn('Push notification failed:', err.message);
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
  console.log('MongoDB connected');
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
      user = await User.findByIdAndUpdate(user._id, { vendorId }, { new: true }).populate('cafeId');
    }
    if (!user.cafeId) {
      let cafe = await Cafe.findOne({ vendorId });
      if (!cafe) {
        const baseSlug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '').slice(0, 40) || `vendor-${Date.now()}`;
        const slug = `${baseSlug}-${crypto.randomBytes(3).toString('hex')}`; // Collision-safe
        cafe = await Cafe.create({ name: `${name}'s Cafe`, slug, cuisine: 'General', description: '', location: '', city: '', pin: '', vendorId, active: true });
      }
      user = await User.findByIdAndUpdate(user._id, { cafeId: cafe._id, vendorId }, { new: true }).populate('cafeId');
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
  const user = await User.findByIdAndUpdate(req.params.id, allowed, { new: true, runValidators: true }).populate('cafeId');
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
  const cafe = await Cafe.findByIdAndUpdate(req.params.id, safeBody, { new: true, runValidators: true });
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
  const cafe = await Cafe.findById(req.params.id);
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });

  const existing = cafe.ratings.find(r => r.userId === userId);
  if (existing) {
    existing.stars = stars;
  } else {
    cafe.ratings.push({ userId, stars });
  }
  const total = cafe.ratings.reduce((s, r) => s + r.stars, 0);
  cafe.rating  = Math.round((total / cafe.ratings.length) * 10) / 10;
  cafe.reviews = cafe.ratings.length;
  await cafe.save();
  audit('rating.submitted', userId, 'cafe', req.params.id, { stars, updated: !!existing });
  res.json({ rating: cafe.rating, reviews: cafe.reviews });
}));

app.delete('/api/cafes/:id/review', requireFirebaseAuth, validateObjectId('id'), asyncHandler(async (req, res) => {
  const userId = req.firebaseUser.uid; // Always from token
  const cafe = await Cafe.findById(req.params.id);
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });

  cafe.ratings = cafe.ratings.filter(r => r.userId !== userId);
  const total  = cafe.ratings.reduce((s, r) => s + r.stars, 0);
  cafe.rating  = cafe.ratings.length ? Math.round((total / cafe.ratings.length) * 10) / 10 : 4;
  cafe.reviews = cafe.ratings.length;
  await cafe.save();
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
  const item = await MenuItem.findByIdAndUpdate(req.params.id, safeBody, { new: true, runValidators: true });
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
    cart: {
      userId: resolvedUserId, customerName, customerEmail,
      cafeId: resolvedCafeId, cafeteriaName,
      items: normalizedItems,
      itemTotal, platformFee, convenienceFee, discount: discountAmt, total,
      location: location || 'Pickup counter',
      pickupTime: pickupTime || '',
      notes: notes || '',
    },
  });

  // Return key ID so the Flutter client doesn't need to hardcode it.
  res.json({ razorpayOrder, razorpayKeyId: process.env.RAZORPAY_KEY_ID });
}));

// Step 2: verify HMAC, retrieve cart from DB, create order.
app.post('/api/orders/confirm', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;
  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    return res.status(400).json({ message: 'razorpay_order_id, razorpay_payment_id, and razorpay_signature are required' });
  }

  // 1. Cryptographic verification first.
  if (!verifyRazorpaySignature({ razorpay_order_id, razorpay_payment_id, razorpay_signature })) {
    return res.status(400).json({ message: 'Payment verification failed — invalid signature' });
  }

  // 2. Retrieve and atomically delete the session (findOneAndDelete = one-time use).
  const session = await PaymentSession.findOneAndDelete({ razorpayOrderId: razorpay_order_id });
  if (!session) {
    return res.status(400).json({ message: 'Payment session expired or already used' });
  }

  const cart = session.cart;

  // 3. Create the DB order — only reachable after valid signature + valid session.
  const orderId     = makeOrderId();
  const tokenNumber = await generateTokenNumber(cart.cafeId);
  const order = await Order.create({
    orderId, tokenNumber,
    userId:         cart.userId,
    customerName:   cart.customerName,
    customerEmail:  cart.customerEmail,
    cafeId:         cart.cafeId,
    cafeteriaName:  cart.cafeteriaName,
    items:          cart.items,
    itemTotal:      cart.itemTotal,
    platformFee:    cart.platformFee,
    convenienceFee: cart.convenienceFee,
    discount:       cart.discount,
    total:          cart.total,
    status:         'Pending',
    payment: {
      method:          'Online',
      provider:        'Razorpay',
      providerOrderId: razorpay_order_id,
      transactionId:   razorpay_payment_id,
      status:          'Paid',
    },
    location:   cart.location,
    pickupTime: cart.pickupTime,
    notes:      cart.notes,
  });

  audit('payment.confirmed', cart.userId, 'payment', order.orderId, { amount: cart.total, razorpayPaymentId: razorpay_payment_id, cafeId: cart.cafeId });

  // 4. Notify customer.
  if (order.userId) {
    await Notification.create({
      userId: order.userId, title: 'Order Placed 🎉',
      message: `Token #${order.tokenNumber} confirmed — payment received.`,
      type: 'order', orderId: order._id, items: order.items.map(i => i.name),
    });
    await sendPushNotification(
      [order.userId], 'Order Placed 🎉',
      `Token #${order.tokenNumber} confirmed — payment received.`,
      { type: 'order', orderId: order.orderId, status: 'Pending' }
    );
  }

  // 5. Notify vendor of new order.
  if (order.cafeId) {
    const vendorUser = await User.findOne({ cafeId: order.cafeId, role: 'vendor' }).select('_id').lean();
    if (vendorUser) {
      await sendPushNotification(
        [vendorUser._id],
        'New Order 🛎️',
        `Token #${order.tokenNumber} — new order from ${order.customerName || 'a customer'}`,
        { type: 'vendor_order', orderId: order.orderId, status: 'Pending' }
      );
    }
  }

  res.status(201).json(order);
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
connectDatabase()
  .then(() => app.listen(PORT, () => console.log(`Server running on port ${PORT}`)))
  .catch(err => { console.error('Failed to start server:', err.message); process.exit(1); });
