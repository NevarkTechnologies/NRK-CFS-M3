const mongoose = require('mongoose');

const OrderItemSchema = new mongoose.Schema(
  {
    menuItemId: { type: mongoose.Schema.Types.ObjectId, ref: 'MenuItem' },
    name: { type: String, required: true, trim: true },
    qty: { type: Number, required: true, min: 1 },
    price: { type: Number, required: true, min: 0 },
    image: { type: String, default: '' },
  },
  { _id: false }
);

const OrderSchema = new mongoose.Schema(
  {
    orderId: { type: String, required: true, unique: true, index: true },
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    customerName: { type: String, required: true, trim: true },
    customerEmail: { type: String, lowercase: true, trim: true },
    cafeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Cafe', index: true },
    cafeteriaName: { type: String, required: true, trim: true },
    items: { type: [OrderItemSchema], validate: v => Array.isArray(v) && v.length > 0 },
    itemTotal: { type: Number, required: true, min: 0 },
    platformFee: { type: Number, default: 3, min: 0 },
    discount: { type: Number, default: 0, min: 0 },
    total: { type: Number, required: true, min: 0 },
    status: {
      type: String,
      enum: ['Pending', 'Preparing', 'Ready', 'Completed', 'Rejected'],
      default: 'Pending',
      index: true,
    },
    payment: {
      method: { type: String, enum: ['UPI', 'Wallet', 'NetBanking', 'Cash', 'Mock', 'Online'], default: 'Mock' },
      provider: { type: String, default: '' },
      transactionId: { type: String, default: '' },
      status: { type: String, enum: ['Pending', 'Paid', 'Failed', 'Refunded'], default: 'Paid' },
    },
    location: { type: String, default: 'Pickup counter' },
    notes: { type: String, default: '' },
  },
  { timestamps: true }
);

OrderSchema.index({ cafeId: 1, createdAt: -1 });
OrderSchema.index({ customerEmail: 1, createdAt: -1 });

module.exports = mongoose.model('Order', OrderSchema);
