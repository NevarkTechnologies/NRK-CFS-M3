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
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
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
