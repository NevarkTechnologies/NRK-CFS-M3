import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'printer_transport.dart';

PrinterBackend createPrinterBackend() => IoPrinterBackend();

/// Native printer I/O: Bluetooth Classic via `print_bluetooth_thermal`, and
/// raw TCP for networked ESC/POS printers.
///
/// `print_bluetooth_thermal` was chosen over `blue_thermal_printer` because it
/// does not request location permission. The latter's own example warns that
/// its location prompt crashes the app even when the user grants it, and Play
/// Console rejects location use a receipt printer cannot justify.
class IoPrinterBackend implements PrinterBackend {
  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  Future<void> send(PrinterConfig config, List<int> bytes) async {
    switch (config.connection) {
      case PrinterConnection.off:
        throw const PrinterException('Printing is turned off.');
      case PrinterConnection.network:
        await _sendNetwork(config, bytes);
      case PrinterConnection.bluetooth:
        await _sendBluetooth(config, bytes);
    }
  }

  // ── Network (Wi-Fi / LAN) ─────────────────────────────────────────────────

  Future<void> _sendNetwork(PrinterConfig config, List<int> bytes) async {
    if (config.ip.isEmpty) {
      throw const PrinterException('No printer IP address set.');
    }

    Socket? socket;
    try {
      // A fresh socket per ticket, deliberately. Printers drop idle sockets
      // without telling anyone, and a held-open connection only reveals it is
      // dead on the next order — exactly when it matters most.
      socket = await Socket.connect(
        config.ip,
        config.port,
        timeout: const Duration(seconds: 6),
      );
      socket.add(bytes);
      await socket.flush();
      // close() resolves when the printer closes its side, which many ESC/POS
      // units never do. Bound the wait, then force it down in the finally.
      await socket.close().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    } on SocketException catch (error) {
      throw PrinterException(
        'Could not reach the printer at ${config.ip}:${config.port}. '
        '${error.osError?.message ?? 'Check it is powered on and on the same network.'}',
      );
    } on TimeoutException {
      throw PrinterException('The printer at ${config.ip} did not respond.');
    } finally {
      socket?.destroy();
    }
  }

  // ── Bluetooth ─────────────────────────────────────────────────────────────

  Future<void> _sendBluetooth(PrinterConfig config, List<int> bytes) async {
    if (config.btMac.isEmpty) {
      throw const PrinterException('No Bluetooth printer selected.');
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw const PrinterException('Bluetooth is switched off on this phone.');
    }

    // Never assume the link survived since the last ticket. An idle Bluetooth
    // connection dropping silently between orders is the single most common
    // real-world failure for counter printers, so reconnect before every send.
    if (!await PrintBluetoothThermal.connectionStatus) {
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: config.btMac,
      );
      if (!connected) {
        throw PrinterException(
          'Could not connect to ${config.label}. Check it is powered on '
          'and still paired in Android Bluetooth settings.',
        );
      }
    }

    final written = await PrintBluetoothThermal.writeBytes(bytes);
    if (!written) {
      // Treat a rejected write as a stale link so the next attempt re-pairs
      // from scratch rather than retrying down a dead connection.
      await _disconnectQuietly();
      throw const PrinterException(
        'The printer did not accept the ticket. It may have been switched off.',
      );
    }
  }

  Future<void> _disconnectQuietly() async {
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (error) {
      debugPrint('Bluetooth disconnect failed: $error');
    }
  }

  // ── Status and discovery ──────────────────────────────────────────────────

  @override
  Future<bool> probe(PrinterConfig config) async {
    try {
      switch (config.connection) {
        case PrinterConnection.off:
          return false;
        case PrinterConnection.network:
          if (config.ip.isEmpty) return false;
          final socket = await Socket.connect(
            config.ip,
            config.port,
            timeout: const Duration(seconds: 3),
          );
          socket.destroy();
          return true;
        case PrinterConnection.bluetooth:
          if (config.btMac.isEmpty) return false;
          if (!await PrintBluetoothThermal.bluetoothEnabled) return false;
          if (await PrintBluetoothThermal.connectionStatus) return true;
          return PrintBluetoothThermal.connect(macPrinterAddress: config.btMac);
      }
    } catch (error) {
      debugPrint('Printer probe failed: $error');
      return false;
    }
  }

  @override
  Future<List<PairedDevice>> pairedDevices() async {
    try {
      if (!await ensureBluetoothReady()) return const [];
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      return devices
          // NOTE: the plugin spells the field "macAdress" (one d). Keep it.
          .map((d) => PairedDevice(name: d.name, mac: d.macAdress))
          .where((d) => d.mac.isNotEmpty)
          .toList();
    } catch (error) {
      debugPrint('Listing paired printers failed: $error');
      return const [];
    }
  }

  @override
  Future<bool> ensureBluetoothReady() async {
    try {
      // Android 12+ needs BLUETOOTH_CONNECT granted at runtime; the manifest
      // entry alone is not enough. On Android 11 and below this resolves as
      // already-granted, so the same call is safe on every version.
      if (Platform.isAndroid) {
        final status = await Permission.bluetoothConnect.request();
        if (!status.isGranted) return false;
      }
      if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
        return false;
      }
      return PrintBluetoothThermal.bluetoothEnabled;
    } catch (error) {
      debugPrint('Bluetooth readiness check failed: $error');
      return false;
    }
  }

  @override
  Future<List<String>> scanForNetworkPrinters({
    int port = PrinterConfig.defaultPort,
  }) async {
    final found = <String>[];
    final prefixes = <String>{};

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length == 4) {
            prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
          }
        }
      }
    } catch (error) {
      debugPrint('Could not read local network interfaces: $error');
      return const [];
    }

    for (final prefix in prefixes) {
      // Batched rather than 254 sockets at once — Android caps open file
      // descriptors, and a flood makes every probe time out spuriously.
      for (var start = 1; start <= 254; start += 32) {
        final batch = <Future<void>>[];
        for (var host = start; host < start + 32 && host <= 254; host++) {
          final ip = '$prefix.$host';
          batch.add(
            Socket.connect(ip, port, timeout: const Duration(milliseconds: 400))
                .then((socket) {
                  socket.destroy();
                  found.add(ip);
                })
                .catchError((_) {}),
          );
        }
        await Future.wait(batch);
      }
    }

    found.sort();
    return found;
  }
}
