import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/tags.dart';

/// A tag's grammar (lib/core/tags.dart), case for case with the web's `core/tags.test.ts`.

List<String> names(String text) => [for (final tag in tagsIn(text)) text.substring(tag.from, tag.to)];

void main() {
  group('tags', () {
    test('finds a # against a letter, after the start, a space or a bracket', () {
      expect(names('- [ ] Ship it #web #Launch-2 (#later)'), ['#web', '#Launch-2', '#later']);
      expect(names('#inbox first'), ['#inbox']);
      expect(names('#work/clients and #café'), ['#work/clients', '#café']);
      expect(tagsIn('#Web').first.name, 'web');
    });

    test('leaves headings, numbers, words and links alone, and trims a trailing dash or slash', () {
      expect(names('# Weekend trip'), isEmpty);
      expect(names('## The budget'), isEmpty);
      expect(names('issue #42 and C#sharp'), isEmpty);
      expect(names('see https://example.com/#section'), isEmpty);
      expect(names('- [ ] Ship it #web [notion](https://notion.so/a#b) ^ship'), ['#web']);
      expect(names('tagged #todo- and #a/'), ['#todo', '#a']);
    });

    test('counts positions from the line it was given', () {
      expect(tagsIn('a #b', 10), [const Tag(from: 12, to: 14, name: 'b')]);
    });
  });
}
