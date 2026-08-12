import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart';

// FEATURE 2026-08-12: Backend-driven mandatory update gate.
//
// The server (GET /api/payment/fees → minAppVersion.minVersionCode) decides the
// minimum supported Android build. When the installed versionCode is below it,
// the app forces a Google Play *immediate* (blocking) update before it can be
// used. This is a kill-switch: bump minVersionCode in MongoDB and every old
// install is forced to update on next launch.
//
// Notes:
//  - In-App Updates only work for builds installed from Google Play (or its
//    testing tracks). Sideloaded/debug builds return no update — the blocking
//    screen still shows, with a Play Store fallback button.
//  - Android-only. On web/iOS this is a no-op (returns "not required").
class UpdateService {
  /// True when the installed build is older than the backend's minimum and the
  /// user must update before continuing. Never throws — any network/parse
  /// failure returns false so a backend hiccup can't lock users out.
  static Future<bool> isUpdateMandatory() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final data = await ApiService.getPaymentFees();
      final min = data['minAppVersion'];
      final minVersionCode =
          (min is Map) ? (min['minVersionCode'] as num?)?.toInt() : null;
      if (minVersionCode == null) return false;

      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber) ?? 0;
      return installed < minVersionCode;
    } catch (_) {
      return false;
    }
  }

  /// Launches Google Play's full-screen immediate update flow. On success Play
  /// restarts the app on the new version; on cancel/failure it returns and the
  /// caller keeps the blocking screen up. Returns true if the flow completed.
  static Future<bool> startImmediateUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        final result = await InAppUpdate.performImmediateUpdate();
        return result == AppUpdateResult.success;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
