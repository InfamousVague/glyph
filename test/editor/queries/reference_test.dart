// Drawn queries held to the web page: every case test/editor/queries/fixtures/reference.mjs measured in Chromium
// (the web app's own CodeMirror with `queries()` over a fixed library) drawn here, and each line's box, the card's,
// and every named piece inside it (lib/editor/queries/query_layout.dart `Part`) compared with the page's element of
// the same class, in order, to half a pixel. The timeline is not held: it is another drawing
// (lib/editor/queries/query_gantt.dart).
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/query/query.dart';

import '../../support/render.dart';
import '../view/support.dart' show borderBox;
import 'support.dart';

/// How far a rectangle may be from the page's, in logical pixels.
final double tolerance = double.tryParse(Platform.environment['EDITOR_TOLERANCE'] ?? '') ?? 0.5;

/// Pieces whose box on the page is the letters' own (an inline span), where the piece here is its whole line; and a
/// table's cells, each as tall as its row on the page and as its own words here, in a row as tall as the page's.
/// Held from side to side only.
const Set<String> _acrossOnly = <String>{'keyCell', 'key', 'cm-tag', 'td', 'nameCell'};

/// A lane's cards: the page's list fills its lane to the foot; the list here is as tall as its cards, in a lane as
/// tall as the page's. Held from side to side and at its top.
const Set<String> _topOnly = <String>{'cards'};

/// Pieces that are not inside a table's or a board's own scroller.
const Set<String> _outside = <String>{'query', 'head', 'title', 'count', 'views', 'view', 'edit', 'group', 'groupHead', 'tableScroll', 'board', 'totals', 'total', 'split', 'grip'};

/// Pieces the page has that are held by another piece, or are not boxes of their own here.
const Set<String> _notPieces = <String>{'svg', 'picked', 'span', 'strong', 'thead', 'tbody', 'tfoot', 'tr', 'tables', 'section', 'header', 'time', 'cm-mermaid'};

String _plain(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(3);

void main() {
  setUpAll(loadAppFonts);

  final only = Platform.environment['EDITOR_CASE'];
  for (final name in PageFixture.names(queryFixtures)) {
    if (only != null && only.isNotEmpty && !name.contains(only)) continue;
    testWidgets('$name: lines, the card and its pieces where the page has them', (tester) async {
      final fixture = PageFixture.read(queryFixtures, name);
      // With the open note at the fixture's own day, not the day this runs (support.dart `PageFixture.open`).
      final library = <QueryNote>[...fixture.library, fixture.open];
      final asked = Asked();
      await pumpQueries(tester, fixture.doc, options: optionsOver(() => library, asked, adds: fixture.add ? false : null), theme: fixture.theme, readOnly: fixture.readOnly, caret: fixture.caret, today: fixture.today, locale: fixture.locale, shadows: true);
      final problems = <String>[];
      var slip = 0.0;
      var worst = 0.0;
      var held = 0;
      void hold(String what, Rect own, Rect page, {bool across = false, bool top = false}) {
        final offs = <double>[(own.left - page.left).abs(), (own.right - page.right).abs(), if (!across) (own.top - page.top).abs(), if (!across && !top) (own.bottom - page.bottom).abs()];
        final off = offs.reduce((a, b) => a > b ? a : b);
        held += 1;
        if (off > worst) worst = off;
        if (off > tolerance) problems.add('[$what] ${_show(own)}, the page ${_show(page)}');
      }

      Finder across() => find.descendant(of: drawn, matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right));
      final pageScroll = fixture.blocks.isEmpty
          ? null
          : (fixture.blocks.first['parts'] as List).cast<Map<String, dynamic>>().where((part) => part['scroll'] != null && ((part['names'] as List).contains('board') || (part['names'] as List).contains('tableScroll'))).firstOrNull;
      if (pageScroll != null && ((pageScroll['scroll'] as Map)['left'] as num) > 0) {
        // The board or the table scrolled along as far as the page's was.
        final wanted = ((pageScroll['scroll'] as Map)['left'] as num).toDouble();
        final scrollable = tester.state<ScrollableState>(across().last);
        scrollable.position.jumpTo(wanted.clamp(0, scrollable.position.maxScrollExtent));
        await tester.pump();
        if ((scrollable.position.pixels - wanted).abs() > 1) problems.add('[scroll] ${scrollable.position.pixels}, the page $wanted');
        // The page keeps a scroll offset to the whole pixel, and at its end that is up to half a pixel past where the
        // content ends; what is scrolled is held from where the page's stood.
        slip = scrollable.position.pixels - wanted;
      }

      if (fixture.compose != null) {
        await tester.tap(said('Add a ticket to ${fixture.compose}'));
        await tester.pump();
        await tester.pump();
      }

      final gantt = fixture.blocks.isNotEmpty && ((fixture.blocks.first['parts'] as List).first as Map)['data'] is Map && (((fixture.blocks.first['parts'] as List).first as Map)['data'] as Map)['data-show'] == 'gantt';
      final lines = drawnLines(tester);
      expect(lines.length, fixture.lines.length, reason: 'as many lines as the page drew');
      for (var i = 0; i < lines.length; i++) {
        final want = fixture.lines[i];
        expect(lines[i].from, want['from'], reason: 'line $i starts where the page\'s does');
        // A timeline is as tall as its own drawing, and the lines after it start where that ends.
        if (gantt && i >= 2) continue;
        hold('line ${want['from']}', borderBox(lines[i]), PageFixture.rect(want['rect']));
      }

      expect(drawn.evaluate().length, fixture.blocks.length, reason: 'as many queries drawn as on the page');
      final notHeld = <String>{};
      for (var n = 0; n < fixture.blocks.length; n++) {
        final block = fixture.blocks[n];
        final under = drawn.at(n);
        if (!gantt) hold('block $n', boxOf(tester, under), PageFixture.rect(block['rect']));
        final page = PageFixture.partsOf(block);
        for (final MapEntry(key: name, value: wanted) in page.entries) {
          if (_notPieces.contains(name) || name.startsWith('_mark') || name.startsWith('lucide')) continue;
          // The timeline's own drawing is another: only the card round it is held.
          if (gantt && name == 'gantt') continue;
          final own = name == 'split' || name == 'grip' ? find.descendant(of: under, matching: find.byKey(ValueKey<String>('board-$name'))) : parts(name, under);
          final count = own.evaluate().length;
          if (count == 0) {
            notHeld.add(name);
            continue;
          }
          if (count != wanted.length) {
            problems.add('[$name] $count here, ${wanted.length} on the page');
            continue;
          }
          for (var i = 0; i < count; i++) {
            if (gantt && name == 'query') continue;
            hold('$name $i', boxOf(tester, own.at(i)).shift(Offset(_outside.contains(name) ? 0 : slip, 0)), PageFixture.rect(wanted[i]['rect']), across: _acrossOnly.contains(name) || wanted[i]['display'] == 'inline', top: _topOnly.contains(name));
          }
        }
      }

      // The picture, to look at beside the page's (fixtures/<name>.png): `EDITOR_SHOTS=1 flutter test --update-goldens`.
      if (Platform.environment['EDITOR_SHOTS'] != null) {
        await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name.png'));
      }
      debugDisableShadows = true;

      // ignore: avoid_print
      print('$name: $held held, worst ${_plain(worst)}${notHeld.isEmpty ? '' : ', not pieces here: ${notHeld.join(' ')}'}');
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}

String _show(Rect r) => '[${_plain(r.left)},${_plain(r.top)} ${_plain(r.width)}x${_plain(r.height)}]';
