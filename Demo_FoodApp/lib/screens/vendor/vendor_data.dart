import '../../services/session.dart';

class VendorData {
  static const String notSet = "Not set yet";
  static String imageUrl = "";

  static String get displayImage {
    final cafeImage = AppSession.cafe?['image']?.toString().trim();
    return cafeImage != null && cafeImage.isNotEmpty ? cafeImage : "";
  }

  static String get displayName {
    final cafeName = AppSession.cafe?['name']?.toString().trim();
    if (cafeName != null && cafeName.isNotEmpty) return cafeName;
    return AppSession.name.isNotEmpty ? AppSession.name : notSet;
  }

  static String get displayCuisine {
    final cafeCuisine = AppSession.cafe?['cuisine']?.toString().trim();
    return cafeCuisine != null && cafeCuisine.isNotEmpty ? cafeCuisine : notSet;
  }

  static String get displayDescription {
    final cafeDescription = AppSession.cafe?['description']?.toString().trim();
    return cafeDescription != null && cafeDescription.isNotEmpty
        ? cafeDescription
        : notSet;
  }

  static String get displayEmail {
    return AppSession.email.isNotEmpty ? AppSession.email : notSet;
  }

  static String get displayPhone {
    final userPhone = AppSession.currentUser?['phone']?.toString().trim();
    return userPhone != null && userPhone.isNotEmpty ? userPhone : notSet;
  }

  static String get displayAddress {
    final location = AppSession.cafe?['location']?.toString().trim();
    return location != null && location.isNotEmpty ? location : notSet;
  }

  static String get displayCity {
    final cafeCity = AppSession.cafe?['city']?.toString().trim();
    return cafeCity != null && cafeCity.isNotEmpty ? cafeCity : notSet;
  }

  static String get displayPin {
    final cafePin = AppSession.cafe?['pin']?.toString().trim();
    return cafePin != null && cafePin.isNotEmpty ? cafePin : notSet;
  }

  static bool get isBusinessDetailsComplete {
    final cafe = AppSession.cafe;
    if (cafe == null) return false;

    final name = cafe['name']?.toString().trim();
    final cuisine = cafe['cuisine']?.toString().trim();
    final description = cafe['description']?.toString().trim();
    final location = cafe['location']?.toString().trim();
    final city = cafe['city']?.toString().trim();
    final pin = cafe['pin']?.toString().trim();
    final phone = AppSession.currentUser?['phone']?.toString().trim();

    return name != null && name.isNotEmpty &&
        cuisine != null && cuisine.isNotEmpty &&
        description != null && description.isNotEmpty &&
        location != null && location.isNotEmpty &&
        city != null && city.isNotEmpty &&
        pin != null && pin.isNotEmpty &&
        phone != null && phone.isNotEmpty;
  }
}
