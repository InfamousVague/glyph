import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/widgets.dart' hide Canvas;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/canvas/canvas_view.dart';
import 'package:ghost_md/canvas/sample_canvas.dart';

import '../support/render.dart';

/// The canvas against the web app's own, drawn by Chromium (tool/canvas_reference.mjs): the example canvas filling
/// a page at 390 x 844 (a finger) and at 1280 x 800 (a mouse), light and dark. The view the camera fitted, every
/// card's rectangle, a note's and a link's title and hint, the group's name, the toolbar and each tool, the map,
/// and for four cards and the group picked in turn: the ring, each handle's 44px box, the bar and its buttons, to
/// half a pixel. A picture of each is written beside this file (shots/) to be looked at beside the page's
/// (reference/).

const notes = {
  'Launch week': '# Launch week\n\n- [ ] Get the photos back\n- [x] Book the hall\n\nSome words about the week.',
  'How to format a note': '# How to format a note\n\nEvery mark a note can hold, one after another.',
};

final wiki = CanvasWiki(known: notes.containsKey, open: (title, [at]) {}, body: (title) => notes[title], titles: () => notes.keys.toList());

Map<String, dynamic> reference(int width, String theme) => jsonDecode(File('test/canvas/fixtures/reference_${width}_$theme.json').readAsStringSync()) as Map<String, dynamic>;

Matcher isBox(Object? box, [double within = 0.5]) {
  final b = (box! as List).cast<num>();
  return predicate<Rect>(
    (rect) => (rect.left - b[0]).abs() <= within && (rect.top - b[1]).abs() <= within && (rect.width - b[2]).abs() <= within && (rect.height - b[3]).abs() <= within,
    'a box within $within of $b',
  );
}

/// A picture of the screen as it stands, written to shots/ beside this file (`--update-goldens` writes).
Future<void> picture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 300));
  await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name.png'));
}

/// What `shot` (test/support/render.dart) does as it ends: the binding's own switch for shadows put back.
Future<void> done(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

Finder labelled(Pattern label) => find.bySemanticsLabel(label);

void main() {
  setUpAll(loadAppFonts);

  for (final (width, height, phone) in [(390.0, 844.0, true), (1280.0, 800.0, false)]) {
    for (final theme in ['light', 'dark']) {
      testWidgets('the example canvas at ${width.toInt()} x ${height.toInt()}, $theme, is the page’s', (tester) async {
        final ref = reference(width.toInt(), theme);
        // The wide page was read in a desktop's browser, whose own pointer is a mouse.
        debugCanvasCoarse = phone;
        addTearDown(() => debugCanvasCoarse = null);
        var body = sampleCanvasBody();
        final key = GlobalKey<CanvasViewState>();
        await pumpApp(
          tester,
          size: Size(width, height),
          prefs: AppPreferences(theme: theme),
          home: StatefulBuilder(
            builder: (context, setState) => CanvasView(key: key, body: body, wiki: wiki, openLink: (_) async {}, threads: (context, {required canvas, required node, required start, required change}) {}, onChange: (next) => setState(() => body = next)),
          ),
        );
        // The page has no safe areas round its canvas: the whole window.
        await tester.pump();
        final state = key.currentState!;
        final view = (ref['view'] as List).cast<num>();
        expect(state.camera.view.x, closeTo(view[0], 1e-3));
        expect(state.camera.view.y, closeTo(view[1], 1e-3));
        expect(state.camera.view.scale, closeTo(view[2], 1e-5));

        for (final card in (ref['cards'] as List).cast<Map<String, dynamic>>()) {
          final id = card['id'] as String;
          expect(tester.getRect(find.byKey(ValueKey('card $id'))), isBox(card['box']), reason: 'card $id');
          if (card['name'] != null) expect(tester.getRect(find.byKey(ValueKey('name $id'))), isBox(card['name']), reason: 'the name of $id');
        }
        // A note's title and a link's, and the link's address under it.
        final byId = {for (final card in (ref['cards'] as List).cast<Map<String, dynamic>>()) card['id']: card};
        expect(tester.getRect(find.text('Launch week').first), isBox(byId['board']!['title']));
        expect(tester.getRect(find.text('attack.fm/glyph')), isBox(byId['site']!['title']));
        expect(tester.getRect(find.text('https://attack.fm/glyph')), isBox(byId['site']!['hint']));

        final tools = ref['tools'] as Map<String, dynamic>;
        expect(tester.getRect(labelled('Canvas tools')), isBox(tools['box']), reason: 'the toolbar');
        for (final button in (tools['buttons'] as List).cast<Map<String, dynamic>>()) {
          final box = (button['box'] as List).cast<num>();
          final found = labelled(button['label'] as String);
          if (box[2] == 0) {
            expect(found, findsNothing, reason: '${button['label']} is a window’s');
          } else {
            expect(tester.getRect(found), isBox(box), reason: button['label'] as String);
          }
        }
        expect(tester.getRect(find.byKey(const ValueKey('map'))), isBox((ref['map'] as Map)['box']), reason: 'the map');
        await picture(tester, '${width.toInt()}_$theme');

        final picked = ref['picked'] as Map<String, dynamic>;
        for (final id in picked.keys) {
          final want = picked[id] as Map<String, dynamic>;
          final card = tester.getRect(find.byKey(ValueKey('card $id')));
          // A group is picked by its border: its ground is the page's.
          final at = id == 'before' ? Offset(card.left + 3, card.center.dy) : card.center;
          await tester.tapAt(at, kind: phone ? PointerDeviceKind.touch : PointerDeviceKind.mouse);
          await tester.pump();
          expect(state.chosen, id);
          expect(tester.getRect(find.byKey(ValueKey('ring $id'))), isBox(want['ring']), reason: 'the ring of $id');
          final handles = (want['handles'] as List).cast<Map<String, dynamic>>();
          expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('handle $id ')), findsNWidgets(handles.length));
          for (final handle in handles) {
            expect(tester.getRect(find.byKey(ValueKey('handle $id ${handle['handle']}'))), isBox(handle['box']), reason: 'the ${handle['handle']} handle of $id');
          }
          expect(tester.getRect(find.byKey(ValueKey('bar $id'))), isBox(want['bar']), reason: 'the bar of $id');
          expect(state.debugBarBelow, want['below']);
          for (final button in (want['buttons'] as List).cast<Map<String, dynamic>>()) {
            expect(tester.getRect(labelled(button['label'] as String)), isBox(button['box']), reason: '${button['label']} of $id');
          }
          if (id == 'book') await picture(tester, '${width.toInt()}_${theme}_picked');
          await tester.tapAt(Offset(width / 2, height - 120), kind: phone ? PointerDeviceKind.touch : PointerDeviceKind.mouse);
          await tester.pump(const Duration(milliseconds: 450));
          expect(state.chosen, isNull);
        }
        await done(tester);
      });
    }
  }
}
