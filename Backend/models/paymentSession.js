const mongoose = require('mongoose');

const PaymentSessionSchema = new mongoose.Schema({
  razorpayOrderId: { type: String, required: true, unique: true, index: true },
  cart: { type: mongoose.Schema.Types.Mixed, required: true },
  createdAt: { type: Date, default: Date.now, expires: 1800 }, // auto-delete after 30 min
});

module.exports = mongoose.model('PaymentSession', PaymentSessionSchema);
