const mongoose = require('mongoose');

const CafeSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    slug: { type: String, required: true, unique: true, lowercase: true, trim: true },
    cuisine: { type: String, required: true, trim: true },
    description: { type: String, default: '', trim: true },
    category: { type: String, default: '', trim: true },
    image: { type: String, default: '' },
    imageType: { type: String, enum: ['url', 'asset', 'base64', 'none'], default: 'asset' },
    rating: { type: Number, default: 0, min: 1, max: 5 },
    reviews: { type: Number, default: 0, min: 0 },
    ratings: [{ userId: String, stars: { type: Number, min: 1, max: 5 } }],
    time: { type: String, default: 'Open Now' },
    price: { type: String, default: '' },
    tag: { type: String, default: '' },
    offer: { type: String, default: '' },
    location: { type: String, default: '' },
    city: { type: String, default: '', trim: true },
    pin: { type: String, default: '', trim: true },
    vendorId: { type: String, default: 'ADMIN_01', index: true },
    active: { type: Boolean, default: true },
  },
  { timestamps: true }
);

CafeSchema.index({ name: 'text', cuisine: 'text', location: 'text', category: 'text' });

module.exports = mongoose.model('Cafe', CafeSchema, 'cafes');