import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../services/session.dart';
import '../model/favorite_model.dart';
import 'cafeteria_page.dart';
import 'cart_page.dart';
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
    // Restore persisted cart and favorites before any UI runs
    await Future.wait([loadCart(AppSession.userId), FavoriteModel.load(AppSession.userId)]);
    if (!mounted) return;
    await NotificationService.instance.ensurePermissionRequired(context);
    if (!mounted) return;

    // Run splash timer and Firebase auth restore in parallel — don't navigate
    // until Firebase confirms whether a session exists, or token calls will 401.
    final results = await Future.wait([
      Future.delayed(const Duration(seconds: 3)),
      FirebaseAuth.instance.authStateChanges().first,
    ]);

    // authStateChanges() can emit an initial null before the native SDK
    // finishes restoring the persisted session (platform-channel race). By the
    // time the parallel 3s splash delay has elapsed the restore is complete,
    // so fall back to currentUser — only a real sign-out leaves both null.
    final firebaseUser = (results[1] as User?) ?? FirebaseAuth.instance.currentUser;

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
