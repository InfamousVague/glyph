import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/activity/activity_ring.dart' show ActivityRing;
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
        // The bar's own take two rings' room on the line that the page has for the note's spare tools: today's •••
        // after the sidebar's icon, which holds every note by folder and a new note (Matt, 2026-10-29: "Put the all
        // files folder icon under the more menu as well as the + button in the header"; the folder had been a ring of
        // its own there), and the activity ring, always there and grey while nothing runs (Matt, 2026-10-29: "Keep
        // the activity indicator always showing just have it gray put when nothing is happening"). Where the page had
        // room for spare tools more, up to two are More's alone now (the last of the spares, by the order they come
        // out of More); the view switch and More are the last two, as on the page. The ring stands after the view
        // switch, so the tools before it stand where the page's stood less the ring and its gap, and More, after it,
        // where the page's does.
        final spares = tools.length - 2;
        final dropped = tools.length - drawn.length;
        expect(dropped, inInclusiveRange(0, 2), reason: 'two rings’ room, two spare tools at most');
        final want = [for (final (at, tool) in tools.indexed) if (at < spares - dropped || at >= spares) tool['label']];
        expect([for (final tool in drawn) tool.label], want, reason: 'which of the spare tools the row has room for');
        final ring = tester.getRect(find.byKey(ActivityRing.key_));
        final view = tester.getRect(find.byWidget(drawn[drawn.length - 2]));
        final more = tester.getRect(find.byWidget(drawn.last));
        expect(ring.left > view.right && ring.right < more.left, isTrue, reason: 'the ring after the view switch, before More');
        final shift = ring.width + (ring.left - view.right);
        for (final (at, button) in drawn.indexed) {
          final rect = webRect(tools[at + dropped]['rect'], down: notch);
          near(tester.getRect(find.byWidget(button)), button == drawn.last ? rect : rect.translate(-shift, 0), button.label);
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
