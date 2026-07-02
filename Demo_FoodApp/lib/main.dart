import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'services/session.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/nav.dart';
import 'services/theme_service.dart';
import 'model/favorite_model.dart';
import 'screens/login_page.dart';
import 'screens/splash_page.dart';
import 'screens/cart_page.dart';

export 'services/nav.dart' show navigatorKey;

Future<void> handleAuthError() async {
  await FirebaseAuth.instance.signOut();
  clearCart();
  FavoriteModel.clear();
  await AppSession.clear();
  navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
}


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge on every Android version, not just 15+ where the OS forces
  // it — all screens already handle insets via SafeArea/AppBar/padding.
  // The nav bar scrim itself is applied by initTheme() below via
  // applySystemNavStyle(), once the saved theme is known.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await AppSession.init();
    await initTheme();

    ApiService.onAuthError = handleAuthError;
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint("Startup Error: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  void toggleTheme() {
    toggleAppTheme();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode currentMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'BenchBites',

          /// 🌞 LIGHT THEME
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFF0A1F44),
            scaffoldBackgroundColor: const Color(0xFFF5F7FA),
            cardColor: Colors.white,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              elevation: 0,
              iconTheme: IconThemeData(color: Color(0xFF0F4CFF)),
              titleTextStyle: TextStyle(
                color: Color(0xFF0F4CFF),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              // Every AppBar re-applies its SystemUiOverlayStyle on build,
              // which was clobbering the global transparent nav bar set in
              // main() on Android ≤ 14 — reinforce it from the theme instead.
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness: Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ),
            ),
          ),

          /// 🌑 DARK THEME
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF0A1F44),
            scaffoldBackgroundColor: const Color(0xFF020617),
            cardColor: const Color(0xFF0F172A),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0F172A),
              elevation: 0,
              iconTheme: IconThemeData(color: Color(0xFF0F4CFF)),
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness: Brightness.light,
                systemNavigationBarContrastEnforced: false,
              ),
              titleTextStyle: TextStyle(
                color: Color(0xFF0F4CFF),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          /// 🔥 GLOBAL THEME MODE
          themeMode: currentMode,
          themeAnimationDuration: const Duration(milliseconds: 400),
          themeAnimationCurve: Curves.easeInOutCubic,

          // Two app-wide adjustments:
          // 1. Lift all bottom-anchored UI (nav bar, Pay buttons, …) slightly
          //    higher above the system nav: every screen positions its bottom
          //    UI with SafeArea, which reads MediaQuery.padding.bottom, so
          //    inflating the inset here raises everything at once.
          // 2. Draw a gradient scrim over the system nav area (35% opacity at
          //    the bottom fading to 20% at the top). The window's own nav bar
          //    color is fully transparent — Android windows only support a
          //    flat color, and app-rendered pixels are immune to OEM ROMs
          //    force-overriding the window color.
          builder: (context, child) {
            if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
              return child!;
            }
            final mq = MediaQuery.of(context);
            const extraLift = 10.0;
            // System nav inset (0 while the keyboard covers the nav area).
            final navInset = mq.padding.bottom;
            final isDark = currentMode == ThemeMode.dark;
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
                children: [
                  MediaQuery(
                    data: mq.copyWith(
                      padding: mq.padding.copyWith(
                        bottom: mq.padding.bottom + extraLift,
                      ),
                      viewPadding: mq.viewPadding.copyWith(
                        bottom: mq.viewPadding.bottom + extraLift,
                      ),
                    ),
                    child: child!,
                  ),
                  if (navInset > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: navInset,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isDark
                                  ? const [navScrimTopDark, navScrimBottomDark]
                                  : const [
                                      navScrimTopLight,
                                      navScrimBottomLight,
                                    ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },

          /// ROUTES
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/':
                return MaterialPageRoute(
                  builder: (_) => SplashPage(toggleTheme: toggleTheme),
                );

              case '/login':
                return MaterialPageRoute(
                  builder: (_) => LoginPage(toggleTheme: toggleTheme),
                );

              default:
                return MaterialPageRoute(
                  builder: (_) => SplashPage(toggleTheme: toggleTheme),
                );
            }
          },

          /// HOME
          home: SplashPage(toggleTheme: toggleTheme),
        );
      },
    );
  }
}
