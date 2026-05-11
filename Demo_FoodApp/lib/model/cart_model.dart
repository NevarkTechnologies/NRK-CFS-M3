

class CartModel {
  /// stores itemId : quantity
  static Map<String, int> cart = {};

  /// ➕ Add item
  static void add(String id) {
    cart[id] = (cart[id] ?? 0) + 1;
  }

  /// ➖ Remove item
  static void remove(String id) {
    if (!cart.containsKey(id)) return;

    if (cart[id]! > 1) {
      cart[id] = cart[id]! - 1;
    } else {
      cart.remove(id);
    }
  }

  /// ❌ Remove completely
  static void delete(String id) {
    cart.remove(id);
  }

  /// 🔢 Get quantity
  static int getQty(String id) {
    return cart[id] ?? 0;
  }

  /// 🧹 Clear cart
  static void clear() {
    cart.clear();
  }
}
