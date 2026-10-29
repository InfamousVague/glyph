import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/note/byline.dart';
import 'package:ghost_md/note/note_place.dart';
import 'package:ghost_md/note/note_settings.dart';
import 'package:ghost_md/note/note_tools.dart';
import 'package:ghost_md/sheet/kit.dart';

import '../support/header_bar.dart';
import '../support/render.dart';
import 'support.dart';

/// Where a note's screen stands, held to what the web page measured (test/note/reference/note_reference.mjs: the dev
/// server at 390 x 844 and 840 x 900, the same note, the smoke on): the tools in the bar, the byline, where the
/// editor starts and its first line, and every row of the More sheet, to half a pixel.
void main() {
  setUpAll(loadAppFonts);
  // Held to the web page's note, whose bar is today's: its rings, its height and where the page starts under it.
  setUp(pinTodaysBar);

  for (final width in [390, 840]) {
    final web = webNote(width);
    final frame = (web['frame'] as Map).cast<String, dynamic>();
    final size = Size(width.toDouble(), width == 390 ? 844 : 900);

    void near(Rect got, Rect want, String what, {double within = 0.5}) {
      expect(got.left, closeTo(want.left, within), reason: '$what, left');
      expect(got.top, closeTo(want.top, within), reason: '$what, top');
      expect(got.width, closeTo(want.width, within), reason: '$what, width');
      expect(got.height, closeTo(want.height, within), reason: '$what, height');
    }

    group('at $width', () {
      testWidgets('the tools stand in the bar where the page puts them', (tester) async {
        final world = NoteWorld();
        final note = await tester.runAsync(() => seedNote(world, 'lisbon', web['body'] as String));
        await pumpNote(tester, world, note!, size: size, seams: measuredSeams(world.asked), speak: true);
        final tools = (frame['tools'] as List).cast<Map<String, dynamic>>();
        final drawn = tester.widgetList<NoteToolButton>(find.byType(NoteToolButton)).toList();
        // The bar's folder after the sidebar's icon (Matt, 2026-10-29: "add a folder icon to the top near home and
        // sidebar to show all notes in the folder / icon view") is the app's own and takes a ring's room on the line:
        // where the page had room for one spare tool more, that tool is More's alone now (the last of the spares, by
        // the order they come out of More), and the rest stand where the page's last ones stood. The view switch and
        // More are the last two, as on the page.
        final spares = tools.length - 2;
        final dropped = tools.length - drawn.length;
        expect(dropped, inInclusiveRange(0, 1), reason: 'a ring’s room, one spare tool at most');
        final want = [for (final (at, tool) in tools.indexed) if (at < spares - dropped || at >= spares) tool['label']];
        expect([for (final tool in drawn) tool.label], want, reason: 'which of the spare tools the row has room for');
        for (final (at, button) in drawn.indexed) {
          near(tester.getRect(find.byWidget(button)), webRect(tools[at + dropped]['rect'], down: notch), button.label);
        }
        await closeNote(tester);
      });

      testWidgets('the byline and the editor start where the page starts them', (tester) async {
        final world = NoteWorld();
        final note = await tester.runAsync(() => seedNote(world, 'lisbon', web['body'] as String));
        final screen = await pumpNote(tester, world, note!, size: size, seams: measuredSeams(world.asked), speak: true);
        final marks = (frame['bylineMarks'] as List).cast<Map<String, dynamic>>();
        for (final mark in marks) {
          near(tester.getRect(find.byKey(ValueKey('author:${mark['title']}'))), webRect(mark['rect'], down: notch), 'the mark of ${mark['title']}');
        }
        near(tester.getRect(find.byKey(const ValueKey('byline-names'))), webRect(frame['bylineNames'], down: notch), 'the names');
        final byline = webRect(frame['byline'], down: notch);
        expect(tester.getRect(find.byType(NoteByline)).bottom, closeTo(byline.bottom, 0.5), reason: 'the byline’s foot');

        // The editor: its sliver starts under the byline, and its first heading is where the page's is.
        final view = screen.view!;
        final editor = webRect(frame['editor'], down: notch);
        expect(documentOffset(view)! - view.look!.env.contentTop, closeTo(editor.top, 0.5), reason: 'where the editor starts');
        final lines = (frame['lines'] as List).cast<Map<String, dynamic>>();
        final heading = view.state.doc.toString().indexOf('# Trip');
        final line = view.lineAt(heading)!;
        expect(line.localToGlobal(Offset.zero).dy, closeTo(webRect(lines.first['rect'], down: notch).top, 0.5), reason: 'the first heading’s line');
        expect(line.size.width, closeTo(size.width, 0.5), reason: 'the line is as wide as the page');
        await closeNote(tester);
      });

      testWidgets('the More sheet’s rows stand where the page’s do', (tester) async {
        final world = NoteWorld();
        final note = await tester.runAsync(() => seedNote(world, 'lisbon', web['body'] as String));
        if (width == 840) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await pumpNote(tester, world, note!, size: size, seams: measuredSeams(world.asked), speak: true);
        await tester.tap(find.bySemanticsLabel('More for this note'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final measured = (web['sheet'] as Map).cast<String, dynamic>();
        final blocks = (measured['blocks'] as List).cast<Map<String, dynamic>>();
        // The sheet hangs from the window's foot, so the notch does not move it.
        final titleWeb = webRect(blocks.firstWhere((block) => block['cls'] == 'title')['rect']);
        final titleHere = tester.getRect(find.byType(SheetTitle));
        expect(titleHere.left, closeTo(titleWeb.left, 0.5), reason: 'the title, left');
        expect(titleHere.top, closeTo(titleWeb.top, 0.5), reason: 'the title, top');
        final rows = <Rect>[];
        final names = <String>[];
        for (final block in blocks) {
          for (final row in ((block['rows'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
            rows.add(webRect(row['rect']));
            names.add((row['text'] as String).isEmpty ? 'Ask' : row['text'] as String);
          }
        }
        final drawn = tester.renderObjectList<RenderBox>(find.byWidgetPredicate((widget) => widget is SheetRuled, skipOffstage: false)).toList();
        expect(drawn.length, rows.length, reason: 'as many rows as the page has: $names');
        for (final (at, box) in drawn.indexed) {
          final got = box.localToGlobal(Offset.zero) & box.size;
          near(got, rows[at], 'the row ${names[at]}');
        }
        final look = (measured['look'] as Map).cast<String, dynamic>();
        for (final option in (look['options'] as List).cast<Map<String, dynamic>>()) {
          near(tester.getRect(find.byKey(ValueKey('look:${option['text']}'))), webRect(option['rect']), 'the look ${option['text']}');
        }
        expect(find.byType(NoteSettings), findsOneWidget);
        await closeNote(tester);
        debugDefaultTargetPlatformOverride = null;
      });
    });
  }
}
