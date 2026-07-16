const mongoose = require('mongoose');

// Small key/value store for operational settings edited directly in MongoDB
// (no admin UI). Read live on every request that needs them, so edits reflect
// without a deploy or restart.
//
// Known keys:
//   pickup_window → value: { start: 'HH:mm', end: 'HH:mm' }  (24h, IST)
const AppConfigSchema = new mongoose.Schema(
  {
    key: { type: String, required: true, unique: true, trim: true },
    value: { type: mongoose.Schema.Types.Mixed, default: {} },
  },
  { timestamps: true }
);

module.exports = mongoose.model('AppConfig', AppConfigSchema, 'app_configs');
