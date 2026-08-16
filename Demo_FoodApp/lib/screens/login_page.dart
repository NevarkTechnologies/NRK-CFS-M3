import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:ui' as ui;
import '../services/google_signin_button_web.dart'
    if (dart.library.io) '../services/google_signin_button_stub.dart'
    as gsi_button;
import 'package:google_fonts/google_fonts.dart';
import 'vendor/vendor_home_page.dart';
import 'cafeteria_page.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/session.dart';
// CODEX EDITS: Recover payments made before an auth/process interruption.
import '../services/pending_payment_service.dart';
import '../model/favorite_model.dart';
import '../model/cart_model.dart';
import 'cart_page.dart';
import 'success_page.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback? toggleTheme;
  const LoginPage({super.key, this.toggleTheme});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final Color appBlue = const Color(0xFF2563EB);
  bool isSigningIn = false;

  // Web-only Google Sign-In. On web the imperative signIn() can't return an
  // idToken, so we render Google's GIS button and receive the credential
  // (with idToken) via onCurrentUserChanged. Both are unused on mobile.
  GoogleSignIn? _webGoogleSignIn;
  StreamSubscription<GoogleSignInAccount?>? _webAuthSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Client ID is auto-detected from the <meta google-signin-client_id>
      // tag in web/index.html (the same mechanism splash_page relies on).
      _webGoogleSignIn = GoogleSignIn();
      _webAuthSub = _webGoogleSignIn!.onCurrentUserChanged.listen(
        _onWebUserChanged,
      );
    }
  }

  @override
  void dispose() {
    _webAuthSub?.cancel();
    super.dispose();
  }

  Future<void> _askPhoneNumber(String userId) async {
    final ctrl = TextEditingController();
    bool isValidPhone = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F4CFF).withValues(alpha: 0.15),
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F4CFF).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.phone_android_rounded,
                        color: Color(0xFF0F4CFF),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Add Phone Number',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Add your number so that payment can be processed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.white60
                            : const Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      onChanged: (value) {
                        setDialogState(() {
                          isValidPhone = RegExp(
                            r'^\d{10}$',
                          ).hasMatch(value.trim());
                        });
                      },
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter Number',
                        prefixIcon: const Icon(
                          Icons.local_phone_rounded,
                          color: Color(0xFF0F4CFF),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFF0F4CFF).withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF0F4CFF),
                            width: 1.5,
                          ),
                        ),
                        counterText: '',
                        errorText: ctrl.text.isEmpty || isValidPhone
                            ? null
                            : 'Please enter a valid 10-digit phone number',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0F4CFF),
                              side: const BorderSide(
                                color: Color(0xFF0F4CFF),
                                width: 1.5,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text(
                              'Skip',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F4CFF),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: !isValidPhone
                                ? null
                                : () async {
                                    final phone = ctrl.text.trim();
                                    if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Enter Valid 10-Digit Phone Number',
                                          ),
                                          backgroundColor: Colors.redAccent,
                                          behavior: SnackBarBehavior.floating,
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                      return;
                                    }
                                    try {
                                      await ApiService.updateUser(userId, {
                                        'phone': '+91$phone',
                                      });
                                      await AppSession.setUser({
                                        ...AppSession.currentUser!,
                                        'phone': '+91$phone',
                                      });
                                    } catch (_) {}

                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                            child: const Text(
                              'Save',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Web: Google's rendered GIS button delivers a signed-in account (carrying a
  // valid idToken) through onCurrentUserChanged. signIn() can't return an
  // idToken on web, so web routes through here instead of _signInWithGoogle.
  Future<void> _onWebUserChanged(GoogleSignInAccount? account) async {
    if (account == null || isSigningIn || !mounted) return;
    setState(() => isSigningIn = true);
    try {
      final googleAuth = await account.authentication;
      await _authenticateWithGoogle(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
    } catch (e) {
      _handleSignInError(e);
    }
  }

  // Mobile: imperative Google sign-in triggered by the custom button.
  Future<void> _signInWithGoogle() async {
    if (isSigningIn) return;
    setState(() => isSigningIn = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();

      try {
        await googleSignIn.signOut();
      } catch (_) {}

      try {
        await googleSignIn.disconnect();
      } catch (_) {}

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        setState(() => isSigningIn = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      await _authenticateWithGoogle(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
    } catch (e) {
      _handleSignInError(e);
    }
  }

  // Shared post-auth flow: exchange Google tokens for a Firebase session,
  // resolve role, sync with the backend, and navigate. Mobile + web.
  Future<void> _authenticateWithGoogle({
    required String? idToken,
    required String? accessToken,
  }) async {
    final credential = GoogleAuthProvider.credential(
      accessToken: accessToken,
      idToken: idToken,
    );

    final UserCredential userCredential = await FirebaseAuth.instance
        .signInWithCredential(credential);
    final User? firebaseUser = userCredential.user;

    if (firebaseUser == null || firebaseUser.email == null) {
      setState(() => isSigningIn = false);
      return;
    }

    // 2. Check Firestore 'user' collection where 'email' array contains the logged-in email
    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('email', arrayContains: firebaseUser.email)
        .get();

    String role;
    if (querySnapshot.docs.isEmpty) {
      // New user — add email to the students document and read its role
      final studentsRef = FirebaseFirestore.instance
          .collection('users')
          .doc('students');
      await studentsRef.update({
        'email': FieldValue.arrayUnion([firebaseUser.email!]),
      });
      final studentsSnap = await studentsRef.get();
      role = (studentsSnap.data()?['role'] as String?) ?? 'customer';
    } else {
      // Get the role from the matching Firestore document
      final userData = querySnapshot.docs.first.data();
      role = userData['role'] ?? 'customer';
    }

    // 4. Send the authenticated Firebase user to the backend
    final backendUser = await ApiService.googleSignIn(
      googleId: firebaseUser.uid,
      name: firebaseUser.displayName ?? '',
      email: firebaseUser.email!,
      role: role,
      avatar:
          firebaseUser.photoURL ??
          firebaseUser.providerData
              .firstWhere(
                (p) => p.providerId == 'google.com',
                orElse: () => firebaseUser.providerData.first,
              )
              .photoURL ??
          '',
      idToken: await firebaseUser.getIdToken(),
    );
    //final b = backendUser;
    //debugPrint(b.toString());
    await AppSession.setUser(backendUser);
    await Future.wait([
      loadCart(AppSession.userId),
      FavoriteModel.load(AppSession.userId),
    ]);
    await NotificationService.instance.registerFcmToken(AppSession.userId);

    if ((backendUser['phone'] ?? '').toString().isEmpty) {
      await _askPhoneNumber(AppSession.userId);
    }

    if (!mounted) return;

    // CODEX EDITS: A customer who had to sign in again must see the already
    // captured order before any home-page retry can create confusion.
    if (role != 'vendor') {
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
          setState(() => isSigningIn = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => SuccessPage(order: order)),
          );
          return;
        }
      } catch (error) {
        debugPrint(
          'CODEX EDITS: Post-login payment reconciliation deferred: $error',
        );
      }
    }

    // 5. Navigate based on the fetched role
    if (role == 'vendor') {
      setState(() => isSigningIn = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              VendorHomePage(toggleTheme: widget.toggleTheme ?? () {}),
        ),
      );
    } else {
      setState(() => isSigningIn = false);
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color.fromARGB(220, 15, 23, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: const Color(0xFF0F4CFF).withValues(alpha: 0.3),
            ),
          ),
          title: Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                color: const Color(0xFF0F4CFF),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Pickup Time Notice',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: const Text(
            'Please ensure your selected pickup time is accurate. Canteen prepares order based on the time provided.\nOnce prepared, food will not be reheated. We are not responsible for food that has gone cold due to delayed pickup.\nThank you for your understanding.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF0F4CFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
              ),
              child: const Text(
                'Got it',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CafeteriaPage(toggleTheme: widget.toggleTheme ?? () {}),
        ),
      );
    }
  }

  void _handleSignInError(Object e) {
    debugPrint("Sign-in error: $e");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Sign-in failed: Server Not Responding - Try Again Later",
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
    setState(() => isSigningIn = false);
  }

  // On web, Google's official GIS button is the reliable path to an idToken;
  // clicking it drives _onWebUserChanged via onCurrentUserChanged.
  Widget _buildWebGoogleButton() {
    if (isSigningIn) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
          ),
        ),
      );
    }
    return Center(child: gsi_button.renderGoogleSignInButton());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 1000;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF0F4FC),
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: isDesktop ? _buildDesktop(size) : _buildMobile(size),
      ),
    );
  }

  // ─── 1. DESKTOP LAYOUT ───────────────────────────────────────────────────
  Widget _buildDesktop(Size size) {
    const isMobile = false;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _PremiumWavePainter(isMobile: false, appBlue: appBlue),
          ),
        ),

        Positioned(
          top: size.height * 0.1,
          left: size.width * 0.05,
          child: _buildDotGrid(),
        ),
        Positioned(
          bottom: size.height * 0.15,
          left: size.width * 0.45,
          child: _buildDotGrid(),
        ),

        Positioned(
          top: size.height * 0.18,
          left: size.width * 0.08,
          child: _FadeSlide(delay: 0, child: _buildBranding(isMobile: false)),
        ),

        // PULSING FOOD ANIMATIONS
        _buildFood(
          'assets/burger.png',
          top: size.height * 0.1,
          left: size.width * 0.43,
          size: 180,
          duration: 2500,
          delay: 500,
          isMobile: isMobile,
          angle: 0.10,
        ),
        _buildFood(
          'assets/food_bowl.png',
          bottom: size.height * 0.05,
          left: size.width * 0.30,
          size: 280,
          duration: 2500,
          delay: 500,
          isMobile: isMobile,
        ),
        _buildFood(
          'assets/donut.png',
          bottom: size.height * 0.12,
          right: size.width * 0.05,
          size: 110,
          blur: 1.0,
          duration: 3000,
          delay: 1000,
          isMobile: isMobile,
        ),
        _buildFood(
          'assets/pizza.png',
          bottom: size.height * 0.3,
          right: size.width * 0.12,
          size: 200,
          blur: 2.5,
          duration: 4500,
          delay: 200,
          isMobile: isMobile,
        ),
        _buildFood(
          'assets/tomato.png',
          top: size.height * 0.42,
          left: size.width * 0.32,
          size: 80,
          blur: 2.0,
          duration: 3200,
          delay: 800,
          isMobile: isMobile,
        ),

        // Fillers for the otherwise-empty corners/edges — placed away from the
        // branding column, sign-in card, name, and watermark. Same breathing
        // animation; smaller ones blurred so they read as ambient depth.
        _buildFood(
          'assets/leaf.png',
          top: size.height * 0.06,
          right: size.width * 0.08,
          size: 110,
          duration: 3700,
          delay: 400,
          isMobile: isMobile,
          angle: -0.3,
        ),
        _buildFood(
          'assets/tomato.png',
          top: size.height * 0.26,
          right: size.width * 0.24,
          size: 70,
          blur: 2.0,
          duration: 4100,
          delay: 1100,
          isMobile: isMobile,
          angle: 0.5,
        ),
        _buildFood(
          'assets/donut.png',
          top: size.height * 0.04,
          left: size.width * 0.16,
          size: 80,
          blur: 2.0,
          duration: 3300,
          delay: 700,
          isMobile: isMobile,
          angle: 0.25,
        ),
        _buildFood(
          'assets/pizza.png',
          bottom: size.height * 0.08,
          left: size.width * 0.06,
          size: 200,
          duration: 3900,
          delay: 300,
          isMobile: isMobile,
          angle: -0.15,
        ),
        _buildFood(
          'assets/leaf.png',
          bottom: size.height * 0.40,
          left: size.width * 0.18,
          size: 80,
          blur: 1.5,
          duration: 4300,
          delay: 900,
          isMobile: isMobile,
          angle: 0.7,
        ),
        _buildFood(
          'assets/burger.png',
          bottom: size.height * 0.20,
          right: size.width * 0.28,
          size: 70,
          blur: 2.0,
          duration: 3500,
          delay: 600,
          isMobile: isMobile,
          angle: 0.4,
        ),

        // 🌟 UTENSILS (DESKTOP) - 6 TOTAL 🌟
        _buildFood(
          null,
          bottom: size.height * 0.45,
          left: size.width * 0.28,
          size: 35,
          duration: 3800,
          delay: 100,
          iconData: Icons.local_dining_rounded,
          iconColor: Colors.white.withValues(alpha: 0.6),
          isMobile: isMobile,
          angle: 0.4,
        ),
        _buildFood(
          null,
          bottom: size.height * 0.15,
          left: size.width * 0.6,
          size: 40,
          duration: 4200,
          delay: 600,
          iconData: Icons.restaurant_rounded,
          iconColor: Colors.white.withValues(alpha: 0.6),
          isMobile: isMobile,
          angle: -0.2,
        ),
        _buildFood(
          null,
          top: size.height * 0.15,
          right: size.width * 0.35,
          size: 30,
          duration: 3400,
          delay: 900,
          iconData: Icons.local_dining_rounded,
          iconColor: Colors.white.withValues(alpha: 0.6),
          isMobile: isMobile,
          angle: 0.1,
        ),
        _buildFood(
          null,
          top: size.height * 0.3,
          right: size.width * 0.45,
          size: 28,
          duration: 3600,
          delay: 300,
          iconData: Icons.restaurant_rounded,
          iconColor: Colors.white.withValues(alpha: 0.5),
          isMobile: isMobile,
          angle: 0.8,
        ),
        _buildFood(
          null,
          bottom: size.height * 0.4,
          right: size.width * 0.2,
          size: 32,
          duration: 4000,
          delay: 700,
          iconData: Icons.local_dining_rounded,
          iconColor: Colors.white.withValues(alpha: 0.5),
          isMobile: isMobile,
          angle: -0.5,
        ),
        _buildFood(
          null,
          top: size.height * 0.6,
          left: size.width * 0.1,
          size: 38,
          duration: 3900,
          delay: 200,
          iconData: Icons.restaurant_rounded,
          iconColor: Colors.white.withValues(alpha: 0.5),
          isMobile: isMobile,
          angle: 1.2,
        ),

        // Extra scattered dining glyphs filling the remaining gaps. Varied
        // sizes/angles/durations and irregular positions so the spread reads
        // as random rather than gridded; all keep the breathing animation.
        _buildFood(
          null,
          top: size.height * 0.07,
          right: size.width * 0.42,
          size: 26,
          duration: 3550,
          delay: 450,
          iconData: Icons.restaurant_rounded,
          iconColor: Colors.white.withValues(alpha: 0.45),
          isMobile: isMobile,
          angle: -0.7,
        ),
        _buildFood(
          null,
          top: size.height * 0.47,
          right: size.width * 0.07,
          size: 34,
          duration: 4100,
          delay: 850,
          iconData: Icons.local_dining_rounded,
          iconColor: Colors.white.withValues(alpha: 0.55),
          isMobile: isMobile,
          angle: 0.95,
        ),
        _buildFood(
          null,
          bottom: size.height * 0.07,
          right: size.width * 0.38,
          size: 30,
          duration: 3750,
          delay: 150,
          iconData: Icons.restaurant_rounded,
          iconColor: Colors.white.withValues(alpha: 0.5),
          isMobile: isMobile,
          angle: -0.35,
        ),
        _buildFood(
          null,
          top: size.height * 0.36,
          right: size.width * 0.17,
          size: 24,
          duration: 4350,
          delay: 1000,
          iconData: Icons.local_dining_rounded,
          iconColor: Colors.white.withValues(alpha: 0.4),
          isMobile: isMobile,
          angle: 1.5,
        ),
        _buildFood(
          null,
          bottom: size.height * 0.33,
          right: size.width * 0.06,
          size: 28,
          duration: 3450,
          delay: 550,
          iconData: Icons.restaurant_rounded,
          iconColor: Colors.white.withValues(alpha: 0.45),
          isMobile: isMobile,
          angle: 0.15,
        ),
        _buildFood(
          null,
          top: size.height * 0.72,
          right: size.width * 0.33,
          size: 32,
          duration: 4250,
          delay: 350,
          iconData: Icons.local_dining_rounded,
          iconColor: Colors.white.withValues(alpha: 0.5),
          isMobile: isMobile,
          angle: -0.9,
        ),
        _buildFood(
          null,
          bottom: size.height * 0.52,
          left: size.width * 0.03,
          size: 26,
          duration: 3650,
          delay: 750,
          iconData: Icons.restaurant_rounded,
          iconColor: appBlue.withValues(alpha: 0.28),
          isMobile: isMobile,
          angle: 0.6,
        ),
        _buildFood(
          null,
          top: size.height * 0.2,
          left: size.width * 0.24,
          size: 22,
          duration: 4450,
          delay: 950,
          iconData: Icons.local_dining_rounded,
          iconColor: appBlue.withValues(alpha: 0.25),
          isMobile: isMobile,
          angle: -1.1,
        ),

        // Scattered pulsing dots
        _buildDotGroup(
          top: size.height * 0.25,
          left: size.width * 0.37,
          color: appBlue,
          dotSize: 12,
          isMobile: isMobile,
        ),
        _buildDotGroup(
          bottom: size.height * 0.2,
          right: size.width * 0.13,
          color: appBlue,
          dotSize: 9,
          isMobile: isMobile,
        ),

        // WELCOME CARD CENTERED
        Align(
          alignment: const Alignment(0, 0.1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: _FadeSlide(
                  delay: 300,
                  child: _buildGoogleCard(isMobile: true, context: context),
                ),
              ),
              const SizedBox(height: 20),
              _AnimatedName(isMobile: false, appBlue: appBlue),
            ],
          ),
        ),

        // DESKTOP WATERMARK
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: _FadeSlide(delay: 600, child: _buildWatermark()),
        ),
      ],
    );
  }

  // ─── 2. MOBILE LAYOUT ────────────────────────────────────────────────────
  Widget _buildMobile(Size size) {
    const isMobile = true;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _PremiumWavePainter(isMobile: true, appBlue: appBlue),
          ),
        ),

        // PULSING FOOD ANIMATIONS
        _buildFood(
          'assets/burger.png',
          top: 10,
          right: 10,
          size: 100,
          duration: 3500,
          delay: 0,
          isMobile: isMobile,
          angle: 0.35,
        ),
        _buildFood(
          'assets/food_bowl.png',
          top: size.height * 0.2,
          right: -50,
          size: 240,
          duration: 4000,
          delay: 500,
          isMobile: isMobile,
        ),
        _buildFood(
          'assets/donut.png',
          bottom: 50,
          left: -20,
          size: 100,
          blur: 4.0,
          duration: 3000,
          delay: 1000,
          isMobile: isMobile,
        ),
        _buildFood(
          'assets/pizza.png',
          bottom: -10,
          right: -20,
          size: 240,
          blur: 4.0,
          duration: 4500,
          delay: 200,
          isMobile: isMobile,
        ),
        _buildFood(
          'assets/tomato.png',
          top: size.height * 0.45,
          left: 10,
          size: 70,
          blur: 2.5,
          duration: 3200,
          delay: 800,
          isMobile: isMobile,
        ),

        // 🌟 UTENSILS (MOBILE)
        _buildFood(
          null,
          top: size.height * 0.12,
          right: 120,
          size: 30,
          duration: 3800,
          delay: 100,
          iconData: Icons.local_dining_rounded,
          iconColor: Colors.white.withValues(alpha: 0.6),
          isMobile: isMobile,
          angle: 0.4,
        ),
        _buildFood(
          null,
          top: size.height * 0.55,
          right: 20,
          size: 35,
          duration: 4200,
          delay: 600,
          iconData: Icons.restaurant_rounded,
          iconColor: Colors.white.withValues(alpha: 0.6),
          isMobile: isMobile,
          angle: -0.2,
        ),
        _buildFood(
          null,
          top: size.height * 0.65,
          left: 30,
          size: 32,
          duration: 3400,
          delay: 900,
          iconData: Icons.local_dining_rounded,
          iconColor: Colors.white.withValues(alpha: 0.6),
          isMobile: isMobile,
          angle: 0.1,
        ),
        _buildFood(
          null,
          top: size.height * 0.28,
          left: 20,
          size: 28,
          duration: 3600,
          delay: 300,
          iconData: Icons.restaurant_rounded,
          iconColor: Colors.white.withValues(alpha: 0.5),
          isMobile: isMobile,
          angle: 0.8,
        ),
        _buildFood(
          null,
          bottom: size.height * 0.25,
          right: 15,
          size: 32,
          duration: 4000,
          delay: 700,
          iconData: Icons.local_dining_rounded,
          iconColor: Colors.white.withValues(alpha: 0.5),
          isMobile: isMobile,
          angle: -0.5,
        ),
        _buildFood(
          null,
          bottom: size.height * 0.15,
          left: 40,
          size: 26,
          duration: 3900,
          delay: 200,
          iconData: Icons.restaurant_rounded,
          iconColor: Colors.white.withValues(alpha: 0.5),
          isMobile: isMobile,
          angle: 1.2,
        ),

        // Scattered dots
        _buildDotGroup(
          top: size.height * 0.15,
          right: -20,
          color: Colors.white,
          dotSize: 10,
          isMobile: isMobile,
        ),
        _buildDotGroup(
          bottom: size.height * 0.3,
          left: 20,
          color: Colors.white,
          dotSize: 9,
          isMobile: isMobile,
        ),

        // BRANDING ON LEFT SIDE
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 24, top: 16),
              child: SizedBox(
                width: size.width * 0.6,
                child: _FadeSlide(
                  delay: 0,
                  child: _buildBranding(isMobile: true),
                ),
              ),
            ),
          ),
        ),

        // WELCOME CARD CENTERED
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: size.height * 0.15),

                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: _FadeSlide(
                    delay: 300,
                    child: _buildGoogleCard(isMobile: true, context: context),
                  ),
                ),

                const SizedBox(height: 20),

                _AnimatedName(isMobile: true, appBlue: appBlue),
                const SizedBox(height: 16),
                _FadeSlide(delay: 600, child: _buildWatermark()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 3. RESPONSIVE BRANDING & SCALED LOGO ─────────────────────────────────
  Widget _buildBranding({required bool isMobile}) {
    final textColor = isMobile ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isMobile
        ? Colors.white.withValues(alpha: 0.9)
        : const Color(0xFF64748B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isMobile ? 110 : (kIsWeb ? 150 : 80),
              height: isMobile ? 60 : (kIsWeb ? 80 : 80),
              // WEB: bare logo — no blue circular badge behind Nevark.png.
              decoration: (isMobile || kIsWeb)
                  ? null
                  : BoxDecoration(
                      color: appBlue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: appBlue.withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
              // Animated GIFs don't reliably decode on Flutter web (only a
              // blank first frame paints, leaving just the blue badge). Use the
              // static logo on web — shown bare, no badge/clip; keep the
              // animated GIF on mobile where it renders correctly.
              child: kIsWeb
                  ? Image.asset(
                      'assets/Nevark.png',
                      
                      fit: BoxFit.contain,
                      
                      errorBuilder: (_, _, _) => Icon(
                        Icons.lunch_dining_rounded,
                        color: appBlue,
                        size: 80,
                      ),
                    )
                  : Transform.scale(
                      scale: isMobile ? 1.3 : 1.8,
                      child: Image.asset(
                        'assets/Nevark.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.lunch_dining_rounded,
                          color: isMobile ? appBlue : Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
            ),
            SizedBox(width: isMobile ? 4 : 14),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          "Skip Waits.\nEnjoy Bites.",
          style: TextStyle(
            fontSize: isMobile ? 14 : 20,
            height: 1.3,
            fontWeight: FontWeight.w500,
            color: subTextColor,
          ),
        ),
        SizedBox(height: isMobile ? 10 : 35),

        if (isMobile)
          _LoopingFeaturePoints(subTextColor: subTextColor, isMobile: isMobile)
        else if (kIsWeb)
          // WEB: the taglines rotate through a circular carousel instead of
          // sitting as a static list.
          _RotatingFeaturePoints(subTextColor: subTextColor, appBlue: appBlue)
        else ...[
          _buildFeaturePoint(
            Icons.bolt_rounded,
            "Instant Food Order",
            isMobile,
            subTextColor,
          ),
          _buildFeaturePoint(
            Icons.local_offer_outlined,
            "Exclusive App Discounts",
            isMobile,
            subTextColor,
          ),
          _buildFeaturePoint(
            Icons.map_outlined,
            "Real-Time Order Tracking",
            isMobile,
            subTextColor,
          ),
          _buildFeaturePoint(
            Icons.health_and_safety_outlined,
            "100% Contactless Options",
            isMobile,
            subTextColor,
          ),
        ],
      ],
    );
  }

  Widget _buildFeaturePoint(
    IconData icon,
    String text,
    bool isMobile,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isMobile
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isMobile ? Colors.white : appBlue,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 15,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 4. PREMIUM GOOGLE-ONLY CARD WITH REDIRECT ───────────────────────────
  Widget _buildGoogleCard({
    required bool isMobile,
    required BuildContext context,
  }) {
    final card = _buildGoogleCardBody(isMobile: isMobile, context: context);
    // WEB: a faint blue streak of light continuously runs around the card's
    // rounded border. Painted as a foreground overlay so it sits on top of the
    // opaque card edge rather than behind it.
    if (!kIsWeb) return card;
    return _StreakBorder(
      borderRadius: 32,
      color: appBlue,// Color.fromARGB(255, 114, 112, 235),
      child: card,
    );
  }

  Widget _buildGoogleCardBody({
    required bool isMobile,
    required BuildContext context,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 28,
        vertical: isMobile ? 36 : 44,
      ),
      decoration: BoxDecoration(
        color: const Color.fromARGB(189, 255, 255, 255),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color.fromARGB(133, 255, 255, 255), width: 2),
        boxShadow: [
          BoxShadow(
            color: appBlue.withValues(alpha: 0.5),
            blurRadius: 40,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Color.fromARGB(0, 241, 245, 249),
              shape: BoxShape.rectangle,
            ),
            // App logo instead of the bare person glyph (web + Android).
            child: ClipOval(
              child: Image.asset(
                'assets/icon/icon3.png',
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.person_outline_rounded,
                  color: appBlue,
                  size: 30,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            "Welcome Back",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),

          Text(
            "Login to Your Account",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: const Color.fromARGB(255, 83, 97, 117),
            ),
          ),
          const SizedBox(height: 38),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: kIsWeb
                ? _buildWebGoogleButton()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F172A),
                      elevation: 3,
                      side: BorderSide(color: Colors.grey.shade200, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: isSigningIn ? null : _signInWithGoogle,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!isSigningIn) ...[
                          Image.asset(
                            'assets/google.png',
                            height: 24,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.g_mobiledata,
                              size: 28,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 14),
                        ],

                        Text(
                          isSigningIn
                              ? "Signing in..."
                              : "Continue with Google",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),

                        if (isSigningIn) ...[
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─── 5. WATERMARK ────────────────────────────────────────────────────────
  Widget _buildWatermark() {
    final row = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          "Powered  by  ",
          style: GoogleFonts.manrope(
            color: const Color(0xFF475569),
            fontSize: 12,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          "© Nevark Foods",
          style: GoogleFonts.plusJakartaSans(
            color: appBlue,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
    if (!kIsWeb) return row;
    // WEB: the watermark sits over the blue wave at the bottom where the grey
    // and blue lettering nearly vanish — float it on a frosted white pill so
    // it stays legible on any part of the background.
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: row,
      ),
    );
  }

  // ─── 6. STATIC ASSET LOADER WITH ANIMATION & BLUR ────────────────────────
  Widget _buildFood(
    String? name, {
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    double blur = 0,
    required int duration,
    required int delay,
    IconData? iconData,
    Color iconColor = Colors.green,
    required bool isMobile,
    double angle = 0.0,
  }) {
    bool isJpg = name?.endsWith('.jpg') ?? false;

    Widget imageWidget;
    if (name != null) {
      imageWidget = Image.asset(
        name,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Icon(
          iconData ?? Icons.food_bank_rounded,
          size: size * 0.7,
          color: isMobile ? Colors.white70 : const Color(0xFF64748B),
        ),
      );
    } else {
      imageWidget = Icon(
        iconData ?? Icons.local_dining_rounded,
        size: size,
        color: iconColor,
      );
    }

    if (isJpg) {
      imageWidget = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipOval(child: imageWidget),
      );
    }

    if (blur > 0) {
      imageWidget = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: imageWidget,
      );
    }

    if (angle != 0.0) {
      imageWidget = Transform.rotate(angle: angle, child: imageWidget);
    }

    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: _FloatingAnim(
        durationMillis: duration,
        delayMillis: delay,
        child: imageWidget,
      ),
    );
  }

  Widget _buildDotGroup({
    double? top,
    double? bottom,
    double? left,
    double? right,
    Color? color,
    required double dotSize,
    required bool isMobile,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: _FloatingAnim(
        durationMillis: 3500,
        delayMillis: 0,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            3,
            (c) => Container(
              width: dotSize,
              height: dotSize,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color ?? appBlue,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDotGrid({int rows = 4, int cols = 5}) {
    return Column(
      children: List.generate(
        rows,
        (r) => Row(
          children: List.generate(
            cols,
            (c) => Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: appBlue.withValues(alpha: 0.15),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── WEB ANIMATED BORDER STREAK ──────────────────────────────────────────
// Runs a faint blue light streak continuously around a rounded-rect border.
// The streak is a moving slice of the border path (extracted via PathMetric)
// stroked with a blur mask, so it traces the exact card outline including the
// corner curves.
class _StreakBorder extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final Color color;
  const _StreakBorder({
    required this.child,
    required this.borderRadius,
    required this.color,
  });

  @override
  State<_StreakBorder> createState() => _StreakBorderState();
}

class _StreakBorderState extends State<_StreakBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => CustomPaint(
        foregroundPainter: _StreakPainter(
          progress: _ctrl.value,
          borderRadius: widget.borderRadius,
          color: widget.color,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _StreakPainter extends CustomPainter {
  final double progress;
  final double borderRadius;
  final Color color;

  _StreakPainter({
    required this.progress,
    required this.borderRadius,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final border = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(borderRadius),
        ),
      );

    for (final metric in border.computeMetrics()) {
      final total = metric.length;
      // Streak spans ~10% of the perimeter; wraps around the seam.
      final tailLength = total * 0.3;
      final head = progress * total;
      final start = head - tailLength;

      Path segment;
      if (start >= 0) {
        segment = metric.extractPath(start, head);
      } else {
        segment = metric.extractPath(total + start, total)
          ..addPath(metric.extractPath(0, head), Offset.zero);
      }

      // Soft outer halo, then a brighter core — both faint.
      canvas.drawPath(
        segment,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.58)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawPath(
        segment,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(_StreakPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─── WEB ROTATING TAGLINES (circular carousel) ───────────────────────────
// Desktop-web replacement for the static 4-line feature list: one tagline is
// visible at a time and the set cycles circularly, each entry sliding up and
// fading in while the previous slides away.
class _RotatingFeaturePoints extends StatefulWidget {
  final Color subTextColor;
  final Color appBlue;
  const _RotatingFeaturePoints({
    required this.subTextColor,
    required this.appBlue,
  });

  @override
  State<_RotatingFeaturePoints> createState() => _RotatingFeaturePointsState();
}

class _RotatingFeaturePointsState extends State<_RotatingFeaturePoints> {
  static const _features = [
    (icon: Icons.bolt_rounded, text: 'Instant Food Order'),
    (icon: Icons.local_offer_outlined, text: 'Exclusive App Discounts'),
    (icon: Icons.map_outlined, text: 'Real-Time Order Tracking'),
    (icon: Icons.health_and_safety_outlined, text: '100% Contactless Options'),
  ];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2400), (_) {
      if (mounted) {
        setState(() => _index = (_index + 1) % _features.length);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feature = _features[_index];
    return SizedBox(
      height: 42,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.9),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Row(
            key: ValueKey(_index),
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(feature.icon, color: widget.appBlue, size: 16),
              ),
              const SizedBox(width: 12),
              Text(
                feature.text,
                style: TextStyle(
                  fontSize: 15,
                  color: widget.subTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── STATIC NAME COMPONENT ────────────────────────────
class _AnimatedName extends StatelessWidget {
  final bool isMobile;
  final Color appBlue;

  const _AnimatedName({required this.isMobile, required this.appBlue});

  @override
  Widget build(BuildContext context) {
    final fill = Text(
      "BenchBites",
      style: GoogleFonts.poppins(
        fontSize: isMobile ? 34 : 54,
        fontWeight: FontWeight.w900,
        color: const Color.fromARGB(255, 47, 59, 228),
        letterSpacing: 0,
        height: 1.0,
      ),
    );
    if (!kIsWeb) return fill;
    // WEB: the name sits across the light/blue wave boundary where the plain
    // blue fill loses contrast on the blue half — draw a white outline (stroke
    // pass under the fill pass) so it reads on both backgrounds.
    return Stack(
      children: [
        Text(
          "BenchBites",
          style: GoogleFonts.poppins(
            fontSize: isMobile ? 34 : 54,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
            height: 1.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.white,
          ),
        ),
        fill,
      ],
    );
  }
}

// ─── 7. PREMIUM MULTI-LAYERED WAVE BACKGROUND ──────────────────────────────
class _PremiumWavePainter extends CustomPainter {
  final bool isMobile;
  final Color appBlue;

  _PremiumWavePainter({required this.isMobile, required this.appBlue});

  @override
  void paint(Canvas canvas, Size size) {
    if (isMobile) {
      final paintMain = Paint()
        ..color = appBlue
        ..style = PaintingStyle.fill;
      final paintAccent = Paint()
        ..color = appBlue.withValues(alpha: 0.4)
        ..style = PaintingStyle.fill;

      final pathAccent = Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height * 0.45)
        ..cubicTo(
          size.width * 0.8,
          size.height * 0.55,
          size.width * 0.1,
          size.height * 0.4,
          0,
          size.height * 0.65,
        )
        ..close();

      final pathMain = Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height * 0.38)
        ..cubicTo(
          size.width * 0.8,
          size.height * 0.48,
          size.width * 0.2,
          size.height * 0.38,
          0,
          size.height * 0.58,
        )
        ..close();

      canvas.drawPath(pathAccent, paintAccent);
      canvas.drawPath(pathMain, paintMain);
    } else {
      final paintMain = Paint()
        ..color = appBlue
        ..style = PaintingStyle.fill;
      final paintAccent = Paint()
        ..color = appBlue.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;

      final pathAccent = Path()
        ..moveTo(size.width * 0.35, 0)
        ..cubicTo(
          size.width * 0.4,
          size.height * 0.4,
          size.width * 0.7,
          size.height * 0.7,
          size.width * 0.5,
          size.height,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, 0)
        ..close();

      final pathMain = Path()
        ..moveTo(size.width * 0.45, 0)
        ..cubicTo(
          size.width * 0.55,
          size.height * 0.4,
          size.width * 0.8,
          size.height * 0.6,
          size.width * 0.55,
          size.height,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, 0)
        ..close();

      canvas.drawPath(pathAccent, paintAccent);
      canvas.drawPath(pathMain, paintMain);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// ─── 8. ANIMATIONS (FADE-IN & PULSING) ────────────────────────────────────
class _FadeSlide extends StatefulWidget {
  final Widget child;
  final int delay;
  const _FadeSlide({required this.child, required this.delay});
  @override
  State<_FadeSlide> createState() => _FadeSlideState();
}

class _FadeSlideState extends State<_FadeSlide>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _FloatingAnim extends StatefulWidget {
  final Widget child;
  final int durationMillis;
  final int delayMillis;

  const _FloatingAnim({
    required this.child,
    required this.durationMillis,
    required this.delayMillis,
  });

  @override
  State<_FloatingAnim> createState() => _FloatingAnimState();
}

class _FloatingAnimState extends State<_FloatingAnim>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMillis),
    );

    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine));

    Future.delayed(Duration(milliseconds: widget.delayMillis), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scaleAnim, child: widget.child);
  }
}

class _FadeSlideStaggered extends StatefulWidget {
  final Widget child;
  final int delay;
  const _FadeSlideStaggered({required this.child, required this.delay});
  @override
  State<_FadeSlideStaggered> createState() => _FadeSlideStaggeredState();
}

class _FadeSlideStaggeredState extends State<_FadeSlideStaggered>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(
      begin: const Offset(-0.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ─── LOOPING FEATURE POINTS FOR MOBILE ──────────────────────────────────
class _LoopingFeaturePoints extends StatefulWidget {
  final Color subTextColor;
  final bool isMobile;

  const _LoopingFeaturePoints({
    required this.subTextColor,
    required this.isMobile,
  });

  @override
  State<_LoopingFeaturePoints> createState() => _LoopingFeaturePointsState();
}

class _LoopingFeaturePointsState extends State<_LoopingFeaturePoints>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<Map<String, dynamic>> _features = [
    {'icon': Icons.bolt_rounded, 'text': 'Instant Order'},
    {'icon': Icons.local_offer_outlined, 'text': 'Exclusive App Discounts'},
    {'icon': Icons.map_outlined, 'text': 'Real-Time Order Tracking'},
    {'icon': Icons.health_and_safety_outlined, 'text': '100% Contactless'},
    {'icon': Icons.sports_handball_rounded, 'text': 'Grab & Go'},
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        int currentIndex =
            (_controller.value * _features.length).floor() % _features.length;
        final feature = _features[currentIndex];

        return _FadeSlideStaggered(
          delay: 0,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    feature['icon'] as IconData,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  feature['text'] as String,
                  style: TextStyle(
                    fontSize: 14,
                    color: widget.subTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
