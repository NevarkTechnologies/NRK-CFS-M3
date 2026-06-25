import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSession {
  static Map<String, dynamic>? currentUser;
  static const String _userKey = 'app_user_session';

  static bool get isLoggedIn => currentUser != null;
  static bool get isVendor => currentUser?["role"] == "vendor";

  static String get userId => currentUser?["_id"]?.toString() ?? "";
  static String get name => currentUser?["name"]?.toString() ?? "";
  static String get email => currentUser?["email"]?.toString() ?? "";
  static String get vendorId {
    final vendor = currentUser?["vendorId"]?.toString();
    if (vendor != null && vendor.isNotEmpty) return vendor;
    return currentUser?["_id"]?.toString() ?? "";
  }

  static String get cafeId {
    final cafeData = currentUser?["cafeId"];

    if (cafeData is Map<String, dynamic>) {
      return cafeData["_id"]?.toString() ?? "";
    }

    if (cafeData is Map) {
      return cafeData["_id"]?.toString() ?? "";
    }

    return cafeData?.toString() ?? "";
  }

  static String get phone => currentUser?["phone"]?.toString() ?? "";

  static String get paymentLabel =>
      currentUser?["paymentLabel"]?.toString() ?? "UPI";

  static Map<String, dynamic> get address {
    final value = currentUser?["address"];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  static Map<String, dynamic>? get cafe {
    final value = currentUser?["cafeId"];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  /// Initialize session from persistent storage
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);
      if (userJson != null) {
        currentUser = jsonDecode(userJson) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error initializing session: $e');
    }
  }

  /// Save user to session and persist to storage
  static Future<void> setUser(Map<String, dynamic> user) async {
    currentUser = user;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(user));
    } catch (e) {
      debugPrint('Error saving user session: $e');
    }
  }

  /// Clear session and persistent storage
  static Future<void> clear() async {
    currentUser = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
    } catch (e) {
      debugPrint('Error clearing session: $e');
    }
  }
}
