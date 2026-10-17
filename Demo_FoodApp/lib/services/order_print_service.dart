import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'printer_transport.dart';
import 'receipt_builder.dart';

/// How the vendor wants incoming orders handled.
enum OrderHandlingMode {
  /// The vendor taps Accept or Reject. The ticket prints on Accept.
  manual('manual'),

  /// Orders are accepted and printed with no interaction. The counter works
  /// off paper and never touches the phone.
  auto('auto');

  const OrderHandlingMode(this.value);

  /// Persisted in SharedPreferences — must stay stable across releases.
  final String value;

  static OrderHandlingMode fromValue(String? raw) =>
      raw == 'auto' ? OrderHandlingMode.auto : OrderHandlingMode.manual;
}

/// Prints vendor kitchen tickets and remembers how the vendor wants orders
/// handled.
///
/// Structured like [OrderSpeechService] deliberately: one shared instance,
/// SharedPreferences-backed settings exposed as ValueNotifiers so the settings
/// screen and the orders screen stay in sync without passing state between
/// them.
///
/// Everything here runs in the main isolate. The FCM background isolate has no
/// session and no API client — it sees only type/orderId/status/tokenNumber and
/// cannot fetch the item lines, so it could not build a kitchen ticket anyway.
/// The foreground keep-alive service is what makes sure the main isolate is
/// alive to do this work.
class OrderPrintService {
  OrderPrintService._();
  static final OrderPrintService instance = OrderPrintService._();

  final PrinterBackend _backend = createPrinterBackend();

  static const _prefConnection = 'vendor_printer_mode';
  static const _prefBtMac = 'vendor_printer_bt_mac';
  static const _prefBtName = 'vendor_printer_bt_name';
  static const _prefIp = 'vendor_printer_ip';
  static const _prefPort = 'vendor_printer_port';
  static const _prefPaper = 'vendor_printer_paper';
  static const _prefCopies = 'vendor_printer_copies';
  static const _prefOrderMode = 'vendor_order_mode';
  static const _prefPrintedIds = 'vendor_printed_order_ids';
  static const _prefAutoAcceptedIds = 'vendor_auto_accepted_ids';
  static const _prefQueue = 'vendor_print_queue';

  /// Id lists are capped so a long day of service cannot grow storage without
  /// limit. Far more than enough to cover anything still on screen.
  static const _idHistoryLimit = 200;
  static const _queueLimit = 50;

  /// A job that has failed this many times stops being retried automatically
  /// and is surfaced on the banner instead, so a dead printer does not have the
  /// app hammering it on every poll.
  static const _maxAttempts = 3;

  final ValueNotifier<PrinterConfig> config = ValueNotifier(
    const PrinterConfig(),
  );
  final ValueNotifier<PaperWidth> paper = ValueNotifier(PaperWidth.mm80);
  final ValueNotifier<int> copies = ValueNotifier(1);
  final ValueNotifier<OrderHandlingMode> orderMode = ValueNotifier(
    OrderHandlingMode.manual,
  );

  /// Tickets that gave up retrying. Drives the Orders page banner — a failed
  /// print must never be silent, or the kitchen simply never sees the order.
  final ValueNotifier<int> failedCount = ValueNotifier(0);

  final Set<String> _autoAccepted = <String>{};
  bool _loaded = false;

  /// Sends are serialised through this chain. Two tickets writing to one
  /// Bluetooth socket at once interleave their bytes and print garbage.
  Future<void> _sendChain = Future<void>.value();

  /// False on web, where neither transport exists. The settings card and every
  /// print action are hidden rather than offered and then failing.
  bool get isSupported => _backend.isSupported;

  /// Whether a printer is actually set up and switched on.
  bool get isReady =>
      isSupported &&
      config.value.connection != PrinterConnection.off &&
      config.value.isConfigured;

  bool get isAutoMode => orderMode.value == OrderHandlingMode.auto;

  // ── Settings ──────────────────────────────────────────────────────────────

  /// Reads saved settings. Safe to call repeatedly; only the first call touches
  /// storage.
  Future<void> loadSettings() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      config.value = PrinterConfig(
        connection: PrinterConnection.fromValue(
          prefs.getString(_prefConnection),
        ),
        btMac: prefs.getString(_prefBtMac) ?? '',
        btName: prefs.getString(_prefBtName) ?? '',
        ip: prefs.getString(_prefIp) ?? '',
        port: prefs.getInt(_prefPort) ?? PrinterConfig.defaultPort,
      );
      paper.value = PaperWidth.fromValue(prefs.getString(_prefPaper));
      copies.value = (prefs.getInt(_prefCopies) ?? 1).clamp(1, 3);
      orderMode.value = OrderHandlingMode.fromValue(
        prefs.getString(_prefOrderMode),
      );
      _autoAccepted
        ..clear()
        ..addAll(prefs.getStringList(_prefAutoAcceptedIds) ?? const []);
      failedCount.value = (await _readQueue())
          .where((job) => (job['attempts'] as int? ?? 0) >= _maxAttempts)
          .length;
    } catch (error) {
      debugPrint('Failed to load printer settings: $error');
    }
  }

  Future<void> setConnection(PrinterConnection connection) async {
    config.value = config.value.copyWith(connection: connection);
    await _write((prefs) => prefs.setString(_prefConnection, connection.value));
  }

  Future<void> setBluetoothDevice(PairedDevice device) async {
    config.value = config.value.copyWith(
      btMac: device.mac,
      btName: device.name,
    );
    await _write((prefs) async {
      await prefs.setString(_prefBtMac, device.mac);
      await prefs.setString(_prefBtName, device.name);
    });
  }

  Future<void> setNetworkTarget(String ip, int port) async {
    config.value = config.value.copyWith(ip: ip.trim(), port: port);
    await _write((prefs) async {
      await prefs.setString(_prefIp, ip.trim());
      await prefs.setInt(_prefPort, port);
    });
  }

  Future<void> setPaper(PaperWidth width) async {
    paper.value = width;
    await _write((prefs) => prefs.setString(_prefPaper, width.value));
  }

  Future<void> setCopies(int count) async {
    copies.value = count.clamp(1, 3);
    await _write((prefs) => prefs.setInt(_prefCopies, copies.value));
  }

  Future<void> setOrderMode(OrderHandlingMode mode) async {
    orderMode.value = mode;
    await _write((prefs) => prefs.setString(_prefOrderMode, mode.value));
  }

  Future<void> _write(FutureOr<void> Function(SharedPreferences) action) async {
    try {
      await action(await SharedPreferences.getInstance());
    } catch (error) {
      debugPrint('Failed to save printer setting: $error');
    }
  }

  // ── Discovery, passed straight through to the platform backend ────────────

  Future<List<PairedDevice>> pairedDevices() => _backend.pairedDevices();

  Future<bool> ensureBluetoothReady() => _backend.ensureBluetoothReady();

  Future<List<String>> scanForNetworkPrinters({int port = 9100}) =>
      _backend.scanForNetworkPrinters(port: port);

  Future<bool> probe() => _backend.probe(config.value);

  // ── Auto-accept bookkeeping ───────────────────────────────────────────────

  /// Whether this order was accepted by Auto mode rather than by hand.
  ///
  /// Tracked locally because the server records only the resulting status —
  /// `updateOrderStatus` has no notion of *how* an order was accepted — and the
  /// card needs to show the marker for the life of the order.
  bool isAutoAccepted(String orderId) =>
      orderId.isNotEmpty && _autoAccepted.contains(orderId);

  Future<void> markAutoAccepted(String orderId) async {
    if (orderId.isEmpty || !_autoAccepted.add(orderId)) return;
    await _write((prefs) async {
      final ids = prefs.getStringList(_prefAutoAcceptedIds) ?? <String>[];
      if (ids.contains(orderId)) return;
      ids.add(orderId);
      if (ids.length > _idHistoryLimit) {
        ids.removeRange(0, ids.length - _idHistoryLimit);
      }
      await prefs.setStringList(_prefAutoAcceptedIds, ids);
    });
  }

  // ── Printing ──────────────────────────────────────────────────────────────

  /// Prints the kitchen ticket for [order].
  ///
  /// Claims the order id before sending, and keeps that claim even when the
  /// send fails — the job moves to the retry queue instead. This is the
  /// opposite of how announcements dedupe, on purpose: announcements fail open
  /// because saying "one new order" twice is harmless, whereas two identical
  /// tickets for one token has the kitchen cooking it twice. A delayed ticket
  /// is recoverable by the queue and the reprint button; a duplicate is not.
  ///
  /// Pass [force] to bypass dedup — that is what the card's reprint button does.
  Future<void> printOrder(
    Map<String, dynamic> order, {
    bool force = false,
  }) async {
    if (!isSupported) return;
    await loadSettings();
    if (!isReady) return;

    final orderId = order['id']?.toString() ?? '';
    if (!force && !await _reservePrint(orderId)) return;

    try {
      await _send(order);
    } catch (error) {
      debugPrint('Print failed for order $orderId: $error');
      // A forced reprint is a deliberate manual action — surface the failure to
      // the caller instead of silently queueing behind the vendor's back.
      if (force) rethrow;
      await _enqueue(order);
    }
  }

  /// Prints a sample slip so the vendor can prove the printer works before
  /// relying on it during service. Deliberately bypasses dedup and the queue,
  /// and lets errors surface so the settings screen can show them.
  Future<void> testPrint() async {
    await loadSettings();
    if (!isReady) {
      throw const PrinterException('Pick a printer first.');
    }
    await _sendBytes(ReceiptBuilder.testTicket(paper: paper.value));
  }

  Future<void> _send(Map<String, dynamic> order) async {
    await _sendBytes(ReceiptBuilder.kitchenTicket(order, paper: paper.value));
  }

  Future<void> _sendBytes(List<int> bytes) {
    return _serialise(() async {
      for (var copy = 0; copy < copies.value; copy++) {
        await _backend.send(config.value, bytes);
      }
    });
  }

  /// Runs [action] after every previously queued send has finished.
  Future<T> _serialise<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _sendChain = _sendChain.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Claims [orderId], returning false if it was already printed.
  ///
  /// Mirrors `OrderSpeechService._reserveAnnouncement`, including the
  /// `prefs.reload()`: each isolate caches its own snapshot, so without it a
  /// write made elsewhere is invisible here.
  Future<bool> _reservePrint(String orderId) async {
    if (orderId.isEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final ids = prefs.getStringList(_prefPrintedIds) ?? <String>[];
      if (ids.contains(orderId)) return false;
      ids.add(orderId);
      if (ids.length > _idHistoryLimit) {
        ids.removeRange(0, ids.length - _idHistoryLimit);
      }
      await prefs.setStringList(_prefPrintedIds, ids);
      return true;
    } catch (error) {
      // Storage trouble must not stop the kitchen getting its ticket. Erring
      // toward a possible duplicate is the lesser harm when the alternative is
      // printing nothing at all.
      debugPrint('Print dedupe unavailable: $error');
      return true;
    }
  }

  // ── Retry queue ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _readQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return (prefs.getStringList(_prefQueue) ?? const <String>[])
          .map((raw) {
            try {
              return jsonDecode(raw) as Map<String, dynamic>;
            } catch (_) {
              return <String, dynamic>{};
            }
          })
          .where((job) => job.isNotEmpty)
          .toList();
    } catch (error) {
      debugPrint('Could not read print queue: $error');
      return [];
    }
  }

  Future<void> _writeQueue(List<Map<String, dynamic>> jobs) async {
    if (jobs.length > _queueLimit) {
      jobs = jobs.sublist(jobs.length - _queueLimit);
    }
    failedCount.value = jobs
        .where((job) => (job['attempts'] as int? ?? 0) >= _maxAttempts)
        .length;
    await _write(
      (prefs) => prefs.setStringList(_prefQueue, jobs.map(jsonEncode).toList()),
    );
  }

  Future<void> _enqueue(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString() ?? '';
    try {
      final jobs = await _readQueue();
      if (jobs.any((job) => job['id'] == orderId)) return;
      jobs.add({'id': orderId, 'order': order, 'attempts': 1});
      await _writeQueue(jobs);
    } catch (error) {
      debugPrint('Could not queue failed print for $orderId: $error');
    }
  }

  /// Retries queued tickets. Called on app start, after each refresh, and from
  /// the banner's "Retry" action.
  Future<void> drainQueue({bool resetAttempts = false}) async {
    if (!isReady) return;

    final jobs = await _readQueue();
    if (jobs.isEmpty) return;

    final remaining = <Map<String, dynamic>>[];
    for (final job in jobs) {
      var attempts = job['attempts'] as int? ?? 0;
      if (resetAttempts) attempts = 0;
      if (attempts >= _maxAttempts) {
        // Left in place, not dropped: the banner surfaces it and the vendor can
        // retry or use the card's reprint button.
        remaining.add({...job, 'attempts': attempts});
        continue;
      }

      final order = job['order'];
      if (order is! Map) continue;
      try {
        await _send(Map<String, dynamic>.from(order));
      } catch (error) {
        debugPrint('Queued print retry failed: $error');
        remaining.add({...job, 'attempts': attempts + 1});
      }
    }

    await _writeQueue(remaining);
  }
}
