import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Web-only imports via conditional import
import 'csv_export_web.dart' if (dart.library.io) 'csv_export_stub.dart'
    as web_helper;

/// Saves [csvData] as a file named [fileName].
/// On mobile: opens system Save dialog so user can pick location.
/// On web: triggers a browser download.
Future<String> saveCsvFile(String fileName, String csvData) async {
  if (kIsWeb) {
    web_helper.downloadCsvOnWeb(fileName, csvData);
    return fileName;
  }

  final bytes = Uint8List.fromList(utf8.encode(csvData));

  // Open system file picker so user can choose where to save
  final String? outputPath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save CSV Report',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: ['csv'],
    bytes: bytes,
  );

  if (outputPath != null) return outputPath;

  // Fallback: save to external storage (visible in file manager)
  final Directory dir = await _getFallbackDirectory();
  final String filePath = '${dir.path}/$fileName';
  await File(filePath).writeAsBytes(bytes, flush: true);
  return filePath;
}

Future<Directory> _getFallbackDirectory() async {
  if (Platform.isAndroid) {
    return await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
  } else if (Platform.isIOS) {
    return await getApplicationDocumentsDirectory();
  } else {
    return await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
  }
}
