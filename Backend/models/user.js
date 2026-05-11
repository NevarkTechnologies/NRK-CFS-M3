const mongoose = require('mongoose');

const UserSchema = new mongoose.Schema(
  {
    googleId: { type: String, trim: true },
    name: { type: String, required: true, trim: true },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    avatar: { type: String, trim: true },
    role: { type: String, enum: ['customer', 'vendor', 'admin'], default: 'customer' },
    vendorId: { type: String, trim: true },
    cafeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Cafe' },
    address: {
      street1: { type: String, default: '' },
      street2: { type: String, default: '' },
      district: { type: String, default: '' },
      state: { type: String, default: '' },
      country: { type: String, default: 'India' },
      pincode: { type: String, default: '' },
    },
    paymentLabel: { type: String, default: 'UPI' },
    fcmTokens: [{ type: String, trim: true }],
  },
  { timestamps: true }
);

module.exports = mongoose.model('User', UserSchema);
