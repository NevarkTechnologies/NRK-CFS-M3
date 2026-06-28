import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

/// Call once at app startup to restore the saved theme.
Future<void> initTheme() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  } catch (_) {}
}

void toggleAppTheme() {
  final next = themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  themeNotifier.value = next;
  SharedPreferences.getInstance()
      .then((prefs) => prefs.setBool('isDarkMode', next == ThemeMode.dark))
      .ignore();
}
