import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/entry_starts.dart';
import 'package:ghost_md/book/journal.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;

/// What a new page and a new entry start with (lib/book/entry_starts.dart), case for case with the web's
/// `book/entryStarts.test.ts`.
void main() {
  group('what a new page starts with', () {
    test('offers just the title first, then the journal templates', () {
      expect([for (final each in pageStarts()) each.name], ['Just the title', for (final each in entryPresets) each.name]);
      expect(pageStarts()[0].text, '');
    });

    test('keeps the page’s title as its heading, so the index still finds it, with the template under it', () {
      final at = DateTime(2026, 9, 29, 14, 5);
      expect(pageBody('Monday', '', 'Field guide', at), '# Monday\n\n');
      final morning = pageBody('Monday', entryPresets[2].text, 'Field guide', at);
      expect(noteTitle(morning), 'Monday');
      expect(morning.startsWith('# Monday\n\n## '), isTrue);
      expect(morning, contains('> What is on your mind this morning?'));
      expect(RegExp(r'^# ', multiLine: true).allMatches(morning), hasLength(1));
      expect(pageBody('Monday', '**{{time}}** from {{journal}}, {{title}}', 'Field guide', at), '# Monday\n\n**14:05** from Field guide, Monday');
    });
  });

  group('what a new entry starts with', () {
    test('puts the usual template first, then the presets it is not, then an empty page', () {
      expect([for (final each in entryStarts(entryPresets[1].text)) each.id], ['usual', 'stamped', 'morning', 'todos', 'empty']);
      expect(startLine('', 'Log'), 'Nothing, a blank page');
    });
  });
}
