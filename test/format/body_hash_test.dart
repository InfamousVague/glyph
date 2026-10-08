// A port of src/app/format/bodyHash.test.ts.
//
// The hash is kept: a gist, the AI's marks and a run's record are written against it, on the device and in the
// store's i64 column. So it must be the same number for the same text on every run and every device (the web's
// number, bit for bit), a different one for a text that differs by a character, and a number JSON carries without
// rounding.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/format/body_hash.dart';

void main() {
  group('the hash a kept thing is written against', () {
    test('is the same for the same text, every time', () {
      const body = '# Trip\n\n- [ ] call the plumber before Thursday\n';
      expect(bodyHash(body), bodyHash(String.fromCharCodes(body.codeUnits)));
      // Pinned: a change to the function would strand every gist and mark already kept against the old numbers.
      expect(bodyHash(''), 0x29ce484222325);
      expect(bodyHash('call Sam'), 2362324126580082);
    });

    test('tells apart texts that differ by one character, a case or a newline', () {
      final hashes = ['call Sam', 'call Sa m', 'Call Sam', 'call Sam\n', 'call Sam ', 'call Sán'].map(bodyHash).toSet();
      expect(hashes.length, 6);
    });

    test('stays a whole number JSON and an i64 column carry unchanged', () {
      for (final text in ['', 'x', 'a much longer note, with 🍞 and ünïcödé in it\n' * 40]) {
        final hash = bodyHash(text);
        // `Number.isSafeInteger`.
        expect(hash <= 9007199254740991, isTrue);
        expect(hash, greaterThanOrEqualTo(0));
        expect(jsonDecode(jsonEncode(hash)), hash);
      }
    });

    test('is the page’s number for text past the first plane and for a long note', () {
      // Not a case of the web's: its own answers for three more texts (the function of src/app/format/bodyHash.ts run in node), so the
      // 64-bit wrap and the UTF-16 units are held to it beyond the two pinned above.
      expect(bodyHash('🍞'), _web['bread']);
      expect(bodyHash('a much longer note, with 🍞 and ünïcödé in it\n' * 40), _web['long']);
      expect(bodyHash('# Trip\n\n- [ ] call the plumber before Thursday\n'), _web['trip']);
    });
  });
}

const Map<String, int> _web = {'bread': 679541741017823, 'long': 989861902071989, 'trip': 3247034570822769};
