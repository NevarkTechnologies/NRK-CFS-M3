const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config();

const Cafe = require('./models/cafe');
const MenuItem = require('./models/menuitems');
const Order = require('./models/order');
const User = require('./models/user');

const app = express();
const allowedStatuses = ['Pending', 'Preparing', 'Ready', 'Completed', 'Rejected'];

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
    platformFee = 3,
    discount = 0,
    payment = {},
    location,
    notes,
  } = req.body;

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
  const total = toMoney(itemTotal + Number(platformFee) - Number(discount));

  const order = await Order.create({
    orderId: makeOrderId(),
    userId,
    customerName,
    customerEmail,
    cafeId: resolvedCafeId,
    cafeteriaName,
    items: normalizedItems,
    itemTotal,
    platformFee,
    discount,
    total,
    payment,
    location,
    notes,
  });

  res.status(201).json(order);
}

async function connectDatabase() {
  if (!process.env.MONGO_URI) {
    throw new Error('MONGO_URI is missing. Add it to Backend/.env');
  }

  await mongoose.connect(process.env.MONGO_URI);
  console.log('MongoDB connected');
}

app.get('/api/health', (req, res) => {
  res.json({
    ok: true,
    service: 'nevark-food-backend',
    mongoState: mongoose.connection.readyState,
  });
});

app.post('/api/auth/google', asyncHandler(async (req, res) => {
  const { googleId, name, email, avatar } = req.body;
  if (!name || !email) {
    return res.status(400).json({ message: 'name and email are required' });
  }

  let user = await User.findOneAndUpdate(
    { email: email.toLowerCase() },
    {
      $set: { googleId, name, avatar },
      $setOnInsert: { role: 'customer' },
    },
    { new: true, upsert: true, runValidators: true }
  ).populate('cafeId');

  if (user.role === 'vendor' && user.vendorId && !user.cafeId) {
    const cafe = await Cafe.findOne({ vendorId: user.vendorId });
    if (cafe) {
      user = await User.findByIdAndUpdate(
        user._id,
        { cafeId: cafe._id },
        { new: true, runValidators: true }
      ).populate('cafeId');
    }
  }

  res.status(200).json(user);
}));

app.patch('/api/users/:id', asyncHandler(async (req, res) => {
  const allowed = {};
  for (const key of ['name', 'email', 'avatar', 'address', 'paymentLabel']) {
    if (req.body[key] !== undefined) allowed[key] = req.body[key];
  }

  const user = await User.findByIdAndUpdate(req.params.id, allowed, {
    new: true,
    runValidators: true,
  }).populate('cafeId');

  if (!user) return res.status(404).json({ message: 'User not found' });
  res.json(user);
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

app.post('/api/cafes', asyncHandler(async (req, res) => {
  const cafe = await Cafe.create(req.body);
  res.status(201).json(cafe);
}));

app.patch('/api/cafes/:id', asyncHandler(async (req, res) => {
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

app.post('/api/menu', asyncHandler(async (req, res) => {
  const item = await MenuItem.create(req.body);
  res.status(201).json(item);
}));

app.post('/api/menu/add', asyncHandler(async (req, res) => {
  const item = await MenuItem.create(req.body);
  res.status(201).json(item);
}));

app.patch('/api/menu/:id', asyncHandler(async (req, res) => {
  const item = await MenuItem.findByIdAndUpdate(req.params.id, req.body, {
    new: true,
    runValidators: true,
  });
  if (!item) return res.status(404).json({ message: 'Menu item not found' });
  res.json(item);
}));

app.delete('/api/menu/:id', asyncHandler(async (req, res) => {
  const item = await MenuItem.findByIdAndDelete(req.params.id);
  if (!item) return res.status(404).json({ message: 'Menu item not found' });
  res.status(204).send();
}));

app.post('/api/orders', asyncHandler(createOrder));
app.post('/api/orders/place', asyncHandler(createOrder));

app.get('/api/orders', asyncHandler(async (req, res) => {
  const query = {};
  if (req.query.cafeId) query.cafeId = req.query.cafeId;
  if (req.query.customerEmail) query.customerEmail = req.query.customerEmail.toLowerCase();
  if (req.query.status) query.status = req.query.status;

  const orders = await Order.find(query).sort({ createdAt: -1 });
  res.json(orders);
}));

app.get('/api/orders/:orderId', asyncHandler(async (req, res) => {
  const order = await Order.findOne({ orderId: req.params.orderId });
  if (!order) return res.status(404).json({ message: 'Order not found' });
  res.json(order);
}));

app.patch('/api/orders/:orderId/status', asyncHandler(async (req, res) => {
  const { status } = req.body;
  if (!allowedStatuses.includes(status)) {
    return res.status(400).json({ message: `status must be one of: ${allowedStatuses.join(', ')}` });
  }

  const order = await Order.findOneAndUpdate(
    { orderId: req.params.orderId },
    { status },
    { new: true, runValidators: true }
  );

  if (!order) return res.status(404).json({ message: 'Order not found' });
  res.json(order);
}));

app.get('/api/vendor/:vendorId/dashboard', asyncHandler(async (req, res) => {
  const cafes = await Cafe.find({ vendorId: req.params.vendorId }).select('_id');
  const cafeIds = cafes.map(cafe => cafe._id);
  const orderQuery = cafeIds.length ? { cafeId: { $in: cafeIds } } : {};

  const [summary] = await Order.aggregate([
    { $match: orderQuery },
    {
      $group: {
        _id: null,
        totalOrders: { $sum: 1 },
        revenue: { $sum: '$total' },
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
  res.status(500).json({ message: 'Internal server error' });
});

const PORT = process.env.PORT || 5000;

connectDatabase()
  .then(() => app.listen(PORT, () => console.log(`Server running on port ${PORT}`)))
  .catch(err => {
    console.error('Failed to start server:', err.message);
    process.exit(1);
  });
