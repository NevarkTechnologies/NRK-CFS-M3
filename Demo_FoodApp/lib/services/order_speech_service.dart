import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

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
      await tts.setLanguage('en-IN');
    } catch (_) {}
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

    speakingOrderId.value = orderId;
    try {
      await tts.speak(utterance);
    } catch (error) {
      speakingOrderId.value = null;
      debugPrint('Order readout failed: $error');
    }
  }

  Future<void> stop() async {
    speakingOrderId.value = null;
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
