import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart';

void downloadExcelOnWeb(String fileName, List<int> bytes) {
  final uint8Array = Uint8List.fromList(bytes).toJS;
  final blob = Blob(
    <JSAny>[uint8Array].toJS,
    BlobPropertyBag(
      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ),
  );
  final url = URL.createObjectURL(blob);
  final anchor = document.createElement('a') as HTMLAnchorElement;
  anchor.href = url;
  anchor.setAttribute('download', fileName);
  anchor.click();
  URL.revokeObjectURL(url);
}
