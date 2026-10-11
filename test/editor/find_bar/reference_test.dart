// The find bar held to the web page: every case test/editor/find_bar/fixtures/reference.mjs measured in Chromium
// (the web app's own FindBar over its own editor) drawn here, and the bar's box, its rows, each control's box, words
// and icon, their inks and grounds, the note's lines and each match's mark compared with the page's.
//
//   FIND_SHOTS=1 flutter test --no-pub --update-goldens test/editor/find_bar/reference_test.dart
//
// writes shots/<name>.png, to look at beside fixtures/<name>.png.
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/editor/find_bar/find_bar.dart';
import 'package:ghost_md/editor/find_bar/find_marks.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

/// How far a rectangle may be from the page's, in logical pixels.
const double tolerance = 0.5;

/// How far a colour may be from the page's, in steps of 255.
const double shade = 1.5;

void main() {
  setUpAll(loadAppFonts);

  final only = Platform.environment['FIND_CASE'];
  for (final name in BarFixture.names()) {
    if (only != null && only.isNotEmpty && name != only) continue;
    testWidgets('$name: the bar, its controls and the marks where the page has them', (tester) async {
      final fixture = BarFixture.read(name);
      final (view, _) = await pumpBar(tester, fixture.doc, initial: fixture.initial, theme: fixture.theme);
      for (final step in fixture.steps) {
        final key = barLabels[step[1] as String]!;
        switch (step[0] as String) {
          case 'click' || 'clickText':
            await press(tester, key);
          case 'fill':
            await typeInto(tester, key, step[2] as String);
          case 'focus':
            await tester.showKeyboard(editableOf(key));
            await settle(tester);
        }
      }
      final t = tester.element(find.byKey(FindBarKeys.bar)).tokens;
      final problems = <String>[];
      var worst = 0.0, worstMark = 0.0, worstShade = 0.0, notHeld = 0;

      void box(String what, Rect own, Rect want) {
        final off = rectGap(own, want);
        if (off > worst) worst = off;
        if (off > tolerance) problems.add('$what $own, the page $want');
      }

      void ink(String what, Color? own, String want) {
        final wanted = pageColor(want, t);
        final off = own == null ? 999.0 : colorGap(own, wanted);
        if (off > worstShade && off < 999) worstShade = off;
        if (off > shade) problems.add('$what $own, the page $wanted ($want)');
      }

      // The search itself.
      final state = findOf(view.state);
      expect(view.state.doc.toString(), fixture.now, reason: 'the note after the steps');
      expect(<List<int>>[for (final m in state.matches) <int>[m.from, m.to]], fixture.matches, reason: 'the matches');
      expect(state.current, fixture.current, reason: 'which match is current');

      // The bar and its rows.
      box('bar', tester.getRect(find.byKey(FindBarKeys.bar)), BarFixture.rect(fixture.bar['rect'] as Map<String, dynamic>));
      final ground = tester.widget<DecoratedBox>(find.byKey(FindBarKeys.bar)).decoration as BoxDecoration;
      ink('bar ground', ground.color, fixture.bar['background'] as String);
      ink('bar hairline', ground.border!.top.color, fixture.bar['border'] as String);
      expect(ground.border!.top.width, fixture.bar['borderWidth'], reason: 'the hairline');
      final rows = <Key>[FindBarKeys.findRow, FindBarKeys.replaceRow];
      expect(find.byKey(FindBarKeys.replaceRow).evaluate().length, fixture.rows.length - 1, reason: 'the replace row');
      for (var i = 0; i < fixture.rows.length; i++) {
        box('row $i', tester.getRect(find.byKey(rows[i])), BarFixture.rect(fixture.rows[i]));
      }

      // Each control.
      for (final entry in fixture.controls.entries) {
        final key = barKeys[entry.key]!;
        final want = entry.value as Map<String, dynamic>?;
        if (want == null) {
          expect(find.byKey(key), findsNothing, reason: '${entry.key} is not on the page');
          continue;
        }
        expect(find.byKey(key), findsOneWidget, reason: entry.key);
        box(entry.key, tester.getRect(find.byKey(key)), BarFixture.rect(want['rect'] as Map<String, dynamic>));
        final isField = entry.key == 'find' || entry.key == 'replaceWith';
        if (isField) {
          final editable = tester.widget<EditableText>(editableOf(key));
          expect(editable.controller.text, want['text'], reason: '${entry.key} holds');
          expect(editable.focusNode.hasFocus, want['focused'], reason: '${entry.key} focused');
          expect(editable.style.fontSize, closeTo((want['size'] as num).toDouble(), 0.01), reason: '${entry.key} size');
          ink('${entry.key} ink', editable.style.color, want['color'] as String);
          final shape = tester.widgetList<DecoratedBox>(find.descendant(of: find.byKey(key), matching: find.byType(DecoratedBox))).map((b) => b.decoration).whereType<ShapeDecoration>().single.shape as StadiumBorder;
          ink('${entry.key} line', shape.side.color, want['border'] as String);
          expect(shape.side.width, want['borderWidth'], reason: '${entry.key} line width');
          if ((want['text'] as String).isEmpty) {
            final placeholder = tester.widget<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)));
            expect(placeholder.data, want['placeholder']);
            ink('${entry.key} placeholder', placeholder.style!.color, want['placeholderColor'] as String);
          }
          continue;
        }
        final words = find.descendant(of: find.byKey(key), matching: find.byType(RichText));
        if (want['icon'] != null) {
          final icon = find.descendant(of: find.byKey(key), matching: find.byType(AppIcon));
          box('${entry.key} icon', tester.getRect(icon), BarFixture.rect(want['icon'] as Map<String, dynamic>));
          ink('${entry.key} ink', tester.widget<AppIcon>(icon).color, want['color'] as String);
          final on = tester.widgetList<Container>(find.descendant(of: find.byKey(key), matching: find.byType(Container))).map((c) => c.decoration).whereType<ShapeDecoration>().firstOrNull;
          ink('${entry.key} ground', on?.color ?? const Color(0x00000000), want['background'] as String);
          expect(enabled(tester, key), !(want['disabled'] as bool), reason: '${entry.key} enabled');
          continue;
        }
        final text = tester.widget<RichText>(words);
        expect(text.text.toPlainText(), want['text'], reason: '${entry.key} says');
        expect(text.text.style!.fontSize, closeTo((want['size'] as num).toDouble(), 0.01), reason: '${entry.key} size');
        expect(text.text.style!.fontWeight!.value, int.parse(want['weight'] as String), reason: '${entry.key} weight');
        ink('${entry.key} ink', text.text.style!.color, want['color'] as String);
        if (want['words'] != null) {
          final wanted = BarFixture.rect(want['words'] as Map<String, dynamic>);
          // A paragraph is as wide as its box here; the words' own width is what the page's range measured.
          final paragraph = tester.renderObject<RenderParagraph>(words);
          final at = paragraph.localToGlobal(Offset.zero);
          final ownWords = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.text.toPlainText().length)).map((b) => b.toRect()).reduce((a, b) => a.expandToInclude(b)).shift(at);
          box('${entry.key} words', Rect.fromLTRB(ownWords.left, at.dy, ownWords.right, at.dy + paragraph.size.height), wanted);
        }
        if (entry.key == 'all') {
          final pill = tester.widgetList<Container>(find.descendant(of: find.byKey(key), matching: find.byType(Container))).map((c) => c.decoration).whereType<ShapeDecoration>().single;
          ink('all ground', pill.color, want['background'] as String);
        }
        if (entry.key == 'replaceOne' || entry.key == 'all' || entry.key == 'done') {
          expect(enabled(tester, key), !(want['disabled'] as bool), reason: '${entry.key} enabled');
        }
      }

      // The note under it: the same lines, so the marks are compared like with like.
      final lines = view.lines;
      expect(lines.length, fixture.lines.length, reason: 'as many lines as the page drew');
      for (var i = 0; i < lines.length; i++) {
        final at = lines[i].localToGlobal(Offset.zero);
        box('line ${lines[i].from}', at & lines[i].size, BarFixture.rect(fixture.lines[i]['rect'] as Map<String, dynamic>));
      }

      // The marks: what each line paints behind its words, in the screen's coordinates.
      final grounds = <(Rect, Color, bool)>[];
      for (final line in lines) {
        final canvas = TestRecordingCanvas();
        line.paint(TestRecordingPaintingContext(canvas), line.localToGlobal(Offset.zero));
        for (final call in canvas.invocations) {
          final drawn = call.invocation;
          if (drawn.memberName == #drawRRect) {
            final rrect = drawn.positionalArguments[0] as RRect;
            expect(rrect.tlRadiusX, 2, reason: 'a match\'s corners');
            grounds.add((rrect.outerRect, (drawn.positionalArguments[1] as Paint).color, true));
          } else if (drawn.memberName == #drawRect) {
            grounds.add((drawn.positionalArguments[0] as Rect, (drawn.positionalArguments[1] as Paint).color, false));
          }
        }
      }
      final rounded = grounds.where((g) => g.$3).toList();
      // A line whose leading is tighter than its letters (a heading): the view paints no run's ground there yet
      // (find_marks.dart `groundsOnTightLines`), so its marks are not held, and the current one keeps its ink.
      bool tight(int pos) => view.lineAt(pos)!.visualLines.any((v) => v.contentTop < v.top);
      final held = <Map<String, dynamic>>[for (final mark in fixture.marks) if (groundsOnTightLines || !tight(mark['from'] as int)) mark];
      notHeld = fixture.marks.length - held.length;
      final boxes = held.fold<int>(0, (n, m) => n + (m['rects'] as List).length);
      if (rounded.length != boxes) {
        problems.add(
          rounded.length > boxes && !groundsOnTightLines
              ? 'the view paints grounds on tight lines now: make groundsOnTightLines true (lib/editor/find_bar/find_marks.dart)'
              : '${rounded.length} grounds painted, the page has $boxes: ${rounded.map((g) => g.$1).join(' ')}',
        );
      }
      for (final mark in fixture.marks) {
        if (!held.contains(mark)) {
          final line = view.lineAt(mark['from'] as int)!;
          final paper = t.color('glacier-bg');
          for (final run in line.spec.runs) {
            expect(colorGap(run.color, paper), greaterThan(40), reason: 'words with no ground behind them keep an ink that can be read');
          }
          continue;
        }
        final wantGround = pageColor(mark['background'] as String, t);
        for (final r in (mark['rects'] as List).cast<Map<String, dynamic>>()) {
          final want = BarFixture.rect(r);
          if (rounded.isEmpty) break;
          final own = rounded.reduce((a, b) => rectGap(a.$1, want) <= rectGap(b.$1, want) ? a : b);
          final off = rectGap(own.$1, want);
          if (off > worstMark) worstMark = off;
          if (off > tolerance) problems.add('mark ${mark['from']}-${mark['to']} ${own.$1}, the page $want');
          final gap = colorGap(own.$2, wantGround);
          if (gap > worstShade) worstShade = gap;
          if (gap > shade) problems.add('mark ${mark['from']}-${mark['to']} ground ${own.$2}, the page $wantGround');
        }
        // The words inside, in the ink the page gave them.
        final from = mark['from'] as int, to = mark['to'] as int;
        final line = view.lineAt(from)!;
        final proj = line.spec.projection;
        final inks = <Color>[
          for (var s = 0; s < proj.segments.length; s++)
            if (proj.segments[s].from + line.from < to && proj.segments[s].to + line.from > from && proj.segments[s].displayLength > 0) line.spec.runs[s].color,
        ];
        final wanted = (mark['inks'] as List).cast<String>();
        if (inks.length != wanted.length) problems.add('mark $from-$to: ${inks.length} runs, the page ${wanted.length}');
        for (var i = 0; i < inks.length && i < wanted.length; i++) {
          ink('mark $from-$to words', inks[i], wanted[i]);
        }
        final classes = <String>{for (final seg in proj.segments) if (seg.from + line.from < to && seg.to + line.from > from) for (final m in seg.marks) ...(m.attrs['class'] ?? '').split(' ')};
        expect(classes.contains('cm-findCurrent'), mark['current'], reason: 'mark $from-$to current');
      }

      // ignore: avoid_print
      print('$name: worst box ${worst.toStringAsFixed(3)}, worst mark ${worstMark.toStringAsFixed(3)}, worst shade ${worstShade.toStringAsFixed(2)}, ${fixture.marks.length} marks${notHeld > 0 ? ', $notHeld on a tight line not held' : ''}');
      if (Platform.environment['FIND_SHOTS'] != null) {
        await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name.png'));
      }
      expect(problems, isEmpty, reason: problems.take(10).join('\n'));
      await away(tester);
    });
  }
}
