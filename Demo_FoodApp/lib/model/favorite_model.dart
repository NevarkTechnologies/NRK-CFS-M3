class FavoriteModel {
  static List<Map<String, dynamic>> favorites = [];

  static void toggleFavorite(Map<String, dynamic> food) {
    final index = favorites.indexWhere((item) => item["id"] == food["id"]);

    if (index != -1) {
      favorites.removeAt(index);
    } else {
      favorites.add(food);
    }
  }

  static bool isFavorite(String id) {
    return favorites.any((item) => item["id"] == id);
  }
}
