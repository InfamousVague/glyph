// The twelve marks held to the web page: tool/editor_reference.mjs drew the marks' note with the web app's whole
// `Editor` in Chromium, and here it is drawn with the marks' extensions over the base editor. Each line's box and
// classes, and the rectangle of every `<span>` the page gave a mark (`cm-formatLook`, `cm-wispFormat`,
// `cm-textEffect`, `cm-textEffectAbove`), are compared to half a pixel. Pictures are written beside the page's.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/marks/marks.dart';
import 'package:ghost_md/editor/state/state.dart' show Extension;
import 'package:ghost_md/editor/view/view_mode.dart';

import '../../support/render.dart';
import 'support.dart';

const double tolerance = 0.5;

void main() {
  setUpAll(loadAppFonts);

  final only = Platform.environment['EDITOR_CASE'];
  for (final name in const <String>['marks-mixed', 'marks-formatted', 'marks-dark', 'marks-readonly', 'marks-caret']) {
    if (only != null && only.isNotEmpty && !name.contains(only)) continue;
    testWidgets('$name: lines and marks where the page has them', (tester) async {
      MarkClock.hold = 0;
      addTearDown(() => MarkClock.hold = null);
      final fixture = Measured.read('marks', name);
      final view = await pumpMeasured(tester, fixture, formats: marks, more: <Extension>[markExtensions(marks)], reducedMotion: true, shaders: true);
      // Outside the formatted view the effects' delimiters are drawn, and they are emoji: Apple's on the page (21px
      // to a flame at this size), and in a test no emoji face at all. From the first line with one on it the words
      // wrap elsewhere, so only what stands above it is held to the page there; the formatted case holds it all.
      final until = fixture.display == NoteView.formatted ? fixture.doc.length + 1 : fixture.doc.indexOf('🔥');
      final lines = drawnLines(tester);
      final problems = <String>[];
      expect(lines.length, fixture.lines.length);
      var worstBox = 0.0, worstMark = 0.0;
      for (var i = 0; i < lines.length; i++) {
        final want = fixture.lines[i];
        if ((want['from'] as int) >= until) continue;
        final box = borderBox(lines[i]), wantBox = Measured.rect(want['rect'] as Map<String, dynamic>);
        final off = worst(box, wantBox);
        if (off > worstBox) worstBox = off;
        if (off > tolerance) problems.add('line ${want['from']} box $box, the page $wantBox');
        final classes = lines[i].spec.projection.className.split(' ').where((c) => c.isNotEmpty).toSet();
        final wantClasses = (want['classes'] as List).cast<String>().toSet();
        if (!(classes.length == wantClasses.length && classes.containsAll(wantClasses))) problems.add('line ${want['from']} classes $classes, the page $wantClasses');
      }
      // Every span the page drew for a mark, by the document range under it.
      var held = 0;
      for (final mark in fixture.drawn) {
        final pos = mark['pos'] as int?, text = mark['text'] as String;
        if (pos == null || text.isEmpty || pos >= until) continue;
        final classes = (mark['classes'] as List).cast<String>();
        final wantRects = (mark['rects'] as List).cast<Map<String, dynamic>>().map(Measured.rect).toList();
        final rects = spanRects(view, pos, pos + text.length);
        if (rects.length != wantRects.length) {
          problems.add('${classes.join('.')} "$text" at $pos: ${rects.length} rectangles, the page ${wantRects.length}');
          continue;
        }
        for (var i = 0; i < rects.length; i++) {
          final off = worst(rects[i], wantRects[i]);
          if (off > worstMark) worstMark = off;
          if (off > tolerance) problems.add('${classes.join('.')} "$text" at $pos: ${rects[i]}, the page ${wantRects[i]}');
        }
        // And the class on the run, as the page's span has it.
        final line = view.lineAt(pos)!;
        final seg = line.spec.projection.segmentAt(pos - line.from, 1);
        final own = <String>{for (final m in seg?.marks ?? const []) ...(m.attrs['class'] ?? '').split(' ')};
        for (final c in classes) {
          if (!own.contains(c)) problems.add('"$text" at $pos has no class $c (has $own)');
        }
        held += 1;
      }
      // ignore: avoid_print
      print('$name: ${lines.length} lines, worst box ${worstBox.toStringAsFixed(3)}; $held marks, worst ${worstMark.toStringAsFixed(3)}');
      await shot(tester, name);
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}
