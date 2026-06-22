import 'dart:async';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/session.dart';
import 'cafeteria_page.dart';
import 'vendor/vendor_home_page.dart';

class SplashPage extends StatefulWidget {
  final VoidCallback toggleTheme;

  const SplashPage({super.key, required this.toggleTheme});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {

  @override
  void initState() {
    super.initState();
    _navigate();
  }

  void _navigate() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final allowed = await NotificationService.instance.ensurePermissionRequired(context);
    if (!allowed || !mounted) return;

    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;
    if (AppSession.isLoggedIn) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AppSession.isVendor
              ? VendorHomePage(toggleTheme: widget.toggleTheme)
              : CafeteriaPage(toggleTheme: widget.toggleTheme),
        ),
      );
      return;
    }

    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Image.asset(
          'assets/splashscreen.gif',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
