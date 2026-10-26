/// Every mark a note can carry, as a table: what you type, what it does, and a line showing it at work. A port of
/// `src/app/guide/marks.ts` (`MarkRow`, `MarkGroup`, `Looks`, `markGroups`), for marks_table.dart and whatever else
/// shows the marks.
///
/// The rows are the app's own Markdown, then the marks the plugins add, read from the registry
/// (lib/plugins/registry.dart `plugins.formats()`) so a plugin switched off is not promised and a new one shows up
/// here by itself. Every row carries its own icon, and the example is [MarkRow.typed]: the pages draw it with the
/// note's own editor (mark_example.dart), so what is shown is what the app does with those characters.
///
/// What differs:
/// - An icon is lucide's own name for it (`'heading-1'`), looked up in lib/art/lucide.g.dart `Lucide.all`, where the
///   page holds the component; a plugin's mark already names its icon that way (lib/plugins/marks.dart).
/// - `Looks` is a string, one of [looks], where the page has a union of them.
/// - The due date's example counts from [markGroups]' `now`, the clock unless a caller says; the page counts once,
///   from the moment the module loaded.
/// - **This overlaps lib/settings/panes/marks.g.dart**, a snapshot of this table read off the running page with
///   every plugin on, which the cheat sheet (lib/settings/panes/cheat_sheet.dart) draws. The names are the same on
///   purpose (`MarkRow`, `MarkGroup`; the snapshot's `markGroups` is a list and this one a function), so the sheet
///   can take this file in the snapshot's place and follow the switches; test/guide/marks_test.dart holds the two
///   equal meanwhile.
library;

import '../core/days.dart';
import '../plugins/marks.dart';
import '../plugins/registry.dart';

/// The kinds of mark a row can be (`Looks`).
const Set<String> looks = <String>{
  'plain', 'h1', 'h2', 'h3', 'bold', 'italic', 'both', 'struck', 'code', 'link', 'quote', 'bullet', 'number', 'todo', 'done', 'rule', 'table', 'picture', 'fence', 'wisp', //
  'effect', 'style', 'note', 'tint', 'sup', 'sub', 'callout', 'wiki', 'foot', 'comment', 'definition', 'maths', 'emoji', 'anchor', 'board', 'diagram', 'itemRef', 'tag', //
  'counter', 'sum', 'blank', 'progress', 'choice', 'spoilerLine', 'bookmark', 'place', 'ticket', 'field', 'query',
};

/// One mark (`MarkRow`).
class MarkRow {
  const MarkRow({required this.symbol, required this.name, required this.typed, required this.words, required this.looks, required this.icon, this.css, this.say, this.note, this.needs});

  /// The mark itself, as a person would type it: `**`, `- [ ]`.
  final String symbol;
  final String name;

  /// What to type, whole: the example's Markdown, drawn by the note's own editor.
  final String typed;

  /// The words that carry the mark in the example, for anything that needs them without the marks.
  final String words;

  /// Which kind of mark it is, one of [looks].
  final String looks;

  /// The mark's icon, shown beside its name: lucide's name for it.
  final String icon;

  /// How it is drawn, where a page needs the plugin's own CSS.
  final String? css;

  /// Said while recording, where there is a way to say it: a cue (lib/capture/markdown.dart), never a spoken
  /// command, since a command puts words into a note or makes a list, and none makes a mark.
  /// test/guide/marks_test.dart says each phrase to the recorder and holds it to the mark it writes.
  final String? say;

  /// What the popover says, for the row that shows a note on a mark.
  final String? note;

  /// The plugin mark this row belongs to, by name, for one of the app's own rows that only works while that mark
  /// is switched on: a hidden line is the Spoiler's, and with it off the line is a quote.
  final String? needs;
}

/// A group of marks, with the line under its title (`MarkGroup`).
class MarkGroup {
  const MarkGroup({required this.title, required this.lead, required this.rows});
  final String title;
  final String lead;
  final List<MarkRow> rows;
}

/// The marks the app itself knows, in the order the page shows them (`OWN`). [soon] is the due date a to-do's
/// example carries: two days on, so the chip it draws says a day to come rather than going red the week after the
/// example was written (docs/DESIGN.md §158).
List<MarkGroup> _own(String soon) => <MarkGroup>[
  MarkGroup(
    title: 'Words',
    lead: 'Around the words they mark, anywhere in a line.',
    rows: <MarkRow>[
      MarkRow(symbol: '**', name: 'Bold', typed: '**Friday at noon**', words: 'Friday at noon', looks: 'bold', icon: 'bold', say: '“bold” … “end bold”'),
      MarkRow(symbol: '_', name: 'Italic', typed: '_a quiet aside_', words: 'a quiet aside', looks: 'italic', icon: 'italic', say: '“italic” … “end italic”'),
      MarkRow(symbol: '***', name: 'Both', typed: '***really now***', words: 'really now', looks: 'both', icon: 'baseline', say: '“bold italic” … “end bold italic”'),
      MarkRow(symbol: '~~', name: 'Struck through', typed: '~~the old plan~~', words: 'the old plan', looks: 'struck', icon: 'strikethrough', say: '“strike” … “end strike”'),
      MarkRow(symbol: '`', name: 'Code', typed: '`npm run dev`', words: 'npm run dev', looks: 'code', icon: 'code', say: '“code” … “end code”'),
      MarkRow(symbol: '[ ]( )', name: 'A link', typed: '[Ghost.md](https://attack.fm/glyph)', words: 'Ghost.md', looks: 'link', icon: 'link', say: '“link our site to attack dot fm end link”'),
      MarkRow(symbol: '#', name: 'A tag', typed: '- [ ] Ship the pricing page #web #launch', words: '#web', looks: 'tag', icon: 'hash', say: '“hashtag web”'),
    ],
 ),
  MarkGroup(
    title: 'Lines',
    lead: 'At the start of a line, with a space after them.',
    rows: <MarkRow>[
      MarkRow(symbol: '#', name: 'Title', typed: '# Weekend trip', words: 'Weekend trip', looks: 'h1', icon: 'heading-1', say: '“title” or “call this note”'),
      MarkRow(symbol: '##', name: 'Heading', typed: '## The budget', words: 'The budget', looks: 'h2', icon: 'heading-2', say: '“heading” or “new section”'),
      MarkRow(symbol: '###', name: 'Smaller heading', typed: '### Friday', words: 'Friday', looks: 'h3', icon: 'heading-3', say: '“subheading”'),
      MarkRow(symbol: '-', name: 'A list', typed: '- Oat milk\n- Rye bread', words: 'Oat milk', looks: 'bullet', icon: 'list', say: '“bullet point”'),
      MarkRow(symbol: '1.', name: 'In order', typed: '1. Unplug it\n2. Wait a minute', words: 'Unplug it', looks: 'number', icon: 'list-ordered', say: '“number one”, “first”'),
      MarkRow(symbol: '- [ ]', name: 'A to-do', typed: '- [ ] Book the cabin', words: 'Book the cabin', looks: 'todo', icon: 'list-todo', say: '“remember to”, “check box”'),
      MarkRow(symbol: '- [x]', name: 'Done', typed: '- [x] Call Sam', words: 'Call Sam', looks: 'done', icon: 'square-check-big', say: '“done task: …”'),
      // A to-do's fields, in Obsidian Tasks' own signs and Dataview's brackets, drawn as chips (core/taskFields.ts,
      // editor/taskFields.ts, docs/DESIGN.md §158).
      MarkRow(symbol: '📅', name: 'A due date', typed: '- [ ] Book the cabin 📅 $soon', words: 'Book the cabin', looks: 'field', icon: 'calendar-days', say: '“due Friday”'),
      MarkRow(symbol: '⏫', name: 'A priority', typed: '- [ ] Fix the gate ⏫', words: 'Fix the gate', looks: 'field', icon: 'chevrons-up', say: '“high priority”, “urgent”'),
      MarkRow(symbol: '@', name: 'A person', typed: '- [ ] Book the cabin @sam', words: 'sam', looks: 'field', icon: 'at-sign', say: '“for Sam”'),
      MarkRow(symbol: '[ :: ]', name: 'A field by name', typed: '- [ ] Ask about the budget [effort:: 3]', words: '3', looks: 'field', icon: 'tag'),
      MarkRow(symbol: '- ( )', name: 'A choice', typed: 'Where do we stay?\n- ( ) Tent\n- (x) Cabin', words: 'Cabin', looks: 'choice', icon: 'circle-dot', say: '“option: tent”, “picked option: cabin”'),
      MarkRow(symbol: '[ / ]', name: 'A counter', typed: '- Water [3/8]', words: '3/8', looks: 'counter', icon: 'gauge', say: '“counter three of eight”'),
      MarkRow(symbol: '=', name: 'A sum', typed: '= \$450 + 120 * 2', words: '\$690', looks: 'sum', icon: 'calculator', say: '“calculate: four hundred plus one hundred twenty”'),
      // A question the AI answers where it stands (docs/DESIGN.md §145). No `say`: a blank has no spoken cue.
      MarkRow(symbol: '{?}', name: 'A blank', typed: 'Cheapest day to fly: {?which day}', words: 'which day', looks: 'blank', icon: 'square-dashed'),
      MarkRow(
        symbol: '>',
        name: 'A quote',
        typed: '> The deposit comes back in full.',
        words: 'The deposit comes back in full.',
        looks: 'quote',
        icon: 'message-square-quote',
        say: '“quote”',
     ),
      MarkRow(
        symbol: '>|',
        name: 'A hidden line',
        typed: '>| The answer is forty-two.',
        words: 'The answer is forty-two.',
        looks: 'spoilerLine',
        icon: 'eye-off',
        say: '“hidden line: …”',
        needs: 'Spoiler',
     ),
      MarkRow(
        symbol: '#',
        name: 'Progress',
        typed: '## Packing\n- [x] Tent\n- [ ] Stove',
        words: '1 of 2',
        looks: 'progress',
        icon: 'list-checks',
     ),
      MarkRow(symbol: '---', name: 'A dividing line', typed: '---', words: '', looks: 'rule', icon: 'minus', say: '“divider”'),
    ],
 ),
  MarkGroup(
    title: 'Pointing somewhere',
    lead: 'At another note, at a line of this one, at a place on a map, or at the small print underneath.',
    rows: <MarkRow>[
      MarkRow(symbol: '[[ ]]', name: 'Another note', typed: 'the deposit is in [[The cabin trip]]', words: 'The cabin trip', looks: 'wiki', icon: 'square-arrow-out-up-right', say: '“note link The cabin trip end link”'),
      MarkRow(
        symbol: '^',
        name: 'A name for an item',
        typed: '- [ ] Ship the pricing page ^ship-page\n- Ask Sam about the copy ^ask-sam',
        words: 'ship-page',
        looks: 'anchor',
        icon: 'anchor',
        say: '“anchor ship page end anchor”',
     ),
      MarkRow(
        symbol: '[[#^ ]]',
        name: 'That item, from the words',
        typed: 'the page is waiting on [[#^ask-sam]]\n\n- Ask Sam about the copy ^ask-sam',
        words: 'ask-sam',
        looks: 'itemRef',
        icon: 'link',
        say: '“item link ask Sam end link”',
     ),
      MarkRow(symbol: '§§', name: 'The bookmark', typed: 'the deposit is four hundred §§', words: 'the deposit is four hundred', looks: 'bookmark', icon: 'bookmark', note: 'The note opens here. Tap the bookmark button to move it to the line you are on.', say: '“… bookmark this”'),
      // A place the + beside the line adds (core/placeRefs.ts): alone on its line, it reads as its name, with its map under it.
      MarkRow(symbol: '[ ](geo: )', name: 'A place', typed: '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)', words: 'Cais do Sodré, Lisbon', looks: 'place', icon: 'map-pin'),
      MarkRow(symbol: '[^ ]', name: 'A footnote', typed: 'four hundred[^sam]\n\n[^sam]: Sam said so.', words: 'four hundred', looks: 'foot', icon: 'asterisk', note: 'Sam said so.', say: '“footnote Sam said so end footnote”'),
      // A comment (core/comments/format.ts; docs/SHARED.md, S8): the anchor after the words, the thread in the fence at
      // the end. Usually made with Comment rather than typed; written out here so it can be read anywhere.
      MarkRow(
        symbol: '[^c1]',
        name: 'A comment',
        typed: 'Call the band[^c1]\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nWhich band?\n  resolved sam 2026-10-04T19:06:02Z\n```',
        words: 'Call the band',
        looks: 'comment',
        icon: 'message-square',
     ),
    ],
 ),
  MarkGroup(
    title: 'Raised and lowered',
    lead: 'Around one part of a word, the way the rest of markdown writes them.',
    rows: <MarkRow>[
      MarkRow(symbol: '^ ^', name: 'Raised', typed: 'the 2^nd^ of June', words: 'nd', looks: 'sup', icon: 'superscript', say: '“superscript” … “end superscript”'),
      MarkRow(symbol: '~ ~', name: 'Lowered', typed: 'H~2~O', words: '2', looks: 'sub', icon: 'subscript', say: '“subscript” … “end subscript”'),
    ],
 ),
  MarkGroup(
    title: 'Blocks',
    lead: 'A few lines that work together.',
    rows: <MarkRow>[
      MarkRow(symbol: ':', name: 'A definition', typed: 'Deposit\n: what you pay up front', words: 'what you pay up front', looks: 'definition', icon: 'text-align-start', note: 'Deposit', say: '“define deposit as what you pay up front”'),
      MarkRow(symbol: '\$', name: 'Maths', typed: 'when \$x^2 + y\$ holds', words: '\$x^2 + y\$', looks: 'maths', icon: 'sigma', say: '“maths x squared plus y end maths”'),
      MarkRow(symbol: ': :', name: 'An emoji', typed: 'shipped :tada:', words: '🎉', looks: 'emoji', icon: 'sticker', say: '“emoji party popper”'),
      MarkRow(
        symbol: '| |',
        name: 'A table',
        typed: '| What | Packed |\n| --- | --- |\n| Tent | Yes |',
        words: '',
        looks: 'table',
        icon: 'table',
     ),
      MarkRow(symbol: '![ ]( )', name: 'A picture', typed: '![A cassette](image/sample-tape.svg)', words: 'A cassette', looks: 'picture', icon: 'image'),
      // Written by the +, never typed: a still of the film's first frame, linked to the film (core/videoRefs.ts). It is drawn here as its still.
      MarkRow(symbol: '[![ ]( )]( )', name: 'A video', typed: '[![video 0:12](image/sample-tape.svg)](video/a1b2c3.mp4)', words: 'video 0:12', looks: 'picture', icon: 'film'),
      MarkRow(symbol: '```', name: 'A block of code', typed: '```js\nconst note = "hello";\n```', words: 'const note = "hello";', looks: 'fence', icon: 'square-code', say: '“code block in bash” … “end code block”'),
      MarkRow(
        symbol: '[! ]',
        name: 'A callout',
        typed: '> [!NOTE]\n> The deposit comes back in full.',
        words: 'The deposit comes back in full.',
        looks: 'callout',
        icon: 'info',
        note: 'NOTE',
        say: '“info box: …”, “warning callout: …”',
     ),
      MarkRow(
        symbol: '```mermaid',
        name: 'A diagram',
        typed: '```mermaid\nflowchart TD\n  A[Speak] --> B[Note]\n  B --> C[Board]\n```',
        words: 'flowchart TD',
        looks: 'diagram',
        icon: 'workflow',
     ),
      MarkRow(
        symbol: '```board',
        name: 'A board',
        typed: '```board\nTo do: ship-page\nDone: pick-date\n```\n\n- [ ] Ship the pricing page ^ship-page\n- [x] Pick a launch date ^pick-date',
        words: 'ship-page',
        looks: 'board',
        icon: 'layout-grid',
     ),
      // A note that is a ticket, by its front matter (docs/TICKETS.md): drawn in a note as its properties, and here as
      // the lines it is, since a cheat sheet's example has no library of tickets to draw them from.
      MarkRow(
        symbol: 'type: ticket',
        name: 'A ticket',
        typed: '---\ntype: ticket\nid: GHO-12\nstatus: In progress\nassignee: Sam\n---\n# Fix the login loop',
        words: 'GHO-12',
        looks: 'ticket',
        icon: 'ticket',
        note: 'Its properties are drawn as a card over its words. [[GHO-12]] in any note links to it.',
     ),
      // A query (docs/QUERIES.md): drawn in a note as what it finds across the library, and here as the lines it is,
      // since a cheat sheet's example has no library to read.
      MarkRow(
        symbol: '```query',
        name: 'A query',
        typed: '```query\nfrom: tickets #bug\nwhere: status != Done\nshow: board\n```',
        words: 'from: tickets #bug',
        looks: 'query',
        icon: 'database',
        note: 'Drawn as what it finds in every note: a table, a list, a board, a month, a timeline or a count. Tap the pencil to change it.',
     ),
    ],
 ),
];

/// Every group the page shows: the app's own marks, then the ones the switched-on plugins add (`markGroups`).
/// [registry] is the app's unless a caller brings one, and [now] the clock.
List<MarkGroup> markGroups({Registry? registry, DateTime? now}) {
  final formats = (registry ?? plugins).formats();
  // A row that is part of a plugin's mark goes when the mark does.
  final on = <String>{for (final format in formats) format.name};
  final own = <MarkGroup>[
    for (final group in _own(isoDayAfterDate(now ?? DateTime.now(), 2)))
      MarkGroup(
        title: group.title,
        lead: group.lead,
        rows: <MarkRow>[
          for (final row in group.rows)
            if (row.needs == null || on.contains(row.needs)) row,
        ],
      ),
  ];
  if (formats.isEmpty) return own;
  final rows = <MarkRow>[
    for (final format in formats) _pluginRow(format),
  ];
  // A colour named after a highlight, which is the same brackets saying something else (lib/plugins/marks.dart).
  const tinted = MarkRow(
    symbol: '==( )',
    name: 'A colored highlight',
    typed: '==the cabin key==(green) and ==the deadline==(red)',
    words: 'the cabin key',
    looks: 'tint',
    icon: 'highlighter',
  );
  // A note on a mark is shown last, because it is written on top of any of the marks above it.
  const noted = MarkRow(
    symbol: '( )',
    name: 'A note on a mark',
    typed: '??four hundred??(Sam said 400)',
    words: 'four hundred',
    looks: 'note',
    icon: 'info',
    note: 'Sam said 400',
    say: '“… end unsure, note Sam said 400, end note”',
  );
  return <MarkGroup>[
    ...own,
    MarkGroup(title: 'Ghost.md’s own', lead: 'Marks the app adds, all from the Marks plugin, which the Market can switch off.', rows: <MarkRow>[...rows, tinted, noted]),
  ];
}

/// A plugin's icon by the name the drawn set has it under, where the plugin says an older one: lucide's `Waves` is
/// `waves-horizontal` in lib/art/lucide.g.dart, and lib/plugins/marks.dart says `waves` (which falls back to nothing
/// wherever it is looked up as it stands).
const Map<String, String> _drawn = <String, String>{'waves': 'waves-horizontal'};

MarkRow _pluginRow(GlyphFormat format) {
  final look = format.look;
  final words = format.name == 'Spoiler' ? 'the cabin key' : '${format.name.toLowerCase()} this';
  // Heat bends the text above its words, not the words themselves, so its example has a line above for the haze to
  // rise into; alone on a line, the example would show only bold words.
  final above = look is EffectLook && look.effect == 'heat' ? 'The air above wavers\n' : '';
  final cue = format.cue;
  return MarkRow(
    symbol: format.delimiter,
    name: format.name,
    typed: '$above${format.delimiter}$words${format.delimiter}',
    words: words,
    looks: switch (look) {
      WispLook() => 'wisp',
      EffectLook() => 'effect',
      StyleLook() => 'style',
    },
    icon: _drawn[format.icon] ?? format.icon ?? 'underline',
    css: look is StyleLook ? look.css : null,
    say: cue != null && cue.isNotEmpty ? '“$cue” … “end $cue”' : null,
  );
}
