import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads a vendor order aloud so the counter can hear what to prepare without
/// looking at the screen.
///
/// One shared engine for the whole app: the platform TTS engines (Android
/// TextToSpeech, the browser's SpeechSynthesis) are process-wide singletons, so
/// holding several FlutterTts instances would let two cards talk over each
/// other. Speaking a new order therefore stops whatever is already playing.
class OrderSpeechService {
  OrderSpeechService._();
  static final OrderSpeechService instance = OrderSpeechService._();

  FlutterTts? _tts;
  bool _configured = false;

  /// The order currently being read, or null when silent. The vendor card
  /// listens to this to flip its icon between "play" and "stop" — including on
  /// the card that did not start the speech, so only one ever shows as active.
  final ValueNotifier<String?> speakingOrderId = ValueNotifier<String?>(null);

  Future<FlutterTts> _engine() async {
    final tts = _tts ??= FlutterTts();
    if (_configured) return tts;
    _configured = true;

    // Each of these is best-effort: an engine that does not support the voice
    // or language still speaks, just with its default. Never let setup throw
    // and cost the vendor the readout.
    try {
      // Slightly under normal pace — order lines are short and full of numbers,
      // and counter areas are noisy.
      await tts.setSpeechRate(kIsWeb ? 0.9 : 0.45);
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
    } catch (_) {}

    tts.setCompletionHandler(() => speakingOrderId.value = null);
    tts.setCancelHandler(() => speakingOrderId.value = null);
    tts.setErrorHandler((_) => speakingOrderId.value = null);

    return tts;
  }

  /// Sets the language for this utterance only. The engine's language is global
  /// state, so it has to be applied before every speak — the card readout is
  /// always English (item names are English) while announcements follow the
  /// vendor's choice.
  Future<void> _applyLanguage(FlutterTts tts, String code) async {
    try {
      await tts.setLanguage(code);
    } catch (_) {
      // Voice data for this language is not installed — the engine falls back
      // to its default rather than staying silent.
    }
  }

  /// Builds the spoken line for [order] — "2 Veg Biryani, 1 Masala Dosa, for
  /// Arjun". Returns an empty string when there is nothing worth reading.
  String buildUtterance(Map<String, dynamic> order) {
    final rawItems = order['items'];
    final parts = <String>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is! Map) continue;
        final name = item['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final qty = int.tryParse(item['qty']?.toString() ?? '') ?? 1;
        parts.add('$qty $name');
      }
    }
    if (parts.isEmpty) return '';

    final customer = order['customer']?.toString().trim() ?? '';
    final items = parts.join(', ');
    return customer.isEmpty ? items : '$items, for $customer';
  }

  /// Speaks [order]. Tapping the same order while it is talking stops it, so
  /// the one icon serves as both play and stop.
  Future<void> toggle(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString() ?? '';
    if (speakingOrderId.value == orderId) {
      await stop();
      return;
    }

    final utterance = buildUtterance(order);
    if (utterance.isEmpty) return;

    final tts = await _engine();
    // Stop first: speaking while the engine is already talking queues on some
    // Android engines and is ignored outright on others.
    try {
      await tts.stop();
    } catch (_) {}

    await _applyLanguage(tts, 'en-IN');
    speakingOrderId.value = orderId;
    try {
      await tts.speak(utterance);
    } catch (error) {
      speakingOrderId.value = null;
      debugPrint('Order readout failed: $error');
    }
  }

  // ── New-order announcements ────────────────────────────────────────────────

  /// Languages offered to the vendor. Value is the BCP-47 tag handed to the
  /// platform engine; key order drives the picker order.
  static const Map<String, String> announcementLanguages = {
    'en-IN': 'English',
    'hi-IN': 'हिंदी  (Hindi)',
    'kn-IN': 'ಕನ್ನಡ  (Kannada)',
  };

  static const _prefLanguage = 'vendor_announce_language';
  static const _prefEnabled = 'vendor_announce_enabled';
  static const _prefAnnouncedIds = 'vendor_announced_order_ids';

  /// Vendor's chosen announcement language, and whether announcements play at
  /// all. Both are ValueNotifiers so the settings screen and the orders screen
  /// stay in sync without passing state between them.
  final ValueNotifier<String> announcementLanguage = ValueNotifier('en-IN');
  final ValueNotifier<bool> announcementsEnabled = ValueNotifier(true);

  bool _prefsLoaded = false;
  final List<String> _announceQueue = [];
  bool _draining = false;

  /// Reads the saved preferences. Safe to call repeatedly; only the first call
  /// touches storage.
  Future<void> loadPreferences() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefLanguage);
      if (saved != null && announcementLanguages.containsKey(saved)) {
        announcementLanguage.value = saved;
      }
      announcementsEnabled.value = prefs.getBool(_prefEnabled) ?? true;
    } catch (error) {
      debugPrint('Failed to load announcement preferences: $error');
    }
  }

  Future<void> setAnnouncementLanguage(String code) async {
    if (!announcementLanguages.containsKey(code)) return;
    announcementLanguage.value = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLanguage, code);
    } catch (error) {
      debugPrint('Failed to save announcement language: $error');
    }
  }

  Future<void> setAnnouncementsEnabled(bool enabled) async {
    announcementsEnabled.value = enabled;
    if (!enabled) await stop();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabled, enabled);
    } catch (error) {
      debugPrint('Failed to save announcement toggle: $error');
    }
  }

  /// Whether the device actually has voice data for [code]. Hindi ships with
  /// most Google TTS installs; Kannada often does not, and an unavailable
  /// language would silently fall back to the engine default — so the settings
  /// screen greys it out and tells the vendor to install it instead.
  Future<bool> isLanguageAvailable(String code) async {
    try {
      final tts = await _engine();
      final result = await tts.isLanguageAvailable(code);
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Normalises a token for speech. Tokens are zero-padded for display
  /// ("0001"), and every TTS engine reads a leading zero literally — "zero zero
  /// zero one". Parsing to an int and back drops the padding so it is read as
  /// "one" in whichever language is selected. Non-numeric tokens (e.g. "A12")
  /// are left untouched.
  String _spokenToken(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return int.tryParse(trimmed)?.toString() ?? trimmed;
  }

  String _announcementFor(String tokenNumber) {
    final token = _spokenToken(tokenNumber);
    switch (announcementLanguage.value) {
      case 'hi-IN':
        return token.isEmpty ? 'एक नया ऑर्डर' : 'एक नया ऑर्डर, टोकन $token';
      case 'kn-IN':
        return token.isEmpty
            ? 'ಒಂದು ಹೊಸ ಆರ್ಡರ್'
            : 'ಒಂದು ಹೊಸ ಆರ್ಡರ್, ಟೋಕನ್ $token';
      default:
        return token.isEmpty ? 'One new order' : 'One new order, token $token';
    }
  }

  /// Claims [orderId] for announcement, returning false if it was already
  /// announced.
  ///
  /// This has to survive crossing isolates: an order that arrives while the app
  /// is backgrounded is announced from the FCM background isolate, and the
  /// orders page would otherwise announce it a second time when the app returns
  /// to the foreground and polls. SharedPreferences is the only state the two
  /// isolates share, and reload() is required because each isolate caches its
  /// own snapshot on first read.
  Future<bool> _reserveAnnouncement(String orderId) async {
    if (orderId.isEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final ids = prefs.getStringList(_prefAnnouncedIds) ?? <String>[];
      if (ids.contains(orderId)) return false;
      ids.add(orderId);
      // Bounded so a long day of service cannot grow this without limit; far
      // more than enough to cover any order still on screen.
      if (ids.length > 200) ids.removeRange(0, ids.length - 200);
      await prefs.setStringList(_prefAnnouncedIds, ids);
      return true;
    } catch (error) {
      // Storage trouble must never silence the counter — announcing twice is
      // recoverable, missing an order is not.
      debugPrint('Announcement dedupe unavailable: $error');
      return true;
    }
  }

  /// Announces a newly arrived order. Several orders landing at once are queued
  /// and read one after another rather than cutting each other off — the whole
  /// point is that the counter hears every token.
  ///
  /// [orderId] drives cross-isolate deduplication; pass it whenever it is
  /// known. Callers without one (the settings preview) always speak.
  Future<void> announceNewOrder({
    required String tokenNumber,
    String orderId = '',
  }) async {
    await loadPreferences();
    if (!announcementsEnabled.value) return;
    if (!await _reserveAnnouncement(orderId)) return;
    await _enqueueAnnouncement(_announcementFor(tokenNumber));
  }

  /// Speaks a sample line so the vendor can confirm the voice works before
  /// relying on it during service. Deliberately ignores the mute toggle so the
  /// voice can be tested before switching announcements on.
  Future<void> previewAnnouncement() async {
    await loadPreferences();
    await _enqueueAnnouncement(_announcementFor('7'));
  }

  Future<void> _enqueueAnnouncement(String utterance) async {
    _announceQueue.add(utterance);
    if (_draining) return;

    _draining = true;
    try {
      final tts = await _engine();
      // Completion is awaited so queued announcements do not talk over each
      // other; without it speak() returns as soon as the utterance is handed
      // to the platform engine.
      try {
        await tts.awaitSpeakCompletion(true);
      } catch (_) {}

      while (_announceQueue.isNotEmpty) {
        final next = _announceQueue.removeAt(0);
        await _applyLanguage(tts, announcementLanguage.value);
        try {
          await tts.speak(next);
        } catch (error) {
          debugPrint('Order announcement failed: $error');
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> stop() async {
    speakingOrderId.value = null;
    // Muting mid-queue must drop what is still pending, not just cut off the
    // utterance currently playing.
    _announceQueue.clear();
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
