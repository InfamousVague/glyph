// The two readings of a body the sync merge leans on, where they are ported for it: the app's own summary section
// (lib/core/summary_text.dart, from `src/app/ai/summaryText.ts`) and one line added to a notebook's index
// (lib/core/book.dart `withChapter`, from `src/app/book/book.ts`). The cases are the web's own, from
// `ai/summaryText.test.ts` and `book/book.test.ts`, for the functions that crossed.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/summary_text.dart';
import 'package:ghost_md/sync/notes.dart';

void main() {
  const section = '## Summary\nWe agreed the plan.\n\n- Decided: ship on Friday.\n- [ ] Sam writes the notes.';

  group('the summary section', () {
    test('goes after the title, with a blank line either side, and is found again by its shape', () {
      const body = '# Meeting, 26 Sep 14:05\n\n## Transcript\n\nHello there.';
      final written = withSummary(body, section);
      expect(written, '# Meeting, 26 Sep 14:05\n\n$section\n\n## Transcript\n\nHello there.');
      final found = summarySection(written)!;
      expect(found.text, section);
      expect(written.substring(found.start, found.end), section);
      expect(summaryLine(written), 'We agreed the plan.');
      expect(withoutSummary(written), body);
    });

    test('goes after a plain first paragraph and after the front matter, never above the words', () {
      expect(withSummary('First words\nsecond line\n\nMore.', section), 'First words\nsecond line\n\n$section\n\nMore.');
      const fronted = '---\ntitle: "Plan"\n---\nThe words.';
      expect(withSummary(fronted, section), '---\ntitle: "Plan"\n---\nThe words.\n\n$section');
      expect(summaryPlace('# Title\n\nwords'), '# Title\n'.length);
      expect((hasWords('![a](image/a.jpg)\n'), hasWords('---\ntitle: "Plan"\n---\n'), hasWords('words')), (false, true, true));
    });

    test('is written over the one a note has, and a note with no words at all gets the model’s heading above it', () {
      final first = withSummary('# Plan\n\nwords', section);
      const next = '## Summary\nA new line.\n\n- Other.';
      expect(withSummary(first, next), '# Plan\n\n$next\n\nwords');
      expect(withSummary('', section, title: 'Standup'), '# Standup\n\n$section');
      expect(withSummary('# Meeting, 26 Sep 14:05\n\nwords', section, title: 'Standup'), startsWith('# Standup\n'));
      expect(withSummary('# My own title\n\nwords', section, title: 'Standup'), startsWith('# My own title\n'));
    });

    test('ends at a heading, a rule, or the first line that is not an item; the kept text closes it under a list of the person’s own', () {
      const body = '# Plan\n\n$section\n\n- [ ] my own to-do\n\nAfter.';
      // By shape alone the person's list straight under it reads as the section's.
      expect(summarySection(body)!.text, '$section\n\n- [ ] my own to-do');
      expect(summarySection(body, section)!.text, section);
      // A box ticked since still reads as the kept section.
      final ticked = body.replaceFirst('- [ ] Sam', '- [x] Sam');
      expect(summarySection(ticked, section)!.text, section.replaceFirst('- [ ] Sam', '- [x] Sam'));
      expect(withoutSummary(body, section), '# Plan\n\n- [ ] my own to-do\n\nAfter.');
      expect(summarySection('# Plan\n\nNo section.'), isNull);
      expect(withoutSummary('# Plan\n\nNo section.'), '# Plan\n\nNo section.');
    });

    test('is all two copies of a note differ by, as the merge asks it', () {
      const base = '# Plan\n\nwords';
      const other = '## Summary\nAnother line.\n\n- Two.';
      expect(withoutSummary(withSummary(base, section)), withoutSummary(withSummary(base, other)));
      expect(withoutSummary(withSummary(base, section)), isNot(withoutSummary(withSummary('$base more', other))));
    });
  });

  group('a chapter added to a notebook’s index', () {
    const book = '---\ntitle: "Trip"\nbook: true\n---\n# Trip\n\n- [[Packing]]\n- [[Route]]\n';

    test('goes after the one named, else last, and never twice', () {
      expect(withChapter(book, 'Food', 'Packing'), book.replaceFirst('- [[Packing]]\n', '- [[Packing]]\n- [[Food]]\n'));
      expect(withChapter(book, 'Food'), book.replaceFirst('- [[Route]]\n', '- [[Route]]\n- [[Food]]\n'));
      expect(withChapter(book, 'Food', 'Not there'), withChapter(book, 'Food'));
      expect(withChapter(book, 'packing'), book);
      expect(withChapter(book, '   '), book);
    });

    test('goes on numbering a numbered index, keeps an indent, and starts an index where there is none', () {
      const numbered = '---\nbook: true\n---\n# Trip\n\n1. [[One]]\n2. [[Two]]\n';
      expect(withChapter(numbered, 'Three'), '${numbered}3. [[Three]]\n');
      const nested = '---\nbook: true\n---\n- [[One]]\n  - [[Inner]]\n';
      expect(withChapter(nested, 'Deeper', 'Inner'), '---\nbook: true\n---\n- [[One]]\n  - [[Inner]]\n  - [[Deeper]]\n');
      expect(withChapter('---\nbook: true\n---\n# Log\n\n', 'First'), '---\nbook: true\n---\n# Log\n\n- [[First]]\n');
    });

    test('is how two copies of one notebook become one', () {
      final merged = mergedIndex('$book- [[Mine]]\n', '$book- [[Theirs]]\n');
      expect(merged, '$book- [[Theirs]]\n'.replaceFirst('- [[Route]]\n', '- [[Route]]\n- [[Mine]]\n'));
      expect(mergedIndex('# Not a book\n\n- [[A]]\n', '# Not a book\n\n- [[B]]\n'), isNull);
      expect(mergedIndex('$book\nA line here.', '$book- [[Theirs]]\n'), isNull);
    });
  });
}
