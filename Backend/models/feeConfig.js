const mongoose = require('mongoose');

// Fee structure per payment gateway. There is no admin UI yet — documents are
// edited directly in MongoDB. Both GET /api/payment/fees and
// POST /api/payment/initiate read this collection live on every request, so an
// edit reflects in the customer app and in charged totals immediately.
//
// platformFee charged = itemTotal * platformFeePercent / 100 + platformFeeFlat
// convenienceFee charged = convenienceFee (flat, per order)
const FeeConfigSchema = new mongoose.Schema(
  {
    gateway: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
      enum: ['razorpay', 'paytm'],
    },
    platformFeePercent: { type: Number, default: 3, min: 0, max: 100 },
    platformFeeFlat: { type: Number, default: 0, min: 0 },
    convenienceFee: { type: Number, default: 1.5, min: 0 },
    // Inactive gateways are hidden from the app and rejected at initiation.
    active: { type: Boolean, default: true },
  },
  { timestamps: true }
);

module.exports = mongoose.model('FeeConfig', FeeConfigSchema);
