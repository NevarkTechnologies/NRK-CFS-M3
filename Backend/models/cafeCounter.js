const mongoose = require('mongoose');

const CafeCounterSchema = new mongoose.Schema({
  key: { type: String, required: true, unique: true }, // "{cafeId}:{YYYY-MM-DD}"
  seq: { type: Number, default: 0 },
});

module.exports = mongoose.model('CafeCounter', CafeCounterSchema);
