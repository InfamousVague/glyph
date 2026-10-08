// The inline items held to the web page: tool/editor_reference.mjs drew the items' note with the web app's whole
// `Editor` in Chromium, and here it is drawn with the marks' and the items' extensions over the base editor. Each
// line's box and classes, the rectangle of every `<span>` the page gave an item drawn in the words (a tag, a
// counter, a choice's box, a footnote's marker, a link, an anchor), and the box of every widget (a field's chip, a
// heading's count, a sum's answer, the bookmark's ribbon, the hint in an open heading) are compared to half a
// pixel. Pictures are written beside the page's.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/editor/items/inline_box.dart';
import 'package:ghost_md/editor/items/items.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/state/state.dart' show Extension;
import 'package:ghost_md/editor/view/line.dart';

import '../../support/render.dart';
import '../marks/support.dart';

const double tolerance = 0.5;

/// Cases measured on the page that cannot be drawn the same yet, and why.
const Map<String, String> _notHeld = <String, String>{
  // A to-do's and a choice's box are in the kit's code face, JetBrains Mono, which the app does not ship
  // (test/editor/view/reference_test.dart has the same gap).
  'items-inter': 'needs JetBrains Mono',
};

/// Things the page draws that are known to be drawn elsewhere here, by where they start in the items' note.
const Map<int, String> _elsewhere = <int, String>{
  // `[0/50]` starts a visual line. The page's chip is one box with its padding inside it, so the padding starts
  // the line and the count stands 6px in; here the padding is a gap of its own before the mark, which stays at
  // the end of the line above, and the count starts the line (lib/editor/items/counters.dart).
  190: 'a chip that starts a wrapped line keeps its leading padding on the line above',
};

Rect boxOf(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset.zero) & box.size;
}

void main() {
  setUpAll(loadAppFonts);

  final only = Platform.environment['EDITOR_CASE'];
  for (final name in const <String>['items-mixed', 'items-formatted', 'items-readonly', 'items-caret', 'items-peek', 'items-inter', 'open-mixed']) {
    if (only != null && only.isNotEmpty && !name.contains(only)) continue;
    testWidgets('$name: lines, marks and widgets where the page has them', skip: _notHeld.containsKey(name), (tester) async {
      final fixture = Measured.read('items', name);
      final view = await pumpMeasured(
        tester,
        fixture,
        formats: marks,
        more: <Extension>[
          markExtensions(marks),
          itemExtensions(wiki: fixture.peek ? null : WikiOptions(known: (title) => title.toLowerCase().startsWith('known'), open: (title, [anchor]) {}), peek: fixture.peek, openHeading: name.startsWith('open')),
          fieldsToday.of(() => fixture.today),
          fieldsLocale.of(fixture.json['locale'] as String),
        ],
      );
      final lines = drawnLines(tester);
      final problems = <String>[];
      // With the caret on a line of fields the page shows their signs, which are emoji (no emoji face in a test):
      // that line wraps elsewhere, so only what stands above it is held.
      // And on a card, drawn narrow and small, the line with the shortcode's emoji on it is one line here and two on
      // the page, by the width of Apple's party popper.
      final until = fixture.caret != null
          ? fixture.doc.lastIndexOf('\n', fixture.caret!) + 1
          : (fixture.peek ? fixture.doc.lastIndexOf('\n', fixture.doc.indexOf(':tada:')) + 1 : fixture.doc.length + 1);
      expect(lines.length, fixture.lines.length);
      var worstBox = 0.0, worstMark = 0.0, held = 0;
      for (var i = 0; i < lines.length; i++) {
        final want = fixture.lines[i];
        if ((want['from'] as int) >= until) continue;
        final box = borderBox(lines[i]), wantBox = Measured.rect(want['rect'] as Map<String, dynamic>);
        final off = worst(box, wantBox);
        if (off > worstBox) worstBox = off;
        if (off > tolerance) problems.add('line ${want['from']} "${want['text']}" box $box, the page $wantBox');
        final classes = lines[i].spec.projection.className.split(' ').where((c) => c.isNotEmpty).toSet();
        final wantClasses = (want['classes'] as List).cast<String>().toSet();
        if (!(classes.length == wantClasses.length && classes.containsAll(wantClasses))) problems.add('line ${want['from']} classes $classes, the page $wantClasses');
      }

      void hold(String what, Rect rect, Rect want) {
        final off = worst(rect, want);
        if (off > worstMark) worstMark = off;
        if (off > tolerance) problems.add('$what: $rect, the page $want');
        held += 1;
      }

      // The widgets, each kind in document order on both sides.
      final chips = find.byType(FieldChip).evaluate().toList();
      final counts = find.byType(InlineWidgetHost).evaluate().where((e) => (e.widget as InlineWidgetHost).widget is CountWidget).toList();
      final answers = find.byType(InlineWidgetHost).evaluate().where((e) => (e.widget as InlineWidgetHost).widget is AnswerWidget).toList();
      final hints = find.byType(InlineWidgetHost).evaluate().where((e) => (e.widget as InlineWidgetHost).widget is HintWidget).toList();
      var chip = 0, count = 0, answer = 0, hint = 0;
      Rect textIn(Element host) => boxOf(tester, find.descendant(of: find.byElementPredicate((e) => identical(e, host)), matching: find.byType(RichText)).first);

      for (final mark in fixture.drawn) {
        final pos = mark['pos'] as int?, text = mark['text'] as String;
        final classes = (mark['classes'] as List).cast<String>();
        if (pos == null || pos >= until) continue;
        if (!fixture.peek && _elsewhere.containsKey(pos) && !name.startsWith('open')) continue;
        final want = Measured.rect(mark['rect'] as Map<String, dynamic>);
        final size = (mark['size'] as num).toDouble();
        final label = '${classes.join('.')} "$text" at $pos';
        if (classes.contains('cm-field')) {
          if (chip >= chips.length) {
            problems.add('$label: no chip drawn');
            continue;
          }
          final host = chips[chip++];
          hold(label, boxOf(tester, find.descendant(of: find.byElementPredicate((e) => identical(e, host)), matching: find.byType(InlineBox)).first), want);
          final look = (host.widget as FieldChip).look;
          final said = '${look.initial ?? ''}${look.name ?? ''}${look.text}';
          if (said != text) problems.add('$label: the chip says "$said"');
          if (look.tone != (mark['attrs'] as Map)['data-tone']) problems.add('$label: tone ${look.tone}');
        } else if (classes.contains('cm-headingCount')) {
          if (count >= counts.length) {
            problems.add('$label: no count drawn');
            continue;
          }
          final host = counts[count++];
          expect(find.descendant(of: find.byElementPredicate((e) => identical(e, host)), matching: find.text(text)), findsOneWidget);
          hold(label, textIn(host), want);
        } else if (classes.contains('cm-sumAnswer')) {
          hold(label, textIn(answers[answer++]), want);
        } else if (classes.contains('cm-openHint')) {
          hold(label, textIn(hints[hint++]), want);
        } else if (classes.contains('cm-bookmarkMark')) {
          hold(label, boxOf(tester, find.descendant(of: find.byType(InlineWidgetHost), matching: find.byType(AppIcon)).last), want);
        } else if (!fixture.peek && classes.any(const <String>{'cm-tag', 'cm-counter', 'cm-choiceBox', 'cm-footMark', 'cm-wiki', 'cm-itemAnchor', 'cm-itemRef'}.contains)) {
          // A span over the note's own text. A tag's and a counter's reach past their words by their padding (and
          // a counter's border).
          final wantRects = (mark['rects'] as List).cast<Map<String, dynamic>>().map(Measured.rect).toList();
          var rects = spanRects(view, pos, pos + text.length);
          final pad = classes.contains('cm-tag') ? 0.3 * size : (classes.contains('cm-counter') ? 0.3 * size + 1 : 0.0);
          final edge = classes.contains('cm-counter') ? 1.0 : 0.0;
          rects = <Rect>[for (final r in rects) Rect.fromLTRB(r.left - pad, r.top - edge, r.right + pad, r.bottom + edge)];
          // The page gives a span with marks inside it a rectangle for each piece: the whole is what is held.
          Rect union(List<Rect> all, double top) => all.where((r) => (r.top - top).abs() < 6).reduce((a, b) => a.expandToInclude(b));
          for (final r in rects) {
            final page = union(wantRects, r.top);
            // A footnote's marker is two spans, the parser's link inside the marker's, each smaller and higher
            // than the one round it; the letters are the inner one's, and the page's rectangle the outer's: across
            // is held here, and the letters' own box by `coordsAtPos` in the lines' test.
            hold(label, r, classes.contains('cm-footMark') ? Rect.fromLTRB(page.left, r.top, page.right, r.bottom) : page);
          }
          final line = view.lineAt(pos)!;
          final seg = line.spec.projection.segmentAt(pos - line.from, 1);
          final own = <String>{for (final m in seg?.marks ?? const []) ...(m.attrs['class'] ?? '').split(' ')};
          for (final c in classes) {
            if (!own.contains(c)) problems.add('$label has no class $c (has $own)');
          }
        }
      }
      // ignore: avoid_print
      print('$name: ${lines.length} lines, worst box ${worstBox.toStringAsFixed(3)}; $held drawn things, worst ${worstMark.toStringAsFixed(3)}');
      await shot(tester, name);
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}
