import 'dart:convert';

import 'package:nevark_foods/services/receipt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the printable characters of a ticket, dropping ESC/POS control
/// sequences, so layout assertions read like the paper the vendor holds.
List<String> renderLines(List<int> bytes) {
  final text = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final byte = bytes[i];
    if (byte == 0x1B) {
      // ESC @ is 2 bytes; ESC t/a/E/d are 3.
      i += (i + 1 < bytes.length && bytes[i + 1] == 0x40) ? 2 : 3;
    } else if (byte == 0x1D) {
      // GS ! is 3 bytes, GS V is 3 or 4.
      if (i + 1 < bytes.length && bytes[i + 1] == 0x56) {
        i += (i + 2 < bytes.length && bytes[i + 2] == 0x42) ? 4 : 3;
      } else {
        i += 3;
      }
    } else {
      text.writeCharCode(byte);
      i++;
    }
  }
  return const LineSplitter().convert(text.toString());
}

Map<String, dynamic> sampleOrder({
  String token = '0042',
  String customer = 'Arjun',
  List<Map<String, dynamic>>? items,
}) {
  return {
    'id': 'BB2847193',
    'tokenNumber': token,
    'customer': customer,
    'cafeteriaName': 'Sunrise Cafeteria',
    'createdAt': DateTime(2026, 9, 15, 13, 42).toIso8601String(),
    'items':
        items ??
        [
          {'name': 'Veg Biryani', 'qty': 2},
          {'name': 'Masala Dosa', 'qty': 1},
        ],
  };
}

void main() {
  group('control sequences', () {
    test('starts by initialising the printer and selecting a codepage', () {
      final bytes = ReceiptBuilder.kitchenTicket(
        sampleOrder(),
        paper: PaperWidth.mm80,
      );
      // A printer left in another codepage by previous software would render
      // our ASCII as accented noise without this.
      expect(bytes.take(5), [0x1B, 0x40, 0x1B, 0x74, 0x00]);
    });

    test('ends by feeding past the cutter and cutting', () {
      final bytes = ReceiptBuilder.kitchenTicket(
        sampleOrder(),
        paper: PaperWidth.mm80,
      );
      // Feeding first matters: cutting immediately slices off the last lines.
      expect(bytes.skip(bytes.length - 7), [
        0x1B, 0x64, 0x03, // feed 3 lines
        0x1D, 0x56, 0x42, 0x00, // partial cut
      ]);
    });

    test('prints the token at double size and returns to normal', () {
      final bytes = ReceiptBuilder.kitchenTicket(
        sampleOrder(),
        paper: PaperWidth.mm80,
      );
      final doubleAt = _indexOfSequence(bytes, [0x1D, 0x21, 0x11]);
      final normalAt = _indexOfSequence(bytes, [0x1D, 0x21, 0x00]);
      expect(doubleAt, isNonNegative);
      expect(
        normalAt,
        greaterThan(doubleAt),
        reason: 'the rest of the ticket must not inherit double size',
      );
    });
  });

  group('layout', () {
    test('80mm rules span 48 columns, 58mm span 32', () {
      final wide = renderLines(
        ReceiptBuilder.kitchenTicket(sampleOrder(), paper: PaperWidth.mm80),
      );
      final narrow = renderLines(
        ReceiptBuilder.kitchenTicket(sampleOrder(), paper: PaperWidth.mm58),
      );
      expect(wide.firstWhere((l) => l.startsWith('---')).length, 48);
      expect(narrow.firstWhere((l) => l.startsWith('---')).length, 32);
    });

    test('carries token, items, customer and order id', () {
      final lines = renderLines(
        ReceiptBuilder.kitchenTicket(sampleOrder(), paper: PaperWidth.mm80),
      );
      expect(lines, contains('TOKEN #0042'));
      expect(lines, contains('2 x Veg Biryani'));
      expect(lines, contains('1 x Masala Dosa'));
      expect(lines, contains('Customer : Arjun'));
      expect(lines, contains('Ordered  : 1:42 PM'));
      expect(lines, contains('Order #BB2847193'));
    });

    test('keeps the display token exactly as the customer sees it', () {
      // Unlike the spoken announcement, which strips leading zeros so "0042"
      // is not read as "zero zero four two", the printed token must match the
      // app screen the customer is holding.
      final lines = renderLines(
        ReceiptBuilder.kitchenTicket(
          sampleOrder(token: '0007'),
          paper: PaperWidth.mm80,
        ),
      );
      expect(lines, contains('TOKEN #0007'));
    });

    test('wraps long item names instead of truncating them', () {
      final lines = renderLines(
        ReceiptBuilder.kitchenTicket(
          sampleOrder(
            items: [
              {
                'name': 'Paneer Butter Masala with Extra Butter Naan and Salad',
                'qty': 1,
              },
            ],
          ),
          paper: PaperWidth.mm58,
        ),
      );
      final firstLine = lines.indexWhere((l) => l.contains('Paneer'));
      final lastLine = lines.indexWhere((l) => l.contains('Salad'));
      expect(firstLine, isNonNegative);
      expect(
        lastLine,
        greaterThan(firstLine),
        reason:
            'the kitchen needs the whole name, so it must wrap onto '
            'further lines rather than being cut short',
      );
      // Continuation lines sit under the name, keeping the quantity column
      // scannable straight down the slip.
      expect(lines[lastLine].startsWith('    '), isTrue);
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(32));
      }
      // Nothing may be silently dropped on the way.
      final rejoined = lines.join(' ').replaceAll(RegExp(r'\s+'), ' ');
      expect(rejoined, contains('Extra Butter Naan and Salad'));
    });

    test('survives an order with no items', () {
      final lines = renderLines(
        ReceiptBuilder.kitchenTicket(
          sampleOrder(items: []),
          paper: PaperWidth.mm80,
        ),
      );
      expect(lines, contains('(no items listed)'));
    });

    test('falls back when the token is missing', () {
      final lines = renderLines(
        ReceiptBuilder.kitchenTicket(
          sampleOrder(token: ''),
          paper: PaperWidth.mm80,
        ),
      );
      expect(lines, contains('NO TOKEN'));
    });
  });

  group('sanitisation', () {
    test('folds accents to ASCII rather than printing noise', () {
      final lines = renderLines(
        ReceiptBuilder.kitchenTicket(
          sampleOrder(customer: 'José Müller'),
          paper: PaperWidth.mm80,
        ),
      );
      expect(lines, contains('Customer : Jose Muller'));
    });

    test('drops characters no ESC/POS codepage can render', () {
      final bytes = ReceiptBuilder.kitchenTicket(
        sampleOrder(customer: 'अर्जुन 🎉'),
        paper: PaperWidth.mm80,
      );
      // Every byte must stay inside the ASCII range the printer understands;
      // anything else turns the slip into garbage.
      for (final byte in bytes) {
        expect(byte, lessThan(0x80));
      }
    });

    test('never emits a bare customer label when the name is unprintable', () {
      final lines = renderLines(
        ReceiptBuilder.kitchenTicket(
          sampleOrder(customer: '🎉'),
          paper: PaperWidth.mm80,
        ),
      );
      expect(lines, contains('Customer : Customer'));
    });
  });

  test('test ticket is printable on both paper widths', () {
    for (final paper in PaperWidth.values) {
      final lines = renderLines(ReceiptBuilder.testTicket(paper: paper));
      expect(lines, contains('TOKEN #0042'));
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(paper.columns));
      }
    }
  });
}

int _indexOfSequence(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
