import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

    // Run splash timer and Firebase auth restore in parallel — don't navigate
    // until Firebase confirms whether a session exists, or token calls will 401.
    final results = await Future.wait([
      Future.delayed(const Duration(seconds: 3)),
      FirebaseAuth.instance.authStateChanges().first,
    ]);

    final firebaseUser = results[1] as User?;

    if (!mounted) return;

    if (AppSession.isLoggedIn && firebaseUser != null) {
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

    // Session data exists but Firebase session is gone — clear stale data.
    if (AppSession.isLoggedIn) {
      await AppSession.clear();
      if (!mounted) return;
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
