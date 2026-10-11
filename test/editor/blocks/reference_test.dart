// Fenced code, maths, a diagram's box and a word too long for its line, held to the web page: every case
// tool/blocks_reference.mjs measured in Chromium (the web app's own CodeMirror with `drawnMaths()` and
// `drawnMermaid()`) drawn here, at a phone's width and the Fold's inner one, light and dark, and held four ways:
//
//   boxes    every line's box, every block's, a formula's own boxes and a diagram's words, reason and picture, to
//            half a pixel (the tolerance of test/editor/view/reference_test.dart); where the caret stands at every
//            position in the notes that have a word too long for a line
//   grounds  what is painted behind each line: its colour to a step of 255, the transparent borders that stand a
//            block clear of its neighbours, its padding, its corners, a quote's bar
//   inks     every letter's colour (to two steps of 255), weight and slope, which is what a code theme is; and
//            where each visual line starts and ends, which is where it wrapped
//   picture  this drawing laid over the page's own (test/support/page_picture.dart): the same size, the ground the
//            same colour wherever either has ground, and the ink within a limit
//
// THE LIMITS. Drawn right (2026-10-11) the forty-four cases measure no more than 4 pixels of ground in another
// colour than the page's (the limit is [groundLimit]), in runs no longer than 4 ([runLimit]); ink 0.10 to 1.67
// ([inkLimit]) and 12 to 32 at its worst place ([inkWorstLimit]). The group at the foot draws a note wrong on
// purpose nine ways and holds that each is caught, and says by what: a picture does not see everything (a corner
// four pixels tighter, a word in bold, a sloped line), and what it does not see the boxes, grounds and inks do.
//
// The pictures to look at: `EDITOR_LAID=1` writes build/blocks-compare/<name>.png, the page's, this one and their
// difference, with the ground that is off in red. `EDITOR_CASE=<part of a name>` runs some; `EDITOR_REPORT=<folder>`
// writes what differs, a file for each case.
//
// A diagram's picture is Mermaid's own, drawn by the app's diagram page in Chromium and kept beside the diagrams'
// tests (test/editor/diagrams/support.dart `PicturedBridge`): `DIAGRAM_FIXTURES=want flutter test <this file>`,
// then `node tool/diagram_fixtures.mjs`.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_math_fork/flutter_math.dart' show Math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/code/code_highlight.dart';
import 'package:ghost_md/editor/diagrams/diagrams.dart';
import 'package:ghost_md/editor/looks/look.dart' show LineContext, LookElement, LookEnv, LookRule, LookSheet, Props, debugPaintPixelRatio;
import 'package:ghost_md/editor/maths/maths.dart';
import 'package:ghost_md/editor/media/inline_box.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/projection.dart';

import '../../support/page_picture.dart';
import '../../support/render.dart';
import '../diagrams/support.dart' show HeldBridge, PicturedBridge, settleDiagrams;
import 'support.dart';

/// How far a rectangle may be from the page's, in logical pixels: the neighbouring references' (test/editor/view).
final double tolerance = double.tryParse(Platform.environment['EDITOR_TOLERANCE'] ?? '') ?? 0.5;

/// The most a picture's ink may differ from the page's, of 255 (test/support/page_picture.dart `Laid.ink`).
const double inkLimit = 2.0;

/// And the most it may differ at any one place.
const double inkWorstLimit = 40;

/// The most pixels of ground that may be another colour than the page's, and the longest they may run in a row or
/// down a column.
const int groundLimit = 60, runLimit = 24;

/// Cases the page drew that are not held, and why.
const Map<String, String> _notHeld = <String, String>{
  // In a phone's own pixels (fixtures/phone/, Chromium launched at 2.625), two of the seven are not held yet.
  // A heading of four visual lines is a device pixel taller a line on the page drawn there (182.87 against
  // 181.34): a line made of two boxes (the line's own and the heading's tighter one) depends on how a face's
  // descent is rounded, and the instrument is a Mac's Chromium, which rounds it to the nearest, where a phone's
  // gives a descent rounded down a pixel from the ascent (looks/look.dart `_box`, measured beside a phone).
  // Which is the phone's for this line can only be told on a phone.
  'phone/long-words': 'a Mac\'s Chromium rounds a face\'s descent another way than a phone\'s',
  // A diagram's words and reason are set in whole CSS pixels (lib/editor/media/inline_box.dart): every box is
  // within 0.37px, and the letters a device pixel from the page's, which the ink says (43 at its worst place).
  'phone/mermaid-missing': 'words in a box are set in CSS pixels, not the phone\'s',
  // The page's own note grows as wide as its widest formula: `.cm-content` is a flex item no narrower than what
  // is in it, and a `$$` block's `overflow-x: auto` does not make it any narrower, so every line of the note is
  // 834 px wide in a window of 390, the words run off the screen and the whole note scrolls sideways. That is
  // not what mathsDrawn.ts says it means ("scrolling sideways rather than running off it"), and it is not copied:
  // here the note keeps to the screen and the formula scrolls in its own box.
  'maths-overwide': 'the page lets a wide formula widen the whole note',
};

const Key _text = ValueKey<String>('cm-mermaidText');
const Key _why = ValueKey<String>('cm-mermaidWhy');
const Key _picture = ValueKey<String>('cm-mermaidPicture');

void main() {
  setUpAll(loadAppFonts);
  int? apply;
  setUp(() {
    // Every block read at once: the page's were, before it was measured.
    apply = CodeWorkBudget.apply;
    CodeWorkBudget.apply = null;
    rememberDiagramHeights = false;
    // The picture is taken at two device pixels to one, and an edge is put on a whole pixel of it.
    debugPaintPixelRatio = 2;
  });
  tearDown(() {
    CodeWorkBudget.apply = apply;
    debugPaintPixelRatio = null;
  });

  /// The case `name` drawn and held to the page: what differs, in words, and the picture laid over the page's.
  /// `sheets`, `codeLight` and `ratio` draw it wrong on purpose (rules over the editor's own, another code theme
  /// than the page's, edges on another pixel than the picture's).
  Future<({List<String> problems, Laid laid, (int, int) size, (int, int) pageSize, List<DiagramAsk> missing})> compare(WidgetTester tester, String name, {List<LookSheet> sheets = const <LookSheet>[], String? codeLight, double? ratio, String? shot}) async {
    final fixture = BlockFixture.read(name);
    final page = await pagePicture(tester, fixture.picture);
    final held = HeldBridge();
    final pictured = PicturedBridge();
    diagramStore = DiagramStore(bridge: fixture.mermaid == null ? pictured : held);
    final boundary = GlobalKey();
    debugPaintPixelRatio = ratio ?? fixture.pictureRatio;
    final view = await pumpBlocks(tester, fixture, tall: page.height / fixture.pictureRatio, boundary: boundary, sheets: sheets, codeLight: codeLight);
    if (fixture.mermaid == 'refused') {
      // Nothing to draw it: each ask, as it comes (one diagram is drawn at a time), is told so.
      for (var answered = 0, tries = 0; tries < 8; tries++) {
        for (; answered < held.asked.length; answered++) {
          held.fail(answered, '');
        }
        await tester.pump();
        await tester.pump();
      }
    } else if (fixture.mermaid == null) {
      await settleDiagrams(tester);
    }
    final problems = <String>[];
    var worst = 0.0;
    var heldBoxes = 0;
    void hold(String what, Rect own, Rect wanted, {bool across = false, bool down = false}) {
      final offs = <double>[if (!down) (own.left - wanted.left).abs(), if (!down) (own.right - wanted.right).abs(), if (!across) (own.top - wanted.top).abs(), if (!across) (own.bottom - wanted.bottom).abs()];
      final off = offs.reduce((a, b) => a > b ? a : b);
      heldBoxes += 1;
      if (off > worst) worst = off;
      if (off > tolerance) problems.add('[$what] ${show(own)}, the page ${show(wanted)}');
    }

    void near(String what, double own, num wanted, [double? within]) {
      if ((own - wanted).abs() > (within ?? tolerance)) problems.add('[$what] $own, the page $wanted');
    }

    // -- lines ---------------------------------------------------------------------------------------------------
    final withMaths = <int>{for (final formula in fixture.maths) formula['line'] as int};
    final lines = drawnLines(tester);
    expect(lines.length, fixture.lines.length, reason: 'as many lines as the page drew');
    for (var i = 0; i < lines.length; i++) {
      final want = fixture.lines[i], line = lines[i];
      final text = want['text'] as String;
      final label = '${want['from']} ${text.length > 24 ? text.substring(0, 24) : text}';
      expect(line.from, want['from'], reason: 'line $i starts where the page\'s does');
      final classes = line.spec.projection.className.split(' ').where((c) => c.isNotEmpty).toSet();
      final wantClasses = (want['classes'] as List).cast<String>().toSet();
      if (!(classes.length == wantClasses.length && classes.containsAll(wantClasses))) problems.add('[$label] classes $classes, the page $wantClasses');
      hold(label, borderBox(line), BlockFixture.rect(want['rect']));

      // What is painted behind it: the ground's colour, the transparent borders that stand it clear of its
      // neighbours, its padding, its corners and a quote's bar.
      final look = line.spec.look, ground = want['ground'] as Map<String, dynamic>;
      final wantGround = BlockFixture.colour(ground['color']);
      if (coloursApart(look.background ?? const Color(0x00000000), wantGround) > 1) problems.add('[$label] ground ${look.background}, the page $wantGround');
      final borders = (ground['borders'] as List).cast<num>(), padding = (ground['padding'] as List).cast<num>(), margins = (ground['margins'] as List).cast<num>();
      near('$label: border above', look.borderTop, borders[0]);
      near('$label: border below', look.borderBottom, borders[2]);
      near('$label: padding above', look.paddingTop, padding[0]);
      near('$label: padding below', look.paddingBottom, padding[2]);
      near('$label: margin before', look.marginStart, margins[0]);
      near('$label: margin after', look.marginEnd, margins[1]);
      final bar = ground['bar'] as num?;
      final ownBar = look.barColor != null && look.barWidth > 0 ? look.barWidth : null;
      if ((bar == null) != (ownBar == null) || (bar != null && (bar - ownBar!).abs() > tolerance)) problems.add('[$label] a bar $ownBar wide, the page ${bar ?? 'none'}');
      // The corner the eye sees: the border box's radius less the border (markdown.module.css `.lineCodeTop`).
      final corners = (ground['corners'] as List).map((each) => (each as List).cast<num>()).toList();
      Radius seen(List<num> corner, num border) => corner.every((r) => r == 0) ? Radius.zero : Radius.elliptical(corner[0].toDouble(), (corner.length > 1 ? corner[1] : corner[0]).toDouble() - border);
      final wantCorners = <Radius>[seen(corners[0], borders[0]), seen(corners[1], borders[0]), seen(corners[2], borders[2]), seen(corners[3], borders[2])];
      final ownCorners = <Radius>[look.topStart, look.topEnd, look.bottomEnd, look.bottomStart];
      for (var c = 0; c < 4; c++) {
        if ((ownCorners[c].x - wantCorners[c].x).abs() > tolerance || (ownCorners[c].y - wantCorners[c].y).abs() > tolerance) problems.add('[$label] corner $c ${ownCorners[c]}, the page ${wantCorners[c]}');
      }
      near('$label: type', look.base.fontSize, want['size'] as num, 0.02);

      // The words: letter for letter in the page's ink, weight and slope.
      final proj = line.spec.projection;
      final own = <(Color, int, bool)>[];
      final said = StringBuffer();
      for (var s = 0; s < proj.segments.length; s++) {
        final seg = proj.segments[s];
        if (seg.kind != SegmentKind.text || seg.displayLength == 0) continue;
        final run = line.spec.runs[s];
        final piece = proj.display.substring(seg.displayFrom, seg.displayTo);
        said.write(piece);
        for (var n = 0; n < piece.length; n++) {
          own.add((run.color, (run.style.fontWeight ?? FontWeight.w400).value, run.style.fontStyle == FontStyle.italic));
        }
      }
      final wanted = <(Color, int, bool)>[];
      final wantSaid = StringBuffer();
      for (final run in (want['runs'] as List).cast<Map<String, dynamic>>()) {
        final piece = run['text'] as String;
        wantSaid.write(piece);
        for (var n = 0; n < piece.length; n++) {
          wanted.add((BlockFixture.colour(run['color']), int.parse(run['weight'] as String), run['style'] == 'italic'));
        }
      }
      if (said.toString() != wantSaid.toString()) {
        problems.add('[$label] says "$said", the page "$wantSaid"');
      } else {
        for (var n = 0; n < own.length; n++) {
          if (coloursApart(own[n].$1, wanted[n].$1) > 2 || own[n].$2 != wanted[n].$2 || own[n].$3 != wanted[n].$3) {
            problems.add('[$label] letter $n "${said.toString()[n]}" ${own[n]}, the page ${wanted[n]}');
            break;
          }
        }
      }

      // Where it wrapped: each visual line's first and last letter where the page's are. (A line with a
      // formula in it is held by the formula's own boxes.)
      if (!withMaths.contains(want['from']) && text.isNotEmpty) {
        final rows = <Rect>[];
        for (final each in (want['words'] as List).map(BlockFixture.rect)) {
          if (each.width == 0) continue;
          final at = rows.indexWhere((row) => each.center.dy > row.top && each.center.dy < row.bottom);
          if (at < 0) {
            rows.add(each);
          } else {
            rows[at] = rows[at].expandToInclude(each);
          }
        }
        final origin = line.localToGlobal(Offset.zero);
        final ownRows = <Rect>[for (final each in line.rectsForRange(0, line.to - line.from)) each.shift(origin)];
        if (ownRows.length != rows.length) {
          problems.add('[$label] ${ownRows.length} visual lines, the page ${rows.length}');
        } else {
          for (var r = 0; r < rows.length; r++) {
            hold('$label: visual line $r', ownRows[r], rows[r], across: true);
          }
        }
      }
    }

    // Where the caret stands at every position, from either side: a line that wraps at another place has its
    // carets on another line.
    var worstCaret = 0.0;
    for (final at in fixture.coords) {
      final pos = at['pos'] as int;
      for (final side in const <int>[1, -1]) {
        final want = at[side > 0 ? 'after' : 'before'];
        if (want == null) continue;
        final wanted = BlockFixture.rect(want);
        final own = view.coordsAtPos(pos, side);
        if (own == null) {
          problems.add('coordsAtPos($pos, $side) null, the page ${show(wanted)}');
          continue;
        }
        final off = [(own.left - wanted.left).abs(), (own.top - wanted.top).abs(), (own.bottom - wanted.bottom).abs()].reduce((a, b) => a > b ? a : b);
        if (off > worstCaret) worstCaret = off;
        if (off > tolerance) problems.add('coordsAtPos($pos, $side) ${show(own)}, the page ${show(wanted)}');
      }
    }

    // -- formulas and diagrams -------------------------------------------------------------------------------------
    final formulas = <(DrawnMaths, Element)>[for (final element in find.byType(DrawnMaths).evaluate()) (element.widget as DrawnMaths, element)];
    Rect boxOf(Element element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    /// The formula's own drawing: KaTeX's boxes, one for the whole or one for each piece of a broken one.
    List<(Rect, double)> mathsOf(Element under) => <(Rect, double)>[
      for (final each in find.descendant(of: find.byElementPredicate((e) => identical(e, under)), matching: find.byType(Math)).evaluate()) (boxOf(each), (each.widget as Math).options?.fontSize ?? 0),
    ];

    // A formula in a line is drawn piece by piece, a widget for each: the pieces after a formula's first.
    final later = <Element, List<Element>>{};
    void holdKatex(String what, Element under, Map<String, dynamic> katex) {
      final bases = (katex['bases'] as List).cast<Map<String, dynamic>>();
      final own = <(Rect, double)>[...mathsOf(under), for (final piece in later[under] ?? const <Element>[]) ...mathsOf(piece)];
      if (own.isEmpty) {
        problems.add('[$what] not drawn, the page drew it');
        return;
      }
      near('$what: size', own.first.$2, katex['size'] as num, 0.02);
      // The formula's own box: each of KaTeX's bases from its height above the baseline to its depth below (its
      // strut), and as wide as the base.
      Rect inked(Map<String, dynamic> base) {
        final all = BlockFixture.rect(base['rect']);
        // (A column of row numbers has no strut of its own: its box.)
        final strut = base['strut'] == null ? all : BlockFixture.rect(base['strut']);
        return Rect.fromLTRB(all.left, strut.top, all.right, strut.bottom);
      }

      final formula = bases.where((b) => b['tag'] != true).map(inked).toList();
      final tags = bases.where((b) => b['tag'] == true).map(inked).toList();
      // What stands at the far side: the page has one box for a formula's `\tag` and one for a whole column of
      // row numbers; here each number is a box of its own.
      final numbers = tags.isEmpty ? 0 : own.length - 1;
      final ownFormula = own.take(own.length - numbers).map((m) => m.$1).toList();
      if (formula.isEmpty || ownFormula.isEmpty) return;
      // Row by row, where a formula in a line was broken onto two.
      List<Rect> rowsOf(List<Rect> boxes) {
        final rows = <Rect>[];
        for (final each in boxes) {
          final at = rows.indexWhere((row) => each.top < row.bottom - 1 && each.bottom > row.top + 1);
          if (at < 0) {
            rows.add(each);
          } else {
            rows[at] = rows[at].expandToInclude(each);
          }
        }
        return rows;
      }

      final wantRows = rowsOf(formula), ownRows = rowsOf(ownFormula);
      if (wantRows.length != ownRows.length) {
        problems.add('[$what] on ${ownRows.length} rows, the page ${wantRows.length}');
      } else {
        for (var r = 0; r < wantRows.length; r++) {
          // A formula with something at its far side is given the whole width here, to set that there: its
          // place across is the picture's to hold.
          hold('$what: row $r', ownRows[r], wantRows[r], down: tags.isNotEmpty);
        }
      }
      if (tags.isNotEmpty) {
        final all = own.skip(own.length - numbers).map((m) => m.$1).reduce((a, b) => a.expandToInclude(b));
        final wanted = tags.reduce((a, b) => a.expandToInclude(b));
        // One number: its own box. A column of them: where the column stands, across.
        hold('$what: its number${numbers > 1 ? 's' : ''}', all, wanted, across: numbers > 1);
      }
    }

    void holdFailed(String what, DrawnMaths formula, Element under, Map<String, dynamic> wanted) {
      final texts = find.descendant(of: find.byElementPredicate((e) => identical(e, under)), matching: find.byType(Text)).evaluate();
      if (texts.isEmpty) {
        problems.add('[$what] drawn, the page could not');
        return;
      }
      final shown = texts.first.widget as Text;
      if (shown.data != wanted['said']) problems.add('[$what] says "${shown.data}", the page "${wanted['said']}"');
      near('$what: type', shown.style!.fontSize!, wanted['size'] as num, 0.02);
      if (coloursApart(shown.style!.color!, BlockFixture.colour(wanted['color'])) > 2) problems.add('[$what] ink ${shown.style!.color}, the page ${wanted['color']}');
      // Underlined with dots: where the dots are, and how thick, is the picture's to hold.
      final dotted = find.descendant(of: find.byElementPredicate((e) => identical(e, under)), matching: find.byType(DottedUnderline)).evaluate().isNotEmpty;
      if (dotted != (wanted['decoration'] == 'underline' && wanted['decorationStyle'] == 'dotted')) problems.add('[$what] underlined with dots: $dotted, the page ${wanted['decoration']} ${wanted['decorationStyle']}');
    }

    // In the lines.
    final inLines = <(DrawnMaths, Element)>[];
    for (final each in formulas.where((f) => !f.$1.block)) {
      if ((each.$1.piece ?? 0) == 0) {
        inLines.add(each);
      } else {
        later.putIfAbsent(inLines.last.$2, () => <Element>[]).add(each.$2);
      }
    }
    if (inLines.length != fixture.maths.length) {
      problems.add('${inLines.length} formulas in the lines, the page ${fixture.maths.length}');
    } else {
      for (var n = 0; n < inLines.length; n++) {
        final want = fixture.maths[n];
        final (formula, element) = inLines[n];
        final what = 'formula ${want['pos']}';
        if (formula.display != (want['display'] as bool)) problems.add('[$what] set apart: ${formula.display}, the page ${want['display']}');
        if (want['display'] == true) {
          // `.cm-mathsBlock` inside its line: under the line box CodeMirror's buffer makes before it.
          final own = find.descendant(of: find.byElementPredicate((e) => identical(e, element)), matching: find.byType(LayoutBuilder)).evaluate();
          if (own.isNotEmpty) hold('$what: its box', boxOf(own.first), BlockFixture.rect(want['box']));
        }
        if (want['drawn'] == true) {
          holdKatex(what, element, want['katex'] as Map<String, dynamic>);
        } else {
          holdFailed(what, formula, element, want);
          // The words as typed, where the page's span of them is: across, and no taller than the line.
          hold('$what: its words', boxOf(element), BlockFixture.rect((want['rects'] as List).first), across: true);
        }
      }
    }

    // Between the lines.
    final blocks = tester.renderObjectList<RenderEditorBlock>(find.byType(EditorBlock)).toList()..sort((a, b) => a.spec.from - b.spec.from);
    final setApart = formulas.where((f) => f.$1.block).toList();
    final diagrams = find.byType(DrawnDiagram).evaluate().toList();
    expect(blocks.length, fixture.blocks.length, reason: 'as many blocks as the page drew');
    var nextFormula = 0, nextDiagram = 0;
    for (var n = 0; n < blocks.length; n++) {
      final want = fixture.blocks[n];
      final kind = ((want['classes'] as List).first as String);
      final what = '$kind ${want['from']}';
      hold(what, blocks[n].localToGlobal(Offset.zero) & blocks[n].size, BlockFixture.rect(want['rect']));
      if (kind == 'cm-mathsBlock') {
        final (formula, element) = setApart[nextFormula++];
        if (want['drawn'] == true) {
          holdKatex(what, element, want['katex'] as Map<String, dynamic>);
        } else {
          holdFailed(what, formula, element, want);
        }
      } else if (kind == 'cm-mermaid') {
        final diagram = diagrams[nextDiagram++];
        final under = find.byElementPredicate((e) => identical(e, diagram));
        final parts = <String, Map<String, dynamic>>{for (final part in (want['parts'] as List).cast<Map<String, dynamic>>()) part['name'] as String: part};
        for (final (name, key) in const <(String, Key)>[('cm-mermaidText', _text), ('cm-mermaidWhy', _why), ('svg', _picture)]) {
          final own = find.descendant(of: under, matching: find.byKey(key)).evaluate();
          final wanted = parts[name];
          if ((wanted == null) != own.isEmpty) {
            problems.add('[$what] $name ${own.isEmpty ? 'not here' : 'here'}, the page ${wanted == null ? 'has none' : 'has it'}');
            continue;
          }
          if (wanted == null) continue;
          if (name == 'svg') {
            hold('$what: its picture', boxOf(own.first), BlockFixture.rect(wanted['rect']));
            continue;
          }
          final shown = own.first.widget as InlineWords;
          if (shown.text != wanted['said']) problems.add('[$what] $name says "${shown.text}", the page "${wanted['said']}"');
          near('$what: $name type', shown.style.fontSize!, wanted['size'] as num, 0.02);
          if (coloursApart(shown.style.color!, BlockFixture.colour(wanted['color'])) > 2) problems.add('[$what] $name ink ${shown.style.color}, the page ${wanted['color']}');
          // Its box, down the page: from the top of its first line to the foot of its last. (Across, the box on
          // the page is as wide as the block and the words here as wide as they are: its left edge.)
          final words = (wanted['words'] as List).map(BlockFixture.rect).reduce((a, b) => a.expandToInclude(b));
          final box = boxOf(own.first), all = BlockFixture.rect(wanted['rect']);
          hold('$what: $name', Rect.fromLTRB(box.left, box.top, box.left, box.bottom), Rect.fromLTRB(words.left, all.top, words.left, all.bottom));
          // And each line's letters, in their own box in it (the face's ascent and descent): the first.
          final inner = (own.first.renderObject! as RenderInlineWords).contentRect.shift(box.topLeft);
          hold('$what: $name, its first line\'s letters', Rect.fromLTRB(inner.left, inner.top, inner.left, inner.bottom), Rect.fromLTRB(words.left, BlockFixture.rect((wanted['words'] as List).first).top, words.left, BlockFixture.rect((wanted['words'] as List).first).bottom));
        }
      }
    }

    // -- the picture -----------------------------------------------------------------------------------------------
    // The caret is the browser's own on the page (glyphTheme.ts sets only its colour), and a picture of a page
    // has none; where it stands is held by test/editor/view's `coordsAtPos`.
    view.caretOpacity.value = 0;
    await tester.pump();
    final mine = await ownPicture(tester, boundary, ratio: fixture.pictureRatio);
    final laid = lay(page, mine);
    if (Platform.environment['EDITOR_LAID'] != null) await writeLaid(tester, 'build/blocks-compare/${shot ?? name}.png', page, mine);
    debugDisableShadows = true;
    // ignore: avoid_print
    print('${shot ?? name}: ${lines.length} lines, $heldBoxes boxes held, worst ${worst.toStringAsFixed(3)}${fixture.coords.isEmpty ? '' : ', carets worst ${worstCaret.toStringAsFixed(3)}'}; picture $laid');
    final report = Platform.environment['EDITOR_REPORT'];
    if (report != null && report.isNotEmpty) {
      File('$report/$name.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync(problems.join('\n'));
    }
    return (problems: problems, laid: laid, size: (mine.width, mine.height), pageSize: (page.width, page.height), missing: pictured.missing);
  }

  for (final name in BlockFixture.names(Platform.environment['EDITOR_CASE'])) {
    testWidgets('$name: the lines, their grounds and inks, the blocks and the picture as the page has them', skip: _notHeld.containsKey(name), (tester) async {
      final held = await compare(tester, name);
      final laid = held.laid;
      expect(held.missing, isEmpty, reason: 'a diagram with no picture kept for it: DIAGRAM_FIXTURES=want, then node tool/diagram_fixtures.mjs');
      expect(held.problems, isEmpty, reason: held.problems.take(10).join('\n'));
      // (To a pixel, where the screen is not a whole number of them across: 475 at 2.625 is 1246.875.)
      expect((held.size.$1 - held.pageSize.$1).abs() <= 1 && (held.size.$2 - held.pageSize.$2).abs() <= 1, isTrue, reason: 'the picture is the page\'s size: ${held.size}, the page ${held.pageSize}');
      expect(laid.off, lessThanOrEqualTo(groundLimit), reason: 'ground in another colour than the page\'s: $laid');
      expect(laid.worstRun, lessThanOrEqualTo(runLimit), reason: 'ground in another colour than the page\'s, in a run: $laid');
      expect(laid.ink, lessThan(inkLimit), reason: 'the picture\'s ink, over the page\'s: $laid');
      // In a phone's pixels a line's words stand a device pixel from the page's until they are placed by the
      // page's own baseline (the editor's branch `baseline`): the worst place is let half as much again.
      expect(laid.inkWorst, lessThan(name.startsWith('phone/') ? inkWorstLimit * 1.5 : inkWorstLimit), reason: 'the picture\'s ink, over the page\'s, at its worst: $laid');
    });
  }

  // -- the limits, proven ------------------------------------------------------------------------------------------
  // Each of these draws a note wrong on purpose, in one way a person would see, and holds that it is caught, and
  // by what: the ground or the ink of the picture over its limit, or a fact of the look that is no longer the
  // page's. What each measured (2026-10-11) is beside it; drawn right the same case measures ground off 0,
  // ink 0.38, worst 15.9.
  group('drawn wrong on purpose', () {
    LookSheet over(String name, {void Function(Props p, LookEnv e)? apply, void Function(Props p, LookEnv e)? box, bool Function(LookElement element, LineContext context)? when}) =>
        LookSheet('wrong', <LookRule>[LookRule(name, apply, classes: 9, box: box, when: when)]);

    // ground off 484,581
    testWidgets('a block\'s ground a shade lighter (the ink at 5% in the page, not 7%): the ground', (tester) async {
      final held = await compare(tester, 'code-light-pastel', shot: 'wrong-shade', sheets: <LookSheet>[over('lineCode', box: (p, e) => p.background = ((_) => Color.lerp(e.t.color('glacier-bg'), e.t.color('glacier-text'), 0.05)!))]);
      expect(held.laid.off, greaterThan(groundLimit * 100));
    });

    // ground off 976, longest run 17
    testWidgets('a block\'s corners square: the ground', (tester) async {
      final held = await compare(
        tester,
        'code-light-pastel',
        shot: 'wrong-square',
        sheets: <LookSheet>[
          over(
            'lineCodeTop',
            box: (p, e) => p
              ..topStart = Radius.zero
              ..topEnd = Radius.zero,
          ),
          over(
            'lineCodeFoot',
            box: (p, e) => p
              ..bottomStart = Radius.zero
              ..bottomEnd = Radius.zero,
          ),
        ],
      );
      expect(held.laid.off, greaterThan(groundLimit * 4));
    });

    // ground off 0: a corner four pixels tighter is inside what two engines' edges differ by. The look's own
    // corner is what holds it.
    testWidgets('a block\'s corners at the kit\'s medium radius, not its large: the corner the look says', (tester) async {
      Radius tighter(Props p, LookEnv e) => Radius.elliptical(e.t.radius('md'), e.t.radius('md') + p.em(0.5));
      final held = await compare(
        tester,
        'code-light-pastel',
        shot: 'wrong-radius',
        sheets: <LookSheet>[
          over(
            'lineCodeTop',
            box: (p, e) => p
              ..topStart = tighter(p, e)
              ..topEnd = tighter(p, e),
          ),
          over(
            'lineCodeFoot',
            box: (p, e) => p
              ..bottomStart = tighter(p, e)
              ..bottomEnd = tighter(p, e),
          ),
        ],
      );
      expect(held.problems.where((problem) => problem.contains('corner')), isNotEmpty);
    });

    // ground off 6,156, longest run 684 (the block's width)
    testWidgets('edges on a third of a pixel, as a test\'s window has them: a seam between the lines of a block', (tester) async {
      final held = await compare(tester, 'code-light-pastel', shot: 'wrong-seam', ratio: 3);
      expect(held.laid.off, greaterThan(groundLimit * 50));
      expect(held.laid.worstRun, greaterThan(runLimit * 10));
    });

    // ground off 336, longest run 121; and the look's own bar
    testWidgets('a quote\'s bar down a block of code in the quote: the ground, and the bar the look says', (tester) async {
      final held = await compare(
        tester,
        'code-places',
        shot: 'wrong-bar',
        sheets: <LookSheet>[
          over(
            'lineCode',
            when: (el, c) => el.has('lineQuote'),
            box: (p, e) => p
              ..barWidth = e.t.len('glacier-shape-accent-edge')
              ..barColor = e.t.color('glacier-border-strong'),
          ),
        ],
      );
      expect(held.laid.off, greaterThan(groundLimit * 3));
      expect(held.laid.worstRun, greaterThan(runLimit * 3));
      expect(held.problems.where((problem) => problem.contains('a bar')), isNotEmpty);
    });

    // ground off 7,258; ink 1.18, worst 65.2
    testWidgets('the words of a block four pixels further in: the ground and the ink', (tester) async {
      final held = await compare(
        tester,
        'code-light-pastel',
        shot: 'wrong-in',
        sheets: <LookSheet>[
          over(
            'lineCode',
            box: (p, e) => p
              ..paddingStart = p.em(0.85) + 4
              ..paddingEnd = p.em(0.85) - 4,
          ),
        ],
      );
      expect(held.laid.off, greaterThan(groundLimit * 10));
      expect(held.laid.inkWorst, greaterThan(inkWorstLimit));
    });

    // ink 0.99, worst 87.7; and a letter's ink
    testWidgets('another code theme (GitHub\'s where the page chose Pastel): the ink, and a letter\'s colour', (tester) async {
      final held = await compare(tester, 'code-light-pastel', shot: 'wrong-theme', codeLight: 'github');
      expect(held.laid.inkWorst, greaterThan(inkWorstLimit));
      expect(held.problems.where((problem) => problem.contains('letter')), isNotEmpty);
    });

    // ink 0.49, worst 34.1: under the limit, as a bold word among twenty lines is. A letter's weight holds it.
    testWidgets('keywords in bold where the theme sets them at the reading weight: a letter\'s weight', (tester) async {
      final held = await compare(tester, 'code-light-pastel', shot: 'wrong-bold', sheets: <LookSheet>[over('codeKeyword', apply: (p, e) => p.weight = 700)]);
      expect(held.problems.where((problem) => problem.contains('letter')), isNotEmpty);
    });

    // ink 0.38, worst 15.9: a sloped line of eleven letters is not ink a picture can tell. A letter's slope holds it.
    testWidgets('comments upright where the page slopes them: a letter\'s slope', (tester) async {
      final held = await compare(tester, 'code-light-pastel', shot: 'wrong-upright', sheets: <LookSheet>[over('codeComment', apply: (p, e) => p.italic = false)]);
      expect(held.problems.where((problem) => problem.contains('letter')), isNotEmpty);
    });

    // A formula's surd an em of the text tall where the type is smaller (the package as it was) is held by KaTeX's
    // own heights (test/editor/maths/katex_test.dart); a formula alone on its line without the empty lines round
    // it, and a diagram's words on the text engine's own lines, by their boxes above.
  });
}
