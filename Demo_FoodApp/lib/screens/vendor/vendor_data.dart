import '../../services/session.dart';

class VendorData {
  static String name = "Burger King";
  static String cuisine = "Burgers, Fast Food";
  static String description = "Premium burgers and fast food with fresh ingredients";
  static String phone = "+91 98765 43210";
  static String email = "contact@burgerking.com";
  static String imageUrl = "";
  static String get displayImage {
  final cafeImage = AppSession.cafe?['image']?.toString().trim();

  if (cafeImage != null && cafeImage.isNotEmpty) {
    return cafeImage;
  }

  return VendorData.imageUrl;
}
  static String address = "Shop No. 12, Food Court, Tech Park";
  static String city = "Noida";
  static String pin = "201301";

  static bool orderNotif = true;
  static bool emailNotif = true;
  static bool smsNotif = false;

  static String get displayName {
    final cafeName = AppSession.cafe?['name']?.toString().trim();
    if (cafeName != null && cafeName.isNotEmpty) return cafeName;
    return AppSession.name;
  }

  static String get displayCuisine {
    final cafeCuisine = AppSession.cafe?['cuisine']?.toString().trim();
    return cafeCuisine != null && cafeCuisine.isNotEmpty ? cafeCuisine : VendorData.cuisine;
  }

  static String get displayDescription {
    final cafeDescription = AppSession.cafe?['description']?.toString().trim();
    return cafeDescription != null && cafeDescription.isNotEmpty ? cafeDescription : VendorData.description;
  }

  static String get displayEmail {
    return AppSession.email.isNotEmpty ? AppSession.email : VendorData.email;
  }

  static String get displayPhone {
    final userPhone = AppSession.currentUser?['phone']?.toString().trim();
    return userPhone != null && userPhone.isNotEmpty ? userPhone : VendorData.phone;
  }

  static String get displayAddress {
    final location = AppSession.cafe?['location']?.toString().trim();
    return location != null && location.isNotEmpty ? location : VendorData.address;
  }

  static String get displayCity {
    final cafeCity = AppSession.cafe?['city']?.toString().trim();
    return cafeCity != null && cafeCity.isNotEmpty ? cafeCity : VendorData.city;
  }

  static String get displayPin {
    final cafePin = AppSession.cafe?['pin']?.toString().trim();
    return cafePin != null && cafePin.isNotEmpty ? cafePin : VendorData.pin;
  }
}