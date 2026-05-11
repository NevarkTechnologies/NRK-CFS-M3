import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Web-only imports via conditional import
import 'csv_export_web.dart' if (dart.library.io) 'csv_export_stub.dart'
    as web_helper;

/// Saves [csvData] as a file named [fileName] and returns the saved path.
/// On mobile/desktop: saves to the documents directory.
/// On web: triggers a browser download.
Future<String> saveCsvFile(String fileName, String csvData) async {
  if (kIsWeb) {
    web_helper.downloadCsvOnWeb(fileName, csvData);
    return fileName; // No real path on web
  }

  final Directory dir = await _getTargetDirectory();
  final String filePath = '${dir.path}/$fileName';
  final File file = File(filePath);
  await file.writeAsString(csvData, flush: true);
  return filePath;
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