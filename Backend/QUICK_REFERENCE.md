# Quick Reference: Vendor-Cafeteria Connection Implementation

## System Architecture

```
┌─────────────────┐
│   Google Auth   │
│    (Firebase)   │
└────────┬────────┘
         │
         ▼
    ┌─────────┐
    │ User    │ ← role: 'vendor'
    │ _id     │
    │ cafeId  │ ──┐
    └─────────┘   │
                  │ ObjectId reference
                  │
    ┌─────────┐   │
    │ Cafe    │ ◄─┘
    │ _id     │
    │vendorId │ ──┐
    └─────────┘   │
                  │ ObjectId reference
                  │
    ┌──────────────┴──────────┐
    │                         │
┌───┴─────┐          ┌────────┴────┐
│ MenuItem│          │  MenuItem   │
│cafeId   │          │ vendorId    │
│vendorId │          │             │
└─────────┘          └─────────────┘
```

## API Quick Reference

| Operation | Method | Endpoint | Purpose |
|-----------|--------|----------|---------|
| Login | POST | `/api/auth/google` | Auth & auto-link vendor to cafe |
| Assign Cafe to Vendor | POST | `/api/vendors/:vendorId/assign-cafe` | Link vendor with cafeteria |
| Get Vendor's Cafe | GET | `/api/vendors/:vendorId/cafes` | Retrieve assigned cafeteria |
| Get Cafe's Vendor | GET | `/api/cafes/:cafeId/vendor` | Get vendor info for a cafe |
| Get Vendor's Menu | GET | `/api/vendors/:vendorId/menu` | All items from this vendor |
| Get Cafe's Menu | GET | `/api/cafes/:cafeId/menu` | All items in this cafeteria |
| Unassign Cafe | DELETE | `/api/vendors/:vendorId/cafes/:cafeId` | Remove vendor-cafe link |

## Flutter Implementation Examples

### 1. Vendor Login (Auto-linking)

```dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AuthService {
  final String baseUrl = 'http://your-backend-url';
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<void> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'googleId': googleUser.id,
          'name': googleUser.displayName,
          'email': googleUser.email,
          'avatar': googleUser.photoUrl,
        }),
      );

      if (response.statusCode == 200) {
        final userData = jsonDecode(response.body);
        
        // If vendor, cafeId is auto-populated
        if (userData['role'] == 'vendor' && userData['cafeId'] != null) {
          print('Vendor linked to: ${userData['cafeId']['name']}');
        }
        
        // Store user data (Firebase, SharedPreferences, Provider, etc.)
        return userData;
      }
    } catch (e) {
      print('Error: $e');
    }
  }
}
```

### 2. Assign Cafeteria to Vendor

```dart
class VendorService {
  final String baseUrl = 'http://your-backend-url';

  Future<void> assignCafeteriaToVendor(
    String vendorId,
    String cafeId,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/vendors/$vendorId/assign-cafe'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'cafeId': cafeId}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        print('Vendor assigned to: ${result['cafe']['name']}');
        return result;
      } else {
        throw Exception('Failed to assign cafeteria');
      }
    } catch (e) {
      print('Error: $e');
    }
  }
}
```

### 3. Get Vendor's Assigned Cafeteria

```dart
Future<Map<String, dynamic>?> getVendorCafeteria(String vendorId) async {
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/vendors/$vendorId/cafes'),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      if (result['cafe'] != null) {
        return result['cafe'];
      }
      return null;
    }
  } catch (e) {
    print('Error: $e');
  }
}
```

### 4. Get Vendor's Menu Items

```dart
class MenuService {
  final String baseUrl = 'http://your-backend-url';

  Future<List<MenuItem>> getVendorMenuItems(String vendorId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/vendors/$vendorId/menu'),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final items = (result['items'] as List)
            .map((item) => MenuItem.fromJson(item))
            .toList();
        return items;
      }
    } catch (e) {
      print('Error: $e');
    }
    return [];
  }

  Future<List<MenuItem>> getCafeMenuItems(String cafeId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/cafes/$cafeId/menu'),
      );

      if (response.statusCode == 200) {
        final items = (jsonDecode(response.body) as List)
            .map((item) => MenuItem.fromJson(item))
            .toList();
        return items;
      }
    } catch (e) {
      print('Error: $e');
    }
    return [];
  }
}
```

### 5. Create Menu Item with Vendor Reference

```dart
Future<void> createMenuItem({
  required String cafeId,
  required String vendorId,
  required String name,
  required double price,
  required String category,
}) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/api/menu'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'cafeId': cafeId,
        'vendorId': vendorId,
        'name': name,
        'price': price,
        'category': category,
        'available': true,
        'isVeg': true,
      }),
    );

    if (response.statusCode == 201) {
      print('Menu item created successfully');
      return jsonDecode(response.body);
    }
  } catch (e) {
    print('Error: $e');
  }
}
```

### 6. Model Classes

```dart
class MenuItem {
  final String id;
  final String name;
  final double price;
  final String cafeId;
  final String vendorId;
  final String category;
  final bool available;
  final bool isVeg;

  MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.cafeId,
    required this.vendorId,
    required this.category,
    required this.available,
    required this.isVeg,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['_id'] ?? '',
      name: json['name'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      cafeId: json['cafeId'] is Map ? json['cafeId']['_id'] : json['cafeId'],
      vendorId: json['vendorId'] is Map ? json['vendorId']['_id'] : json['vendorId'],
      category: json['category'] ?? '',
      available: json['available'] ?? true,
      isVeg: json['isVeg'] ?? true,
    );
  }
}

class Cafe {
  final String id;
  final String name;
  final String slug;
  final String cuisine;
  final String? vendorId;
  final String? vendorName;
  final double rating;
  final String location;

  Cafe({
    required this.id,
    required this.name,
    required this.slug,
    required this.cuisine,
    this.vendorId,
    this.vendorName,
    required this.rating,
    required this.location,
  });

  factory Cafe.fromJson(Map<String, dynamic> json) {
    return Cafe(
      id: json['_id'] ?? '',
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      cuisine: json['cuisine'] ?? '',
      vendorId: json['vendorId'] is Map ? json['vendorId']['_id'] : json['vendorId'],
      vendorName: json['vendorId'] is Map ? json['vendorId']['name'] : null,
      rating: (json['rating'] ?? 4.0).toDouble(),
      location: json['location'] ?? '',
    );
  }
}

class User {
  final String id;
  final String name;
  final String email;
  final String role; // 'customer', 'vendor', 'admin'
  final String? cafeId;
  final Cafe? cafe;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.cafeId,
    this.cafe,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'customer',
      cafeId: json['cafeId'] is Map ? json['cafeId']['_id'] : json['cafeId'],
      cafe: json['cafeId'] != null && json['cafeId'] is Map
          ? Cafe.fromJson(json['cafeId'])
          : null,
    );
  }
}
```

### 7. Provider Pattern (State Management)

```dart
import 'package:flutter/material.dart';

class VendorProvider extends ChangeNotifier {
  Cafe? _assignedCafe;
  List<MenuItem> _menuItems = [];
  String? _vendorId;

  Cafe? get assignedCafe => _assignedCafe;
  List<MenuItem> get menuItems => _menuItems;

  final VendorService _vendorService = VendorService();

  Future<void> assignCafe(String vendorId, String cafeId) async {
    _vendorId = vendorId;
    await _vendorService.assignCafeteriaToVendor(vendorId, cafeId);
    await loadAssignedCafe();
  }

  Future<void> loadAssignedCafe() async {
    if (_vendorId != null) {
      _assignedCafe = await _vendorService.getVendorCafeteria(_vendorId!);
      notifyListeners();
    }
  }

  Future<void> loadMenuItems() async {
    if (_vendorId != null) {
      final menuService = MenuService();
      _menuItems = await menuService.getVendorMenuItems(_vendorId!);
      notifyListeners();
    }
  }
}
```

## Key Points

✅ **Bidirectional Linking:** When you assign a vendor to a cafe, both sides are updated automatically

✅ **Auto-population:** When a vendor logs in via Firebase, their assigned cafe is automatically retrieved

✅ **Type Safety:** Use ObjectId references instead of string IDs for better data integrity

✅ **Backwards Compatible:** Legacy string IDs still work via `legacyVendorId` field

✅ **Populated References:** API responses include nested vendor/cafe information when requested

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| Vendor doesn't have cafe after login | Run migration script, ensure vendorId is ObjectId in database |
| Menu items not showing vendor | Use `/api/vendors/{id}/menu` endpoint with proper ID type |
| Can't find vendor for a cafe | Check `GET /api/cafes/{id}/vendor` response, ensure vendorId is linked |
| ObjectId validation errors | Pass actual MongoDB user `_id`, not custom vendorId strings |

---

For detailed API documentation, see [VENDOR_CAFE_RELATIONSHIP.md](./VENDOR_CAFE_RELATIONSHIP.md)

For data migration, see [MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md)
