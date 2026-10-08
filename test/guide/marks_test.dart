import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/capture/markdown.dart';
import 'package:ghost_md/capture/spoken/extras.dart';
import 'package:ghost_md/capture/spoken/inline.dart';
import 'package:ghost_md/guide/marks.dart';
import 'package:ghost_md/plugins/marks_plugin.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/settings/panes/marks.g.dart' as sheet;

/// `guide/marks.test.ts`, case for case, and one case of this port's own: the table agrees with the snapshot of it
/// the cheat sheet draws (lib/settings/panes/marks.g.dart).
///
/// The page's `BUILT_IN` is every plugin that ships; the only one with formats is the Marks plugin, which is the
/// registry these cases are run over (the four integrations are another piece's, and add no mark).
void main() {
  final formats = [for (final plugin in const [marksPlugin]) ...plugin.formats];
  late Registry registry;
  setUp(() => usePlugins(registry = createRegistry(const [marksPlugin], store: MemorySwitches())));
  tearDown(() => usePlugins(createRegistry(const [])));

  List<MarkRow> rows() => [for (final group in markGroups()) ...group.rows];
  MarkGroup? own() => markGroups().where((group) => group.title == 'Ghost.md’s own').firstOrNull;

  group('the guide’s table of marks', () {
    test('shows every mark the app writes, each with its own example', () {
      final symbols = [for (final row in rows()) row.symbol];
      for (final mark in ['**', '_', '~~', '`', '#', '##', '-', '1.', '- [ ]', '>', '---', '| |', '![ ]( )', '```', '[ ]( )']) {
        expect(symbols, contains(mark), reason: mark);
      }
      for (final row in rows()) {
        expect(row.typed, isNotEmpty, reason: row.name);
        expect(row.name, isNotEmpty, reason: row.typed);
        expect(looks, contains(row.looks), reason: row.name);
      }
      expect({for (final row in rows()) row.name}, hasLength(rows().length));
    });

    test('gives every mark an icon, which is what the cheat sheet and the Academy lead the row with', () {
      for (final row in rows()) {
        expect(row.icon, isNotEmpty, reason: row.name);
        // An icon is lucide's name for it here: one the drawn set has.
        expect(Lucide.all, contains(row.icon), reason: row.name);
      }
    });

    test('teaches the board: a name for an item, a pointer at it, and the fence itself', () {
      final symbols = [for (final row in rows()) row.symbol];
      for (final mark in ['^', '[[#^ ]]', '```board']) {
        expect(symbols, contains(mark), reason: mark);
      }
      final board = rows().where((row) => row.looks == 'board').firstOrNull;
      // The example is a working board: the fence, and the items its columns name (docs/BOARDS.md).
      expect(board?.typed, contains('```board'));
      expect(board?.typed, contains('^ship-page'));
      expect(rows().firstWhere((row) => row.looks == 'anchor').typed, contains('- [ ] Ship the pricing page ^ship-page'));
      expect(rows().firstWhere((row) => row.looks == 'itemRef').typed, contains('[[#^ask-sam]]'));
    });

    test('shows each mark a switched-on plugin adds, with the words it would say', () {
      // The plugin's own marks, then the two rows about what goes in brackets after one: a colour, and a note.
      expect(own()?.rows, hasLength(formats.length + 2));
      for (final format in formats) {
        final row = own()?.rows.where((r) => r.name == format.name).firstOrNull;
        expect(row, isNotNull, reason: format.name);
        expect(row?.symbol, format.delimiter);
        // The example ends in the mark around its words, so a person can copy it as it stands. Heat's has a line
        // above them first, for its haze to rise into.
        final last = row?.typed.split('\n').last ?? '';
        expect(last.startsWith(format.delimiter) && last.endsWith(format.delimiter), isTrue, reason: format.name);
        if (format.cue != null) expect(row?.say, contains(format.cue));
      }
    });

    test('says each mark with a cue, never a “Hey Ghost” command, since the recorder makes no mark from one', () {
      for (final row in rows()) {
        if (row.say != null) expect(row.say, isNot(matches(RegExp('hey ghost|glyph,', caseSensitive: false))), reason: row.name);
      }
    });

    test('draws a plugin’s look from the CSS the plugin declares', () {
      final highlight = own()?.rows.where((row) => row.name == 'Highlight').firstOrNull;
      expect(highlight?.looks, 'style');
      expect(highlight?.css, contains('background'));
      expect(own()?.rows.firstWhere((row) => row.name == 'Spoiler').looks, 'wisp');
    });
  });

  group('a note on a mark', () {
    test('is shown last, with the brackets in the example and the words the popover says', () {
      final row = own()?.rows.last;
      expect(row?.name, 'A note on a mark');
      expect(row?.looks, 'note');
      expect(row?.typed, '??four hundred??(Sam said 400)');
      expect(row?.note, 'Sam said 400');
    });
  });

  group('with the Marks plugin switched off', () {
    test('promises none of its marks, a hidden line included, which is the Spoiler’s', () {
      registry.setEnabled('marks', false);
      try {
        final groups = markGroups();
        expect(groups.where((group) => group.title == 'Ghost.md’s own'), isEmpty);
        final names = [for (final group in groups) ...group.rows.map((row) => row.name)];
        expect(names, isNot(contains('A hidden line')));
        // The app's own marks are all still there.
        expect(names, contains('A board'));
      } finally {
        registry.setEnabled('marks', true);
      }
      expect([for (final row in rows()) row.name], contains('A hidden line'));
    });
  });

  group('beside the cheat sheet’s snapshot', () {
    test('is the same table, row for row, with every plugin on', () {
      final live = markGroups();
      expect([for (final group in live) group.title], [for (final group in sheet.markGroups) group.title]);
      for (final (index, group) in live.indexed) {
        final kept = sheet.markGroups[index];
        expect(group.lead, kept.lead, reason: group.title);
        expect([for (final row in group.rows) row.name], [for (final row in kept.rows) row.name], reason: group.title);
        for (final (at, row) in group.rows.indexed) {
          final was = kept.rows[at];
          expect(row.symbol, was.symbol, reason: row.name);
          expect(row.words, was.words, reason: row.name);
          expect(row.looks, was.looks, reason: row.name);
          expect(row.icon, was.icon, reason: row.name);
          expect(row.say, was.say, reason: row.name);
          // The due date's example counts from the day it is made, so the snapshot's day is not today's.
          if (row.name != 'A due date') expect(row.typed, was.typed, reason: row.name);
        }
      }
      expect(markGroups(now: DateTime(2026, 10, 1, 9)).expand((group) => group.rows).firstWhere((row) => row.name == 'A due date').typed, '- [ ] Book the cabin 📅 2026-10-03');
    });
  });

  // What a person would say for each row with words to say, and what the recorder writes from it
  // (lib/capture/markdown.dart), a note's first sentence first. Every phrase a row's `say` quotes is in one of its
  // examples, and the words said are gone from what is written, so a phrase the recorder stopped reading fails here
  // rather than on the cheat sheet, and so does one that writes the wrong thing. A plugin's mark is said one way, its
  // cue around the words, and its example is made from the plugin's own cue and delimiter below.
  final said = <String, List<({List<String> said, String writes})>>{
    'Bold': [(said: ['The trip.', 'We leave on bold Friday at noon end bold.'], writes: '**Friday at noon**')],
    'Italic': [(said: ['The trip.', 'Just italic a quiet aside end italic.'], writes: '_a quiet aside_')],
    'Both': [(said: ['The trip.', 'Is it bold italic really now end bold italic.'], writes: '***really now***')],
    'Struck through': [(said: ['The trip.', 'We dropped strike the old plan end strike.'], writes: '~~the old plan~~')],
    'Code': [(said: ['The trip.', 'Run code npm run dev end code.'], writes: '`npm run dev`')],
    'A link': [(said: ['The trip.', 'Read link our site to attack dot fm end link.'], writes: '[our site](https://attack.fm)')],
    'A tag': [(said: ['The trip.', 'Ship the pricing page hashtag web.'], writes: 'Ship the pricing page #web')],
    'Title': [
      (said: ['Title: weekend trip.', 'We need a tent.'], writes: '# Weekend trip'),
      (said: ['Call this note weekend trip.', 'We need a tent.'], writes: '# Weekend trip'),
    ],
    'Heading': [
      (said: ['The trip.', 'Heading: the budget.'], writes: '## The budget'),
      (said: ['The trip.', 'New section: the budget.'], writes: '## The budget'),
    ],
    'Smaller heading': [(said: ['The trip.', 'Subheading: Friday.'], writes: '### Friday')],
    'A list': [(said: ['The trip.', 'Bullet point: oat milk.'], writes: '- Oat milk')],
    'In order': [
      (said: ['The trip.', 'Number one: unplug it.'], writes: '1. Unplug it'),
      (said: ['The trip.', 'First, unplug it.'], writes: '1. Unplug it'),
    ],
    'A to-do': [
      (said: ['The trip.', 'Remember to book the cabin.'], writes: '- [ ] Book the cabin'),
      (said: ['The trip.', 'Check box: book the cabin.'], writes: '- [ ] Book the cabin'),
    ],
    'Done': [(said: ['The trip.', 'Done task: call Sam.'], writes: '- [x] Call Sam')],
    'A due date': [(said: ['The trip.', 'Remember to book the cabin due Friday.'], writes: '- [ ] Book the cabin 📅 ')],
    'A priority': [
      (said: ['The trip.', 'Remember to fix the gate, high priority.'], writes: '- [ ] Fix the gate ⏫'),
      (said: ['The trip.', 'Remember to fix the gate, urgent.'], writes: '- [ ] Fix the gate ⏫'),
    ],
    'A person': [(said: ['The trip.', 'Remember to book the cabin for Sam.'], writes: '- [ ] Book the cabin @Sam')],
    'A choice': [(said: ['The trip.', 'Option: tent.', 'Picked option: cabin.'], writes: '- ( ) Tent\n- (x) Cabin')],
    'A counter': [(said: ['The trip.', 'Water counter three of eight.'], writes: 'Water [3/8]')],
    'A sum': [(said: ['The trip.', 'Calculate: four hundred plus one hundred twenty.'], writes: '= 400 + 120')],
    'A quote': [(said: ['The trip.', 'Quote: the plan is good.'], writes: '> The plan is good.')],
    'A hidden line': [(said: ['The trip.', 'Hidden line: the answer is forty-two.'], writes: '>| The answer is forty-two.')],
    'A dividing line': [(said: ['The trip.', 'That covers the morning.', 'Divider.', 'The afternoon is free.'], writes: '\n---\n')],
    'Another note': [(said: ['The trip.', 'The deposit is in note link The cabin trip end link.'], writes: '[[The cabin trip]]')],
    'A name for an item': [(said: ['The trip.', 'Check box: ship the pricing page anchor ship page end anchor.'], writes: '- [ ] Ship the pricing page ^ship-page')],
    'That item, from the words': [(said: ['The trip.', 'Remember item link ask Sam end link.'], writes: '[[#^ask-sam]]')],
    'The bookmark': [(said: ['The trip.', 'The deposit is four hundred bookmark this.'], writes: 'The deposit is four hundred. §§')],
    'A footnote': [(said: ['The trip.', 'The deposit is four hundred footnote Sam said so end footnote.'], writes: '[^1]: Sam said so.')],
    'Raised': [(said: ['The trip.', 'The 2 superscript nd end superscript of June.'], writes: '2^nd^')],
    'Lowered': [(said: ['The trip.', 'Water is H subscript 2 end subscript O.'], writes: 'H~2~O')],
    'A definition': [(said: ['The trip.', 'Define deposit as what you pay up front.'], writes: 'Deposit\n: What you pay up front')],
    'Maths': [(said: ['The trip.', 'When maths x squared plus y end maths holds.'], writes: '\$x^2 + y\$')],
    'An emoji': [(said: ['The trip.', 'Shipped emoji party popper.'], writes: 'Shipped :tada:')],
    'A block of code': [(said: ['The trip.', 'Code block in bash.', 'npm run dev.', 'End code block.'], writes: '```bash\nnpm run dev\n```')],
    'A callout': [
      (said: ['The trip.', 'Info box: the gate code is four two one.'], writes: '> [!NOTE]\n> The gate code is four two one.'),
      (said: ['The trip.', 'Warning callout: the road floods.'], writes: '> [!WARNING]\n> The road floods.'),
    ],
    'A note on a mark': [(said: ['The trip.', 'The deposit is unsure four hundred end unsure, note Sam said 400, end note.'], writes: '??four hundred??(Sam said 400)')],
    for (final format in formats)
      if (format.cue != null) format.name: [(said: ['The trip.', 'Keep ${format.cue} the cabin key end ${format.cue}.'], writes: '${format.delimiter}the cabin key${format.delimiter}')],
  };

  /// The phrases a row's `say` quotes, each without the "…" that stands for the words and the colon before them.
  List<String> phrasesOf(String say) => [
    for (final found in RegExp('“([^”]+)”').allMatches(say)) found.group(1)!.replaceAll('…', ' ').trim().replaceFirst(RegExp(r'[:,]$'), '').trim(),
  ];

  /// The same shape the capture tests use: a second per phrase, with a breath between.
  String written(List<String> said) => renderNote([for (final (index, text) in said.indexed) Segment(text: text, startMs: index * 1300, endMs: index * 1300 + 1000)]).markdown;

  group('what the cheat sheet says to say', () {
    tearDown(() {
      setSpokenFormats(const []);
      setLinkTitles(const []);
    });

    test('writes each row’s mark when said to the recorder, and leaves none of the words said behind', () {
      // As the recorder sets them when it opens: the switched-on plugins' cues, and the library's titles for a spoken
      // link to take the note's own spelling.
      setSpokenFormats([
        for (final format in formats)
          if (format.cue != null) SpokenFormat(word: format.cue!, delimiter: format.delimiter),
      ]);
      setLinkTitles(['The cabin trip']);
      final sayable = rows().where((row) => row.say != null).toList();
      expect(said.keys.toList()..sort(), [for (final row in sayable) row.name]..sort());
      for (final row in sayable) {
        final examples = said[row.name]!;
        final phrases = phrasesOf(row.say!);
        for (final phrase in phrases) {
          expect(examples.any((example) => example.said.join(' ').toLowerCase().contains(phrase.toLowerCase())), isTrue, reason: '${row.name}: “$phrase” is said in an example');
        }
        for (final example in examples) {
          final markdown = written(example.said);
          expect(markdown, contains(example.writes), reason: row.name);
          for (final phrase in phrases) {
            if (example.said.join(' ').toLowerCase().contains(phrase.toLowerCase())) expect(markdown.toLowerCase(), isNot(contains(phrase.toLowerCase())), reason: '${row.name}: “$phrase”');
          }
        }
      }
    });
  });
}
