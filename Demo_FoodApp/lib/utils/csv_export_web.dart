// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Triggers a CSV file download in the browser.
void downloadCsvOnWeb(String fileName, String csvData) {
  final bytes = csvData.codeUnits;
  final blob = html.Blob([bytes], 'text/csv');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();

  html.Url.revokeObjectUrl(url);
}