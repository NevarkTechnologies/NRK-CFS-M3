// Platform split. The Bluetooth plugin and dart:io sockets do not exist in a
// browser — and importantly the plugin imports dart:io at its top level, so a
// plain import would break the *web compile*, not merely fail at runtime.
// Everything platform-specific therefore lives behind this conditional import.
import 'printer_transport_web.dart'
    if (dart.library.io) 'printer_transport_io.dart'
    as impl;

/// How the ticket reaches the printer.
///
/// Bluetooth needs no network at all, which matters because the canteen may not
/// have a router. Network is the better link where a LAN exists: nothing to
/// pair, so nothing to lose pairing with mid-rush.
enum PrinterConnection {
  off('off'),
  bluetooth('bluetooth'),
  network('network');

  const PrinterConnection(this.value);

  /// Persisted in SharedPreferences — must stay stable across releases.
  final String value;

  static PrinterConnection fromValue(String? raw) {
    return PrinterConnection.values.firstWhere(
      (mode) => mode.value == raw,
      orElse: () => PrinterConnection.off,
    );
  }
}

/// Everything needed to reach the vendor's printer. Per-device, never synced to
/// the server — the printer is physically attached to one counter phone.
class PrinterConfig {
  const PrinterConfig({
    this.connection = PrinterConnection.off,
    this.btMac = '',
    this.btName = '',
    this.ip = '',
    this.port = defaultPort,
  });

  /// RAW / JetDirect. Universal on ESC/POS network printers.
  static const int defaultPort = 9100;

  final PrinterConnection connection;
  final String btMac;
  final String btName;
  final String ip;
  final int port;

  /// Whether this config names an actual destination. A connection mode with no
  /// device picked yet is treated as "not set up", not as an error.
  bool get isConfigured {
    switch (connection) {
      case PrinterConnection.bluetooth:
        return btMac.isNotEmpty;
      case PrinterConnection.network:
        return ip.isNotEmpty;
      case PrinterConnection.off:
        return false;
    }
  }

  /// Short human label for the settings screen and error messages.
  String get label {
    switch (connection) {
      case PrinterConnection.bluetooth:
        return btName.isNotEmpty ? btName : btMac;
      case PrinterConnection.network:
        return ip.isEmpty ? '' : '$ip:$port';
      case PrinterConnection.off:
        return '';
    }
  }

  PrinterConfig copyWith({
    PrinterConnection? connection,
    String? btMac,
    String? btName,
    String? ip,
    int? port,
  }) {
    return PrinterConfig(
      connection: connection ?? this.connection,
      btMac: btMac ?? this.btMac,
      btName: btName ?? this.btName,
      ip: ip ?? this.ip,
      port: port ?? this.port,
    );
  }
}

/// A printer already paired in Android's Bluetooth settings.
class PairedDevice {
  const PairedDevice({required this.name, required this.mac});

  final String name;
  final String mac;
}

/// A ticket could not be delivered. The message is vendor-facing — it is shown
/// on the settings screen and in the failed-print banner, so it says what to do
/// rather than quoting a stack trace.
class PrinterException implements Exception {
  const PrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Platform-specific printer I/O. One instance per app, obtained via
/// [createPrinterBackend].
abstract class PrinterBackend {
  /// False on web, where neither transport can exist. Callers use this to hide
  /// the whole feature rather than offering a button that cannot work.
  bool get isSupported;

  /// Sends [bytes] to the configured printer. Throws [PrinterException] with a
  /// vendor-readable message on any failure.
  Future<void> send(PrinterConfig config, List<int> bytes);

  /// Cheap reachability check for the settings status dot. Never throws.
  Future<bool> probe(PrinterConfig config);

  /// Printers already bonded in Android's Bluetooth settings. Listing only
  /// bonded devices is deliberate: it avoids BLUETOOTH_SCAN and the location
  /// permission that Play Console scrutinises.
  Future<List<PairedDevice>> pairedDevices();

  /// Requests BLUETOOTH_CONNECT if needed and confirms the radio is on.
  /// Returns false when the vendor declines or Bluetooth stays off.
  Future<bool> ensureBluetoothReady();

  /// Probes the phone's own subnet for anything listening on [port], so a
  /// non-technical owner never has to find their printer's IP by hand.
  Future<List<String>> scanForNetworkPrinters({
    int port = PrinterConfig.defaultPort,
  });
}

PrinterBackend createPrinterBackend() => impl.createPrinterBackend();
