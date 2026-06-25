const mongoose = require('mongoose');

const AuditLogSchema = new mongoose.Schema({
  action:     { type: String, required: true },   // e.g. 'order.status_changed'
  actorId:    { type: String, required: true },   // Firebase UID
  targetType: { type: String, required: true },   // 'order' | 'cafe' | 'rating' | 'payment'
  targetId:   { type: String },                   // orderId, cafeId, etc.
  meta:       { type: mongoose.Schema.Types.Mixed, default: {} },
  createdAt:  { type: Date, default: Date.now, expires: 60 * 60 * 24 * 90 }, // auto-delete after 90 days
});

AuditLogSchema.index({ actorId: 1, createdAt: -1 });
AuditLogSchema.index({ targetId: 1, createdAt: -1 });

module.exports = mongoose.model('AuditLog', AuditLogSchema);
