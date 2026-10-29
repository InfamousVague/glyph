// A tap on a link opens it, in the words and in a drawn table's cell (lib/editor/media/links.dart `linkTapOpener`,
// lib/editor/tables/table_box.dart). Matt, 2026-10-29: "I can't open links in ghost markdown on the deep link test
// spot": a note of `[hello.trade/…](https://hello.trade/…)` links in a table and in a list, to tap on a phone so
// they open the HelloTrade app, where a tap on any of them only put the caret in the note.
//
// On the real renderer and its gestures: a finger's tap, a mouse's click, the keys held with it, the pointer's
// shape over a link. The opener is a fake: what the note's desk gives the editor is lib/core/open_link.dart's
// `openLink`, held to its own test (test/core/open_link_test.dart).
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/tables.dart' show CellLink;
import 'package:ghost_md/editor/editor.dart' hide Decoration;
import 'package:ghost_md/editor/items/wiki_links.dart';
import 'package:ghost_md/editor/media/links.dart';
import 'package:ghost_md/editor/semantics/line_semantics.dart' show linksOn;
import 'package:ghost_md/editor/tables/tables.dart';

import '../../support/render.dart';
import '../input/support.dart';

const String hello = 'https://hello.trade/waitlist?ref=EXU6LYUP5K';
const String lan = 'http://192.168.18.21:3120';

final String doc = <String>[
  '# Deep link quick test',
  '',
  '3. Tap [$hello]($hello)',
  '   Expect: the app opens on the waitlist.',
  '',
  'The QA page, $lan for test inboxes.',
  '',
  'Plain words with nothing to open.',
  '',
  '| Code | Link |',
  '| --- | --- |',
  '| EXU6LYUP5K | [hello.trade/waitlist?ref=EXU6LYUP5K]($hello) |',
  '| Runbook | [[Invite links QA]] |',
  '| Later | [[Not written yet]] |',
  '| Bare | $lan |',
  '',
  'last line',
].join('\n');

/// The editor with links that open into `opened`, notes into `notes`, and its tables drawn.
Future<Rig> pumpLinks(WidgetTester tester, List<String> opened, List<String> notes, {bool focus = false, bool readOnly = false, int? caret}) => pumpEditor(
  tester,
  doc,
  focus: focus,
  readOnly: readOnly,
  caret: caret,
  more: <Extension>[
    shortLinks(onOpen: opened.add),
    wikiLinks(WikiOptions(known: (title) => title == 'Invite links QA', open: (title, [anchor]) => notes.add(title))),
    drawnTables(),
  ],
);

/// The middle of the drawn words `from`-`to` of the note, on their first row.
Offset wordsAt(Rig rig, int from, int to) {
  final start = rig.view.coordsAtPos(from, 1)!, end = rig.view.coordsAtPos(to, -1)!;
  final right = (end.top - start.top).abs() < 1 ? end.right : start.right + 20;
  return Offset((start.left + right) / 2, start.center.dy);
}

/// The drawn table.
RenderGlyphTable tableOf(WidgetTester tester) => tester.renderObject<RenderGlyphTable>(find.byType(GlyphTable));

/// The middle of a cell's link, or of the cell's words where it has none, on screen.
Offset cellAt(WidgetTester tester, int row, int column) {
  final table = tableOf(tester);
  final cell = table.table.cells[row][column];
  final box = cell.links.isEmpty ? cell.wordBoxes.first : cell.linkBoxes.first.first;
  return table.localToGlobal(box.center);
}

void main() {
  setUpAll(loadAppFonts);

  group('a link in the words', () {
    testWidgets('a finger’s tap on its words opens it, and the caret and the keyboard stay where they were', (tester) async {
      final opened = <String>[], notes = <String>[];
      final rig = await pumpLinks(tester, opened, notes);
      final at = rig.at('[https') + 1;
      await tester.tapAt(wordsAt(rig, at, at + 20));
      await tester.pump();
      expect(opened, <String>[hello]);
      expect(rig.view.hasFocus, isFalse);
      expect(rig.head, 0);
      await finish(tester);
    });

    testWidgets('so does a tap on its address, drawn short', (tester) async {
      final opened = <String>[], notes = <String>[];
      await pumpLinks(tester, opened, notes);
      // The first address drawn short is this link's: the note's first.
      final short = find.byKey(const ValueKey<String>('cm-shortLink'));
      expect(short, findsWidgets);
      await tester.tapAt(tester.getRect(short.first).center);
      await tester.pump();
      expect(opened, <String>[hello]);
      await finish(tester);
    });

    testWidgets('an address said bare in a paragraph, a LAN one with its port, is a link and opens', (tester) async {
      final opened = <String>[], notes = <String>[];
      final rig = await pumpLinks(tester, opened, notes);
      final line = rig.view.state.doc.lineAt(rig.at('The QA page'));
      expect(linksOn(rig.view.state, line.from, line.to).map((link) => link.url), <String>[lan]);
      final from = rig.at(lan);
      final shown = find.byKey(const ValueKey<String>('cm-shortLink'));
      // Short where shortening it says less, else written out: either way its own words are tapped.
      final at = shown.evaluate().length > 1 ? tester.getRect(shown.last).center : wordsAt(rig, from, from + lan.length);
      await tester.tapAt(at);
      await tester.pump();
      expect(opened, <String>[lan]);
      await finish(tester);
    });

    testWidgets('a tap on plain words, or past a link at the end of its line, is the caret’s', (tester) async {
      final opened = <String>[], notes = <String>[];
      final rig = await pumpLinks(tester, opened, notes);
      final plain = rig.at('nothing') + 2;
      await tester.tapAt(rig.point(plain) + const Offset(1, 0));
      await tester.pump();
      expect(opened, isEmpty);
      expect(rig.head, plain);
      // Past the end of the line the link ends: the nearest position is the link's last, and it is not on it.
      rig.view.setFocused(false);
      await tester.pump(const Duration(milliseconds: 600));
      final end = rig.view.state.doc.lineAt(rig.at('[https')).to;
      await tester.tapAt(Offset(380, rig.point(end, -1).dy));
      await tester.pump();
      expect(opened, isEmpty);
      await finish(tester);
    });

    testWidgets('with the caret elsewhere on its line, where it is written out whole, a tap still opens it', (tester) async {
      final opened = <String>[], notes = <String>[];
      final at = doc.indexOf('[https') + 1;
      final rig = await pumpLinks(tester, opened, notes, focus: true, caret: at - 3);
      await tester.tapAt(wordsAt(rig, at, at + 20));
      await tester.pump();
      expect(opened, <String>[hello]);
      expect(rig.head, at - 3);
      await finish(tester);
    });

    testWidgets('with the caret already in it, a tap is the caret’s, so the link can be edited', (tester) async {
      final opened = <String>[], notes = <String>[];
      final at = doc.indexOf('[https') + 1;
      final rig = await pumpLinks(tester, opened, notes, focus: true, caret: at + 2);
      await tester.tapAt(wordsAt(rig, at + 10, at + 12));
      await tester.pump();
      expect(opened, isEmpty);
      expect(rig.head, greaterThan(at + 2));
      expect(rig.head, lessThan(at + 20));
      await finish(tester);
    });

    testWidgets('with Cmd held on a Mac, Ctrl elsewhere, a click opens it even with the caret in it; Shift, Alt, the other button and a Mac’s Ctrl never', (tester) async {
      final apple = defaultTargetPlatform == TargetPlatform.macOS;
      final opened = <String>[], notes = <String>[];
      final at = doc.indexOf('[https') + 1;
      final rig = await pumpLinks(tester, opened, notes, focus: true, caret: at - 3);
      final point = wordsAt(rig, at, at + 20);
      for (final key in <LogicalKeyboardKey>[LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.altLeft, if (apple) LogicalKeyboardKey.controlLeft]) {
        await rig.place(at - 3);
        await tester.sendKeyDownEvent(key);
        await tester.tapAt(point, kind: PointerDeviceKind.mouse);
        await tester.sendKeyUpEvent(key);
        await tester.pump(const Duration(milliseconds: 600));
      }
      await rig.place(at - 3);
      await tester.tapAt(point, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pump(const Duration(milliseconds: 600));
      expect(opened, isEmpty);
      // The other button put the caret in the link; a plain click there is the caret's, Cmd or Ctrl's opens it.
      expect(rig.head, inInclusiveRange(at, at + 60));
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 600));
      expect(opened, isEmpty);
      await tester.sendKeyDownEvent(apple ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft);
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(apple ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(opened, <String>[hello]);
      await finish(tester);
    }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}));

    testWidgets('a mouse’s plain click opens one off the line being written, as a finger’s tap does', (tester) async {
      final opened = <String>[], notes = <String>[];
      final rig = await pumpLinks(tester, opened, notes);
      final at = rig.at('[https') + 1;
      await tester.tapAt(wordsAt(rig, at, at + 20), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(opened, <String>[hello]);
      await finish(tester);
    }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.macOS, TargetPlatform.windows}));

    testWidgets('a view that cannot be edited opens it too', (tester) async {
      final opened = <String>[], notes = <String>[];
      final rig = await pumpLinks(tester, opened, notes, readOnly: true);
      final at = rig.at('[https') + 1;
      await tester.tapAt(wordsAt(rig, at, at + 20));
      await tester.pump();
      expect(opened, <String>[hello]);
      await finish(tester);
    });

    testWidgets('an item’s mark is not opened (its pill lands the caret), nor an address no app is handed', (tester) async {
      final opened = <String>[];
      final rig = await pumpEditor(tester, '- [ ] Buy milk [notion](https://www.notion.so/a/Buy-milk-1a2b3c4d5e6f)\n\nsee [the part](#below) here\n', focus: false, more: <Extension>[shortLinks(onOpen: opened.add)]);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey<String>('cm-itemMark'))));
      await tester.pump(const Duration(milliseconds: 600));
      final part = rig.at('the part') + 1;
      await tester.tapAt(wordsAt(rig, part, part + 6));
      await tester.pump();
      expect(opened, isEmpty);
      await finish(tester);
    });

    testWidgets('without an opener a tap on a link is the caret’s, as on the page', (tester) async {
      final rig = await pumpEditor(tester, doc, focus: false, more: <Extension>[shortLinks()]);
      final at = rig.at('[https') + 1;
      await tester.tapAt(wordsAt(rig, at, at + 20));
      await tester.pump();
      expect(rig.view.hasFocus, isTrue);
      await finish(tester);
    });
  });

  group('a link in a drawn table’s cell', () {
    testWidgets('is drawn as a link: a `[words](address)`’s words and a known note underlined, a bare address muted', (tester) async {
      await pumpLinks(tester, <String>[], <String>[]);
      final cells = tableOf(tester).table.cells;
      expect(cells[1][1].text, 'hello.trade/waitlist?ref=EXU6LYUP5K');
      expect(cells[1][1].links, <CellLink>[const CellLink(from: 0, to: 35, url: hello)]);
      expect(cells[2][1].links.single.title, 'Invite links QA');
      expect(cells[3][1].links.single.waiting, isTrue);
      expect(cells[4][1].links.single, const CellLink(from: 0, to: lan.length, url: lan, bare: true));
      expect(cells[1][0].links, isEmpty);
      for (final row in <int>[1, 2, 3, 4]) {
        expect(cells[row][1].linkBoxes.single, isNotEmpty, reason: 'row $row');
      }
      await finish(tester);
    });

    testWidgets('a tap on a link’s words opens it, and the table stays drawn', (tester) async {
      final opened = <String>[], notes = <String>[];
      final rig = await pumpLinks(tester, opened, notes);
      await tester.tapAt(cellAt(tester, 1, 1));
      await tester.pump();
      expect(opened, <String>[hello]);
      await tester.tapAt(cellAt(tester, 4, 1));
      await tester.pump();
      expect(opened, <String>[hello, lan]);
      expect(rig.view.hasFocus, isFalse);
      expect(drawnTablesIn(rig.view.state).size, 1);
      await finish(tester);
    });

    testWidgets('a `[[link]]` opens its note, or the note waiting to be written', (tester) async {
      final opened = <String>[], notes = <String>[];
      await pumpLinks(tester, opened, notes);
      await tester.tapAt(cellAt(tester, 2, 1));
      await tester.pump();
      await tester.tapAt(cellAt(tester, 3, 1));
      await tester.pump();
      expect(notes, <String>['Invite links QA', 'Not written yet']);
      expect(opened, isEmpty);
      await finish(tester);
    });

    testWidgets('a tap on its plain words, or beside a link in its cell, opens the table’s lines as before', (tester) async {
      final opened = <String>[], notes = <String>[];
      final rig = await pumpLinks(tester, opened, notes);
      final from = rig.view.state.doc.lineAt(rig.at('| Code')).from;
      await tester.tapAt(cellAt(tester, 1, 0));
      await tester.pump();
      expect(opened, isEmpty);
      expect(rig.head, from);
      expect(rig.view.hasFocus, isTrue);
      expect(drawnTablesIn(rig.view.state).size, 0);
      await finish(tester);
    });

    testWidgets('beside the link in its own cell is the table’s too', (tester) async {
      final opened = <String>[], notes = <String>[];
      final rig = await pumpLinks(tester, opened, notes);
      final table = tableOf(tester);
      final cell = table.table.cells[2][1];
      // Under the cell's words, in its padding: the cell's, not its link's.
      final below = table.localToGlobal(Offset(cell.linkBoxes.first.first.center.dx, cell.rect.bottom - 2));
      await tester.tapAt(below);
      await tester.pump();
      expect(notes, isEmpty);
      expect(drawnTablesIn(rig.view.state).size, 0);
      await finish(tester);
    });

    testWidgets('a mouse opens it with a plain click or with Cmd or Ctrl held, as it does a link off the line being written', (tester) async {
      final opened = <String>[], notes = <String>[];
      await pumpLinks(tester, opened, notes);
      await tester.tapAt(cellAt(tester, 1, 1), kind: PointerDeviceKind.mouse);
      await tester.pump();
      final key = defaultTargetPlatform == TargetPlatform.macOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(key);
      await tester.tapAt(cellAt(tester, 1, 1), kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(key);
      await tester.pump();
      expect(opened, <String>[hello, hello]);
      await finish(tester);
    }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.macOS, TargetPlatform.windows}));

    testWidgets('the mouse’s pointer is a hand over a link and the text cursor over the rest of the table', (tester) async {
      await pumpLinks(tester, <String>[], <String>[]);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(cellAt(tester, 1, 1));
      await tester.pump();
      expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
      await mouse.moveTo(cellAt(tester, 1, 0));
      await tester.pump();
      expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.text);
      await finish(tester);
    });

    testWidgets('a finger that scrolls the note from a link opens nothing', (tester) async {
      final opened = <String>[], notes = <String>[];
      await pumpLinks(tester, opened, notes);
      final gesture = await tester.startGesture(cellAt(tester, 1, 1));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.moveBy(const Offset(0, -30));
      await gesture.moveBy(const Offset(0, -60));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      await finish(tester);
    });

    testWidgets('in a view that cannot be edited a link opens, and the rest of the table does nothing', (tester) async {
      final opened = <String>[], notes = <String>[];
      final rig = await pumpLinks(tester, opened, notes, readOnly: true);
      await tester.tapAt(cellAt(tester, 1, 1));
      await tester.pump();
      expect(opened, <String>[hello]);
      await tester.tapAt(cellAt(tester, 1, 0));
      await tester.pump();
      expect(opened, <String>[hello]);
      expect(drawnTablesIn(rig.view.state).size, 1);
      await finish(tester);
    });

    testWidgets('without an opener a tap on a cell’s address opens the table’s lines, as on the page', (tester) async {
      final rig = await pumpEditor(tester, doc, focus: false, more: <Extension>[drawnTables()]);
      await tester.tapAt(cellAt(tester, 1, 1));
      await tester.pump();
      expect(drawnTablesIn(rig.view.state).size, 0);
      await finish(tester);
    });
  });

  // Matt, 2026-10-29: "Clicking links still opens the link for editing instead of opening the link". A plain tap
  // on a phone and a plain click on a Mac's window open every kind of link, and the link is edited by getting the
  // caret into it some other way first.
  for (final (name, size, kind, platform) in <(String, Size, PointerDeviceKind, TargetPlatform)>[
    ('on a phone', const Size(390, 844), PointerDeviceKind.touch, TargetPlatform.android),
    ('on a Mac’s window', const Size(1280, 800), PointerDeviceKind.mouse, TargetPlatform.macOS),
  ]) {
    group(name, () {
      Future<Rig> pump(WidgetTester tester, List<String> opened, List<String> notes, {bool focus = false, int? caret}) => pumpEditor(
        tester,
        doc,
        focus: focus,
        caret: caret,
        size: size,
        more: <Extension>[
          shortLinks(onOpen: opened.add),
          wikiLinks(WikiOptions(known: (title) => title == 'Invite links QA', open: (title, [anchor]) => notes.add(title))),
          drawnTables(),
        ],
      );

      testWidgets('a plain tap or click opens a link in a list, a bare address in a paragraph, and a table’s links', (tester) async {
        final opened = <String>[], notes = <String>[];
        final rig = await pump(tester, opened, notes);
        final at = rig.at('[https') + 1;
        await tester.tapAt(wordsAt(rig, at, at + 20), kind: kind);
        await tester.pump(const Duration(milliseconds: 600));
        final lanAt = rig.at(lan);
        final shown = find.byKey(const ValueKey<String>('cm-shortLink'));
        await tester.tapAt(shown.evaluate().length > 1 ? tester.getRect(shown.last).center : wordsAt(rig, lanAt, lanAt + lan.length), kind: kind);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tapAt(cellAt(tester, 1, 1), kind: kind);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tapAt(cellAt(tester, 4, 1), kind: kind);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tapAt(cellAt(tester, 2, 1), kind: kind);
        await tester.pump(const Duration(milliseconds: 600));
        expect(opened, <String>[hello, lan, hello, lan]);
        expect(notes, <String>['Invite links QA']);
        expect(rig.view.hasFocus, isFalse);
        await finish(tester);
      }, variant: TargetPlatformVariant.only(platform));

      testWidgets('with the caret in a link a tap is the caret’s; a tap just after the link puts it there', (tester) async {
        final opened = <String>[], notes = <String>[];
        final at = doc.indexOf('[https') + 1;
        final rig = await pump(tester, opened, notes, focus: true, caret: 0);
        // Just past the link's end (the line ends there): the caret goes to its end, and nothing opens.
        final end = rig.view.state.doc.lineAt(at).to;
        await tester.tapAt(rig.point(end, -1) + const Offset(24, 0), kind: kind);
        await tester.pump(const Duration(milliseconds: 600));
        expect(opened, isEmpty);
        expect(rig.head, end);
        // The caret at the link's edge, it is being edited: a tap on its words moves the caret into them.
        await tester.tapAt(wordsAt(rig, at + 10, at + 12), kind: kind);
        await tester.pump(const Duration(milliseconds: 600));
        expect(opened, isEmpty);
        expect(rig.head, inExclusiveRange(at, end));
        await finish(tester);
      }, variant: TargetPlatformVariant.only(platform));
    });
  }
}
