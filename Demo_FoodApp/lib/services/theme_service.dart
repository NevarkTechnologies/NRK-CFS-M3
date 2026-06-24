import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
bool _isToggling = false;

/// Call once at app startup to restore the saved theme.
Future<void> initTheme() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  } catch (_) {}
}

void toggleAppTheme() {
  if (_isToggling) return;
  _isToggling = true;
  // Schedule reset BEFORE notifying so the flag always clears even if a listener throws.
  Future.delayed(const Duration(milliseconds: 400), () => _isToggling = false);
  final next = themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  themeNotifier.value = next;
  SharedPreferences.getInstance()
      .then((prefs) => prefs.setBool('isDarkMode', next == ThemeMode.dark))
      // ignore errors — theme persistence failure is non-fatal
      .ignore();
}
