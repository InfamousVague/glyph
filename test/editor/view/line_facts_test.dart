// What the editor's extensions read from a document through the facts its tree keeps (lib/editor/view/line_facts.dart
// and the readers beside each extension), held to the readers of the note's whole words they stand in for: the
// same items, boards, queries, footnotes, bookmark, noted marks, comments, counts under headings and tables, for
// notes made by chance of every awkward line, and for each of the hundreds of documents changes make of them (a
// document made by a change shares the tree's pieces with the one before, which is where a kept answer could go
// stale).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/comments/format.dart' show readComments;
import 'package:ghost_md/core/boards.dart' show boardsIn, itemAt, itemsIn;
import 'package:ghost_md/core/item_syntax.dart' show jsTrim, lineWords, listLead;
import 'package:ghost_md/core/place_refs.dart';
import 'package:ghost_md/core/query/query.dart' show queryFencesIn;
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/task_fields.dart' show withoutFields;
import 'package:ghost_md/core/video_refs.dart';
import 'package:ghost_md/editor/comments/comments.dart' show commentsOf;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/bookmark_line.dart';
import 'package:ghost_md/editor/items/footnotes.dart';
import 'package:ghost_md/editor/items/heading_progress.dart';
import 'package:ghost_md/editor/marks/mark_notes.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queryFencesOf;
import 'package:ghost_md/editor/syntax/language.dart';
import 'package:ghost_md/editor/tables/tables.dart';
import 'package:ghost_md/editor/view/drawn_block.dart' show trackFocus;
import 'package:ghost_md/editor/view/line_facts.dart';
import 'package:ghost_md/editor/view/syntax_tree.dart';
import 'package:ghost_md/plugins/marks.dart' show marks;

/// Lines that are, or nearly are, each thing an extension looks for.
const List<String> awkward = <String>[
  '',
  'Plain words, with a price of \$4 and another of \$5.',
  '# A heading',
  '## Another #tagged',
  '   ### Deep, three spaces in',
  '- [ ] a to-do',
  '- [x] done ^done-one',
  '- [ ] 📅 2026-10-03',
  '* a bullet ^ship-page',
  '1. a step ^step [3/8]',
  '- [ ] linked [notion](https://notion.so/x) ^linked',
  '- an item §§ [github](https://github.com/a/b/issues/1) ^marked',
  'The deposit is four hundred. §§',
  'a§§b and §§',
  'see [[#^ship-page]] and [[#^nowhere]] and [[A note]] and [[Other#part]]',
  '![[A canvas]]',
  '  ![[Indented#frame]]  ',
  '```',
  '~~~',
  '````',
  '  ```dart',
  '```board',
  '```board height=18',
  '~~~~ Board',
  '```query',
  '~~~query height=20',
  '``` query show=board',
  '```query but not one',
  '```comments',
  '~~~comments',
  'To do: ship-page, done-one',
  'Done: step, nowhere',
  'from: notes #bug',
  'c1 @sam 2026-10-01T10:00:00Z',
  '  A comment\'s words.',
  'words[^c1] and ==washed==[^c1] more',
  '[^1]: A footnote said here.',
  '  [^sam]: Sam said so.',
  'marked[^1] and [^sam] and [^none]',
  '??a doubt??(Sam said 400) and ==the key==(green) and **bold**(not a note',
  '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)',
  '- [Roughly here](GEO:38.71,-9.14)',
  '> [A place](geo:91,0)',
  '[![video 0:12](image/poster.jpg)](video/film-1.mp4)',
  '> - [![video 1:02:03](image/p_2.jpg)](video/f2.mov) §§',
  '[![video](image/p.jpg)](video/film.avi)',
  '![a picture](image/one.png) and ![another](image/two.png)',
  '![voice 0:08](tape:1000-9000)',
  'https://example.com/a/page',
  '- [words](https://example.com/b)',
  '| a | b |',
  '| - | - |',
  '|---|:-:|',
  '| 1 | 2 |',
  'a | b',
  '- | -',
  ': a meaning',
  'Term',
  ':smile: and maths \$x^2\$ and H~2~O',
  '> [!NOTE] A callout',
  '> more of it',
  '---',
  'title: "A title"',
];

String chance(Random random, int lines) => <String>[for (var i = 0; i < lines; i++) awkward[random.nextInt(awkward.length)]].join('\n');

/// The counts under headings as lib/editor/items/heading_progress.dart read them before the lines were kept: every
/// line outside fenced code, in order.
List<HeadingCount> countsByWalk(Doc doc) {
  final heading = RegExp(r'^ {0,3}(#{1,6})\s+\S');
  final fenceMark = RegExp(r'^\s*(```|~~~)');
  final open = <List<int>>[]; // line, level, done, total
  final counts = <HeadingCount>[];
  void close(int level) {
    while (open.isNotEmpty && open.last[1] >= level) {
      final h = open.removeLast();
      if (h[3] > 0) counts.add(HeadingCount(line: h[0], done: h[2], total: h[3]));
    }
  }

  String? fence;
  for (var n = 1; n <= doc.lines; n++) {
    final text = doc.line(n).text;
    final marker = fenceMark.firstMatch(text)?.group(1);
    if (marker != null) {
      fence = fence == null ? marker : (fence == marker ? null : fence);
      continue;
    }
    if (fence != null) continue;
    final found = heading.firstMatch(text);
    if (found != null) {
      final level = found.group(1)!.length;
      close(level);
      open.add(<int>[n, level, 0, 0]);
      continue;
    }
    final lead = listLead(text);
    if (lead != null && lead.done != null && withoutFields(text.substring(lead.wordsAt)).isNotEmpty) {
      for (final h in open) {
        h[3] += 1;
        if (lead.done!) h[2] += 1;
      }
    }
  }
  close(0);
  return counts..sort((a, b) => a.line - b.line);
}

/// The tables as lib/editor/tables/tables.dart found them before: the whole tree walked.
List<(int, int)> tablesByWalk(EditorState state) {
  final found = <(int, int)>[];
  syntaxTree(state).iterate(
    enter: (node) {
      if (node.name != 'Table') return null;
      found.add((state.doc.lineAt(node.from).from, state.doc.lineAt(node.to).to));
      return false;
    },
  );
  return found;
}

String commentsSaid(dynamic comments) => <Object?>[
  comments.fence == null ? null : <Object?>[comments.fence.open, comments.fence.close, comments.fence.from, comments.fence.to],
  <Object?>[for (final thread in comments.threads) '${thread.id} ${thread.from} ${thread.to} ${thread.replies.length} ${thread.resolved != null}'],
  <Object?>[for (final anchor in comments.anchors) '${anchor.id} ${anchor.from} ${anchor.to} ${anchor.wash}'],
  comments.strays,
].toString();

void main() {
  final pattern = notePattern(marks)!;

  /// Everything read through the tree, against the same thing read from the words.
  void expectSame(EditorState state, String why) {
    final doc = state.doc;
    final text = doc.toString();
    expect(itemsOf(doc), itemsIn(text), reason: 'the items ($why)');
    expect(boardsOf(doc), boardsIn(text), reason: 'the boards ($why)');
    expect(<Object?>[for (final fence in queryFencesOf(doc)) fence.toJson()].toString(), <Object?>[for (final fence in queryFencesIn(text)) fence.toJson()].toString(), reason: 'the queries ($why)');
    expect(footnotesOf(doc), footnotesIn(text), reason: 'the footnotes ($why)');
    expect(bookmarkLineOf(doc), bookmarkLineIn(text), reason: 'the bookmark ($why)');
    expect(notesOf(doc, pattern).toString(), notesIn(text, pattern).toString(), reason: 'the noted marks ($why)');
    expect(commentsSaid(commentsOf(doc)), commentsSaid(readComments(text)), reason: 'the comments ($why)');
    expect(headingCounts(doc), countsByWalk(doc), reason: 'the counts under headings ($why)');
    for (final item in itemsIn(text).take(3)) {
      expect(itemOf(doc, item.id), itemAt(text, item.id), reason: 'the item ${item.id} ($why)');
    }
    for (var n = 1; n <= doc.lines; n += 7) {
      expect(boardOf(doc, n), boardsIn(text).where((board) => board.to > board.from && n >= board.from && n <= board.to).firstOrNull, reason: 'the board at line $n ($why)');
    }
    // The tables: with no caret in the view, every table is drawn, each over its own lines.
    final drawn = <(int, int)>[];
    drawnTablesIn(state).between(0, doc.length, (from, to, value) {
      drawn.add((from, to));
      return null;
    });
    expect(drawn, tablesByWalk(state), reason: 'the tables ($why)');
  }

  EditorState stateOf(String text) => EditorState.create(
    doc: text,
    extensions: Extension.list(<Extension>[markdownSyntax(glyphMarkdown(marks)), trackFocus, drawnTables()]),
  );

  test('the sample note and notes made by chance read the same through the tree as from their words', () {
    expectSame(stateOf(sampleNoteBody), 'the sample note');
    expectSame(stateOf(boardNoteBody), 'the example board');
    expectSame(stateOf(''), 'an empty note');
    final random = Random(3);
    for (var round = 0; round < 120; round++) {
      expectSame(stateOf(chance(random, 1 + random.nextInt(90))), 'made by chance, $round');
    }
  });

  test('and so does every document changes make of one', () {
    final random = Random(5);
    var state = stateOf(chance(random, 300));
    expectSame(state, 'before any change');
    for (var round = 0; round < 200; round++) {
      final doc = state.doc;
      final from = random.nextInt(doc.length + 1);
      final to = min(doc.length, from + (random.nextInt(5) == 0 ? random.nextInt(120) : random.nextInt(3)));
      final insert = switch (random.nextInt(6)) {
        0 => '',
        1 => 'x',
        2 => '\n',
        3 => '`',
        4 => '\n${awkward[random.nextInt(awkward.length)]}\n',
        _ => chance(random, random.nextInt(12)),
      };
      state = state.update(TransactionSpec(changes: ChangeSpec(from: from, to: to, insert: insert))).state;
      expectSame(state, 'change $round: $from to $to, ${insert.length} letters in');
    }
  });

  test('a film\'s line and a place\'s are found as the patterns alone find them', () {
    // The readers ask a cheap question first (is the link's turn there at all); the answer must be the pattern's.
    final film = RegExp('^${videoRefPattern.pattern}\$');
    final place = RegExp(r'^\[([^\[\]\n]*)\]\(geo:(-?\d{1,3}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)\)$', caseSensitive: false);
    final random = Random(9);
    const bits = <String>['[', ']', '(', ')', 'geo:', 'GEO:', 'Geo:', 'video/', 'image/', '![', '§§', ' ', '^a', '> ', '- ', '- [ ] ', '38.7,-9.1', 'p.jpg', 'f.mp4', 'x', '[3/8]', '[notion](https://n.so/a)'];
    final lines = <String>[
      ...awkward,
      '[![video 0:12](image/p.jpg)](video/f.mp4) §§ ^film',
      '- [ ] [![v](image/p.jpg)](video/f.mp4) [3/8]',
      '[A place](geo:38.7,-9.1) §§',
      '[A place](geo:38.7,-9.1) ^here [notion](https://n.so/a)',
      for (var i = 0; i < 4000; i++) <String>[for (var j = 0; j < 2 + random.nextInt(9); j++) bits[random.nextInt(bits.length)]].join(),
    ];
    var films = 0, places = 0;
    for (final line in lines) {
      final byPattern = film.firstMatch(lineWords(line));
      final found = videoOfLine(line);
      expect(found != null, byPattern != null, reason: 'a film or not: "$line"');
      if (found != null) {
        films += 1;
        expect(found.poster, byPattern!.group(2));
        expect(found.video, byPattern.group(3));
      }
      final placed = place.firstMatch(lineWords(line));
      final there = placeOfLine(line);
      if (placed == null) {
        expect(there, isNull, reason: 'no place: "$line"');
      } else {
        final lat = double.parse(placed.group(2)!), lon = double.parse(placed.group(3)!);
        expect(there != null, lat.abs() <= 90 && lon.abs() <= 180, reason: 'a place or not: "$line"');
        if (there != null) {
          places += 1;
          expect(there.words, jsTrim(placed.group(1)!));
        }
      }
    }
    expect(films, greaterThanOrEqualTo(3), reason: 'films were among the lines');
    expect(places, greaterThanOrEqualTo(3), reason: 'and places');
  });
}
