// The words of a line stand on the rows of pixels the page's stand on.
//
// A line's BOX is held to the page's by test/editor/view/reference_test.dart, and was right while its ink was not:
// the paragraph says a line's baseline is its (rounded) height less its descent, and draws the glyphs at its
// ascent rounded to a whole pixel, which is somewhere else by up to three quarters of a pixel
// (lib/editor/looks/look.dart `inkBaseline`). On a phone that put every heading two device pixels high and every
// paragraph one low. Placed by what the paragraph said, these cases' headings stood one and two device pixels off
// the page here (headings-inter 1.98, headings-mixed 1.06, mixed-larger 1.10, a block of code 0.80); placed by
// where it inks, every line of every case is within a quarter of one.
//
// Held here against the page's own picture: tool/editor_reference.mjs keeps, beside each fixture's rectangles, the
// picture Chromium drew of it (test/editor/view/fixtures/<name>.png, two device pixels to one). For every line of
// every fixture the rows its ink falls on in that picture are found, and in the picture drawn here, and the two are
// compared by where the ink's weight is down the line (its centre, which a different way of smoothing a letter's
// edge does not move) and by its first and last rows. A line drawn one device pixel off the page fails.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ghost_md/editor/looks/look.dart';

import '../../support/ink.dart';
import '../../support/render.dart';
import 'support.dart';

/// Cases whose page was drawn with a face the app does not ship (test/editor/view/reference_test.dart `_notHeld`),
/// and the ones drawn with a caret or a selection, which are another picture by more than their words.
bool _held(String name) => !const <String>{'inline-inter', 'tasks-inter', 'mixed-inter', 'mixed-formatted-inter'}.contains(name) && !name.contains('caret') && !name.contains('selection') && !name.contains('peek') && name != 'full';

/// The fixture drawn here and the page's picture of it, line by line: what is wrong, and the furthest any line's
/// ink is from the page's. `scale` is the device pixels to one of the page's picture.
///
/// `phone` is for a page a DESKTOP's browser drew at a phone's density: a line with a face on it whose descent
/// rounds down there is left out, and counted. On Android and Linux the page gives such a face a device pixel of
/// its ascent to its descent, which lib/editor/looks/look.dart follows (it was measured on the phone's own
/// WebView, for sixty-six sizes of Inter) and a desktop's browser does not do: such a line stands a pixel
/// higher here than in that picture, and rightly.
Future<({List<String> faults, double worst, int lines, int left})> compared(WidgetTester tester, Fixture fixture, String picture, double scale, {required bool loud, bool phone = false}) async {
  final own = await Pixels.screen(tester, across: (fixture.width * scale).round());
  final page = await Pixels.file(tester, picture);
  expect(own.width, page.width);
  final faults = <String>[];
  var worst = 0.0, lines = 0, left = 0;
  final drawn = drawnLines(tester);
  bool givesAPixel(RunLook run) {
    final exact = FaceMetrics.of(run.style).descent * run.fontSize * scale;
    return exact.roundToDouble() < exact - 1e-4;
  }

  for (var i = 0; i < fixture.lines.length; i++) {
    final line = fixture.lines[i];
    final rect = Fixture.rect(line['rect'] as Map<String, dynamic>);
    final top = (rect.top * scale).floor(), bottom = (rect.bottom * scale).ceil();
    if (bottom > page.height || bottom > own.height) continue;
    final text = line['text'] as String;
    final label = '${(line['classes'] as List).join(' ')} "${text.length > 28 ? text.substring(0, 28) : text}"';
    // The line's box first: ink compared over rows that are not the line's says nothing.
    if (i < drawn.length) {
      final box = borderBox(drawn[i]);
      if ((box.top - rect.top).abs() > 0.5 || (box.bottom - rect.bottom).abs() > 0.5) faults.add('$label: its box is ${box.top.toStringAsFixed(2)} to ${box.bottom.toStringAsFixed(2)}, the page\'s ${rect.top} to ${rect.bottom}');
    }
    if (phone && i < drawn.length && (givesAPixel(drawn[i].spec.look.base) || drawn[i].spec.runs.any(givesAPixel))) {
      left += 1;
      continue;
    }
    final theirs = inked(page.ink(top, bottom), top), ours = inked(own.ink(top, bottom), top);
    if (theirs == null || ours == null) {
      if ((theirs == null) != (ours == null)) faults.add('$label: ${theirs == null ? 'the page has no ink and this has' : 'the page has ink and this has none'}');
      continue;
    }
    lines += 1;
    final off = ours.centre - theirs.centre;
    if (off.abs() > worst) worst = off.abs();
    final said = '$label: ink rows ${ours.first}-${ours.last} centred ${ours.centre.toStringAsFixed(2)}, the page ${theirs.first}-${theirs.last} centred ${theirs.centre.toStringAsFixed(2)} (${off >= 0 ? '+' : ''}${off.toStringAsFixed(2)})';
    if (loud) {
      // ignore: avoid_print
      print('  $said');
    }
    // Half a device pixel between the centres, or more than a row at either end, is a line a pixel off. A
    // line with an underline in it is judged by its ends alone: the rule under a link is a great weight of ink
    // on two rows, and the page draws it a row from where the text engine here does, the letters being where
    // the page's are (the first and last rows are the same).
    final ruled = (line['runs'] as List).cast<Map<String, dynamic>>().any((run) => (run['decoration'] as String).contains('underline'));
    if ((!ruled && off.abs() > 0.5) || (ours.first - theirs.first).abs() > 1 || (ours.last - theirs.last).abs() > 1) faults.add(said);
  }
  return (faults: faults, worst: worst, lines: lines, left: left);
}

void main() {
  setUpAll(loadAppFonts);

  final only = Platform.environment['EDITOR_CASE'];
  final loud = Platform.environment['INK_ROWS'] == 'say';
  for (final name in Fixture.names().where(_held)) {
    if (only != null && only.isNotEmpty && !name.contains(only)) continue;
    testWidgets('$name: each line\'s ink is on the rows the page\'s is', (tester) async {
      final fixture = Fixture.read(name);
      // One device pixel to one, as the page was laid out (support.dart `pumpFixture`); the picture is at two.
      await pumpFixture(tester, fixture, ratio: 1);
      final found = await compared(tester, fixture, 'test/editor/view/fixtures/$name.png', 2, loud: loud);
      // ignore: avoid_print
      print('$name: ${found.lines} lines, the worst ${found.worst.toStringAsFixed(2)} device px off the page${found.faults.isEmpty ? '' : '\n  ${found.faults.join('\n  ')}'}');
      expect(found.faults, isEmpty);
      debugDisableShadows = true;
    });
  }

  // The same on a phone's own pixels: the page drawn by a browser that is itself at 2.625 device pixels to one
  // (tool/editor_reference.mjs with GLYPH_DSF=2.625, test/editor/view/fixtures/device), so laid out in device
  // pixels, a face's ascent and a line's top on them, as a phone's WebView lays it out; and the note drawn here on
  // a screen of 2.625. Headings of every level, paragraphs, lists and a mixed note, in Maple Mono. Placed by what
  // the paragraph says, every paragraph and every list item stood a device pixel under the page's there, and the
  // headings up to two over or under (### 2.06, #### 1.97); placed by where it inks, the worst line is 0.27.
  // (Inter is not among them, nor a block of code: see `compared`. They are held at two device pixels above.)
  final device = Directory('test/editor/view/fixtures/device').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) => f.uri.pathSegments.last.replaceAll('.json', '')).toList()..sort();
  for (final name in device) {
    if (only != null && only.isNotEmpty && !name.contains(only)) continue;
    testWidgets('on a phone\'s pixels, $name: each line\'s ink is on the rows the page\'s is', (tester) async {
      final fixture = Fixture.read('device/$name');
      final ratio = (fixture.json['ratio'] as num).toDouble();
      await pumpFixture(tester, fixture, ratio: ratio, measuredAt: ratio);
      final found = await compared(tester, fixture, 'test/editor/view/fixtures/device/$name.png', ratio, loud: loud, phone: true);
      // ignore: avoid_print
      print('device/$name at $ratio: ${found.lines} lines (${found.left} left to a phone\'s own rule), the worst ${found.worst.toStringAsFixed(2)} device px off the page${found.faults.isEmpty ? '' : '\n  ${found.faults.join('\n  ')}'}');
      expect(found.lines, greaterThan(5));
      expect(found.faults, isEmpty);
      debugDisableShadows = true;
    });
  }
}
