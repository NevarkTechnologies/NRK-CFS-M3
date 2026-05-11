import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'excel_export_web.dart' if (dart.library.io) 'excel_export_stub.dart'
    as web_helper;

/// Groups [orders] by date and saves one sheet per day into an Excel file.
/// Returns the saved file path (or the file name on web).
Future<String> saveExcelReport(
  String fileName,
  List<Map<String, dynamic>> orders,
) async {
  final excel = Excel.createExcel();
  // Remove the default blank sheet
  excel.delete('Sheet1');

  // Group orders by date string  "YYYY-MM-DD"
  final Map<String, List<Map<String, dynamic>>> byDay = {};
  for (final order in orders) {
    final raw = order['createdAt']?.toString() ?? '';
    final date = DateTime.tryParse(raw);
    final key = date != null
        ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
        : 'Unknown';
    byDay.putIfAbsent(key, () => []).add(order);
  }

  final sortedDays = byDay.keys.toList()..sort();

  for (final day in sortedDays) {
    final sheetName = day; // e.g. "2025-05-08"
    final sheet = excel[sheetName];

    // ── Header row ──────────────────────────────────────────────
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#0F4CFF'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );
    final headers = [
      'Order ID',
      'Customer',
      'Items',
      'Amount (₹)',
      'Status',
      'Time',
    ];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }

    // ── Data rows ────────────────────────────────────────────────
    final dayOrders = byDay[day]!;
    dayOrders.sort((a, b) {
      final aD = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime(0);
      final bD = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime(0);
      return aD.compareTo(bD);
    });

    double dayTotal = 0;
    for (var r = 0; r < dayOrders.length; r++) {
      final order = dayOrders[r];
      final total = (order['total'] is num)
          ? (order['total'] as num).toDouble()
          : double.tryParse(order['total']?.toString() ?? '0') ?? 0;
      dayTotal += total;

      final itemsSummary = ((order['items'] as List<dynamic>?) ?? [])
          .map((i) => '${i['name']} x${i['qty']}')
          .join(', ');

      final createdAt = DateTime.tryParse(order['createdAt']?.toString() ?? '');
      final timeStr = createdAt != null
          ? '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
          : '';

      final rowData = [
        order['orderId'] ?? order['_id'] ?? '',
        order['customerName'] ?? '',
        itemsSummary,
        total.toStringAsFixed(2),
        order['status'] ?? '',
        timeStr,
      ];

      // Alternating row background
      final rowStyle = CellStyle(
        backgroundColorHex: r.isOdd
            ? ExcelColor.fromHexString('#F0F4FF')
            : ExcelColor.fromHexString('#FFFFFF'),
      );

      for (var c = 0; c < rowData.length; c++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
        );
        cell.value = TextCellValue(rowData[c].toString());
        cell.cellStyle = rowStyle;
      }
    }

    // ── Summary row ──────────────────────────────────────────────
    final summaryRow = dayOrders.length + 2;
    final summaryStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#E8EDFF'),
    );

    void summaryCell(int col, String val) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: summaryRow),
      );
      cell.value = TextCellValue(val);
      cell.cellStyle = summaryStyle;
    }

    summaryCell(0, 'TOTAL');
    summaryCell(1, '${dayOrders.length} orders');
    summaryCell(2, '');
    summaryCell(3, dayTotal.toStringAsFixed(2));
    summaryCell(4, '');
    summaryCell(5, '');

    // Set column widths
    sheet.setColumnWidth(0, 22);
    sheet.setColumnWidth(1, 20);
    sheet.setColumnWidth(2, 40);
    sheet.setColumnWidth(3, 14);
    sheet.setColumnWidth(4, 14);
    sheet.setColumnWidth(5, 10);
  }

  final bytes = excel.encode();
  if (bytes == null) throw Exception('Failed to encode Excel file');

  if (kIsWeb) {
    web_helper.downloadExcelOnWeb(fileName, bytes);
    return fileName;
  }

  final dir = await _getTargetDirectory();
  final path = '${dir.path}/$fileName';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

Future<Directory> _getTargetDirectory() async {
  if (Platform.isAndroid || Platform.isIOS) {
    return await getApplicationDocumentsDirectory();
  } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
  }
  return await getTemporaryDirectory();
}