import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent cache for the Google account avatar.
///
/// Google's avatar CDN (lh3.googleusercontent.com) rate-limits per source IP
/// and answers with 429 once an IP gets hot — which happens easily on campus
/// Wi-Fi, where every device shares one public IP behind NAT. The avatar then
/// intermittently fails to load even though nothing is wrong with the app.
///
/// Caching the bytes after the first successful fetch means a returning user
/// never asks Google for the image again, so the shared IP stops being hammered
/// and the 429s stop.
///
/// One entry is stored (the signed-in user only has one avatar). It records the
/// URL it belongs to, so a changed profile picture invalidates itself and the
/// stale bytes are overwritten rather than accumulating.
class AvatarCache {
  static const _storageKey = 'avatar_cache_v1';

  // Survives navigation within a session without touching storage.
  static String? _memoUrl;
  static Uint8List? _memoBytes;

  // Guards against several widgets racing to fetch the same URL.
  static String? _inFlightUrl;

  /// Cached bytes for [url], or null when nothing is cached for it yet.
  static Future<Uint8List?> load(String url) async {
    if (url.isEmpty) return null;
    if (_memoUrl == url && _memoBytes != null) return _memoBytes;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['url'] != url) return null;
      final bytes = base64Decode(decoded['bytes']?.toString() ?? '');
      if (bytes.isEmpty) return null;
      _memoUrl = url;
      _memoBytes = bytes;
      return bytes;
    } catch (_) {
      // Corrupt or unreadable entry — treat as a miss and refetch.
      return null;
    }
  }

  /// Downloads [url] and stores it for next time. Failures are deliberately
  /// silent: the caller is already showing the image over the network, so a
  /// blocked CORS request, a 429, or being offline costs nothing here.
  static Future<void> populate(String url) async {
    if (url.isEmpty || _inFlightUrl == url) return;
    if (_memoUrl == url && _memoBytes != null) return;
    _inFlightUrl = url;
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return;

      // Guard against caching an error page served with a 200.
      if (response.bodyBytes.lengthInBytes > 2 * 1024 * 1024) return;

      _memoUrl = url;
      _memoBytes = response.bodyBytes;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({'url': url, 'bytes': base64Encode(response.bodyBytes)}),
      );
    } catch (_) {
      // Non-fatal — the network image stays on screen and we retry next launch.
    } finally {
      _inFlightUrl = null;
    }
  }

  /// Clears the stored avatar. Called on sign-out so the next account does not
  /// briefly show the previous user's picture.
  static Future<void> clear() async {
    _memoUrl = null;
    _memoBytes = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (error) {
      debugPrint('Failed to clear avatar cache: $error');
    }
  }
}
