const mongoose = require('mongoose');

const NotificationSchema = new mongoose.Schema(
  {
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    title: { type: String, required: true, trim: true },
    message: { type: String, required: true, trim: true },
    type: { type: String, enum: ['order', 'promotion', 'system'], default: 'system' },
    orderId: { type: mongoose.Schema.Types.ObjectId, ref: 'Order' },
    items: [{ type: String }], // For order-related notifications
    isRead: { type: Boolean, default: false },
    // CODEX EDITS: Optional idempotency key prevents duplicate in-app order
    // notifications when an outbox job is retried by another PM2 worker.
    dedupeKey: { type: String, default: undefined },
  },
  { timestamps: true }
);

NotificationSchema.index({ userId: 1, createdAt: -1 });
NotificationSchema.index({ userId: 1, isRead: 1 });
// CODEX EDITS: Sparse keeps existing promotion/system documents compatible.
NotificationSchema.index({ dedupeKey: 1 }, { unique: true, sparse: true });

module.exports = mongoose.model('Notification', NotificationSchema);
