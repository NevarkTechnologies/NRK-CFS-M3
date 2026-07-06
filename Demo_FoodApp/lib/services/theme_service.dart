import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

const MethodChannel _settingsChannel = MethodChannel('nevark_foods/settings');

/// Gradient scrim over the system nav area, drawn by the app itself in
/// MaterialApp.builder (main.dart): 35% opacity at the very bottom fading to
/// 20% at the top. The Android window nav bar color stays fully TRANSPARENT
/// (windows only support a flat color), so the gradient is app-rendered
/// pixels and immune to OEM color overrides.
const Color navScrimTopLight = Color(0x33FFFFFF); // 80% transparent (top)
const Color navScrimBottomLight = Color(
  0x99FFFFFF,
); // 40% transparent (bottom) // 35% white
const Color navScrimTopDark = Color(0x33000000); // 20% black
const Color navScrimBottomDark = Color(0x59000000); // 35% black

/// Pushes the current theme's system-bar style to both Flutter and the
/// native side. The native call also re-triggers MainActivity's delayed
/// edge-to-edge re-assert, which must run after every style change because
/// ColorOS force-paints the nav bar black whenever the style changes.
Future<void> applySystemNavStyle() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final isDark = themeNotifier.value == ThemeMode.dark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  try {
    await _settingsChannel.invokeMethod(
      'setNavBarScrim',
      Colors.transparent.toARGB32(),
    );
  } catch (_) {}
}

/// Call once at app startup to restore the saved theme.
Future<void> initTheme() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  } catch (_) {}
  await applySystemNavStyle();
}

void toggleAppTheme() {
  final next = themeNotifier.value == ThemeMode.light
      ? ThemeMode.dark
      : ThemeMode.light;
  themeNotifier.value = next;
  applySystemNavStyle();
  SharedPreferences.getInstance()
      .then((prefs) => prefs.setBool('isDarkMode', next == ThemeMode.dark))
      .ignore();
}
