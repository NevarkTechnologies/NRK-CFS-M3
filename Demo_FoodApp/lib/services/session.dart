class AppSession {
  static Map<String, dynamic>? currentUser;

  static bool get isLoggedIn => currentUser != null;
  static bool get isVendor => currentUser?["role"] == "vendor";

  static String get userId => currentUser?["_id"]?.toString() ?? "";
  static String get name => currentUser?["name"]?.toString() ?? "John Doe";
  static String get email => currentUser?["email"]?.toString() ?? "user@gmail.com";
  static String get vendorId {
    final id = currentUser?['_id']?.toString();
    if (id != null && id.isNotEmpty) return id;
    return currentUser?["vendorId"]?.toString() ?? "";
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
  static String get paymentLabel => currentUser?["paymentLabel"]?.toString() ?? "UPI";

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

  static void setUser(Map<String, dynamic> user) {
    currentUser = user;
  }

  static void clear() {
    currentUser = null;
  }
}
