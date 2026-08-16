import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/notification_service.dart';
import '../services/session.dart';
// CODEX EDITS: Cold-start payment reconciliation runs after Firebase auth restore.
import '../services/pending_payment_service.dart';
// FEATURE 2026-08-12: Mandatory Play update gate.
import '../services/update_service.dart';
import '../model/favorite_model.dart';
import '../model/cart_model.dart';
import 'cafeteria_page.dart';
import 'cart_page.dart';
import 'checkout_page.dart';
import 'success_page.dart';
import 'update_required_page.dart';
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

    // FEATURE 2026-08-12: Mandatory update gate. If the installed build is below
    // the backend-configured minimum, block here and force a Play update — the
    // app is unusable until the user updates. A backend/network failure returns
    // false, so this never locks anyone out on a transient error.
    if (await UpdateService.isUpdateMandatory()) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const UpdateRequiredPage()),
      );
      return;
    }
    if (!mounted) return;

    // Restore persisted cart and favorites before any UI runs
    await Future.wait([
      loadCart(AppSession.userId),
      FavoriteModel.load(AppSession.userId),
    ]);
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
    User? firebaseUser =
        (results[1] as User?) ?? FirebaseAuth.instance.currentUser;

    // Fallback: session prefs exist but the SDK has no persisted user — on
    // some devices (seen on ColorOS) firebase_auth silently fails to save
    // the FIREBASE_USER entry at sign-in, so cold starts lose the session.
    // Play Services remembers the account grant at the OS level, so a silent
    // Google sign-in can rebuild the Firebase session without any UI.
    if (AppSession.isLoggedIn && firebaseUser == null) {
      firebaseUser = await _restoreFirebaseSession();
    }

    if (!mounted) return;

    if (AppSession.isLoggedIn && firebaseUser != null) {
      // CODEX EDITS: Recover a captured UPI payment before navigating home. A
      // gateway outage remains pending and never blocks normal app startup.
      if (!AppSession.isVendor) {
        try {
          final recovered = await PendingPaymentService.reconcile();
          if (!mounted) return;
          if (recovered?['state'] == 'captured' && recovered?['order'] is Map) {
            final order = Map<String, dynamic>.from(recovered!['order'] as Map);
            globalCartItems.clear();
            CartModel.clear();
            await saveCart();
            // CODEX EDITS: Clear only after local success state is durable.
            await PendingPaymentService.clear();
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => SuccessPage(order: order)),
            );
            return;
          }
          // A Paytm web redirect that returned to a cold app load reconciles to
          // a terminal failure here (reconcile clears the pending record). Open
          // Checkout straight into the blocker's failure panel — matching the
          // in-page Razorpay/Paytm-mobile failure behaviour — so the user lands
          // where they can retry, not on the home page. Cart is still restored.
          if (recovered?['state'] == 'expired') {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => CafeteriaPage(toggleTheme: widget.toggleTheme),
              ),
            );
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CheckoutPage(
                  initialPaymentFailed: true,
                  cafeteriaName: globalCartItems.isNotEmpty
                      ? globalCartItems.first['cafeteriaName']?.toString()
                      : null,
                  cafeId: globalCartItems.isNotEmpty
                      ? globalCartItems.first['cafeId']?.toString()
                      : null,
                  pickupLocation: globalCartItems.isNotEmpty
                      ? globalCartItems.first['location']?.toString()
                      : null,
                ),
              ),
            );
            return;
          }
        } catch (error) {
          // CODEX EDITS: Startup remains available offline; Checkout/resume will retry.
          debugPrint(
            'CODEX EDITS: Cold-start payment reconciliation deferred: $error',
          );
        }
      }
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

    // Firebase session missing — route to login but do NOT clear the saved
    // session prefs. A transient restore failure (or a build issue like the
    // R8 one) would otherwise permanently destroy a valid session; if the
    // user is genuinely signed out, explicit logout/auth-error paths already
    // clear it, and stale prefs alone can never pass the gate above.
    Navigator.pushReplacementNamed(context, '/login');
  }

  /// Re-establishes the Firebase session without showing any UI, for devices
  /// where firebase_auth fails to persist its user across cold starts.
  /// Returns null when no silent sign-in is possible (account signed out or
  /// access revoked) or when the restored account does not match the saved
  /// session — both fall through to the normal login page.
  Future<User?> _restoreFirebaseSession() async {
    try {
      final googleUser = await GoogleSignIn().signInSilently().timeout(
        const Duration(seconds: 10),
      );
      if (googleUser == null) return null;

      // Never pair the stored session with a different Google account.
      final sessionEmail = AppSession.email.toLowerCase();
      if (sessionEmail.isEmpty ||
          googleUser.email.toLowerCase() != sessionEmail) {
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 15));
      return result.user;
    } catch (_) {
      // Offline, timeout, or revoked grant — treat as not restorable.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Image.asset('assets/splashscreen.gif', fit: BoxFit.cover),
      ),
    );
  }
}
