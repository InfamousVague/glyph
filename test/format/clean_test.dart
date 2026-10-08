// A port of src/app/format/clean.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/format/clean.dart';

const notion = 'https://www.notion.so/attackfm/Buy-milk-1a2b3c4d5e6f';

void main() {
  group('the note as the model sees it', () {
    test('turns an old Notion item link into the mark form, and leaves other links alone', () {
      expect(
        cleanNote('- [ ] [Buy milk]($notion)\n- [ ] [Old one]($notion).\n- read [the docs](https://example.com/docs)\nSee [the board]($notion) too.\n'),
        '- [ ] Buy milk [notion]($notion)\n- [ ] Old one. [notion]($notion)\n- read [the docs](https://example.com/docs)\nSee [the board]($notion) too.\n',
      );
    });

    test('takes any list item for an item, numbered past 999 or spaced wide, and keeps its lead as written (core/itemSyntax.ts)', () {
      expect(cleanNote('1000. [Buy milk]($notion)\n-  [ ] [Buy eggs]($notion)'), '1000. Buy milk [notion]($notion)\n-  [ ] Buy eggs [notion]($notion)');
    });
  });

  group('the rewrite, tidy', () {
    test('unwinds a link nested in a link, keeping the inner one', () {
      expect(cleanRewrite('- [ ] [[Buy milk]($notion)]($notion) today\n'), '- [ ] Buy milk today [notion]($notion)\n');
      expect(cleanRewrite('See [[the docs](https://a.example/d)](https://b.example/x).\n'), 'See [the docs](https://a.example/d).\n');
      expect(cleanRewrite('- [x [inner](https://a.example/i) y](https://b.example/o)\n'), '- x [inner](https://a.example/i) y\n');
    });

    test('keeps an item’s mark once and last, whatever the model did with it', () {
      expect(cleanRewrite('- [ ] [notion]($notion) Buy milk on the way home.\n'), '- [ ] Buy milk on the way home. [notion]($notion)\n');
      expect(cleanRewrite('- [ ] Buy milk [notion]($notion) [notion]($notion)\n'), '- [ ] Buy milk [notion]($notion)\n');
      expect(cleanRewrite('- [ ] [Buy milk]($notion) [notion]($notion)\n'), '- [ ] Buy milk [notion]($notion)\n');
    });

    test('makes the markdown the plain kind: dashes, task boxes with spaces, a space after the hashes, no runs of blank lines', () {
      expect(cleanRewrite('#Title\n\n\n\n* one  \n+ two\n-[ ]three\n- [X] four\n-  [ ]  five\n'), '# Title\n\n- one\n- two\n- [ ] three\n- [x] four\n- [ ] five\n');
    });

    test('leaves words alone', () {
      const text = '# Call the plumber\n\n- [ ] Call the plumber about the leaking tap before **Thursday**, because it\'s getting worse.\n- [ ] Pick up eggs and coffee on the way home.\n';
      expect(cleanRewrite(text), text);
    });
  });
}
