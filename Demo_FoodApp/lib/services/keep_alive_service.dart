import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Entry point for the service's own isolate.
///
/// The handler below deliberately does nothing — see [_KeepAliveTaskHandler].
@pragma('vm:entry-point')
void startKeepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveTaskHandler());
}

/// An intentionally empty task handler.
///
/// The work this service exists for does not happen here. Android only keeps an
/// app's process alive, and exempt from Doze and background restrictions, while
/// a foreground service is running. Keeping the process alive is what keeps the
/// *main* isolate alive, and the main isolate is where `onMessage` fires, where
/// the orders page polls, and where tickets are printed.
///
/// So the service itself is the feature. Emptying this handler is not an
/// oversight — putting logic here would run it in a second isolate with no
/// session and no API client, which is the exact limitation this design avoids.
class _KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Keeps the vendor app running so orders keep arriving, announcing and
/// printing while nobody is looking at the phone.
///
/// Without this, Android suspends the app within minutes of it leaving the
/// screen: `FirebaseMessaging.onMessage` stops firing, the 30s poll stops, and
/// the counter silently stops receiving orders. That is precisely the situation
/// the canteen owner is trying to escape.
class KeepAliveService {
  KeepAliveService._();
  static final KeepAliveService instance = KeepAliveService._();

  static const _channelId = 'benchbites_vendor_service';

  bool _initialized = false;

  /// Web has no such thing, and a customer's phone has no reason to run a
  /// persistent service — this is started only for vendors.
  bool get isSupported => !kIsWeb;

  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'Order service',
        channelDescription:
            'Keeps BenchBites receiving and printing orders while the '
            'screen is off.',
        // LOW importance: the vendor sees a quiet, permanent entry in the
        // shade rather than something that buzzes all day.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // No periodic work — the service exists purely to hold the process
        // open. See _KeepAliveTaskHandler.
        eventAction: ForegroundTaskEventAction.nothing(),
        // The counter phone is expected to be plugged in and always on. Both of
        // these bring the service back without anyone noticing it stopped —
        // after a reboot, and after an app update replaces the package.
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Starts the service if it is not already running. Safe to call repeatedly —
  /// called on vendor login and whenever the orders page mounts.
  Future<void> start() async {
    if (!isSupported) return;
    try {
      _ensureInitialized();
      if (await FlutterForegroundTask.isRunningService) return;

      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        // Android 13+ will not show the service notification without this, and
        // a foreground service cannot run without its notification.
        await FlutterForegroundTask.requestNotificationPermission();
      }

      final result = await FlutterForegroundTask.startService(
        // connectedDevice covers the Bluetooth/network link to the printer;
        // dataSync covers pulling orders down. Both are declared because the
        // service genuinely does both.
        serviceTypes: const [
          ForegroundServiceTypes.connectedDevice,
          ForegroundServiceTypes.dataSync,
        ],
        notificationTitle: 'BenchBites',
        notificationText: 'Receiving orders',
        callback: startKeepAliveCallback,
      );

      if (result is ServiceRequestFailure) {
        debugPrint('Keep-alive service failed to start: ${result.error}');
      }
    } catch (error) {
      // A phone that refuses the service still works while the app is open —
      // never let this take the vendor's session down with it.
      debugPrint('Keep-alive service unavailable: $error');
    }
  }

  Future<void> stop() async {
    if (!isSupported) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (error) {
      debugPrint('Could not stop keep-alive service: $error');
    }
  }

  /// Whether this phone will let the app run unrestricted in the background.
  ///
  /// Aggressive OEM battery managers (Xiaomi, Oppo, Vivo especially) kill even
  /// foreground services, which silently stops orders arriving. The settings
  /// screen surfaces this so the vendor can fix it once rather than discovering
  /// it during a lunch rush.
  Future<bool> isBatteryOptimisationIgnored() async {
    if (!isSupported) return true;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (error) {
      debugPrint('Could not read battery optimisation state: $error');
      return true;
    }
  }

  Future<void> requestIgnoreBatteryOptimisation() async {
    if (!isSupported) return;
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (error) {
      debugPrint('Battery optimisation request failed: $error');
    }
  }
}
