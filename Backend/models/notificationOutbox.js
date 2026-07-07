const mongoose = require('mongoose');

// CODEX EDITS: Notifications are dispatched from a durable outbox so an FCM or
// notification write failure can never turn a committed paid order into HTTP 500.
const NotificationOutboxSchema = new mongoose.Schema({
  dedupeKey: { type: String, required: true, unique: true, index: true },
  orderId: { type: mongoose.Schema.Types.ObjectId, ref: 'Order', required: true, index: true },
  status: {
    type: String,
    enum: ['pending', 'processing', 'sent', 'failed'],
    default: 'pending',
    index: true,
  },
  attempts: { type: Number, default: 0 },
  nextAttemptAt: { type: Date, default: Date.now, index: true },
  processingStartedAt: { type: Date, default: null },
  customerNotificationSentAt: { type: Date, default: null },
  customerPushSentAt: { type: Date, default: null },
  vendorPushSentAt: { type: Date, default: null },
  sentAt: { type: Date, default: null },
  lastError: { type: String, default: '' },
  createdAt: { type: Date, default: Date.now },
  expiresAt: {
    type: Date,
    default: () => new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
  },
});

NotificationOutboxSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model('NotificationOutbox', NotificationOutboxSchema);
