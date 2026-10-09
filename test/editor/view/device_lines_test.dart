// A line of the note on a phone (lib/editor/looks/look.dart `_box`): the pixel a face's ascent and descent are
// rounded to, and half a line's leading floored to, is the device's, because a phone's page is laid out at its
// screen's own scale. Held by the page itself.
//
// The page: the Tauri app's own WebView (Chrome 133) on an emulator set to the Fold's inner display on its side
// (wm size 2448x1848 at 420 dpi: a window of 933 x 704 at 2.625), "How to format a note" open, 2026-10-09. For the
// first run of each line, a Range's client rectangle (its content area: the face's ascent and descent) against its
// `.cm-line`'s, both times the device pixel ratio:
//
//     size      line-height   content area   starts from its own line-height's top   the line (less its padding)
//     42.6954   46.111        148            -14                                   122.88   # the note's name
//     18.7778   30.0445        65              6                                    78.87   a paragraph
//     34.7478   38.9175       120             -9                                   105.87   ##
//     28.2918   33.9502        98             -5                                    92.87   ###
//     23.045    29.9586        80             -1                                    82.87   ####
//
// each a whole number of device pixels, where the same rule worked in logical pixels (the page as a desktop's
// browser at 1 has it, which test/editor/view/reference_test.dart holds) put a heading two device pixels low on the
// phone and a paragraph one or two high.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/looks/look.dart';
import 'package:ghost_md/editor/looks/markdown_look.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<Look> lookAt(WidgetTester tester, double measuredAt) async {
    late Tokens tokens;
    await pumpApp(
      tester,
      size: const Size(933, 704),
      ratio: 2.625,
      measuredAt: measuredAt,
      home: Builder(
        builder: (context) {
          tokens = context.tokens;
          return const SizedBox.expand();
        },
      ),
    );
    debugDisableShadows = true;
    // The page's own sizes there (`--app-body`, `--app-h1` to `--app-h6`), as its computed styles gave them.
    final env = LookEnv(t: tokens, body: 18.7778, headings: const <double>[42.6954, 34.7478, 28.2918, 23.045, 18.7778, 16.7], gutter: 0, devicePixelRatio: 2.625);
    return Look(env, <LookSheet>[markdownLook]);
  }

  testWidgets('a phone’s lines are rounded in the phone’s own pixels', (tester) async {
    final look = await lookAt(tester, 2.625);
    const ratio = 2.625;
    final plain = look.line(LookElement(null));
    RunLook heading(int level) => look.run(look.line(LookElement('lineH$level')), <LookElement>[LookElement('h$level')]);
    void held(RunLook run, double area, double starts, double line, String what) {
      expect((run.ascent + run.descent) * ratio, closeTo(area, 1e-6), reason: '$what: its content area');
      expect((run.above - run.ascent) * ratio, closeTo(starts, 1e-6), reason: '$what: where its content area starts');
      expect((run.above + run.below) * ratio, closeTo(line, 0.05), reason: '$what: its line');
    }

    // The last number is the line's own height on the page, in device pixels, less its padding: a heading's is
    // taller than its line-height, the paragraph's strut reaching under its words.
    held(plain.base, 65, 6, 78.87, 'a paragraph');
    held(heading(1), 148, -14, 122.88, 'the name');
    held(heading(2), 120, -9, 105.87, 'a section');
    held(heading(3), 98, -5, 92.87, 'three hashes');
    held(heading(4), 80, -1, 82.87, 'four hashes');
  });

  testWidgets('and a page measured at a ratio of 1 keeps the whole logical pixels it was measured in', (tester) async {
    final look = await lookAt(tester, 1);
    final base = look.line(LookElement(null)).base;
    expect(base.ascent, base.ascent.roundToDouble());
    expect(base.descent, base.descent.roundToDouble());
    expect(base.above, base.above.roundToDouble());
  });
}
