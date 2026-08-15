import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:http/http.dart' as http;

/// Thrown when the server returns 401 — triggers a global sign-out.
class AuthException implements Exception {
  const AuthException();
  @override
  String toString() => 'Session expired. Please sign in again.';
}

/// Set by main.dart — called on any 401 to sign out and go to login globally.
void Function()? _onAuthError;

class ApiService {
  static set onAuthError(void Function() handler) => _onAuthError = handler;

  // Production/staging builds pass --dart-define=API_BASE_URL=... which always
  // wins. The fallback is for local `flutter run` only and must be
  // platform-aware: 10.0.2.2 is the Android-emulator alias for the host's
  // localhost and is unreachable from a browser, so web falls back to
  // localhost instead (otherwise every request fails with "Failed to fetch").
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static final String baseUrl = _envBaseUrl.isNotEmpty
      ? _envBaseUrl
      : (kIsWeb ? 'http://localhost:5000/api' : 'http://10.0.2.2:5000/api');

  static Future<Map<String, dynamic>> googleSignIn({
    required String googleId,
    required String name,
    required String email,
    required String role,
    String avatar = '',
    String? fcmToken,
    String? idToken,
  }) async {
    final body = {
      'googleId': googleId,
      'name': name,
      'email': email,
      'role': role,
      'avatar': avatar,
      'fcmToken': fcmToken,
      'idToken': idToken,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: await _jsonHeaders(includeAuth: false),
      body: jsonEncode(body),
    );

    return _decodeObject(response);
  }

  /// Returns { itemId: { available: bool, name: String } } for each requested id.
  static Future<Map<String, dynamic>> checkMenuAvailability(
    List<String> itemIds,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/menu/availability-check'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'itemIds': itemIds}),
    );
    return _decodeObject(response);
  }

  static Future<Map<String, dynamic>> updateUser(
    String userId,
    Map<String, dynamic> data,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/users/$userId'),
      headers: await _jsonHeaders(),
      body: jsonEncode(data),
    );

    return _decodeObject(response);
  }

  static Future<Map<String, dynamic>> placeOrder({
    required String customerName,
    required String customerEmail,
    required String cafeteriaName,
    String? userId,
    String? cafeId,
    required List<Map<String, dynamic>> items,
    String paymentMethod = 'UPI',
    String paymentProvider = '',
    String location = 'Pickup counter',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'customerName': customerName,
        'customerEmail': customerEmail,
        'userId': userId,
        'cafeId': cafeId,
        'cafeteriaName': cafeteriaName,
        'items': items,
        'payment': {
          'method': paymentMethod,
          'provider': paymentProvider,
          'status': 'Paid',
        },
        'location': location,
      }),
    );

    final decoded = await _decodeObject(response);
    final order = decoded['order'];
    if (order is Map) return Map<String, dynamic>.from(order);
    return decoded;
  }

  static Future<List<Map<String, dynamic>>> getOrders({
    String? cafeId,
    String? status,
    String? customerEmail,
    String? date,
  }) async {
    final uri = Uri.parse('$baseUrl/orders').replace(
      queryParameters: {
        if (cafeId != null && cafeId.isNotEmpty) 'cafeId': cafeId,
        if (status != null && status.isNotEmpty) 'status': status,
        if (customerEmail != null && customerEmail.isNotEmpty)
          'customerEmail': customerEmail,
        if (date != null && date.isNotEmpty) 'date': date,
      },
    );

    final response = await http.get(uri, headers: await _jsonHeaders());
    return _decodeList(response);
  }

  static Future<List<Map<String, dynamic>>> getCafes({String? search}) async {
    final uri = Uri.parse('$baseUrl/cafes').replace(
      queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    final response = await http.get(uri);
    return _decodeList(response);
  }

  static Future<void> setCafeActive(
    String cafeId, {
    required bool active,
  }) async {
    final uri = Uri.parse('$baseUrl/cafes/$cafeId');
    final response = await http.patch(
      uri,
      headers: await _jsonHeaders(),
      body: jsonEncode({'active': active}),
    );
    await _decodeObject(response);
  }

  static Future<List<Map<String, dynamic>>> getMenu({String? cafeId}) async {
    final uri = Uri.parse('$baseUrl/menu').replace(
      queryParameters: {
        if (cafeId != null && cafeId.isNotEmpty) 'cafeId': cafeId,
      },
    );
    final response = await http.get(uri);
    return _decodeList(response);
  }

  static Future<Map<String, dynamic>> createMenuItem({
    required String name,
    required int price,
    required String category,
    required String cafeId,
    required String vendorId,
    bool available = true,
    String description = '',
    String image = '',
    String imageType = 'none',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/menu'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'name': name,
        'price': price,
        'category': category,
        'cafeId': cafeId,
        'vendorId': vendorId,
        'available': available,
        'description': description,
        'image': image,
        'imageType': imageType,
      }),
    );

    return _decodeObject(response);
  }

  static Future<Map<String, dynamic>> updateMenuItem(
    String itemId,
    Map<String, dynamic> data,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/menu/$itemId'),
      headers: await _jsonHeaders(),
      body: jsonEncode(data),
    );
    return _decodeObject(response);
  }

  static Future<void> deleteMenuItem(String itemId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/menu/$itemId'),
      headers: await _jsonHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Request failed with status ${response.statusCode}';
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['message'] != null) {
          message = decoded['message'].toString();
        }
      }
      throw Exception(message);
    }
  }

  static Future<Map<String, dynamic>> updateOrderStatus(
    String orderId,
    String status,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/orders/$orderId/status'),
      headers: await _jsonHeaders(),
      body: jsonEncode({'status': status}),
    );

    return _decodeObject(response);
  }

  static Future<Map<String, dynamic>> getVendorDashboard(
    String vendorId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/vendor/$vendorId/dashboard'),
      headers: await _jsonHeaders(),
    );
    return _decodeObject(response);
  }

  /// Step 1: compute totals server-side and create a gateway order.
  /// No DB order is created yet — returns razorpayOrder or paytmOrder
  /// depending on the selected gateway.
  static Future<Map<String, dynamic>> initiatePayment({
    required String customerName,
    required String customerEmail,
    required String cafeteriaName,
    String? userId,
    String? cafeId,
    required List<Map<String, dynamic>> items,
    String location = 'Pickup counter',
    String pickupTime = '',
    String gateway = 'razorpay',
    String channel = 'app',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/payment/initiate'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'customerName': customerName,
        'customerEmail': customerEmail,
        'userId': userId,
        'cafeId': cafeId,
        'cafeteriaName': cafeteriaName,
        'items': items,
        'location': location,
        'pickupTime': pickupTime,
        'gateway': gateway,
        'channel': channel,
      }),
    );
    return _decodeObject(response);
  }

  /// Per-gateway fee structure, read live from the backend's fee_configs
  /// collection. Public endpoint — no auth header needed.
  static Future<Map<String, dynamic>> getPaymentFees() async {
    final response = await http.get(Uri.parse('$baseUrl/payment/fees'));
    return _decodeObject(response);
  }

  /// Step 2: verify Razorpay signature server-side and create the DB order.
  /// Only called after Razorpay reports a successful payment.
  static Future<Map<String, dynamic>> confirmOrder({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders/confirm'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
      }),
    );
    return _decodeObject(response);
  }

  /// Recovery: look up an order by its Razorpay order id. Used when the
  /// payment succeeded but the checkout success callback was lost (e.g. the
  /// app was backgrounded during a UPI redirect) — the order is then created
  /// by the server-side Razorpay webhook and fetched here.
  static Future<Map<String, dynamic>> getOrderByRazorpayOrderId(
    String razorpayOrderId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/orders/by-payment/$razorpayOrderId'),
      headers: await _jsonHeaders(),
    );
    return _decodeObject(response);
  }

  // CODEX EDITS: Ask the authenticated backend to fetch Razorpay's authoritative
  // order/payment state. Rich SDK diagnostics are optional and never trusted as
  // proof of success or failure.
  static Future<Map<String, dynamic>> reconcilePayment({
    required String razorpayOrderId,
    Map<String, dynamic>? sdkError,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/payment/reconcile'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'razorpay_order_id': razorpayOrderId,
        'sdk_error': ?sdkError,
      }),
    );
    return _decodeObject(response);
  }

  static Future<Map<String, dynamic>> rateCafe({
    required String cafeId,
    required String userId,
    required int stars,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/cafes/$cafeId/review'),
      headers: await _jsonHeaders(),
      body: jsonEncode({'userId': userId, 'stars': stars}),
    );
    return _decodeObject(response);
  }

  static Future<Map<String, dynamic>> deleteRating({
    required String cafeId,
    String? userId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/cafes/$cafeId/review'),
      headers: await _jsonHeaders(),
    );
    return _decodeObject(response);
  }

  static Future<Map<String, int>> getUserRatings(String userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/$userId/ratings'),
      headers: await _jsonHeaders(),
    );
    final raw = await _decodeObject(response);
    return raw.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  static Future<List<Map<String, dynamic>>> getNotifications(
    String userId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications/$userId'),
      headers: await _jsonHeaders(),
    );
    return _decodeList(response);
  }

  static Future<void> registerFcmToken(String userId, String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/$userId/fcm-token'),
      headers: await _jsonHeaders(),
      body: jsonEncode({'token': token}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = jsonDecode(response.body);
      final message = decoded is Map && decoded['message'] != null
          ? decoded['message'].toString()
          : 'Request failed with status ${response.statusCode}';
      throw Exception(message);
    }
  }

  static Future<void> sendPromotionNotification({
    required String title,
    required String message,
    List<String>? targetUserIds,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/notifications/send'),
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'title': title,
        'message': message,
        'targetUserIds': ?targetUserIds,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = jsonDecode(response.body);
      final message = decoded is Map && decoded['message'] != null
          ? decoded['message'].toString()
          : 'Request failed with status ${response.statusCode}';
      throw Exception(message);
    }
  }

  static Future<void> markNotificationAsRead(String notificationId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/notifications/$notificationId/read'),
      headers: await _jsonHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = jsonDecode(response.body);
      final message = decoded is Map && decoded['message'] != null
          ? decoded['message'].toString()
          : 'Request failed with status ${response.statusCode}';
      throw Exception(message);
    }
  }

  static Future<void> deleteNotification(String notificationId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/notifications/$notificationId'),
      headers: await _jsonHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = jsonDecode(response.body);
      final message = decoded is Map && decoded['message'] != null
          ? decoded['message'].toString()
          : 'Request failed with status ${response.statusCode}';
      throw Exception(message);
    }
  }

  static Future<Map<String, dynamic>> _decodeObject(
    http.Response response,
  ) async {
    // CODEX EDITS: Nginx/AWS can return HTML/plain-text 502/503/504 when the
    // Node server is down; decode safely so users never see JSON parser errors.
    final decoded = await _safeDecode(response);
    if (response.statusCode == 401) {
      _onAuthError?.call();
      throw const AuthException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_messageFromResponse(response, decoded));
    }
    if (decoded is! Map) {
      throw Exception('Invalid server response. Please try again.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Future<Map<String, String>> _jsonHeaders({
    bool includeAuth = true,
  }) async {
    final headers = {'Content-Type': 'application/json'};
    if (!includeAuth) return headers;

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // Token fetch failed (no network, expired refresh token) — request will
      // get a 401 from the server which the UI handles as an auth error.
    }
    return headers;
  }

  static Future<List<Map<String, dynamic>>> _decodeList(
    http.Response response,
  ) async {
    // CODEX EDITS: Safely handle proxy/server-down responses before parsing a
    // list, otherwise HTML 503 pages surface as "Unexpected character".
    final decoded = await _safeDecode(response);
    if (response.statusCode == 401) {
      _onAuthError?.call();
      throw const AuthException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_messageFromResponse(response, decoded));
    }
    if (decoded is! List) {
      throw Exception('Invalid server response. Please try again.');
    }
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  // Payloads above this size (menu/cafe lists carry inline base64 images and
  // easily reach hundreds of KB) are parsed in a background isolate so the UI
  // thread never janks mid-scroll. Below it, isolate spawn overhead would
  // exceed the parse cost. Web has no isolates — it parses inline as before.
  static const int _isolateDecodeThreshold = 64 * 1024;

  static dynamic _jsonParse(String source) => jsonDecode(source);

  static Future<dynamic> _safeDecode(http.Response response) async {
    try {
      final body = response.body.trim();
      if (body.isEmpty) return null;
      if (!kIsWeb && body.length > _isolateDecodeThreshold) {
        return await compute(_jsonParse, body);
      }
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static String _messageFromResponse(http.Response response, dynamic decoded) {
    if (decoded is Map && decoded['message'] != null) {
      return decoded['message'].toString();
    }
    if (response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504) {
      return 'Server is currently unavailable. Please try again.';
    }
    return 'Request failed with status ${response.statusCode}';
  }
}
