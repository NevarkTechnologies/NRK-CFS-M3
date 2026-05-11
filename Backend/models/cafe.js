const mongoose = require('mongoose');

const CafeSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    slug: { type: String, required: true, unique: true, lowercase: true, trim: true },
    cuisine: { type: String, required: true, trim: true },
    category: { type: String, default: '', trim: true },
    image: { type: String, default: '' },
    imageType: { type: String, enum: ['url', 'asset', 'base64', 'none'], default: 'asset' },
    rating: { type: Number, default: 4.4, min: 0, max: 5 },
    reviews: { type: Number, default: 0, min: 0 },
    time: { type: String, default: '30-40 mins' },
    price: { type: String, default: '' },
    tag: { type: String, default: '' },
    offer: { type: String, default: '' },
    location: { type: String, default: '' },
    vendorId: { type: String, default: 'ADMIN_01', index: true },
    active: { type: Boolean, default: true },
  },
  { timestamps: true }
);

CafeSchema.index({ name: 'text', cuisine: 'text', location: 'text', category: 'text' });

module.exports = mongoose.model('Cafe', CafeSchema, 'cafes');