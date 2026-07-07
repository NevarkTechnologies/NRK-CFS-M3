const mongoose = require('mongoose');

// CODEX EDITS: Durable webhook receipts make Razorpay retries idempotent across
// PM2 workers and retain enough metadata for payment incident reconstruction.
const PaymentWebhookEventSchema = new mongoose.Schema({
  eventKey: { type: String, required: true, unique: true, index: true },
  eventType: { type: String, required: true, index: true },
  razorpayOrderId: { type: String, default: '', index: true },
  razorpayPaymentId: { type: String, default: '' },
  status: {
    type: String,
    enum: ['received', 'processing', 'processed', 'failed'],
    default: 'received',
    index: true,
  },
  attempts: { type: Number, default: 0 },
  processingStartedAt: { type: Date, default: null },
  processedAt: { type: Date, default: null },
  lastError: { type: String, default: '' },
  createdAt: { type: Date, default: Date.now },
  expiresAt: {
    type: Date,
    default: () => new Date(Date.now() + 90 * 24 * 60 * 60 * 1000),
  },
});

PaymentWebhookEventSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model('PaymentWebhookEvent', PaymentWebhookEventSchema);
