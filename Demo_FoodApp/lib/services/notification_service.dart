import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'session.dart';

final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initializeLocalNotifications();
  await _showNotification(message);
}

Future<void> _initializeLocalNotifications() async {
  if (kIsWeb) return;

  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  await _localNotificationsPlugin.initialize(
    const InitializationSettings(
      android: android,
      iOS: ios,
    ),
  );

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    const channel = AndroidNotificationChannel(
      'orders',
      'Order Notifications',
      description: 'Notifications for order status and offers',
      importance: Importance.high,
    );
    await _localNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  }
}

Future<void> _showNotification(RemoteMessage message) async {
  if (kIsWeb) return;

  final notification = message.notification;
  final android = message.notification?.android;

  if (notification == null) return;

  final title = notification.title ?? 'Food App';
  final body = notification.body ?? '';

  await _localNotificationsPlugin.show(
    notification.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        'orders',
        'Order Notifications',
        channelDescription: 'Notifications for order status and offers',
        importance: Importance.high,
        priority: Priority.high,
        icon: android?.smallIcon,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  bool _initialized = false;
  late final FirebaseMessaging _messaging;

  Future<void> init() async {
    if (_initialized) return;

    _messaging = FirebaseMessaging.instance;

    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (!kIsWeb) {
      await _initializeLocalNotifications();
    }

    await _requestPermission();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }

    _messaging.onTokenRefresh.listen((token) {
      _updateFcmToken(token);
    });

    _initialized = true;
  }

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Notification permissions denied');
    }

    if (!kIsWeb) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> registerFcmToken(String userId) async {
    if (userId.isEmpty) return;

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      await ApiService.registerFcmToken(userId, token);
    } catch (error) {
      debugPrint('Failed to register FCM token: $error');
    }
  }

  Future<void> _updateFcmToken(String token) async {
    final userId = AppSession.userId;
    if (userId.isEmpty || token.isEmpty) return;
    try {
      await ApiService.registerFcmToken(userId, token);
    } catch (error) {
      debugPrint('Failed to refresh FCM token: $error');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    await _showNotification(message);
  }

  Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    debugPrint('Notification opened: ${message.messageId}');
  }
}
