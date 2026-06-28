import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FavoriteModel {
  static List<Map<String, dynamic>> favorites = [];
  static String _userId = '';

  static String _key() => 'favorites_$_userId';

  static void toggleFavorite(Map<String, dynamic> food) {
    final index = favorites.indexWhere((item) => item["id"] == food["id"]);
    if (index != -1) {
      favorites.removeAt(index);
    } else {
      favorites.add(food);
    }
    save();
  }

  static bool isFavorite(String id) {
    return favorites.any((item) => item["id"] == id);
  }

  static Future<void> save() async {
    if (_userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(), jsonEncode(favorites));
    } catch (_) {}
  }

  static Future<void> load(String userId) async {
    _userId = userId;
    favorites = [];
    if (userId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_key());
      if (str != null) {
        final decoded = jsonDecode(str) as List<dynamic>;
        favorites = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
  }

  static void clear() {
    favorites = [];
    _userId = '';
  }
}
