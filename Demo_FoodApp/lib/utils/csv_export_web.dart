import 'dart:js_interop';
import 'package:web/web.dart';

/// Triggers a CSV file download in the browser.
void downloadCsvOnWeb(String fileName, String csvData) {
  final blob = Blob(
    <JSAny>[csvData.toJS].toJS,
    BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = URL.createObjectURL(blob);
  final anchor = document.createElement('a') as HTMLAnchorElement;
  anchor.href = url;
  anchor.setAttribute('download', fileName);
  anchor.click();
  URL.revokeObjectURL(url);
}
