import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../firebase_options.dart';
import '../model/notification_model.dart';
import '../screens/detail_page.dart';
import '../screens/vendor/order_page.dart';
import 'api_service.dart';
import 'nav.dart';
import 'order_speech_service.dart';
import 'session.dart';

final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
const MethodChannel _settingsChannel = MethodChannel('nevark_foods/settings');

/// FCM Web Push (VAPID) PUBLIC key — Firebase Console → Project Settings →
/// Cloud Messaging → Web Push certificates ("Key pair"). Used only on web
/// (mobile uses native FCM/APNs tokens). This is a public key and is safe to
/// ship in the client; the matching private key is managed by Firebase and
/// must never appear here.
const String _fcmWebVapidKey =
    'BMIj-F-Asq4zaD5hD0EXM3gxDzqJJkA3REv6f5_HQJQam4px8mSMTiKYeTh-tqa5lAYmK-sgI4CsICinTvqSSVM';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await _initializeLocalNotifications();
  await _showNotification(message);

  // FEATURE: announce new orders aloud even when the vendor app is backgrounded.
  // onMessage only fires in the foreground, so this isolate is the only place
  // that sees the push here. The token comes from the payload because this
  // isolate has no session, no API client and no widget tree — it cannot look
  // the order up. Deduplication against the foreground path is handled inside
  // announceNewOrder via SharedPreferences, which both isolates share.
  //
  // Web never reaches this: background messages there are handled by
  // firebase-messaging-sw.js, which cannot run Dart.
  if (!kIsWeb && message.data['type']?.toString() == 'vendor_order') {
    try {
      await OrderSpeechService.instance.announceNewOrder(
        tokenNumber: message.data['tokenNumber']?.toString() ?? '',
        orderId: message.data['orderId']?.toString() ?? '',
      );
    } catch (error) {
      // The notification itself has already been shown; a failed readout must
      // not take the handler down with it.
      debugPrint('Background announcement failed: $error');
    }
  }
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
    const InitializationSettings(android: android, iOS: ios),
  );

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    const channel = AndroidNotificationChannel(
      'orders',
      'Order Notifications',
      description: 'Notifications for Order Status',
      importance: Importance.high,
    );
    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }
}

Future<void> _showNotification(RemoteMessage message) async {
  if (kIsWeb) return;

  final notification = message.notification;
  final android = message.notification?.android;

  if (notification == null) return;

  final title = notification.title ?? 'BenchBites Food App';
  final body = notification.body ?? '';

  await _localNotificationsPlugin.show(
    notification.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        'orders',
        'Order Notifications',
        channelDescription: 'Notifications for Order Status',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true,
        ticker: title,
        styleInformation: BigTextStyleInformation(body),
        icon: android?.smallIcon ?? '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    ),
  );
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// orderId of the most recent 'order' push received in the foreground.
  /// Retains its value so listeners that mount after the push arrives (e.g.
  /// SuccessPage when the webhook-sent push beats the page transition) can
  /// still read it. Used to drive the "Order is being created" footer.
  static final ValueNotifier<String?> lastOrderPushOrderId =
      ValueNotifier<String?>(null);

  /// Bumped every time a 'vendor_order' push lands in the foreground. The
  /// vendor orders page listens to it so a new order refreshes the list (and is
  /// announced aloud) immediately, instead of waiting out the 30s poll.
  static final ValueNotifier<int> vendorOrderPushTick = ValueNotifier<int>(0);

  bool _initialized = false;
  late final FirebaseMessaging _messaging;

  Future<void> init() async {
    if (_initialized) return;

    _messaging = FirebaseMessaging.instance;

    //await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (!kIsWeb) {
      await _initializeLocalNotifications();
    }

    // Permission is handled exclusively in ensurePermissionRequired().
    // Do NOT call _requestPermission() here — calling it before the branded
    // dialog causes the system dialog to fire before we can show context.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // Delay so the navigator is ready after app startup
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleMessageOpenedApp(initialMessage),
      );
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
  }

  Future<bool> ensurePermissionRequired(BuildContext context) async {
    try {
      if (!_initialized) await init();
    } catch (error) {
      debugPrint('Notification setup failed: $error');
      return true;
    }

    while (context.mounted) {
      final settings = await _messaging.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        return true;
      }

      // Request system permission
      await _requestPermission();
      final afterRequest = await _messaging.getNotificationSettings();
      if (afterRequest.authorizationStatus == AuthorizationStatus.authorized ||
          afterRequest.authorizationStatus == AuthorizationStatus.provisional) {
        // Set foreground options now that permission is confirmed
        if (!kIsWeb) {
          await _messaging.setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
        }
        return true;
      }

      // Web cannot re-prompt or open the browser's notification settings once
      // the user has blocked them — the branded "Open Settings" flow below only
      // works on mobile (native deep-link). Show manual unblock guidance and
      // stop, instead of looping on a settings URL that is a no-op on web.
      if (kIsWeb) {
        if (!context.mounted) return false;
        await _showWebBlockedDialog(context);
        return false;
      }

      // Permission denied — show branded dialog directing to settings
      if (!context.mounted) return false;
      final goToSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F4CFF).withValues(alpha: 0.15),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F4CFF).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Color(0xFF0F4CFF),
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Enable Notifications',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'BenchBites needs notifications to alert you when your order is ready for pickup. Please enable them in Settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F4CFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        'Open Settings',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      'Not Now',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white38 : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      // goToSettings == null means dialog was dismissed (shouldn't happen with barrierDismissible: false)
      // goToSettings == false means user chose "Not Now"
      if (!context.mounted) return false;
      if (goToSettings != true) return false;

      await _openNotificationSettings();
      // Wait for user to return from Settings
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  Future<void> _openNotificationSettings() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _settingsChannel.invokeMethod<void>('openNotificationSettings');
      return;
    }

    final settingsUri = Uri.parse('app-settings:');
    if (await canLaunchUrl(settingsUri)) {
      await launchUrl(settingsUri, mode: LaunchMode.externalApplication);
    }
  }

  /// Web-only: once the browser has blocked notifications there is no API to
  /// re-prompt or to open the browser's site-settings panel. Guide the user to
  /// unblock it manually via the address bar, then reload.
  Future<void> _showWebBlockedDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F4CFF).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_off_rounded,
                    color: Color(0xFF0F4CFF),
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Notifications are blocked',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your browser has blocked notifications for BenchBites. To turn '
                  'them on, click the lock (or tune) icon on the left of the '
                  'address bar → Notifications → Allow, then reload the page.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F4CFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Got it',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> registerFcmToken(String userId) async {
    if (userId.isEmpty) return;

    try {
      final token = kIsWeb
          ? await _messaging.getToken(vapidKey: _fcmWebVapidKey)
          : await _messaging.getToken();
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
    final type = message.data['type']?.toString();
    if (type == 'order') {
      lastOrderPushOrderId.value = message.data['orderId']?.toString();
    } else if (type == 'vendor_order') {
      vendorOrderPushTick.value++;
    }
    if (AppSession.isLoggedIn) {
      NotificationModel.fetchNotifications(
        AppSession.userId,
      ).catchError((_) {});
    }
  }

  Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    debugPrint('Notification opened: ${message.messageId}');
    final type = message.data['type']?.toString() ?? '';
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    if (type == 'vendor_order') {
      nav.push(
        MaterialPageRoute(builder: (_) => OrdersPage(toggleTheme: () {})),
      );
    } else if (type == 'order') {
      nav.push(
        MaterialPageRoute(builder: (_) => DetailPage(title: AppSession.name)),
      );
    }
  }
}
