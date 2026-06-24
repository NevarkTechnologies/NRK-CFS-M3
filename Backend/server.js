const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const crypto = require('crypto');
const Razorpay = require('razorpay');
const admin = require('firebase-admin');
require('dotenv').config();

const Cafe = require('./models/cafe');
const MenuItem = require('./models/menuitems');
const Order = require('./models/order');
const User = require('./models/user');
const Notification = require('./models/notification');
const CafeCounter = require('./models/cafeCounter');


const app = express();
const allowedStatuses = ['Pending', 'Preparing', 'Ready', 'Completed', 'Rejected'];
let razorpayClient;
let firebaseInitialized = false;

app.use(cors({ origin: process.env.CLIENT_ORIGIN || '*' }));
app.use(express.json({ limit: '50mb' }));

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
  const today = new Date().toISOString().slice(0, 10); // "YYYY-MM-DD"
  const key = `${cafeId}:${today}`;
  const doc = await CafeCounter.findOneAndUpdate(
    { key },
    { $inc: { seq: 1 } },
    { new: true, upsert: true }
  );
  return String(doc.seq).padStart(4, '0');
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

  razorpayClient = new Razorpay({
    key_id: keyId,
    key_secret: keySecret,
  });
  return razorpayClient;
}

function initializeFirebaseAdmin() {
  if (firebaseInitialized || admin.apps.length) {
    firebaseInitialized = true;
    return admin;
  }

  const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (serviceAccount) {
    admin.initializeApp({
      credential: admin.credential.cert(JSON.parse(serviceAccount)),
    });
  } else {
    admin.initializeApp();
  }

  firebaseInitialized = true;
  return admin;
}

function shouldEnforceFirebaseAuth() {
  return process.env.REQUIRE_FIREBASE_AUTH === 'true' || process.env.NODE_ENV === 'production';
}

async function resolveRoleFromFirebase(email, fallbackRole) {
  try {
    const firebase = initializeFirebaseAdmin();
    const snapshot = await firebase
      .firestore()
      .collection('users')
      .where('email', 'array-contains', email)
      .limit(1)
      .get();

    if (!snapshot.empty) {
      return snapshot.docs[0].data().role || fallbackRole || 'customer';
    }
  } catch (err) {
    if (shouldEnforceFirebaseAuth()) {
      throw err;
    }
    console.warn('Firebase role lookup skipped:', err.message);
  }

  if (shouldEnforceFirebaseAuth()) {
    const error = new Error('Email is not authorized to access this app');
    error.statusCode = 403;
    throw error;
  }

  return fallbackRole || 'customer';
}

async function verifyFirebaseIdentity(idToken) {
  if (!idToken) return null;
  try {
    const firebase = initializeFirebaseAdmin();
    return await firebase.auth().verifyIdToken(idToken);
  } catch (err) {
    if (shouldEnforceFirebaseAuth()) {
      throw err;
    }
    console.warn('Firebase token verification skipped:', err.message);
    return null;
  }
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
        notification: {
          channelId: 'orders',
          sound: 'default',
          priority: 'high',
          defaultVibrateTimings: true,
        },
      },
      apns: {
        headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
        payload: { aps: { sound: 'default', badge: 1, contentAvailable: true } },
      },
      data: Object.fromEntries(
        Object.entries(data).map(([key, value]) => [key, String(value)])
      ),
    });
  } catch (err) {
    console.warn('Push notification failed:', err.message);
  }
}

function verifyRazorpaySignature({ razorpay_order_id, razorpay_payment_id, razorpay_signature }) {
  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    return false;
  }
  if (!process.env.RAZORPAY_KEY_SECRET) {
    const error = new Error('Razorpay credentials are not configured');
    error.statusCode = 503;
    throw error;
  }

  const expectedSignature = crypto
    .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
    .update(`${razorpay_order_id}|${razorpay_payment_id}`)
    .digest('hex');

  if (expectedSignature.length !== razorpay_signature.length) {
    return false;
  }

  return crypto.timingSafeEqual(
    Buffer.from(expectedSignature),
    Buffer.from(razorpay_signature)
  );
}

async function requireFirebaseAuth(req, res, next) {
  try {
    const authHeader = req.get('Authorization') || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
    if (!token) {
      if (shouldEnforceFirebaseAuth()) {
        return res.status(401).json({ message: 'Firebase auth token is required' });
      }
      return next();
    }

    req.firebaseUser = await verifyFirebaseIdentity(token);
    if (!req.firebaseUser && shouldEnforceFirebaseAuth()) {
      return res.status(401).json({ message: 'Invalid Firebase auth token' });
    }
    return next();
  } catch (err) {
    return next(err);
  }
}

function buildCafeQuery(req) {
  const query = { active: true };
  if (req.query.search) {
    query.$text = { $search: req.query.search };
  }
  if (req.query.category) {
    query.category = req.query.category;
  }
  return query;
}

async function createOrder(req, res) {
  const {
    customerName,
    customerEmail,
    userId,
    cafeId,
    cafeteriaName,
    items,
    discount = 0,
    payment = {},
    location,
    notes,
  } = req.body;

  // Online/Razorpay payments must go through /payment/initiate → /orders/confirm.
  // Allowing them here would create unverified ghost orders.
  if (isOnlinePayment(payment)) {
    return res.status(400).json({
      message: 'Online payments must use POST /api/payment/initiate then POST /api/orders/confirm',
    });
  }

  if (!customerName || !cafeteriaName || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ message: 'customerName, cafeteriaName, and items are required' });
  }

  const normalizedItems = items.map(item => ({
    menuItemId: mongoose.Types.ObjectId.isValid(item.menuItemId || item.id)
      ? item.menuItemId || item.id
      : undefined,
    name: item.name,
    qty: Number(item.qty || item.quantity || 1),
    price: Number(item.price || 0),
    image: item.image || '',
  }));

  if (normalizedItems.some(item => !item.name || item.qty < 1 || item.price < 0)) {
    return res.status(400).json({ message: 'Each order item needs name, qty, and price' });
  }

  let resolvedCafeId = cafeId;
  if (!resolvedCafeId && cafeteriaName) {
    const cafe = await Cafe.findOne({ name: cafeteriaName }).select('_id');
    resolvedCafeId = cafe?._id;
  }

  const itemTotal = toMoney(normalizedItems.reduce((sum, item) => sum + item.price * item.qty, 0));
  const platformFee = toMoney(itemTotal * 0.03);
  const convenienceFee = 1.5;
  const total = toMoney(itemTotal + platformFee + convenienceFee - Number(discount));
  if (total <= 0) {
    return res.status(400).json({ message: 'Order total must be greater than zero' });
  }

  const orderId = makeOrderId();
  const tokenNumber = await generateTokenNumber(resolvedCafeId);
  const razorpayOrder = isOnlinePayment(payment)
    ? await createRazorpayOrder(orderId, total)
    : null;

  const order = await Order.create({
    orderId,
    tokenNumber,
    userId,
    customerName,
    customerEmail,
    cafeId: resolvedCafeId,
    cafeteriaName,
    items: normalizedItems,
    itemTotal,
    platformFee,
    convenienceFee,
    discount,
    total,
    payment: {
      ...payment,
      providerOrderId: razorpayOrder?.id || payment.providerOrderId || '',
      status: razorpayOrder ? 'Pending' : payment.status || 'Paid',
    },
    location,
    notes,
  });

  res.status(201).json({ order, razorpayOrder });
}

function getMongoOptions() {
  const uri = process.env.MONGO_URI;
  const dbName = process.env.MONGO_DB_NAME || (() => {
    const uriNoQuery = uri.split('?')[0];
    const lastSegment = uriNoQuery.substring(uriNoQuery.lastIndexOf('/') + 1);
    return lastSegment && !lastSegment.includes('@') ? lastSegment : undefined;
  })();

  if (!dbName) {
    throw new Error('MONGO_DB_NAME is missing and MONGO_URI does not include a database name');
  }

  return { dbName };
}

async function connectDatabase() {
  if (!process.env.MONGO_URI) {
    throw new Error('MONGO_URI is missing. Add it to Backend/.env');
  }

  const options = getMongoOptions();

  try {
    await mongoose.connect(process.env.MONGO_URI, options);
    console.log('MongoDB connected');
  } catch (err) {
    console.error('MongoDB connection failed:', err.message);
    // If the user provided an SRV URI (mongodb+srv://) and DNS/SRV lookup fails
    // attempt a local fallback. This keeps behavior predictable in offline/dev setups.
    if (process.env.MONGO_URI.includes('+srv')) {
      const fallback = process.env.MONGO_URI_FALLBACK || 'mongodb://127.0.0.1:27017/nevark';
      console.log(`Attempting fallback MongoDB URI: ${fallback}`);
      await mongoose.connect(fallback, { dbName: 'nevark' });
      console.log('MongoDB connected (fallback)');
      return;
    }
    throw err;
  }
}

app.get('/api/health', (req, res) => {
  res.json({
    ok: true,
    service: 'nevark-food-backend',
    mongoState: mongoose.connection.readyState,
  });
});

app.post('/api/auth/google', asyncHandler(async (req, res) => {
  const { googleId, name, email, avatar, role, idToken, fcmToken } = req.body;
  if (!name || !email) {
    return res.status(400).json({ message: 'name and email are required' });
  }

  const normalizedEmail = email.toLowerCase();
  const decodedToken = await verifyFirebaseIdentity(idToken);
  if (decodedToken && decodedToken.email?.toLowerCase() !== normalizedEmail) {
    return res.status(403).json({ message: 'Firebase token email does not match request email' });
  }

  const resolvedRole = await resolveRoleFromFirebase(normalizedEmail, role);

  let user = await User.findOneAndUpdate(
    { email: normalizedEmail },
    {
      $set: {
        googleId: decodedToken?.uid || googleId,
        name,
        avatar,
        role: resolvedRole,
      },
      ...(fcmToken ? { $addToSet: { fcmTokens: fcmToken } } : {}),
    },
    { returnDocument: 'after', upsert: true, runValidators: true }
  ).populate('cafeId');

  if (user.role === 'vendor') {
    const vendorId = user.vendorId?.trim() || googleId || user._id.toString();
    if (!user.vendorId || user.vendorId !== vendorId) {
      user = await User.findByIdAndUpdate(
        user._id,
        { vendorId },
        { new: true, runValidators: true }
      ).populate('cafeId');
    }

    if (!user.cafeId) {
      let cafe = await Cafe.findOne({ vendorId });
      if (!cafe) {
        const baseSlug = name
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '-')
            .replace(/(^-|-$)/g, '')
            .slice(0, 40) || `vendor-${Date.now()}`;
        const slug = `${baseSlug}-${Date.now().toString().slice(-4)}`;

        cafe = await Cafe.create({
          name: `${name}'s Cafe`,
          slug,
          cuisine: 'General',
          description: '',
          location: '',
          city: '',
          pin: '',
          vendorId,
          active: true,
        });
      }

      user = await User.findByIdAndUpdate(
        user._id,
        { cafeId: cafe._id, vendorId },
        { new: true, runValidators: true }
      ).populate('cafeId');
    }
  }

  res.status(200).json(user);
}));

app.patch('/api/users/:id', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const allowed = {};
  for (const key of ['name', 'email', 'avatar', 'phone', 'paymentLabel']) {
    if (req.body[key] !== undefined) allowed[key] = req.body[key];
  }

  const user = await User.findByIdAndUpdate(req.params.id, allowed, {
    new: true,
    runValidators: true,
  }).populate('cafeId');

  if (!user) return res.status(404).json({ message: 'User not found' });
  res.json(user);
}));

app.post('/api/users/:id/fcm-token', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const { token } = req.body;
  if (!token || typeof token !== 'string') {
    return res.status(400).json({ message: 'token is required' });
  }

  const user = await User.findByIdAndUpdate(
    req.params.id,
    { $addToSet: { fcmTokens: token.trim() } },
    { new: true }
  ).select('_id');

  if (!user) return res.status(404).json({ message: 'User not found' });
  res.status(204).send();
}));

app.get('/api/cafes', asyncHandler(async (req, res) => {
  const cafes = await Cafe.find(buildCafeQuery(req)).sort({ rating: -1, name: 1 });
  res.json(cafes);
}));

app.get('/api/cafes/:id', asyncHandler(async (req, res) => {
  const cafe = await Cafe.findById(req.params.id);
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });
  res.json(cafe);
}));

app.post('/api/cafes', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const cafe = await Cafe.create(req.body);
  res.status(201).json(cafe);
}));

app.patch('/api/cafes/:id', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const cafe = await Cafe.findByIdAndUpdate(req.params.id, req.body, {
    new: true,
    runValidators: true,
  });
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });
  res.json(cafe);
}));

app.get('/api/menu', asyncHandler(async (req, res) => {
  const query = {};
  if (req.query.cafeId) query.cafeId = req.query.cafeId;
  if (req.query.vendorId) query.vendorId = req.query.vendorId;
  if (req.query.available !== undefined) query.available = req.query.available === 'true';
  if (req.query.search) query.$text = { $search: req.query.search };

  const items = await MenuItem.find(query).populate('cafeId', 'name slug').sort({ category: 1, name: 1 });
  res.json(items);
}));

app.get('/api/cafes/:id/menu', asyncHandler(async (req, res) => {
  const items = await MenuItem.find({ cafeId: req.params.id, available: true }).sort({ category: 1, name: 1 });
  res.json(items);
}));

// POST /api/cafes/:id/review — upsert a user's star rating
app.post('/api/cafes/:id/review', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const { userId, stars } = req.body;
  if (!userId || !stars || stars < 1 || stars > 5) {
    return res.status(400).json({ message: 'userId and stars (1-5) are required' });
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
  cafe.rating = Math.round((total / cafe.ratings.length) * 10) / 10;
  cafe.reviews = cafe.ratings.length;
  await cafe.save();
  res.json({ rating: cafe.rating, reviews: cafe.reviews });
}));

// DELETE /api/cafes/:id/review — remove a user's rating
app.delete('/api/cafes/:id/review', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const userId = req.query.userId || req.body?.userId;
  if (!userId) return res.status(400).json({ message: 'userId is required' });
  const cafe = await Cafe.findById(req.params.id);
  if (!cafe) return res.status(404).json({ message: 'Cafe not found' });

  cafe.ratings = cafe.ratings.filter(r => r.userId !== userId);
  const total = cafe.ratings.reduce((s, r) => s + r.stars, 0);
  cafe.rating = cafe.ratings.length ? Math.round((total / cafe.ratings.length) * 10) / 10 : 4;
  cafe.reviews = cafe.ratings.length;
  await cafe.save();
  res.json({ rating: cafe.rating, reviews: cafe.reviews });
}));

// GET /api/users/:userId/ratings — get all cafe ratings by a user
app.get('/api/users/:userId/ratings', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const { userId } = req.params;
  const cafes = await Cafe.find({ 'ratings.userId': userId }, { ratings: 1 });
  const result = {};
  cafes.forEach(cafe => {
    const r = cafe.ratings.find(r => r.userId === userId);
    if (r) result[cafe._id.toString()] = r.stars;
  });
  res.json(result);
}));

app.post('/api/menu', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const item = await MenuItem.create(req.body);
  res.status(201).json(item);
}));

app.post('/api/menu/add', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const item = await MenuItem.create(req.body);
  res.status(201).json(item);
}));

app.patch('/api/menu/:id', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const item = await MenuItem.findByIdAndUpdate(req.params.id, req.body, {
    new: true,
    runValidators: true,
  });
  if (!item) return res.status(404).json({ message: 'Menu item not found' });
  res.json(item);
}));

app.delete('/api/menu/:id', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const item = await MenuItem.findByIdAndDelete(req.params.id);
  if (!item) return res.status(404).json({ message: 'Menu item not found' });
  res.status(204).send();
}));

// ── Server-side pending-payment store (keyed by Razorpay order ID) ────────────
// Holds cart data between /payment/initiate and /orders/confirm so the client
// never has a chance to tamper with items or amounts.
const _pendingPayments = new Map();
// Purge entries older than 30 minutes every 5 minutes.
setInterval(() => {
  const cutoff = Date.now() - 30 * 60 * 1000;
  for (const [key, val] of _pendingPayments) {
    if (val.createdAt < cutoff) _pendingPayments.delete(key);
  }
}, 5 * 60 * 1000);

// Step 1 of payment: compute totals server-side, create Razorpay order,
// stash cart — return ONLY the Razorpay order to the client (no DB write yet).
app.post('/api/payment/initiate', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const {
    customerName, customerEmail, userId, cafeId, cafeteriaName,
    items, discount = 0, location, pickupTime, notes,
  } = req.body;

  if (!customerName || !cafeteriaName || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ message: 'customerName, cafeteriaName, and items are required' });
  }

  const normalizedItems = items.map(item => ({
    menuItemId: mongoose.Types.ObjectId.isValid(item.menuItemId || item.id)
      ? (item.menuItemId || item.id)
      : undefined,
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

  // Server-side total computation — client cannot tamper.
  const itemTotal      = toMoney(normalizedItems.reduce((s, i) => s + i.price * i.qty, 0));
  const platformFee    = toMoney(itemTotal * 0.03);
  const convenienceFee = 1.5;
  const discountAmt    = toMoney(Number(discount));
  const total          = toMoney(itemTotal + platformFee + convenienceFee - discountAmt);

  if (total <= 0) {
    return res.status(400).json({ message: 'Order total must be greater than zero' });
  }

  const receipt = `init_${makeOrderId()}`;
  const razorpayOrder = await createRazorpayOrder(receipt, total);

  // Stash the verified cart server-side.
  _pendingPayments.set(razorpayOrder.id, {
    customerName, customerEmail,
    userId:        userId   || null,
    cafeId:        resolvedCafeId || null,
    cafeteriaName,
    items:         normalizedItems,
    itemTotal, platformFee, convenienceFee,
    discount:      discountAmt,
    total,
    location:      location   || 'Pickup counter',
    pickupTime:    pickupTime || '',
    notes:         notes      || '',
    createdAt:     Date.now(),
  });

  res.json({ razorpayOrder });
}));

// Step 2 of payment: verify Razorpay HMAC signature, retrieve server-side cart,
// create DB order only on success — the order NEVER exists before payment clears.
app.post('/api/orders/confirm', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = req.body;

  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    return res.status(400).json({ message: 'razorpay_order_id, razorpay_payment_id, and razorpay_signature are required' });
  }

  // 1. Cryptographic proof first — reject before touching anything else.
  if (!verifyRazorpaySignature({ razorpay_order_id, razorpay_payment_id, razorpay_signature })) {
    return res.status(400).json({ message: 'Payment verification failed — invalid signature' });
  }

  // 2. Retrieve the server-side cart stashed during /initiate.
  const cart = _pendingPayments.get(razorpay_order_id);
  if (!cart) {
    return res.status(400).json({ message: 'Payment session expired or already used' });
  }

  // 3. Remove immediately — one-time use.
  _pendingPayments.delete(razorpay_order_id);

  // 4. Create the DB order — only reachable after valid signature + valid session.
  const orderId = makeOrderId();
  const tokenNumber = await generateTokenNumber(cart.cafeId);
  const order = await Order.create({
    orderId,
    tokenNumber,
    userId:       cart.userId,
    customerName: cart.customerName,
    customerEmail: cart.customerEmail,
    cafeId:       cart.cafeId,
    cafeteriaName: cart.cafeteriaName,
    items:        cart.items,
    itemTotal:    cart.itemTotal,
    platformFee:  cart.platformFee,
    convenienceFee: cart.convenienceFee,
    discount:     cart.discount,
    total:        cart.total,
    status:       'Pending',
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

  // 5. Notify customer.
  if (order.userId) {
    await Notification.create({
      userId:  order.userId,
      title:   'Order Placed 🎉',
      message: `Order #${order.orderId} confirmed — payment received.`,
      type:    'order',
      orderId: order._id,
      items:   order.items.map(i => i.name),
    });
    await sendPushNotification(
      [order.userId],
      'Order Placed 🎉',
      `Order #${order.orderId} confirmed — payment received.`,
      { type: 'order', orderId: order.orderId, status: 'Pending' }
    );
  }

  res.status(201).json(order);
}));

app.post('/api/orders', requireFirebaseAuth, asyncHandler(createOrder));
app.post('/api/orders/place', requireFirebaseAuth, asyncHandler(createOrder));

app.get('/api/orders', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const query = {
    // Never surface orders whose payment hasn't cleared — hides ghost orders.
    'payment.status': { $ne: 'Pending' },
  };
  if (req.query.cafeId) query.cafeId = req.query.cafeId;
  if (req.query.customerEmail) query.customerEmail = req.query.customerEmail.toLowerCase();
  if (req.query.status) query.status = req.query.status;

  const orders = await Order.find(query)
    .populate('cafeId', 'name image imageType')
    .sort({ createdAt: -1 });
  res.json(orders);
}));

app.get('/api/orders/:orderId', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const order = await Order.findOne({ orderId: req.params.orderId });
  if (!order) return res.status(404).json({ message: 'Order not found' });
  res.json(order);
}));

app.patch('/api/orders/:orderId/status', requireFirebaseAuth, asyncHandler(async (req, res) => {
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
  if (order.userId) {
    const statusContent = {
      Pending:   { title: 'Order Received 📋',        body: `Order #${order.orderId} is pending confirmation.` },
      Preparing: { title: 'Being Prepared 👨‍🍳',        body: `Order #${order.orderId} — the kitchen is on it!` },
      Ready:     { title: 'Ready for Pickup! 🎉',      body: `Order #${order.orderId} — come collect your order now!` },
      Completed: { title: 'Order Completed ✅',         body: `Order #${order.orderId} — enjoy your meal!` },
      Rejected:  { title: 'Order Rejected ❌',          body: `Order #${order.orderId} was rejected. Please contact support.` },
    };
    const { title, body } = statusContent[order.status] ?? {
      title: 'Order Update',
      body: `Order #${order.orderId} is now ${order.status}.`,
    };
    await Notification.create({
      userId: order.userId,
      title,
      message: body,
      type: 'order',
      orderId: order._id,
      items: order.items.map(item => item.name),
    });
    await sendPushNotification(
      [order.userId],
      title,
      body,
      { type: 'order', orderId: order.orderId, status: order.status }
    );
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
  const {
    transactionId,
    status,
    providerOrderId,
    razorpay_order_id,
    razorpay_payment_id,
    razorpay_signature,
  } = req.body;
  const allowedPaymentStatuses = ['Pending', 'Paid', 'Failed', 'Refunded'];
  if (status && !allowedPaymentStatuses.includes(status)) {
    return res.status(400).json({ message: `status must be one of: ${allowedPaymentStatuses.join(', ')}` });
  }

  const existingOrder = await Order.findOne({ orderId: req.params.orderId });
  if (!existingOrder) return res.status(404).json({ message: 'Order not found' });

  if (status === 'Paid') {
    const signedOrderId = razorpay_order_id || existingOrder.payment.providerOrderId;
    const signedPaymentId = razorpay_payment_id || transactionId;
    if (signedOrderId !== existingOrder.payment.providerOrderId) {
      return res.status(400).json({ message: 'Razorpay order id does not match this order' });
    }

    const isValid = verifyRazorpaySignature({
      razorpay_order_id: signedOrderId,
      razorpay_payment_id: signedPaymentId,
      razorpay_signature,
    });
    if (!isValid) {
      return res.status(400).json({ message: 'Invalid Razorpay signature' });
    }
  }

  const update = {};
  if (transactionId !== undefined) update['payment.transactionId'] = transactionId;
  if (providerOrderId !== undefined) update['payment.providerOrderId'] = providerOrderId;
  if (status !== undefined) update['payment.status'] = status;

  const order = await Order.findOneAndUpdate(
    { orderId: req.params.orderId },
    { $set: update },
    { returnDocument: 'after', runValidators: true }
  );

  if (!order) return res.status(404).json({ message: 'Order not found' });
  res.json(order);
}));

app.get('/api/notifications/:userId', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const notifications = await Notification.find({ userId: req.params.userId })
    .sort({ createdAt: -1 })
    .limit(100);
  res.json(notifications);
}));

app.post('/api/notifications/send', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const { title, message, targetUserIds } = req.body;
  if (!title || !message) {
    return res.status(400).json({ message: 'title and message are required' });
  }

  const users = Array.isArray(targetUserIds) && targetUserIds.length > 0
    ? await User.find({ _id: { $in: targetUserIds } }).select('_id')
    : await User.find({ role: 'customer' }).select('_id');
  const userIds = users.map(user => user._id);

  const notifications = await Notification.insertMany(
    userIds.map(userId => ({
      userId,
      title,
      message,
      type: 'promotion',
    }))
  );

  await sendPushNotification(userIds, title, message, { type: 'promotion' });
  res.status(201).json({ sent: notifications.length });
}));

app.patch('/api/notifications/:notificationId/read', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const notification = await Notification.findByIdAndUpdate(
    req.params.notificationId,
    { isRead: true },
    { returnDocument: 'after' }
  );

  if (!notification) return res.status(404).json({ message: 'Notification not found' });
  res.json(notification);
}));

app.delete('/api/notifications/:notificationId', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const notification = await Notification.findByIdAndDelete(req.params.notificationId);
  if (!notification) return res.status(404).json({ message: 'Notification not found' });
  res.status(204).send();
}));

app.get('/api/vendor/:vendorId/dashboard', requireFirebaseAuth, asyncHandler(async (req, res) => {
  const cafes = await Cafe.find({ vendorId: req.params.vendorId }).select('_id');
  const cafeIds = cafes.map(cafe => cafe._id);
  const orderQuery = cafeIds.length ? { cafeId: { $in: cafeIds } } : {};

  const [summary] = await Order.aggregate([
    { $match: orderQuery },
    {
      $group: {
        _id: null,
        totalOrders: { $sum: 1 },
        revenue: { $sum: '$itemTotal' },
        activeOrders: {
          $sum: { $cond: [{ $in: ['$status', ['Pending', 'Preparing', 'Ready']] }, 1, 0] },
        },
        completed: { $sum: { $cond: [{ $eq: ['$status', 'Completed'] }, 1, 0] } },
      },
    },
  ]);

  const recentOrders = await Order.find(orderQuery).sort({ createdAt: -1 }).limit(6);
  res.json({
    totalOrders: summary?.totalOrders || 0,
    revenue: summary?.revenue || 0,
    activeOrders: summary?.activeOrders || 0,
    completed: summary?.completed || 0,
    recentOrders,
  });
}));

app.use((req, res) => {
  res.status(404).json({ message: 'Route not found' });
});

app.use((err, req, res, next) => {
  console.error(err);
  if (err.name === 'ValidationError') {
    return res.status(400).json({ message: err.message });
  }
  if (err.code === 11000) {
    return res.status(409).json({ message: 'Duplicate value', fields: err.keyValue });
  }
  if (err.statusCode) {
    return res.status(err.statusCode).json({ message: err.message });
  }
  res.status(500).json({ message: 'Internal server error' });
});

const PORT = process.env.PORT || 5000;

connectDatabase()
  .then(() => app.listen(PORT, () => console.log(`Server running on port ${PORT}`)))
  .catch(err => {
    console.error('Failed to start server:', err.message);
    process.exit(1);
  });
