import 'dart:convert';
import 'dart:typed_data';

/// Memoized base64 → bytes for inline (data-URI) images.
///
/// Menu/cafe images arrive as base64 strings inside API payloads and several
/// screens decoded them inside build()/itemBuilder — meaning every rebuild and
/// every scroll frame re-ran base64Decode on the UI isolate. This cache decodes
/// each distinct string once. Dart maps are insertion-ordered, so evicting the
/// first key gives cheap FIFO bounding.
class B64ImageCache {
  static const int _maxEntries = 160;
  static final Map<String, Uint8List> _cache = {};

  static Uint8List decode(String b64) {
    final hit = _cache[b64];
    if (hit != null) return hit;
    final bytes = base64Decode(b64);
    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[b64] = bytes;
    return bytes;
  }
}
