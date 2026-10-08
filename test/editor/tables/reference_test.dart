// Drawn tables held to the web page: every case test/editor/tables/fixtures/reference.mjs measured in Chromium (the
// web app's own CodeMirror with `drawnTables()`) drawn here, and each line's box, each table's, each cell's and its
// words', the buttons' and their words', compared with the page's to half a pixel; the colours too.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/editor/commands/tables.dart' show TableAlign;
import 'package:ghost_md/editor/tables/tables.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import '../view/support.dart' show borderBox;
import 'support.dart';

/// How far a rectangle may be from the page's, in logical pixels.
const double tolerance = 0.5;

/// Cases measured on the page that cannot be drawn the same yet, and why.
const Map<String, String> _notHeld = <String, String>{};

void main() {
  setUpAll(loadAppFonts);

  final only = Platform.environment['EDITOR_CASE'];
  for (final name in TableFixture.names()) {
    if (only != null && only.isNotEmpty && !name.contains(only)) continue;
    testWidgets('$name: lines, tables, cells, words and buttons where the page has them', skip: _notHeld.containsKey(name), (tester) async {
      final fixture = TableFixture.read(name);
      await pumpTableFixture(tester, fixture);
      final t = tester.element(find.byType(DrawnTable).evaluate().isEmpty ? find.byType(SingleChildScrollView).first : find.byType(DrawnTable).first).tokens;
      final problems = <String>[];
      var worst = 0.0;
      // Where the page's editor grew as wide as its table, what is measured from the far side is not held: here the
      // table scrolls in its wrap and the note keeps the screen's width.
      final widened = fixture.widened;
      void hold(String what, Rect own, Rect page, {bool right = true}) {
        final offs = <double>[(own.left - page.left).abs(), (own.top - page.top).abs(), (own.bottom - page.bottom).abs(), if (right) (own.right - page.right).abs()];
        final off = offs.reduce((a, b) => a > b ? a : b);
        if (off > worst) worst = off;
        if (off > tolerance) problems.add('[$what] $own, the page $page');
      }

      final lines = drawnLines(tester);
      expect(lines.length, fixture.lines.length, reason: 'as many lines as the page drew');
      for (var i = 0; i < lines.length; i++) {
        final want = fixture.lines[i];
        expect(lines[i].from, want['from'], reason: 'line $i starts where the page\'s does');
        hold('line ${want['from']}', borderBox(lines[i]), TableFixture.rect(want['rect'] as Map<String, dynamic>), right: !widened);
      }

      final wraps = drawnWraps(tester);
      expect(wraps.length, fixture.tables.length, reason: 'as many tables drawn as on the page');
      var cellCount = 0;
      for (var n = 0; n < wraps.length; n++) {
        final want = fixture.tables[n];
        final wrap = wraps[n];
        final within = find.byElementPredicate((e) => identical(e, wrap));
        // The wrap's box on the page leaves its margins out; here they are the wrap's own padding.
        final wrapBox = wrap.renderObject! as RenderBox;
        final table = tableIn(tester, wrap);
        final origin = table.localToGlobal(Offset.zero);
        hold('table $n', origin & table.size, TableFixture.rect(want['table'] as Map<String, dynamic>));
        final wantWrap = TableFixture.rect(want['rect'] as Map<String, dynamic>);
        final margin = origin.dy - wrapBox.localToGlobal(Offset.zero).dy;
        final ownWrap = wrapBox.localToGlobal(Offset.zero) & wrapBox.size;
        hold('wrap $n', Rect.fromLTRB(ownWrap.left, ownWrap.top + margin, ownWrap.right, ownWrap.bottom - margin), wantWrap, right: !widened);

        final cells = <DrawnCell>[for (final row in table.table.cells) ...row];
        final wantCells = (want['cells'] as List).cast<Map<String, dynamic>>();
        expect(cells.length, wantCells.length, reason: 'as many cells as the page drew');
        cellCount += cells.length;
        for (var i = 0; i < cells.length; i++) {
          final cell = cells[i], wantCell = wantCells[i];
          final label = 'table $n cell ${cell.row},${cell.column} "${cell.text}"';
          expect(cell.row, wantCell['row']);
          expect(cell.column, wantCell['column']);
          expect(cell.head, wantCell['head']);
          expect(cell.text, wantCell['text'], reason: 'the words drawn are the page\'s');
          hold(label, cell.rect.shift(origin), TableFixture.rect(wantCell['rect'] as Map<String, dynamic>));
          // The words, line by line. On the page a `Range` over a wrapped cell answers each line's words and then,
          // as a rectangle of its own, the space the wrap left hanging at the line's end: not words, and not held.
          final pageBoxes = <Rect>[for (final r in (wantCell['words'] as List).cast<Map<String, dynamic>>()) TableFixture.rect(r)];
          final byLine = <Rect>[];
          for (final box in pageBoxes) {
            if (byLine.isNotEmpty && (byLine.last.top - box.top).abs() < 1) continue;
            byLine.add(box);
          }
          final own = <Rect>[for (final box in cell.wordBoxes) box.shift(origin)];
          // A header longer than the measure runs out of its cell on one line, there and here.
          if (own.length != byLine.length) {
            problems.add('[$label] ${own.length} lines of words, the page ${byLine.length}');
            continue;
          }
          for (var l = 0; l < own.length; l++) {
            hold('$label line $l', own[l], byLine[l]);
          }
          // The alignment the page computed, and the colours.
          final wantAlign = switch (wantCell['align']) {
            'center' => TableAlign.center,
            'right' => TableAlign.right,
            'left' => TableAlign.left,
            _ => null,
          };
          if (cell.align != wantAlign) problems.add('[$label] aligned ${cell.align}, the page ${wantCell['align']}');
          final look = table.table.look;
          final face = cell.head ? look.head : look.body;
          if ((face.size - (wantCell['size'] as num)).abs() > 0.001) problems.add('[$label] size ${face.size}, the page ${wantCell['size']}');
          if (face.style.fontFamily != wantCell['family']) problems.add('[$label] family ${face.style.fontFamily}, the page ${wantCell['family']}');
          if ('${face.style.fontWeight!.value}' != wantCell['weight']) problems.add('[$label] weight ${face.style.fontWeight}, the page ${wantCell['weight']}');
          if (face.style.color != t.colorOf(wantCell['color'] as String)) problems.add('[$label] ink ${face.style.color}, the page ${wantCell['color']}');
          if (look.ruleColor != t.colorOf(wantCell['border'] as String)) problems.add('[$label] rule ${look.ruleColor}, the page ${wantCell['border']}');
          final ground = cell.head ? look.headGround : null;
          final wantGround = t.colorOf(wantCell['background'] as String);
          if ((ground ?? const Color(0x00000000)) != wantGround) problems.add('[$label] ground $ground, the page ${wantCell['background']}');
        }

        // The buttons under it.
        final buttons = find.descendant(of: within, matching: find.byType(TableGrowButton));
        final wantGrows = (want['grows'] as List).cast<Map<String, dynamic>>();
        expect(buttons.evaluate().length, wantGrows.length, reason: 'as many buttons as the page drew');
        for (var i = 0; i < wantGrows.length; i++) {
          final wantGrow = wantGrows[i];
          final button = tester.widget<TableGrowButton>(buttons.at(i));
          expect(button.label, wantGrow['text']);
          hold('table $n ${button.label}', tester.getRect(buttons.at(i)), TableFixture.rect(wantGrow['rect'] as Map<String, dynamic>));
          final words = tester.renderObject<RenderTableWords>(find.descendant(of: buttons.at(i), matching: find.byType(TableWords)));
          hold('table $n ${button.label} words', words.wordsBox.shift(words.localToGlobal(Offset.zero)), TableFixture.rect((wantGrow['words'] as List).first as Map<String, dynamic>));
          if ((button.face.size - (wantGrow['size'] as num)).abs() > 0.001) problems.add('[${button.label}] size ${button.face.size}, the page ${wantGrow['size']}');
          if (button.face.style.color != t.colorOf(wantGrow['color'] as String)) problems.add('[${button.label}] ink ${button.face.style.color}, the page ${wantGrow['color']}');
          if (button.ruleColor != t.colorOf(wantGrow['border'] as String)) problems.add('[${button.label}] rule ${button.ruleColor}, the page ${wantGrow['border']}');
        }
        // `.cm-tableTools`: from the first button to the wrap's far gutter.
        if (want['tools'] != null) {
          final tools = TableFixture.rect(want['tools'] as Map<String, dynamic>);
          final first = tester.getRect(buttons.first);
          hold('table $n tools', Rect.fromLTRB(first.left, first.top, widened ? tools.right : ownWrap.right - first.left, first.bottom), tools);
        }
      }

      // ignore: avoid_print
      print('$name: ${lines.length} lines, ${wraps.length} tables, $cellCount cells, worst ${worst.toStringAsFixed(3)}');
      if (Platform.environment['EDITOR_SHOTS'] != null) {
        await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name.png'));
      }
      debugDisableShadows = true;
      expect(problems, isEmpty, reason: problems.take(10).join('\n'));
    });
  }
}
