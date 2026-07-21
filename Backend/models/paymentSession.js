const mongoose = require('mongoose');

// CODEX EDITS: Payment sessions are durable state machines. They are retained
// long enough for Razorpay late-authorisation and are never deleted before the
// paid order is safely persisted.
const PaymentSessionSchema = new mongoose.Schema({
  // Unique provider-side order key. Named for the original Razorpay-only flow;
  // for provider 'paytm' it stores our Paytm merchant orderId (PTM...). Kept
  // under the old name so live production sessions keep working across deploys.
  razorpayOrderId: { type: String, required: true, unique: true, index: true },
  provider: {
    type: String,
    enum: ['razorpay', 'paytm'],
    default: 'razorpay',
    index: true,
  },
  // Paytm-only checkout state: { txnToken, callbackUrl, channel }. The token is
  // required to resume the same Paytm order within the 15-minute active window.
  paytm: { type: mongoose.Schema.Types.Mixed, default: null },
  cart: { type: mongoose.Schema.Types.Mixed, required: true },
  status: {
    type: String,
    enum: ['pending', 'processing', 'completed', 'failed'],
    default: 'pending',
    index: true,
  },
  processingStartedAt: { type: Date, default: null },
  completedAt: { type: Date, default: null },
  completedOrderId: { type: mongoose.Schema.Types.ObjectId, ref: 'Order', default: null },
  lastPaymentId: { type: String, default: '' },
  lastError: { type: mongoose.Schema.Types.Mixed, default: null },
  createdAt: { type: Date, default: Date.now },
  // CODEX EDITS 2026-07-09 11:22:21 IST: Active checkout retry window is
  // separate from seven-day audit retention, so cancelled sessions stop
  // blocking a fresh cart once the window lapses.
  // CHANGE 2026-07-19: 15 → 5 minutes, matching PAYMENT_SESSION_ACTIVE_MS in
  // server.js (server.js always sets activeUntil explicitly; this default is
  // only a fallback).
  activeUntil: {
    type: Date,
    default: () => new Date(Date.now() + 5 * 60 * 1000),
    index: true,
  },
  expiresAt: {
    type: Date,
    default: () => new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
  },
});

// CODEX EDITS: expiresAt is an absolute TTL so completed and pending sessions
// share the same auditable seven-day retention window.
PaymentSessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

module.exports = mongoose.model('PaymentSession', PaymentSessionSchema);
