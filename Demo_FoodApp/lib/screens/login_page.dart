import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;

import 'vendor/vendor_home_page.dart';
import 'cafeteria_page.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/session.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback? toggleTheme;
  const LoginPage({super.key, this.toggleTheme});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final Color appBlue = const Color(0xFF2563EB);
  bool isSigningIn = false;

  Future<void> _signInWithGoogle() async {
    if (isSigningIn) return;
    setState(() => isSigningIn = true);

    try {
      // 1. Sign in with Google using Firebase Auth Web Popup
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      final User? firebaseUser = userCredential.user;

      if (firebaseUser == null || firebaseUser.email == null) {
        setState(() => isSigningIn = false);
        return;
      }

      // 2. Check Firestore 'user' collection where 'email' array contains the logged-in email
      final querySnapshot = await FirebaseFirestore.instance
          .collection('user')
          .where('email', arrayContains: firebaseUser.email)
          .get();

      if (querySnapshot.docs.isEmpty) {
        // If email isn't in the Firestore array, deny access
        await FirebaseAuth.instance.signOut();
        throw Exception("Your email is not authorized to access this app.");
      }

      // 3. Get the role from the matching Firestore document
      final userData = querySnapshot.docs.first.data();
      final String role = userData['role'] ?? 'user';

      // 4. Send the authenticated Firebase user to the backend
      final backendUser = await ApiService.googleSignIn(
        googleId: firebaseUser.uid,
        name: firebaseUser.displayName ?? 'User',
        email: firebaseUser.email!,
        avatar: firebaseUser.photoURL ?? '',
      );

      AppSession.setUser(backendUser);
      await NotificationService.instance.registerFcmToken(AppSession.userId);

      if (!mounted) return;

      // 5. Navigate based on the fetched role
      if (backendUser['role'] == 'vendor') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VendorHomePage(
              toggleTheme: widget.toggleTheme ?? () {},
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CafeteriaPage(
              toggleTheme: widget.toggleTheme ?? () {},
            ),
          ),
        );
      }
    } catch (e) {
      print("Sign-in error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Sign-in failed: $e"),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Scaffold(
      resizeToAvoidBottomInset: false, 
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
          child: CustomPaint(painter: _PremiumWavePainter(isMobile: false, appBlue: appBlue)),
        ),

        Positioned(top: size.height * 0.1, left: size.width * 0.05, child: _buildDotGrid()),
        Positioned(bottom: size.height * 0.15, left: size.width * 0.45, child: _buildDotGrid()),

        Positioned(
          top: size.height * 0.18,
          left: size.width * 0.08,
          child: _FadeSlide(
            delay: 0,
            child: _buildBranding(isMobile: false),
          ),
        ),

        // PULSING FOOD ANIMATIONS
        _buildFood('assets/burger.png', top: size.height * 0.08, left: size.width * 0.48, size: 140, duration: 3500, delay: 0, isMobile: isMobile, angle: 0.35),
        _buildFood('assets/food_bowl.jpg', bottom: size.height * 0.05, left: size.width * 0.35, size: 300, duration: 4000, delay: 500, isMobile: isMobile), 
        _buildFood('assets/donut.png', bottom: size.height * 0.12, right: size.width * 0.05, size: 110, blur: 5.0, duration: 3000, delay: 1000, isMobile: isMobile),
        _buildFood('assets/coke.png', bottom: size.height * 0.3, right: size.width * 0.12, size: 100, blur: 4.5, duration: 4500, delay: 200, isMobile: isMobile),
        _buildFood('assets/tomato.png', top: size.height * 0.42, left: size.width * 0.32, size: 80, blur: 4.0, duration: 3200, delay: 800, isMobile: isMobile), 

        // 🌟 UTENSILS (DESKTOP) - 6 TOTAL 🌟
        _buildFood(null, bottom: size.height * 0.45, left: size.width * 0.28, size: 35, duration: 3800, delay: 100, iconData: Icons.local_dining_rounded, iconColor: Colors.white.withOpacity(0.6), isMobile: isMobile, angle: 0.4),
        _buildFood(null, bottom: size.height * 0.15, left: size.width * 0.6, size: 40, duration: 4200, delay: 600, iconData: Icons.restaurant_rounded, iconColor: Colors.white.withOpacity(0.6), isMobile: isMobile, angle: -0.2),
        _buildFood(null, top: size.height * 0.15, right: size.width * 0.35, size: 30, duration: 3400, delay: 900, iconData: Icons.local_dining_rounded, iconColor: Colors.white.withOpacity(0.6), isMobile: isMobile, angle: 0.1),
        _buildFood(null, top: size.height * 0.3, right: size.width * 0.45, size: 28, duration: 3600, delay: 300, iconData: Icons.restaurant_rounded, iconColor: Colors.white.withOpacity(0.5), isMobile: isMobile, angle: 0.8),
        _buildFood(null, bottom: size.height * 0.4, right: size.width * 0.2, size: 32, duration: 4000, delay: 700, iconData: Icons.local_dining_rounded, iconColor: Colors.white.withOpacity(0.5), isMobile: isMobile, angle: -0.5),
        _buildFood(null, top: size.height * 0.6, left: size.width * 0.1, size: 38, duration: 3900, delay: 200, iconData: Icons.restaurant_rounded, iconColor: Colors.white.withOpacity(0.5), isMobile: isMobile, angle: 1.2),

        // Scattered pulsing dots
        _buildDotGroup(top: size.height * 0.25, left: size.width * 0.37, color: appBlue, dotSize: 8, isMobile: isMobile),
        _buildDotGroup(bottom: size.height * 0.2, right: size.width * 0.13, color: appBlue, dotSize: 9, isMobile: isMobile),
        
        // WELCOME CARD CENTERED 
        Align(
          alignment: const Alignment(0, 0.4),
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
              _AnimatedName( 
                isMobile: false,
                appBlue: appBlue,
              ),
            ],
          ),
        ),
        
        // DESKTOP WATERMARK
        Positioned(
          bottom: 24,
          left: 0, right: 0,
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
          child: CustomPaint(painter: _PremiumWavePainter(isMobile: true, appBlue: appBlue)),
        ),

        // PULSING FOOD ANIMATIONS
        _buildFood('assets/burger.png', top: 10, right: 10, size: 100, duration: 3500, delay: 0, isMobile: isMobile, angle: 0.35),
        _buildFood('assets/food_bowl.jpg', top: size.height * 0.2, right: -50, size: 240, duration: 4000, delay: 500, isMobile: isMobile),
        _buildFood('assets/donut.png', bottom: 50, left: -20, size: 100, blur: 4.0, duration: 3000, delay: 1000, isMobile: isMobile), 
        _buildFood('assets/coke.png', bottom: -10, right: -20, size: 120, blur: 4.0, duration: 4500, delay: 200, isMobile: isMobile), 
        _buildFood('assets/tomato.png', top: size.height * 0.45, left: 10, size: 70, blur: 3.5, duration: 3200, delay: 800, isMobile: isMobile),

        // 🌟 UTENSILS (MOBILE)
        _buildFood(null, top: size.height * 0.12, right: 120, size: 30, duration: 3800, delay: 100, iconData: Icons.local_dining_rounded, iconColor: Colors.white.withOpacity(0.6), isMobile: isMobile, angle: 0.4),
        _buildFood(null, top: size.height * 0.55, right: 20, size: 35, duration: 4200, delay: 600, iconData: Icons.restaurant_rounded, iconColor: Colors.white.withOpacity(0.6), isMobile: isMobile, angle: -0.2),
        _buildFood(null, top: size.height * 0.65, left: 30, size: 32, duration: 3400, delay: 900, iconData: Icons.local_dining_rounded, iconColor: Colors.white.withOpacity(0.6), isMobile: isMobile, angle: 0.1),
        _buildFood(null, top: size.height * 0.28, left: 20, size: 28, duration: 3600, delay: 300, iconData: Icons.restaurant_rounded, iconColor: Colors.white.withOpacity(0.5), isMobile: isMobile, angle: 0.8),
        _buildFood(null, bottom: size.height * 0.25, right: 15, size: 32, duration: 4000, delay: 700, iconData: Icons.local_dining_rounded, iconColor: Colors.white.withOpacity(0.5), isMobile: isMobile, angle: -0.5),
        _buildFood(null, bottom: size.height * 0.15, left: 40, size: 26, duration: 3900, delay: 200, iconData: Icons.restaurant_rounded, iconColor: Colors.white.withOpacity(0.5), isMobile: isMobile, angle: 1.2),
        
        // Scattered dots
        _buildDotGroup(top: size.height * 0.15, right: -20, color: Colors.white, dotSize: 10, isMobile: isMobile),
        _buildDotGroup(bottom: size.height * 0.3, left: 20, color: Colors.white, dotSize: 9, isMobile: isMobile),

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

                _AnimatedName( 
                  isMobile: true,
                  appBlue: appBlue,
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _FadeSlide(
                    delay: 600,
                    child: _buildWatermark(),
                  ),
                ),
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
    final subTextColor = isMobile ? Colors.white.withOpacity(0.9) : const Color(0xFF64748B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: isMobile ? 65 : 90, 
              height: isMobile ? 65 : 90,
              decoration: isMobile 
                  ? null 
                  : BoxDecoration(
                      color: appBlue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: appBlue.withOpacity(0.3), 
                          blurRadius: 15, 
                          offset: const Offset(0, 6),
                        )
                      ]
                    ),
              child: Transform.scale(
                scale: isMobile ? 1.3 : 1.05, 
                child: Image.asset(
                  'assets/logo1.gif',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(Icons.lunch_dining_rounded, color: isMobile ? appBlue : Colors.white, size: 30),
                ),
              ),
            ),
            SizedBox(width: isMobile ? 4 : 14),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          "Delicious food,\navoid the queue",
          style: TextStyle(
            fontSize: isMobile ? 14 : 20, 
            height: 1.3, 
            fontWeight: FontWeight.w500, 
            color: subTextColor,
          ),
        ),
        SizedBox(height: isMobile ? 8 : 35),
        
        if (isMobile)
          _LoopingFeaturePoints(subTextColor: subTextColor, isMobile: isMobile)
        else ...[
          _buildFeaturePoint(Icons.bolt_rounded, "Lightning fast delivery", isMobile, subTextColor),
          _buildFeaturePoint(Icons.local_offer_outlined, "Exclusive app discounts", isMobile, subTextColor),
          _buildFeaturePoint(Icons.map_outlined, "Real-time order tracking", isMobile, subTextColor),
          _buildFeaturePoint(Icons.health_and_safety_outlined, "100% contactless options", isMobile, subTextColor),
        ]
      ],
    );
  }

  Widget _buildFeaturePoint(IconData icon, String text, bool isMobile, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isMobile ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isMobile ? Colors.white : appBlue, size: 16), 
          ),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.w600)), 
        ],
      ),
    );
  }

  // ─── 4. PREMIUM GOOGLE-ONLY CARD WITH REDIRECT ───────────────────────────
  Widget _buildGoogleCard({required bool isMobile, required BuildContext context}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 28, vertical: isMobile ? 36 : 48),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white, width: 2), 
        boxShadow: [
          BoxShadow(color: appBlue.withOpacity(0.2), blurRadius: 40, offset: const Offset(0, 15)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9), 
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_outline_rounded, color: appBlue, size: 30), 
          ),
          const SizedBox(height: 20),
          const Text(
            "Welcome Back", 
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: -0.5)
          ),
          const SizedBox(height: 8),
          const Text(
            "Login to continue to your account", 
            style: TextStyle(color: Color(0xFF64748B), fontSize: 15, fontWeight: FontWeight.w500)
          ),
          const SizedBox(height: 48),
          
          SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                elevation: 3,
                side: BorderSide(color: Colors.grey.shade200, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: isSigningIn ? null : _signInWithGoogle,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/google.png', height: 24, errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 28, color: Colors.blue)),
                  const SizedBox(width: 14),
                  Text(
                    isSigningIn ? "Signing in..." : "Continue with Google",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Brought to you by ", style: TextStyle(color: Color.fromARGB(255, 0, 22, 52), fontSize: 12, fontWeight: FontWeight.w600)),
        Text("Nevark", style: TextStyle(color: appBlue, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
      ],
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
        width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(iconData ?? Icons.food_bank_rounded, size: size * 0.7, color: isMobile ? Colors.white70 : const Color(0xFF64748B)),
      );
    } else {
      imageWidget = Icon(iconData ?? Icons.local_dining_rounded, size: size, color: iconColor);
    }

    if (isJpg) {
      imageWidget = Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 8))],
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
      imageWidget = Transform.rotate(
        angle: angle,
        child: imageWidget,
      );
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

  Widget _buildDotGroup({double? top, double? bottom, double? left, double? right, Color? color, required double dotSize, required bool isMobile}) {
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
              width: dotSize, height: dotSize,
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
              width: 6, height: 6,
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: appBlue.withOpacity(0.15),
              ),
            ),
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

  const _AnimatedName({
    required this.isMobile,
    required this.appBlue,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      "BenchBites",
      style: TextStyle(
        fontSize: isMobile ? 34 : 54,
        fontWeight: FontWeight.w900,
        color: const Color.fromARGB(255, 47, 59, 228),
        letterSpacing: -1.5,
        height: 1.0,
      ),
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
      final paintMain = Paint()..color = appBlue..style = PaintingStyle.fill;
      final paintAccent = Paint()..color = appBlue.withOpacity(0.4)..style = PaintingStyle.fill;

      final pathAccent = Path()
        ..moveTo(0, 0)..lineTo(size.width, 0)..lineTo(size.width, size.height * 0.45)
        ..cubicTo(size.width * 0.8, size.height * 0.55, size.width * 0.1, size.height * 0.4, 0, size.height * 0.65)..close();

      final pathMain = Path()
        ..moveTo(0, 0)..lineTo(size.width, 0)..lineTo(size.width, size.height * 0.38)
        ..cubicTo(size.width * 0.8, size.height * 0.48, size.width * 0.2, size.height * 0.38, 0, size.height * 0.58)..close();

      canvas.drawPath(pathAccent, paintAccent);
      canvas.drawPath(pathMain, paintMain);
    } else {
      final paintMain = Paint()..color = appBlue..style = PaintingStyle.fill;
      final paintAccent = Paint()..color = appBlue.withOpacity(0.1)..style = PaintingStyle.fill;

      final pathAccent = Path()
        ..moveTo(size.width * 0.35, 0)
        ..cubicTo(size.width * 0.4, size.height * 0.4, size.width * 0.7, size.height * 0.7, size.width * 0.5, size.height)
        ..lineTo(size.width, size.height)..lineTo(size.width, 0)..close();
      
      final pathMain = Path()
        ..moveTo(size.width * 0.45, 0)
        ..cubicTo(size.width * 0.55, size.height * 0.4, size.width * 0.8, size.height * 0.6, size.width * 0.55, size.height)
        ..lineTo(size.width, size.height)..lineTo(size.width, 0)..close();

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

class _FadeSlideState extends State<_FadeSlide> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;
  
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: widget.delay), () { if (mounted) _ctrl.forward(); });
  }
  
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  
  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: SlideTransition(position: _slide, child: widget.child));
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

class _FloatingAnimState extends State<_FloatingAnim> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim; 

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: widget.durationMillis));
    
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.1).animate( 
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine) 
    );

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

class _FadeSlideStaggeredState extends State<_FadeSlideStaggered> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;
  
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(-0.2, 0), end: Offset.zero).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: widget.delay), () { if (mounted) _ctrl.forward(); });
  }
  
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  
  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _opacity, child: SlideTransition(position: _slide, child: widget.child));
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

class _LoopingFeaturePointsState extends State<_LoopingFeaturePoints> with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<Map<String, dynamic>> _features = [
    {'icon': Icons.bolt_rounded, 'text': 'Lightning fast delivery'},
    {'icon': Icons.local_offer_outlined, 'text': 'Exclusive app discounts'},
    {'icon': Icons.map_outlined, 'text': 'Real-time order tracking'},
    {'icon': Icons.health_and_safety_outlined, 'text': '100% contactless options'},
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
        int currentIndex = (_controller.value * _features.length).floor() % _features.length;
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
                    color: Colors.white.withOpacity(0.2),
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