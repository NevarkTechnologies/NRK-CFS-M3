import 'package:flutter/material.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void toggleAppTheme() {
  themeNotifier.value =
      themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
}
