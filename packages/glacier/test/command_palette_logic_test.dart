import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/src/logic/command_palette.dart';

/// The cases of packages/logic/test/command-palette.test.ts, one for one and under the same names, then the cases
/// only the Dart port can get wrong.
void main() {
  const commands = <CommandDescriptor>[
    CommandDescriptor(id: 'new', label: 'New file', group: 'File', shortcut: '⌘N'),
    CommandDescriptor(id: 'open', label: 'Open…', group: 'File', keywords: 'load import'),
    CommandDescriptor(id: 'save', label: 'Save', group: 'File', disabled: true),
    CommandDescriptor(id: 'theme', label: 'Toggle theme', group: 'View', keywords: 'dark light appearance'),
    CommandDescriptor(id: 'zen', label: 'Zen mode', group: 'View'),
  ];

  List<String> idsOf(List<CommandMatch> matches) => [for (final m in matches) m.item.id];

  group('matchCommands', () {
    test('returns everything for an empty query, in the caller order', () {
      expect(idsOf(matchCommands(commands, '')), ['new', 'open', 'save', 'theme', 'zen']);
    });

    test('treats a whitespace-only query as empty', () {
      expect(matchCommands(commands, '   '), hasLength(commands.length));
    });

    test('matches the label case-insensitively', () {
      expect(idsOf(matchCommands(commands, 'ZEN')), ['zen']);
    });

    test('matches the group as well as the label', () {
      expect(idsOf(matchCommands(commands, 'view')), ['theme', 'zen']);
    });

    test('matches keywords and reports which one hit', () {
      final match = matchCommands(commands, 'dark').first;
      expect(match.item.id, 'theme');
      expect(match.matchedKeyword, 'dark');
    });

    test('surfaces the tightest keyword run when several terms hit only keywords', () {
      const items = [
        CommandDescriptor(id: 'song', label: 'A Song', keywords: 'artist album hey, girl you know the rest of the lyric goes here'),
      ];
      final match = matchCommands(items, 'girl you know').first;
      expect(match.matchedKeyword, '…girl you know…');
    });

    test('leaves matchedKeyword unset when the label itself matched', () {
      final match = matchCommands(commands, 'toggle').first;
      expect(match.item.id, 'theme');
      expect(match.matchedKeyword, isNull);
    });

    test('stamps flat indices that are contiguous over the survivors', () {
      final matches = matchCommands(commands, 'view');
      expect([for (final m in matches) m.index], [0, 1]);
    });

    test('returns nothing when the query matches nothing', () {
      expect(matchCommands(commands, 'xyzzy'), isEmpty);
    });

    test('keeps disabled commands in the results', () {
      expect(idsOf(matchCommands(commands, 'save')), ['save']);
    });
  });

  group('groupCommands', () {
    test('collects adjacent runs under their heading', () {
      final groups = groupCommands(matchCommands(commands, ''));
      expect([for (final g in groups) g.group], ['File', 'View']);
      expect(idsOf(groups[0].matches), ['new', 'open', 'save']);
    });

    test('preserves the caller order rather than gathering groups globally', () {
      const interleaved = [
        CommandDescriptor(id: 'a', label: 'A', group: 'One'),
        CommandDescriptor(id: 'b', label: 'B', group: 'Two'),
        CommandDescriptor(id: 'c', label: 'C', group: 'One'),
      ];
      final groups = groupCommands(matchCommands(interleaved, ''));
      expect([for (final g in groups) g.group], ['One', 'Two', 'One']);
    });

    test('keeps the flat index so grouped rendering and keyboard order agree', () {
      final groups = groupCommands(matchCommands(commands, ''));
      expect([for (final g in groups) ...g.matches.map((m) => m.index)], [0, 1, 2, 3, 4]);
    });

    test('files ungrouped commands under no heading', () {
      final groups = groupCommands(matchCommands(const [CommandDescriptor(id: 'a', label: 'A')], ''));
      expect(groups, [
        CommandGroup<CommandDescriptor>(matches: [const CommandMatch(item: CommandDescriptor(id: 'a', label: 'A'), index: 0)]),
      ]);
      expect(groups.single.group, isNull);
    });

    test('returns nothing for no matches', () {
      expect(groupCommands(<CommandMatch<CommandDescriptor>>[]), isEmpty);
    });
  });

  group('moveCommandCursor', () {
    final all = matchCommands(commands, '');

    test('steps forward', () => expect(moveCommandCursor(all, 0, 1), 1));

    test('skips a disabled row', () {
      // index 2 is `save`, disabled: down from `open` lands on `theme`.
      expect(moveCommandCursor(all, 1, 1), 3);
    });

    test('skips a disabled row going backwards too', () => expect(moveCommandCursor(all, 3, -1), 1));

    test('wraps past the end', () => expect(moveCommandCursor(all, 4, 1), 0));

    test('wraps past the start', () => expect(moveCommandCursor(all, 0, -1), 4));

    test('reports no cursor for an empty list', () {
      expect(moveCommandCursor(<CommandMatch<CommandDescriptor>>[], 0, 1), -1);
    });

    test('reports no cursor when every row is disabled', () {
      final none = matchCommands(const [CommandDescriptor(id: 'a', label: 'A', disabled: true)], '');
      expect(moveCommandCursor(none, 0, 1), -1);
    });

    test('finds the one runnable row from anywhere', () {
      final mostly = matchCommands(const [
        CommandDescriptor(id: 'a', label: 'A', disabled: true),
        CommandDescriptor(id: 'b', label: 'B', disabled: true),
        CommandDescriptor(id: 'c', label: 'C'),
      ], '');
      expect(moveCommandCursor(mostly, 0, 1), 2);
    });
  });

  group('firstCommandCursor', () {
    test('lands on the top row', () => expect(firstCommandCursor(matchCommands(commands, '')), 0));

    test('skips a disabled first row', () {
      final matches = matchCommands(const [CommandDescriptor(id: 'a', label: 'A', disabled: true), CommandDescriptor(id: 'b', label: 'B')], '');
      expect(firstCommandCursor(matches), 1);
    });

    test('reports no cursor for an empty list', () {
      expect(firstCommandCursor(<CommandMatch<CommandDescriptor>>[]), -1);
    });
  });

  group('isCommandShortcut', () {
    test('accepts Cmd+K', () => expect(isCommandShortcut(key: 'k', metaKey: true), isTrue));
    test('accepts Ctrl+K', () => expect(isCommandShortcut(key: 'k', ctrlKey: true), isTrue));
    test('accepts an uppercase K, as a held Shift reports it', () => expect(isCommandShortcut(key: 'K', metaKey: true), isTrue));
    test('rejects a bare K', () => expect(isCommandShortcut(key: 'k'), isFalse));
    test('rejects another modified key', () => expect(isCommandShortcut(key: 'j', metaKey: true), isFalse));
  });

  group('matchCommands - keyword and multi-term search', () {
    const kit = [
      CommandDescriptor(id: 'slider', label: 'Slider', group: 'Atoms', keywords: 'form input range value drag'),
      CommandDescriptor(id: 'seekbar', label: 'Seek Bar', group: 'Atoms', keywords: 'audio video media player scrub sound'),
      CommandDescriptor(id: 'playercard', label: 'Player Card', group: 'Molecules', keywords: 'audio music media player track'),
      CommandDescriptor(id: 'modal', label: 'Modal', group: 'Organisms', keywords: 'overlay popup dialog window'),
      CommandDescriptor(id: 'progress', label: 'Progress Bar', group: 'Atoms', keywords: 'feedback loading percent'),
    ];
    List<String> ids(String query) => idsOf(matchCommands(kit, query));

    test('finds a component by a concept it never names', () => expect(ids('audio'), ['seekbar', 'playercard']));

    test('finds a component by a synonym of its own name', () => expect(ids('popup'), ['modal']));

    test('ANDs the terms, so a second word narrows rather than widens', () {
      expect(ids('audio'), hasLength(2));
      expect(ids('audio music'), ['playercard']);
    });

    test('matches terms across different fields', () => expect(ids('media card'), ['playercard']));

    test('drops an item when any single term misses', () => expect(ids('audio nonsense'), isEmpty));

    test('ignores extra whitespace between terms', () => expect(ids('  audio   music  '), ['playercard']));

    test('ranks a label hit above a keyword hit', () => expect(ids('bar'), ['seekbar', 'progress']));

    test('ranks a label prefix above a mid-label match', () {
      const items = [
        CommandDescriptor(id: 'mid', label: 'Rich Text Editor'),
        CommandDescriptor(id: 'prefix', label: 'Text Area'),
      ];
      expect(idsOf(matchCommands(items, 'text')), ['prefix', 'mid']);
    });

    test('ranks by the worst term, so a whole-query match wins', () {
      const items = [
        CommandDescriptor(id: 'half', label: 'Audio', keywords: 'zzz'),
        CommandDescriptor(id: 'whole', label: 'Audio Player', keywords: ''),
      ];
      expect(idsOf(matchCommands(items, 'audio player')), ['whole']);
    });

    test('keeps the caller’s order within a tier', () {
      const items = [
        CommandDescriptor(id: 'first', label: 'One', keywords: 'alpha'),
        CommandDescriptor(id: 'second', label: 'Two', keywords: 'alpha'),
        CommandDescriptor(id: 'third', label: 'Three', keywords: 'alpha'),
      ];
      expect(idsOf(matchCommands(items, 'alpha')), ['first', 'second', 'third']);
    });

    test('reports the keyword that earned the hit, for the row to explain itself', () {
      expect(matchCommands(kit, 'audio').first.matchedKeyword, 'audio');
    });

    test('names no keyword when the label already explains the hit', () {
      expect(matchCommands(kit, 'modal').first.matchedKeyword, isNull);
    });

    test('renumbers indices to the ranked order, so the cursor follows the eye', () {
      expect([for (final m in matchCommands(kit, 'bar')) m.index], [0, 1]);
    });

    test('treats a regex-special query as literal text, not a pattern', () {
      const items = [CommandDescriptor(id: 'a', label: 'C++ Guide'), CommandDescriptor(id: 'b', label: 'Anything')];
      expect(idsOf(matchCommands(items, 'c++')), ['a']);
      expect(() => matchCommands(items, '('), returnsNormally);
    });

    test('still returns everything, in the given order, for an empty query', () {
      expect(ids(''), [for (final k in kit) k.id]);
      expect(ids('   '), [for (final k in kit) k.id]);
    });
  });

  group('highlightSegments', () {
    List<String> marked(String text, String query) => [
          for (final s in highlightSegments(text, query))
            if (s.match) s.text,
        ];

    test('returns the whole string unmarked for an empty query', () {
      expect(highlightSegments('Rich Text Editor', ''), [const CommandSegment(text: 'Rich Text Editor', match: false)]);
    });

    test('returns the whole string unmarked when nothing lands', () {
      expect(highlightSegments('Button', 'zzz'), [const CommandSegment(text: 'Button', match: false)]);
    });

    test('marks a single term', () => expect(marked('Rich Text Editor', 'rich'), ['Rich']));

    test('marks each term of a multi-term query', () => expect(marked('Rich Text Editor', 'rich editor'), ['Rich', 'Editor']));

    test('is case-insensitive but preserves the original casing', () => expect(marked('Rich Text Editor', 'RICH'), ['Rich']));

    test('marks every occurrence, not just the first', () => expect(marked('text and more text', 'text'), ['text', 'text']));

    test('merges overlapping hits into one run', () {
      final segments = highlightSegments('textra', 'text extra');
      expect(segments.where((s) => s.match), hasLength(1));
    });

    test('merges touching runs so no zero-width gap appears between them', () => expect(marked('abcd', 'ab cd'), ['abcd']));

    test('reassembles to exactly the original string', () {
      const text = 'Rich Text Editor';
      for (final q in ['', 'rich', 'rich editor', 'zzz', 'e']) {
        expect(highlightSegments(text, q).map((s) => s.text).join(), text);
      }
    });

    test('handles an empty label', () {
      expect(highlightSegments('', 'rich'), [const CommandSegment(text: '', match: false)]);
    });

    test('marks a leading hit without emitting an empty first segment', () {
      expect(highlightSegments('Button', 'butt').first, const CommandSegment(text: 'Butt', match: true));
    });
  });

  // What reading the TypeScript says and its own tests do not.
  group('the port, beyond the kit’s own cases', () {
    test('a term at a word start inside the label outranks one in the middle of a word', () {
      const items = [
        CommandDescriptor(id: 'inside', label: 'Toolbar'), // tier 2: "bar" inside a word
        CommandDescriptor(id: 'word', label: 'Seek Bar'), // tier 1: "bar" starts a word
        CommandDescriptor(id: 'prefix', label: 'Barcode'), // tier 0: the label starts with it
        CommandDescriptor(id: 'keyword', label: 'Slider', keywords: 'bar'), // tier 3
      ];
      expect(idsOf(matchCommands(items, 'bar')), ['prefix', 'word', 'inside', 'keyword']);
    });

    test('a group hit is the keyword tier, but names no keyword', () {
      final matches = matchCommands(commands, 'file');
      // "New file" has it in the label (a word start); the other two only through their group.
      expect(idsOf(matches), ['new', 'open', 'save']);
      expect([for (final m in matches) m.matchedKeyword], [null, null, null]);
    });

    test('no keyword is named unless every term landed on group or keywords alone', () {
      const items = [CommandDescriptor(id: 'a', label: 'Player Card', keywords: 'audio music')];
      expect(matchCommands(items, 'card audio').single.matchedKeyword, isNull);
      expect(matchCommands(items, 'music audio').single.matchedKeyword, 'audio music');
    });

    test('a keyword snippet keeps the words as written and clips to twelve', () {
      const items = [
        CommandDescriptor(id: 'a', label: 'Song', keywords: 'Zero One two three four five six seven eight nine ten eleven twelve thirteen fourteen'),
      ];
      expect(matchCommands(items, 'ONE').single.matchedKeyword, 'One');
      // The tightest run holding "one" and "fourteen" is fourteen words; twelve are shown, with both ends marked.
      expect(
        matchCommands(items, 'one fourteen').single.matchedKeyword,
        '…One two three four five six seven eight nine ten eleven twelve…',
      );
      expect(matchCommands(items, 'zero one').single.matchedKeyword, 'Zero One…');
    });

    test('a term repeated in the query names no keyword run, as the original has it', () {
      // `present` holds the term twice and the window can only ever cover it once.
      const items = [CommandDescriptor(id: 'a', label: 'Song', keywords: 'alpha beta')];
      final match = matchCommands(items, 'alpha alpha').single;
      expect(match.matchedKeyword, isNull);
    });

    test('a word boundary is an ASCII one, as JavaScript’s is', () {
      const items = [CommandDescriptor(id: 'inside', label: 'foobar'), CommandDescriptor(id: 'accent', label: 'ébar')];
      // `\b` knows only A-Z, a-z, 0-9 and _: "é" is not a word character to it, so "bar" starts a word after one
      // and the accented label is lifted over the plain one.
      expect(idsOf(matchCommands(items, 'bar')), ['accent', 'inside']);
    });

    test('the cursor moves from no cursor at all', () {
      final all = matchCommands(commands, '');
      expect(moveCommandCursor(all, -1, 1), 0);
      expect(moveCommandCursor(all, -1, -1), 3);
      // End, as the palette asks for it: one step back from the top.
      expect(moveCommandCursor(all, 0, -1), 4);
    });

    test('a move of any size is one step in its direction', () {
      final all = matchCommands(commands, '');
      expect(moveCommandCursor(all, 0, 5), 1);
      expect(moveCommandCursor(all, 1, -5), 0);
      expect(moveCommandCursor(all, 0, 0), 1);
    });

    test('a label whose lower case is longer than itself is sliced, not thrown at', () {
      // JavaScript lowers a dotted capital I to two code units, so there the haystack outgrows the label and `slice`
      // clamps what falls off the end (node answers "İ" marked, "İ" unmarked, "" marked). Dart lowers it to one, so
      // here the ranges fit; either way nothing is thrown and nothing of the label is lost.
      for (final (text, query) in [('İİ', 'i'), ('aİ', '̇'), ('İstanbul', 'stan')]) {
        expect(() => highlightSegments(text, query), returnsNormally);
        expect(highlightSegments(text, query).map((s) => s.text).join(), text);
      }
    });

    test('descriptors are equal by what they say', () {
      expect(const CommandDescriptor(id: 'a', label: 'A'), const CommandDescriptor(id: 'a', label: 'A'));
      expect(const CommandDescriptor(id: 'a', label: 'A'), isNot(const CommandDescriptor(id: 'a', label: 'A', disabled: true)));
      expect(const CommandDescriptor(id: 'a', label: 'A'), isNot(const CommandDescriptor(id: 'a', label: 'A', band: 1)));
      expect(const CommandDescriptor(id: 'a', label: 'A'), isNot(const CommandDescriptor(id: 'a', label: 'A', detail: 'Added')));
    });

    // The port's own band (Matt, 2026-10-29: "Add the ability to search settings and plugins from the command search"):
    // what is not a command comes after every command, however well it was hit, and the tiers order each band.
    test('offers a later band after every match of an earlier one, each band tiered', () {
      const banded = <CommandDescriptor>[
        CommandDescriptor(id: 'page', label: 'Dark page', group: 'Settings', band: 1),
        CommandDescriptor(id: 'theme', label: 'Toggle theme', group: 'View', keywords: 'dark light'),
        CommandDescriptor(id: 'plugin', label: 'Darkroom', group: 'Plugins', band: 2),
        CommandDescriptor(id: 'row', label: 'Page', group: 'Settings', keywords: 'dark', band: 1),
        CommandDescriptor(id: 'dim', label: 'Darken', group: 'View'),
      ];
      // Band 0 first (Darken's label prefix before the theme's keyword), then 1 (the label before the keyword), then 2.
      expect(idsOf(matchCommands(banded, 'dark')), ['dim', 'theme', 'page', 'row', 'plugin']);
      expect([for (final group in groupCommands(matchCommands(banded, 'dark'))) group.group], ['View', 'Settings', 'Plugins']);
      // With nothing typed every row is offered, the bands still in order.
      expect(idsOf(matchCommands(banded, '')), ['theme', 'dim', 'page', 'row', 'plugin']);
    });
  });
}
