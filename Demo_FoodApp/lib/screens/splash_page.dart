import 'dart:async';
import 'package:flutter/material.dart';

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
    await Future.delayed(const Duration(seconds: 3));

    bool isLoggedIn = false;

    if (isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Image.asset(
          'assets/splashscreen.gif',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}