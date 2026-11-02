// What Cleanup does to a note's words (lib/plugins/cleanup/text.dart): a title written where the title is with no
// words lost, the weak titles it looks for, the formatting-only check a tidy must pass, tags and links added, and a
// duplicate's lines kept in the note it is merged into.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/cleanup/cleanup.dart';

void main() {
  group('a new title', () {
    test('replaces a heading at its level, sets a front matter title, and goes above a first line of prose', () {
      expect(titledBody('# Untitled\n\nWords.', 'Kiln call'), '# Kiln call\n\nWords.');
      expect(titledBody('## Old\n\nWords.', 'New'), '## New\n\nWords.');
      expect(titledBody('---\ntitle: Old\n---\nWords.', 'New one'), '---\ntitle: New one\n---\nWords.');
      // A first line of prose was the title only because it came first: it stays, the heading goes above it.
      expect(titledBody('Call with the shop about prices.\nMore.', 'Shop call'), '# Shop call\n\nCall with the shop about prices.\nMore.');
      expect(titledBody('---\nicon: x\n---\n\n![pic](a.jpg)\n# Old', 'New'), '---\nicon: x\n---\n\n![pic](a.jpg)\n# New');
      expect(titledBody('', 'Fresh'), '# Fresh');
      expect(titledBody('# Same', '  '), '# Same');
    });

    test('a weak title is none, Untitled, a date alone, or a meeting’s or a recording’s date title', () {
      for (final weak in ['', 'Untitled', 'untitled 3', 'New note', '2026-10-16', '16/10/2026', 'Oct 16, 2026', '16 Oct', 'Monday 16 October at 14:05', 'Meeting, 26 Sep 14:05', 'Voice note 3 May']) {
        expect(weakTitle(weak), isTrue, reason: weak);
      }
      for (final strong in ['Standup', 'Kiln spring menu', 'May plans', 'Q1 goals 2026', 'Meeting with Sam']) {
        expect(weakTitle(strong), isFalse, reason: strong);
      }
    });
  });

  group('formatting only', () {
    test('the words kept in order pass; one changed, added or taken away does not', () {
      expect(formattingOnlyWhy('# A\n\n* one\n* two', '# A\n\n- one\n- two'), isNull);
      expect(formattingOnlyWhy('#\n\n### A\n\nWords here.', '## A\n\nWords here.'), isNull);
      expect(formattingOnlyWhy('Words here.', 'Words there.'), contains('“here” went'));
      expect(formattingOnlyWhy('Words here.', 'Words here and more.'), contains('added'));
      expect(formattingOnlyWhy('One. Two.', 'One.'), contains('“two” went'));
      expect(formattingOnlyWhy('Words', '   '), 'it came back empty');
    });

    test('an empty section’s heading may go, a heading over words may not lose them', () {
      expect(formattingOnlyWhy('# Plan\n\n## Empty\n\n## Done\n\nAll good.', '# Plan\n\n## Done\n\nAll good.'), isNull);
      expect(formattingOnlyWhy('# Plan\n\nKeep this.', '# Plan'), contains('“keep” went'));
    });

    test('a rewrite may change the words but not shrink to under half or grow past twice', () {
      final long = 'A fairly long note about the spring menu and its prices, with more words than forty.';
      expect(rewriteWhy(long, 'A note about the spring menu and its prices, said more plainly here.'), isNull);
      expect(rewriteWhy(long, 'Menu.'), contains('under half'));
      expect(rewriteWhy(long, long * 3), contains('over twice'));
    });

    test('an answer is taken out of a fence and past thinking', () {
      expect(unwrapBody('<think>hm</think>\n```markdown\n# A\n\nB\n```'), '# A\n\nB');
      expect(unwrapBody('# A'), '# A');
    });
  });

  group('tags and links', () {
    test('tags join the front matter list, each once in any case', () {
      expect(withTags('# A', ['work', 'q1']), '---\ntags: [work, q1]\n---\n# A');
      expect(withTags('---\ntags: [Work]\n---\n# A', ['work', 'q1']), '---\ntags: [Work, q1]\n---\n# A');
      expect(withTags('# A', const []), '# A');
    });

    test('links are a last line, leaving out any the note links already', () {
      expect(withRelated('# A\n\nWords.\n\n', ['B', 'C']), '# A\n\nWords.\n\nRelated: [[B]] · [[C]]\n');
      expect(withRelated('# A\n\nSee [[b]].', ['B']), '# A\n\nSee [[b]].');
    });
  });

  group('duplicates', () {
    ({String id, String title, String body, int updatedAt}) n(String id, String title, String body, [int at = 0]) => (id: id, title: title, body: '# $title\n\n$body', updatedAt: at);

    test('the same words, or the same title with a copy marked, are one note; notes that merely share a title are not', () {
      final groups = duplicateGroups([
        n('a', 'Standup', 'Shipped the reading view and the map, then fixed the sync for Sam.', 5),
        n('b', 'Standup (shared)', 'Shipped the reading view and the map, then fixed the sync for Sam. And the tiles.', 4),
        n('c', 'Standup', 'Planned the quarter with Ana; nothing shipped this week at all, sadly.', 3),
        n('d', 'Recipe', 'Two eggs, a cup of flour and a pinch of salt, whisked well.'),
        n('e', 'Pancakes', 'Two eggs, a cup of flour and a pinch of salt, whisked well.'),
        n('f', 'Idea', ''),
        n('g', 'Idea copy', ''),
      ]);
      // The same words under two titles: the longer body is kept (its title is longer here).
      expect(groups, unorderedEquals([
        ['a', 'b'],
        ['e', 'd'],
      ]));
    });

    test('the kept one is the one with no copy mark, then the longest', () {
      final groups = duplicateGroups([
        n('copy', 'Plan (copy)', 'The goals for the first quarter, agreed on Monday with everyone there. Extra line here.'),
        n('short', 'Plan', 'The goals for the first quarter, agreed on Monday with everyone there.'),
        n('long', 'Plan', 'The goals for the first quarter, agreed on Monday with everyone there. And more.'),
      ]);
      expect(groups.single.first, 'long');
      expect(groups.single, containsAll(['short', 'copy']));
      expect(sameTitleKey('Standup (shared) (2)'), 'standup');
      expect(sameTitleKey('Notes - Copy'), 'notes');
    });

    test('a merge keeps every line the kept note lacks, under the copy’s name, and nothing it has', () {
      final merged = mergedBody('# Standup\n\nShipped.\n\n- [ ] Fix sync', [
        (title: 'Standup (shared)', body: '# Standup (shared)\n\nShipped.\n\n- [ ] Fix sync\n- [ ] Ask Sam'),
        (title: 'Standup', body: '# Standup\n\nShipped.'),
      ]);
      expect(merged.added, 1);
      expect(merged.body, '# Standup\n\nShipped.\n\n- [ ] Fix sync\n\n## From “Standup (shared)”\n\n- [ ] Ask Sam\n');
      expect(mergedBody('# A\n\nB', [(title: 'A', body: '# A\n\nB')]), (body: '# A\n\nB', added: 0));
    });
  });
}
