// Drawn boards held to the web page: every case test/editor/boards/fixtures/reference.mjs measured in Chromium (the
// web app's own CodeMirror with `drawnBoards()`) drawn here, and each line's box, each board's, each column's, its
// head's, its lane's, each card's and every part of a card compared with the page's to half a pixel; the colours
// too.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/art/wisp_foot.dart';
import 'package:ghost_md/editor/boards/boards.dart';
import 'package:ghost_md/editor/items/field_chips.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import '../view/support.dart' show borderBox;
import 'support.dart';

/// How far a rectangle may be from the page's, in logical pixels.
const double tolerance = 0.5;

/// Cases measured on the page that cannot be drawn the same yet, and why.
const Map<String, String> _notHeld = <String, String>{};

/// Lines of the note itself that are not held in a case, by where they start. In Inter the long item under the
/// board (its anchor drawn small at its end, items/anchors.dart) wraps to six lines here and five on the page: the
/// note's own line, not the board's.
const Map<String, Set<int>> _linesNotHeld = <String, Set<int>>{
  'cards-inter': <int>{107},
};

String _plain(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

void main() {
  setUpAll(loadAppFonts);

  final only = Platform.environment['EDITOR_CASE'];
  for (final name in BoardFixture.names()) {
    if (only != null && only.isNotEmpty && !name.contains(only)) continue;
    testWidgets('$name: lines, boards, lanes, cards and their parts where the page has them', skip: _notHeld.containsKey(name), (tester) async {
      final fixture = BoardFixture.read(name);
      final view = await pumpBoardFixture(tester, fixture);
      final problems = <String>[];
      var worst = 0.0;
      var held = 0;
      void hold(String what, Rect own, Rect page, {bool height = true}) {
        final offs = <double>[(own.left - page.left).abs(), (own.top - page.top).abs(), (own.right - page.right).abs(), if (height) (own.bottom - page.bottom).abs()];
        final off = offs.reduce((a, b) => a > b ? a : b);
        held += 1;
        if (off > worst) worst = off;
        if (off > tolerance) problems.add('[$what] $own, the page $page');
      }

      void same(String what, Object? own, Object? page) {
        if (own != page) problems.add('[$what] $own, the page $page');
      }

      // What the case did to the page's board first.
      final boards = fixture.boards;
      if (fixture.scroll != null) {
        final scrollable = tester.state<ScrollableState>(find.descendant(of: find.byType(DrawnBoardBox), matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right)).first);
        scrollable.position.jumpTo(fixture.scroll!.clamp(0, scrollable.position.maxScrollExtent));
        await tester.pump();
      }
      if (fixture.laneAtFoot) {
        final scrollable = tester.state<ScrollableState>(find.descendant(of: keyed('stack0'), matching: find.byType(Scrollable)).first);
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pump();
        await tester.pump();
      }
      if (fixture.compose != null) {
        // The page's board scrolled the field into view; so here, to wherever it did.
        final along = tester.state<ScrollableState>(find.descendant(of: find.byType(DrawnBoardBox), matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right)).first);
        along.position.jumpTo((boards.first['scrollLeft'] as num).toDouble());
        await tester.pump();
        await tester.tap(said('Add a card to ${(boards.first['columns'] as List)[fixture.compose!]['name']['text']}'));
        await tester.pump();
        if (fixture.typed != null) {
          await tester.enterText(find.byType(EditableText), fixture.typed!);
          await tester.pump(const Duration(milliseconds: 200));
        }
        along.position.jumpTo((boards.first['scrollLeft'] as num).toDouble());
        await tester.pump();
      }
      TestGesture? finger;
      if (fixture.hold != null) {
        final card = boxOf(tester, cardOf(fixture.hold!));
        finger = await holdAt(tester, card.topLeft + const Offset(40, 14));
        if (fixture.held != null && (fixture.held! - (card.topLeft + const Offset(40, 14))).distance > 1) {
          await finger.moveTo(fixture.held!);
          await tester.pump();
        }
      }

      final t = tester.element(find.byType(SingleChildScrollView).first).tokens;
      Color ink(Object? css) => t.colorOf(css! as String);

      final lines = drawnLines(tester);
      expect(lines.length, fixture.lines.length, reason: 'as many lines as the page drew');
      // A line with a field's emoji in it is not held, nor any after it: a test has no colour emoji face, and the
      // line wraps where its boxes put it. The boards are above them.
      var emoji = false;
      for (var i = 0; i < lines.length; i++) {
        final want = fixture.lines[i];
        expect(lines[i].from, want['from'], reason: 'line $i starts where the page\'s does');
        emoji = emoji || (want['text'] as String).runes.any((rune) => rune >= 0x2300);
        if (_linesNotHeld[name]?.contains(want['from']) ?? false) continue;
        if (!emoji) hold('line ${want['from']}', borderBox(lines[i]), BoardFixture.rect(want['rect']));
      }

      final wraps = find.byType(DrawnBoardBox);
      expect(wraps.evaluate().length, boards.length, reason: 'as many boards drawn as on the page');
      for (var n = 0; n < boards.length; n++) {
        final want = boards[n];
        final wrap = wraps.at(n);
        final look = BoardLook.of(tester.element(wrap), view.look);
        hold('wrap $n', boxOf(tester, wrap), BoardFixture.rect(want['rect']));
        final across = find.descendant(of: wrap, matching: find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal));
        hold('board $n', boxOf(tester, across), BoardFixture.rect(want['board']));
        final position = tester.state<ScrollableState>(find.descendant(of: across, matching: find.byType(Scrollable)).first).position;
        if ((position.maxScrollExtent - ((want['scrollWidth'] as num) - (want['clientWidth'] as num))).abs() > 1) {
          problems.add('[board $n] scrolls ${position.maxScrollExtent}, the page ${(want['scrollWidth'] as num) - (want['clientWidth'] as num)}');
        }
        if ((look.em - (want['size'] as num)).abs() > 0.001) problems.add('[board $n] type ${look.em}, the page ${want['size']}');
        same('board $n ink', look.ink, ink(want['color']));
        hold('split $n', boxOf(tester, find.descendant(of: wrap, matching: keyed('board-split'))), BoardFixture.rect((want['split'] as Map)['rect']));
        hold('grip $n', boxOf(tester, find.descendant(of: wrap, matching: keyed('board-grip'))), BoardFixture.rect((want['grip'] as Map)['rect']));
        same('split $n ink', look.splitInk, ink((want['split'] as Map)['background']));
        same('grip $n ink', look.gripInk, ink((want['grip'] as Map)['background']));
        same('split $n says', tester.getSemantics(find.descendant(of: wrap, matching: said('Board height'))).value, (want['split'] as Map)['now']);

        final columns = (want['columns'] as List).cast<Map<String, dynamic>>();
        for (var c = 0; c < columns.length; c++) {
          final column = columns[c];
          final at = 'board $n lane $c';
          hold(at, boxOf(tester, keyed('column$c')), BoardFixture.rect(column['rect']));
          same('$at says', tester.getSemantics(keyed('column$c')).label.split('\n').first, column['label']);
          same('$at ground', look.columnGround, ink(column['background']));
          hold('$at head', boxOf(tester, keyed('head$c')), BoardFixture.rect(column['head']));
          final wantName = column['name'] as Map<String, dynamic>;
          hold('$at name', boxOf(tester, keyed('name$c')), BoardFixture.rect(wantName['rect']));
          hold('$at name words', wordLines(tester, keyed('name$c')).single, BoardFixture.rect((wantName['lines'] as List).single));
          same('$at name ink', look.nameFace.style.color, ink(wantName['color']));
          same('$at name weight', '${look.nameFace.style.fontWeight!.value}', wantName['weight']);
          same('$at name family', look.nameFace.style.fontFamily, wantName['family']);
          if ((look.nameFace.size - (wantName['size'] as num)).abs() > 0.001) problems.add('[$at name] size ${look.nameFace.size}, the page ${wantName['size']}');
          final wantCount = column['count'] as Map<String, dynamic>;
          hold('$at count', boxOf(tester, keyed('count$c')), BoardFixture.rect(wantCount['rect']));
          hold('$at count words', wordLines(tester, find.descendant(of: keyed('count$c'), matching: find.byType(BoardWords))).single, BoardFixture.rect((wantCount['lines'] as List).single));
          same('$at count ground', look.countGround, ink(wantCount['background']));
          same('$at count weight', '${look.countFace.style.fontWeight!.value}', wantCount['weight']);
          final wantAdd = column['add'] as Map<String, dynamic>;
          hold('$at +', boxOf(tester, keyed('add$c')), BoardFixture.rect(wantAdd['rect']));
          hold('$at + icon', boxOf(tester, find.descendant(of: keyed('add$c'), matching: find.byType(BoardIcon))), BoardFixture.rect(wantAdd['icon']));
          same('$at + ground', look.addGround, ink(wantAdd['background']));
          same('$at + ink', look.ink2, ink(wantAdd['color']));
          expect(said(wantAdd['label'] as String), findsOneWidget);

          final wantStack = column['stack'] as Map<String, dynamic>;
          hold('$at stack', boxOf(tester, keyed('stack$c')), BoardFixture.rect(wantStack['rect']));
          final lane = tester.state<ScrollableState>(find.descendant(of: keyed('stack$c'), matching: find.byType(Scrollable)).first).position;
          final pageRoom = (wantStack['scrollHeight'] as num) - (wantStack['clientHeight'] as num);
          // A held card's lanes are not held to the pixel: the page's copy of the card is not the card's own size.
          if (fixture.hold == null && (lane.maxScrollExtent - pageRoom).abs() > 1) problems.add('[$at stack] scrolls ${lane.maxScrollExtent}, the page $pageRoom');
          if (fixture.hold == null && (lane.pixels - (wantStack['scrollTop'] as num)).abs() > 1) problems.add('[$at stack] at ${lane.pixels}, the page ${wantStack['scrollTop']}');

          // More below than the lane shows: its foot fades, over the length the smoke's lip gives it.
          final foot = find.descendant(of: keyed('stack$c'), matching: find.byType(WispFoot));
          same('$at foot', foot.evaluate().isNotEmpty, want['sized']);
          if (want['sized'] == true) {
            same('$at more below', tester.widget<WispFoot>(foot).more, wantStack['more']);
            if (wantStack['fade'] != null) same('$at fade', '${_plain(wispFootFade(boxOf(tester, keyed('stack$c')).height.roundToDouble()))}px', wantStack['fade']);
          }

          // The cards, in the order the lane has them.
          final wantCards = (column['cards'] as List).cast<Map<String, dynamic>>();
          for (final card in wantCards) {
            final id = card['id'] as String;
            final where = '$at card $id';
            if (card['lifted'] == true) {
              hold('$where gap', boxOf(tester, inColumn(c, keyed('gap'))), BoardFixture.rect(card['rect']));
              same('$where gap ground', look.liftedGround, ink(card['background']));
              continue;
            }
            expect(inColumn(c, cardOf(id)), findsOneWidget, reason: '$where is in this lane');
            hold(where, boxOf(tester, cardOf(id)), BoardFixture.rect(card['rect']));
            same('$where ground', look.paper, ink(card['background']));
            final widget = tester.widget<BoardCard>(cardOf(id));
            same('$where done', widget.card.item?.done == true, card['done']);
            same('$where gone', widget.card.item == null, card['gone']);
            if (card['tick'] != null) {
              final tick = card['tick'] as Map<String, dynamic>;
              hold('$where tick', boxOf(tester, inCard(id, 'tick')), BoardFixture.rect(tick['rect']));
              expect(find.descendant(of: cardOf(id), matching: said(tick['label'] as String)), findsOneWidget, reason: '$where tick says so');
              final check = find.descendant(of: inCard(id, 'tick'), matching: find.byType(BoardIcon));
              same('$where check shown', check.evaluate().isNotEmpty, tick['shown'] == 'visible');
              if (check.evaluate().isNotEmpty) hold('$where check', boxOf(tester, check), BoardFixture.rect(tick['check']));
              same('$where tick edge', card['done'] == true ? look.tickDone : look.tickEdge, ink(tick['border']));
            } else {
              expect(inCard(id, 'tick'), findsNothing);
            }
            if (card['dot'] != null) {
              hold('$where dot', boxOf(tester, inCard(id, 'dot')), BoardFixture.rect((card['dot'] as Map)['rect']));
              same('$where dot ink', look.ink3, ink((card['dot'] as Map)['background']));
            }
            final words = card['words'] as Map<String, dynamic>;
            final ownWords = tester.renderObject<RenderBoardWords>(inCard(id, 'words'));
            hold('$where words', boxOf(tester, inCard(id, 'words')), BoardFixture.rect(words['rect']));
            // The page's `Range` answers every line of the words, the ones the clamp hides too, and a wrapped
            // line's hanging space as a box of its own: the lines that show are the first of each top, three at
            // most.
            final shown = BoardFixture.rect(words['rect']);
            final pageLines = <Rect>[];
            for (final r in (words['lines'] as List)) {
              final box = BoardFixture.rect(r);
              if (box.top >= shown.bottom - 1) break;
              if (pageLines.isNotEmpty && (pageLines.last.top - box.top).abs() < 1) continue;
              pageLines.add(box);
            }
            final ownLines = ownWords.wordBoxes;
            final face0 = ownWords.laid.face.style;
            if (ownLines.length != pageLines.length) {
              problems.add('[$where words] ${ownLines.length} lines ${ownWords.laid.said}, the page ${pageLines.length}');
            } else {
              for (var l = 0; l < ownLines.length; l++) {
                // A clamped last line ends in the ellipsis here; the page's range still measures the words under it.
                final clamped = l == ownLines.length - 1 && ownWords.laid.said.last.endsWith('…');
                // And a line that wraps is measured with the space it ends on, which is not words here.
                final wraps = l < ownLines.length - 1;
                if (clamped) {
                  hold('$where words line $l', Rect.fromLTRB(ownLines[l].left, ownLines[l].top, pageLines[l].right, ownLines[l].bottom), pageLines[l]);
                } else if (wraps) {
                  final space = pageLines[l].right - ownLines[l].right;
                  if (space < -tolerance || space > 0.7 * look.em) problems.add('[$where words line $l] ends at ${ownLines[l].right}, the page ${pageLines[l].right}');
                  hold('$where words line $l', Rect.fromLTRB(ownLines[l].left, ownLines[l].top, pageLines[l].right, ownLines[l].bottom), pageLines[l]);
                } else if (face0.fontStyle == FontStyle.italic && !look.coding) {
                  // Slanted here from the upright letters, where the page has the face's own italic: a card whose
                  // item is gone ends within a pixel of the page's.
                  if ((ownLines[l].right - pageLines[l].right).abs() > 1) problems.add('[$where words line $l] ends at ${ownLines[l].right}, the page ${pageLines[l].right}');
                  hold('$where words line $l', Rect.fromLTRB(ownLines[l].left, ownLines[l].top, pageLines[l].right, ownLines[l].bottom), pageLines[l]);
                } else {
                  hold('$where words line $l', ownLines[l], pageLines[l]);
                }
              }
            }
            final face = ownWords.laid.face.style;
            same('$where words ink', face.color, ink(words['color']));
            same('$where words slant', face.fontStyle == FontStyle.italic ? 'italic' : 'normal', words['style']);
            same('$where words struck', face.decoration == TextDecoration.lineThrough ? 'line-through' : 'none', words['decoration']);
            same('$where words family', face.fontFamily, words['family']);
            expect(find.descendant(of: cardOf(id), matching: said(words['label'] as String)), findsOneWidget, reason: '$where words say so');

            final chips = find.descendant(of: cardOf(id), matching: find.byType(FieldChip));
            if (card['fields'] == null) {
              expect(chips, findsNothing, reason: '$where has no chips');
            } else {
              final wantChips = ((card['fields'] as Map)['chips'] as List).cast<Map<String, dynamic>>();
              hold('$where fields', boxOf(tester, inCard(id, 'fields')), BoardFixture.rect((card['fields'] as Map)['rect']));
              expect(chips.evaluate().length, wantChips.length, reason: '$where has as many chips');
              for (var k = 0; k < wantChips.length; k++) {
                // A chip on a page that cannot be edited is a span on the page, and on its own shorter line.
                hold('$where chip $k', boxOf(tester, chips.at(k)), BoardFixture.rect(wantChips[k]['rect']));
                same('$where chip $k tone', tester.widget<FieldChip>(chips.at(k)).look.tone, wantChips[k]['tone']);
                same('$where chip $k says', tester.widget<FieldChip>(chips.at(k)).look.label, wantChips[k]['label']);
              }
            }
            if (card['linked'] != null) {
              hold('$where mark', boxOf(tester, inCard(id, 'linked')), BoardFixture.rect((card['linked'] as Map)['rect']));
              same('$where mark is', tester.widget<BoardIcon>(inCard(id, 'linked')).name, (card['linked'] as Map)['name']);
            } else {
              expect(inCard(id, 'linked'), findsNothing);
            }
            final more = card['more'] as Map<String, dynamic>;
            hold('$where more', boxOf(tester, inCard(id, 'more')), BoardFixture.rect(more['rect']));
            hold('$where more icon', boxOf(tester, find.descendant(of: inCard(id, 'more'), matching: find.byType(BoardIcon))), BoardFixture.rect(more['icon']));
            final moves = (card['moves'] as List).cast<Map<String, dynamic>>();
            for (final (m, by) in <int>[-1, 1].indexed) {
              hold('$where move $by', boxOf(tester, inCard(id, 'move$by')), BoardFixture.rect(moves[m]['rect']));
              hold('$where move $by icon', boxOf(tester, find.descendant(of: inCard(id, 'move$by'), matching: find.byType(BoardIcon))), BoardFixture.rect(moves[m]['icon']));
              same('$where move $by ink', tester.widget<BoardIcon>(find.descendant(of: inCard(id, 'move$by'), matching: find.byType(BoardIcon))).color, moves[m]['disabled'] == true ? look.moveInkOff : look.moveInk);
            }
          }
          expect(inColumn(c, find.byType(BoardCard)).evaluate().length, wantCards.where((card) => card['lifted'] != true).length, reason: '$at holds as many cards');

          // The empty place.
          final empty = column['empty'] as Map<String, dynamic>;
          final place = inColumn(c, find.byType(BoardEmpty));
          same('$at empty shown', place.evaluate().isNotEmpty, empty['shown']);
          if (empty['shown'] == true) {
            // Under a lane's cards the place for a held card sits wherever the page's copy of the card pushed it.
            final under = empty['none'] != true;
            if (!under) hold('$at empty', boxOf(tester, place), BoardFixture.rect(empty['rect']));
            if (empty['icon'] != null) {
              hold('$at empty picture', boxOf(tester, inColumn(c, keyed('empty-icon'))), BoardFixture.rect((empty['icon'] as Map)['rect']));
              same('$at empty picture is', tester.widget<BoardIcon>(inColumn(c, keyed('empty-icon'))).name, (empty['icon'] as Map)['name']);
            }
            if (empty['words'] != null) {
              same('$at empty says', tester.widget<BoardWords>(inColumn(c, keyed('empty-words'))).text, (empty['words'] as Map)['text']);
              hold('$at empty words', wordLines(tester, inColumn(c, keyed('empty-words'))).single, BoardFixture.rect(((empty['words'] as Map)['lines'] as List).single));
            }
            if (empty['drop'] != null) {
              same('$at drop says', tester.widget<BoardWords>(inColumn(c, keyed('drop'))).text, (empty['drop'] as Map)['text']);
              final own = wordLines(tester, inColumn(c, keyed('drop'))).single, page = BoardFixture.rect(((empty['drop'] as Map)['lines'] as List).single);
              if (under) {
                hold('$at drop words', Rect.fromLTWH(own.left, page.top, own.width, own.height), page);
              } else {
                hold('$at drop words', own, page);
              }
            }
            if ((look.emptyFace.size - (empty['size'] as num)).abs() > 0.001) problems.add('[$at empty] size ${look.emptyFace.size}, the page ${empty['size']}');
            same('$at empty ink', look.emptyFace.style.color, ink(empty['color']));
          }

          // The + field.
          final compose = column['compose'] as Map<String, dynamic>?;
          final form = inColumn(c, find.byType(BoardComposer));
          same('$at + field open', form.evaluate().isNotEmpty, compose != null);
          if (compose != null) {
            hold('$at + field', boxOf(tester, form), BoardFixture.rect(compose['rect']));
            hold('$at + field box', boxOf(tester, inColumn(c, keyed('compose-tick'))), BoardFixture.rect((compose['tick'] as Map)['rect']));
            hold('$at + field words', boxOf(tester, inColumn(c, keyed('compose-field'))), BoardFixture.rect((compose['field'] as Map)['rect']));
            final add = compose['add'] as Map<String, dynamic>;
            hold('$at + field Add', boxOf(tester, inColumn(c, keyed('compose-add'))), BoardFixture.rect(add['rect']));
            hold('$at + field Add words', wordLines(tester, find.descendant(of: inColumn(c, keyed('compose-add')), matching: find.byType(BoardWords))).single, BoardFixture.rect((add['lines'] as List).single));
            same('$at + field Add waits', !tester.state<BoardComposerState>(form).ready, add['disabled']);
            same('$at + field ground', look.paper, ink(compose['background']));
            same('$at + field box edge', look.composeTickEdge, ink((compose['tick'] as Map)['border']));
            if (add['disabled'] == true) same('$at + field Add ground', look.composeAddGround(ready: false), ink(add['background']));
          }
        }
      }

      // ignore: avoid_print
      print('$name: $held rectangles, the worst ${worst.toStringAsFixed(3)} px off${problems.isEmpty ? '' : ', ${problems.length} problems'}');
      if (Platform.environment['EDITOR_SHOTS'] != null) {
        await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name.png'));
      }
      await finger?.up();
      // Past the drop's two taps of the motor.
      await tester.pump(const Duration(milliseconds: 200));
      debugDisableShadows = true;
      expect(problems, isEmpty, reason: problems.take(40).join('\n'));
    });
  }
}
