import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/title_key.dart';

/// A title as it is matched (lib/core/title_key.dart), case for case with the web's `core/titleKey.test.ts`.
void main() {
  group('a title as it is matched', () {
    test('keys titles the way links are matched', () {
      expect(titleKey('  The Oaks!  '), 'the oaks');
      expect(titleKey('oaks'), titleKey('Oaks'));
    });

    test('makes every run of punctuation and space one space, so a title said aloud finds the note however it was written', () {
      expect(titleKey('Weekend trip - packing, list'), 'weekend trip packing list');
      expect(titleKey('weekend trip packing list'), 'weekend trip packing list');
      expect(titleKey('AttackFM/bugbash_2'), 'attackfm bugbash 2');
    });

    test('is empty for a title with nothing but punctuation, which matches nothing', () {
      expect(titleKey('  -- !! '), '');
      expect(titleKey(''), '');
    });
  });
}
