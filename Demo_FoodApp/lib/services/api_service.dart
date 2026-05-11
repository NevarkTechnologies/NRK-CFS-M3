import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5000/api',
  );

  static Future<Map<String, dynamic>> googleSignIn({
    required String googleId,
    required String name,
    required String email,
    String avatar = '',
    String? fcmToken,
  }) async {
    final body = {
      'googleId': googleId,
      'name': name,
      'email': email,
      'avatar': avatar,
      if (fcmToken != null) 'fcmToken': fcmToken,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    return _decodeObject(response);
  }

  static Future<Map<String, dynamic>> updateUser(
    String userId,
    Map<String, dynamic> data,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/users/$userId'),
      headers: {'Content-Type': 'application/json'},
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
      headers: {'Content-Type': 'application/json'},
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

    return _decodeObject(response);
  }

  static Future<List<Map<String, dynamic>>> getOrders({
    String? cafeId,
    String? status,
    String? customerEmail,
  }) async {
    final uri = Uri.parse('$baseUrl/orders').replace(queryParameters: {
      if (cafeId != null && cafeId.isNotEmpty) 'cafeId': cafeId,
      if (status != null && status.isNotEmpty) 'status': status,
      if (customerEmail != null && customerEmail.isNotEmpty) 'customerEmail': customerEmail,
    });

    final response = await http.get(uri);
    return _decodeList(response);
  }

  static Future<List<Map<String, dynamic>>> getCafes({String? search}) async {
    final uri = Uri.parse('$baseUrl/cafes').replace(queryParameters: {
      if (search != null && search.isNotEmpty) 'search': search,
    });
    final response = await http.get(uri);
    return _decodeList(response);
  }

  static Future<List<Map<String, dynamic>>> getMenu({String? cafeId}) async {
    final uri = Uri.parse('$baseUrl/menu').replace(queryParameters: {
      if (cafeId != null && cafeId.isNotEmpty) 'cafeId': cafeId,
    });
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
      headers: {'Content-Type': 'application/json'},
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

  static Future<Map<String, dynamic>> updateMenuItem(String itemId, Map<String, dynamic> data) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/menu/$itemId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    return _decodeObject(response);
  }

  static Future<void> deleteMenuItem(String itemId) async {
    final response = await http.delete(Uri.parse('$baseUrl/menu/$itemId'));
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

  static Future<Map<String, dynamic>> updateOrderStatus(String orderId, String status) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/orders/$orderId/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    );

    return _decodeObject(response);
  }

  static Future<Map<String, dynamic>> getVendorDashboard(String vendorId) async {
    final response = await http.get(Uri.parse('$baseUrl/vendor/$vendorId/dashboard'));
    return _decodeObject(response);
  }
  static Future<List<Map<String, dynamic>>> getNotifications(String userId) async {
    final response = await http.get(Uri.parse('$baseUrl/notifications/$userId'));
    return _decodeList(response);
  }

  static Future<void> registerFcmToken(String userId, String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/$userId/fcm-token'),
      headers: {'Content-Type': 'application/json'},
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
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'message': message,
        if (targetUserIds != null) 'targetUserIds': targetUserIds,
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
      headers: {'Content-Type': 'application/json'},
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
  final response = await http.delete(Uri.parse('$baseUrl/notifications/$notificationId'));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    final decoded = jsonDecode(response.body);
    final message = decoded is Map && decoded['message'] != null
        ? decoded['message'].toString()
        : 'Request failed with status ${response.statusCode}';
    throw Exception(message);
  }
}

  static Map<String, dynamic> _decodeObject(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map && decoded['message'] != null
          ? decoded['message'].toString()
          : 'Request failed with status ${response.statusCode}';
      throw Exception(message);
    }
    return Map<String, dynamic>.from(decoded as Map);
  }

  static List<Map<String, dynamic>> _decodeList(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map && decoded['message'] != null
          ? decoded['message'].toString()
          : 'Request failed with status ${response.statusCode}';
      throw Exception(message);
    }
    return (decoded as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }
}

