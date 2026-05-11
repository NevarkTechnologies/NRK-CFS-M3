const mongoose = require('mongoose');

const MenuItemSchema = new mongoose.Schema(
  {
    cafeId: { type: mongoose.Schema.Types.ObjectId, ref: 'Cafe', required: true, index: true },
    vendorId: { type: String, default: 'ADMIN_01', index: true },
    name: { type: String, required: true, trim: true },
    description: { type: String, default: '', trim: true },
    price: { type: Number, required: true, min: 0 },
    category: { type: String, required: true, trim: true },
    available: { type: Boolean, default: true },
    image: { type: String, default: '' },
    imageType: { type: String, enum: ['url', 'asset', 'base64', 'none'], default: 'none' },
    rating: { type: Number, default: 4.5, min: 0, max: 5 },
    reviews: { type: Number, default: 0, min: 0 },
    isVeg: { type: Boolean, default: true },
  },
  { timestamps: true }
);

MenuItemSchema.index({ cafeId: 1, category: 1, available: 1 });
MenuItemSchema.index({ name: 'text', category: 'text', description: 'text' });

module.exports = mongoose.model('MenuItem', MenuItemSchema);
