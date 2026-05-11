import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'screens/login_page.dart';
import 'screens/splash_page.dart';

/// 🌗 GLOBAL THEME CONTROLLER
/// Managed from services/theme_service.dart

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.instance.init();
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
          debugShowCheckedModeBanner: false,
          title: 'Food App',

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