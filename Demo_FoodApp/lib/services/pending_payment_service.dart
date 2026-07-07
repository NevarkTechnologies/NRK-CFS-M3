import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'session.dart';

// CODEX EDITS: A pending Razorpay order survives UPI app switching, process
// death, and cold starts. It is scoped to the authenticated customer email.
class PendingPaymentRecord {
  final String razorpayOrderId;
  final String ownerEmail;
  final DateTime createdAt;

  const PendingPaymentRecord({
    required this.razorpayOrderId,
    required this.ownerEmail,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'razorpayOrderId': razorpayOrderId,
    'ownerEmail': ownerEmail,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static PendingPaymentRecord? fromJson(Map<String, dynamic> json) {
    final orderId = json['razorpayOrderId']?.toString() ?? '';
    final email = json['ownerEmail']?.toString().toLowerCase() ?? '';
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (orderId.isEmpty || email.isEmpty || createdAt == null) return null;
    return PendingPaymentRecord(
      razorpayOrderId: orderId,
      ownerEmail: email,
      createdAt: createdAt,
    );
  }
}

// CODEX EDITS: All clear operations compare the expected order ID so a late
// callback from an older Checkout cannot erase a newer pending payment.
class PendingPaymentService {
  static const _storageKey = 'pending_razorpay_payment_v1';

  static Future<void> save(String razorpayOrderId) async {
    final email = AppSession.email.trim().toLowerCase();
    if (razorpayOrderId.isEmpty || email.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final record = PendingPaymentRecord(
      razorpayOrderId: razorpayOrderId,
      ownerEmail: email,
      createdAt: DateTime.now(),
    );
    await prefs.setString(_storageKey, jsonEncode(record.toJson()));
  }

  static Future<PendingPaymentRecord?> loadForCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await prefs.remove(_storageKey);
        return null;
      }
      final record = PendingPaymentRecord.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (record == null) {
        await prefs.remove(_storageKey);
        return null;
      }
      final currentEmail = AppSession.email.trim().toLowerCase();
      if (currentEmail.isEmpty || record.ownerEmail != currentEmail) {
        return null;
      }
      return record;
    } catch (error) {
      debugPrint('CODEX EDITS: Failed to restore pending payment: $error');
      return null;
    }
  }

  static Future<void> clear({String? expectedOrderId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (expectedOrderId != null) {
      final current = await loadForCurrentUser();
      if (current != null && current.razorpayOrderId != expectedOrderId) return;
    }
    await prefs.remove(_storageKey);
  }

  static Future<Map<String, dynamic>?> reconcile({
    Map<String, dynamic>? sdkError,
  }) async {
    final pending = await loadForCurrentUser();
    if (pending == null) return null;
    final result = await ApiService.reconcilePayment(
      razorpayOrderId: pending.razorpayOrderId,
      sdkError: sdkError,
    );
    final state = result['state']?.toString();
    // CODEX EDITS: Captured is cleared only by the caller after cart persistence
    // and navigation state are ready, closing a process-death recovery gap.
    if (state == 'expired') {
      await clear(expectedOrderId: pending.razorpayOrderId);
    }
    return result;
  }
}
