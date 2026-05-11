import 'package:flutter/material.dart';
import 'screens/vendor/vendor_home_page.dart';

void main() {
  runApp(const VendorApp());
}

class VendorApp extends StatelessWidget {
  const VendorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: VendorHomePage(toggleTheme: () {}),
    );
  }
}
