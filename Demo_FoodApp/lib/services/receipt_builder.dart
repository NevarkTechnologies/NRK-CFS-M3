import 'dart:convert';

/// Paper sizes the vendor can choose, carrying the character columns Font A
/// gives on that width. Every layout decision below is measured in columns, so
/// switching paper re-flows the whole ticket rather than clipping it.
enum PaperWidth {
  mm58('58', 32),
  mm80('80', 48);

  const PaperWidth(this.value, this.columns);

  /// Persisted in SharedPreferences — must stay stable across releases.
  final String value;
  final int columns;

  static PaperWidth fromValue(String? raw) =>
      raw == '58' ? PaperWidth.mm58 : PaperWidth.mm80;

  String get label => this == PaperWidth.mm58 ? '58 mm' : '80 mm';
}

/// ESC/POS commands. This is the complete set the kitchen ticket needs — there
/// are no images, barcodes or QR codes on it.
class _Cmd {
  static const init = [0x1B, 0x40];
  // CP437 is the default codepage on effectively every ESC/POS unit sold in
  // India. Selecting it explicitly means a printer left in another codepage by
  // previous software still renders our ASCII correctly.
  static const codepage437 = [0x1B, 0x74, 0x00];
  static const alignLeft = [0x1B, 0x61, 0x00];
  static const alignCenter = [0x1B, 0x61, 0x01];
  static const boldOn = [0x1B, 0x45, 0x01];
  static const boldOff = [0x1B, 0x45, 0x00];
  static const sizeNormal = [0x1D, 0x21, 0x00];

  /// Double width + double height: `(w-1) << 4 | (h-1)` with w = h = 2.
  static const sizeDouble = [0x1D, 0x21, 0x11];
  static const lineFeed = [0x0A];

  static List<int> feed(int lines) => [0x1B, 0x64, lines];

  /// Partial cut, leaving a small tab so the slip does not fall on the floor.
  /// Some budget units ignore this one. If a test print feeds paper but never
  /// cuts, replace it with the plain full cut: `[0x1D, 0x56, 0x00]`.
  static const cut = [0x1D, 0x56, 0x42, 0x00];
}

/// Builds the ESC/POS byte stream for a vendor kitchen ticket.
///
/// Deliberately dependency-free. The obvious alternative, `esc_pos_utils_plus`,
/// requires `CapabilityProfile.load()`, which pulls a bundled asset through
/// `rootBundle` — avoidable risk for bytes that must generate identically no
/// matter which isolate asks for them. There is exactly one layout here and it
/// needs only the handful of commands in [_Cmd].
///
/// The same bytes are sent over Bluetooth and over TCP; nothing here knows or
/// cares which transport carries them.
class ReceiptBuilder {
  ReceiptBuilder(this.paper);

  final PaperWidth paper;
  final List<int> _out = <int>[];

  int get _columns => paper.columns;

  /// Kitchen ticket: big token, what to cook, who it is for. No prices — the
  /// customer already has their receipt in the app, and a shorter slip is
  /// faster to read at a hot counter.
  static List<int> kitchenTicket(
    Map<String, dynamic> order, {
    required PaperWidth paper,
  }) {
    final builder = ReceiptBuilder(paper);
    return builder._buildKitchenTicket(order);
  }

  /// Sample slip for the settings "Test print" button, so the vendor can prove
  /// the printer works before relying on it during service.
  static List<int> testTicket({required PaperWidth paper}) {
    return ReceiptBuilder.kitchenTicket({
      'tokenNumber': '0042',
      'customer': 'Test Print',
      'cafeteriaName': 'BenchBites',
      'createdAt': DateTime.now().toIso8601String(),
      'id': 'TEST-TICKET',
      'items': [
        {'name': 'Veg Biryani', 'qty': 2},
        {'name': 'Masala Dosa', 'qty': 1},
        {'name': 'Filter Coffee', 'qty': 1},
      ],
    }, paper: paper);
  }

  List<int> _buildKitchenTicket(Map<String, dynamic> order) {
    _raw(_Cmd.init);
    _raw(_Cmd.codepage437);

    // ── Header ──────────────────────────────────────────────────────────────
    _raw(_Cmd.alignCenter);
    _raw(_Cmd.boldOn);
    _line('BENCHBITES');
    _raw(_Cmd.boldOff);

    final cafe = _sanitize(order['cafeteriaName']?.toString() ?? '');
    if (cafe.isNotEmpty) _line(cafe);

    // ── Token ───────────────────────────────────────────────────────────────
    // The one thing that must be readable across a counter, so it is the only
    // double-size element. Alignment is left to the printer (ESC a 1) rather
    // than space padding, which would be wrong at double width.
    _rule();
    _feedLines(1);
    _raw(_Cmd.sizeDouble);
    _raw(_Cmd.boldOn);
    final token = _sanitize(order['tokenNumber']?.toString() ?? '').trim();
    _line(token.isEmpty ? 'NO TOKEN' : 'TOKEN #$token');
    _raw(_Cmd.boldOff);
    _raw(_Cmd.sizeNormal);
    _feedLines(1);
    _rule();

    // ── Items ───────────────────────────────────────────────────────────────
    _raw(_Cmd.alignLeft);
    final items = order['items'];
    var printedAny = false;
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final name = _sanitize(item['name']?.toString() ?? '').trim();
        if (name.isEmpty) continue;
        final qty = int.tryParse(item['qty']?.toString() ?? '') ?? 1;
        final prefix = '$qty x ';
        // Wrapped, never truncated — the kitchen needs the whole name. The
        // hanging indent keeps continuation lines under the name so the
        // quantity column stays scannable down the slip.
        for (final wrapped in _wrap(
          '$prefix$name',
          hangingIndent: prefix.length,
        )) {
          _line(wrapped);
        }
        printedAny = true;
      }
    }
    if (!printedAny) _line('(no items listed)');

    // ── Footer ──────────────────────────────────────────────────────────────
    _rule();
    final customer = _sanitize(order['customer']?.toString() ?? '').trim();
    _line('Customer : ${customer.isEmpty ? 'Customer' : customer}');
    final orderedAt = _formatTime(order['createdAt']?.toString() ?? '');
    if (orderedAt.isNotEmpty) _line('Ordered  : $orderedAt');
    _rule();

    _raw(_Cmd.alignCenter);
    final id = _sanitize(order['id']?.toString() ?? '').trim();
    if (id.isNotEmpty) _line('Order #$id');
    _raw(_Cmd.alignLeft);

    // Feed past the cutter before cutting, or the last lines are sliced off.
    _raw(_Cmd.feed(3));
    _raw(_Cmd.cut);

    return List<int>.unmodifiable(_out);
  }

  // ── Primitives ────────────────────────────────────────────────────────────

  void _raw(List<int> bytes) => _out.addAll(bytes);

  void _line(String text) {
    // Safe because _sanitize has already reduced everything to 0x20-0x7E.
    _out.addAll(ascii.encode(text));
    _raw(_Cmd.lineFeed);
  }

  void _feedLines(int count) {
    for (var i = 0; i < count; i++) {
      _raw(_Cmd.lineFeed);
    }
  }

  void _rule() => _line('-' * _columns);

  /// Wraps to the paper width, indenting continuation lines by [hangingIndent].
  /// Words longer than a full line are hard-split rather than dropped.
  List<String> _wrap(String text, {int hangingIndent = 0}) {
    if (text.length <= _columns) return [text];

    final indent = ' ' * hangingIndent;
    final lines = <String>[];
    var current = '';
    var width = _columns;

    void push() {
      if (current.isEmpty) return;
      lines.add(current);
      current = '';
      // Every line after the first carries the hanging indent.
      width = _columns - hangingIndent;
    }

    for (final word in text.split(' ')) {
      var remaining = word;
      // A single word wider than the line can never fit; break it up.
      while (remaining.length > width) {
        push();
        lines.add(
          (lines.isEmpty ? '' : indent) + remaining.substring(0, width),
        );
        remaining = remaining.substring(width);
        width = _columns - hangingIndent;
      }
      final candidate = current.isEmpty
          ? (lines.isEmpty ? remaining : indent + remaining)
          : '$current $remaining';
      if (candidate.length > _columns) {
        push();
        current = indent + remaining;
      } else {
        current = candidate;
      }
    }
    push();
    return lines;
  }

  /// "1:42 PM" from an ISO timestamp. Empty when unparseable, so the line is
  /// simply omitted rather than printing "Ordered  : ".
  static String _formatTime(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Reduces text to printable ASCII.
  ///
  /// A thermal printer renders anything outside its active codepage as random
  /// glyphs, so an unsanitised customer name turns the slip into noise. Menu
  /// items are English, but names are user-supplied and can carry accents:
  /// those degrade to the closest ASCII letter, and anything else (Devanagari,
  /// emoji) is dropped rather than printed as garbage.
  static String _sanitize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x20 && rune <= 0x7E) {
        buffer.writeCharCode(rune);
      } else if (_diacritics.containsKey(rune)) {
        buffer.write(_diacritics[rune]);
      }
    }
    return buffer.toString();
  }

  static const Map<int, String> _diacritics = {
    0x00E0: 'a',
    0x00E1: 'a',
    0x00E2: 'a',
    0x00E3: 'a',
    0x00E4: 'a',
    0x00E5: 'a',
    0x00E7: 'c',
    0x00E8: 'e',
    0x00E9: 'e',
    0x00EA: 'e',
    0x00EB: 'e',
    0x00EC: 'i',
    0x00ED: 'i',
    0x00EE: 'i',
    0x00EF: 'i',
    0x00F1: 'n',
    0x00F2: 'o',
    0x00F3: 'o',
    0x00F4: 'o',
    0x00F5: 'o',
    0x00F6: 'o',
    0x00F9: 'u',
    0x00FA: 'u',
    0x00FB: 'u',
    0x00FC: 'u',
    0x00C0: 'A',
    0x00C1: 'A',
    0x00C2: 'A',
    0x00C3: 'A',
    0x00C4: 'A',
    0x00C5: 'A',
    0x00C7: 'C',
    0x00C8: 'E',
    0x00C9: 'E',
    0x00CA: 'E',
    0x00CB: 'E',
    0x00CC: 'I',
    0x00CD: 'I',
    0x00CE: 'I',
    0x00CF: 'I',
    0x00D1: 'N',
    0x00D2: 'O',
    0x00D3: 'O',
    0x00D4: 'O',
    0x00D5: 'O',
    0x00D6: 'O',
    0x00D9: 'U',
    0x00DA: 'U',
    0x00DB: 'U',
    0x00DC: 'U',
    0x2018: "'",
    0x2019: "'",
    0x201C: '"',
    0x201D: '"',
    0x2013: '-',
    0x2014: '-',
    0x00A0: ' ',
  };
}
