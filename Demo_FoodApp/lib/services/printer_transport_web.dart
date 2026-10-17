import 'printer_transport.dart';

PrinterBackend createPrinterBackend() => WebPrinterBackend();

/// Web has neither transport: a browser cannot open a raw TCP socket, and the
/// Bluetooth Classic plugin is native-only. This stub exists so the web build
/// still compiles — callers check [isSupported] and hide the feature entirely
/// rather than offering a printer button that can never work.
///
/// This is not a limitation in practice: the printer is attached to the counter
/// phone, and the vendor web app is for a desk.
class WebPrinterBackend implements PrinterBackend {
  @override
  bool get isSupported => false;

  @override
  Future<void> send(PrinterConfig config, List<int> bytes) async {
    throw const PrinterException(
      'Printing is only available in the Android app.',
    );
  }

  @override
  Future<bool> probe(PrinterConfig config) async => false;

  @override
  Future<List<PairedDevice>> pairedDevices() async => const [];

  @override
  Future<bool> ensureBluetoothReady() async => false;

  @override
  Future<List<String>> scanForNetworkPrinters({
    int port = PrinterConfig.defaultPort,
  }) async => const [];
}
