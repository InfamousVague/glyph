// Pictures of the wisp in a note's editor (test/editor_ai/shots/), to be looked at beside what the page's filter
// does (art/WispText.module.css, editor/svgFilters.ts): letters thin, bent and low in smoke, settling crisp exactly
// where the plain text sits.
//
// - `arrival-<theme>-<n>`: one phrase at 0, 12, 30, 50 and 70 hundredths of its arc and settled, on paper and on
//   the dark page. The phrase is one piece of the opening reveal (`revealWisp`), so every letter is at the same
//   moment and the picture is the same each time it is made; these are held as goldens.
// - `ripple-<theme>-<level>`: the same phrase in the last tenth of its arc, where the arrival's own filter has
//   nothing left to do, with the voice at a level: the ripple alone. Held as goldens (the piece is asked for again
//   until its arc, which is a little longer or shorter at random, puts the moment of the picture in that tenth).
// - `heard-<theme>-<n>` and `ripple-over-arrival`: a phrase heard, its words each a step behind the one before, and
//   a ripple through words still mid-arc (both filters on a letter). Each word's arc is a little longer or shorter at
//   random, so these are written to be looked at (`--update-goldens`) and held to nothing.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/editor/ai/wisp_arrivals.dart';
import 'package:ghost_md/editor/ai/wisp_filters.dart';
import 'package:ghost_md/editor/ai/wisp_ripples.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/wisp_motion.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../support/render.dart';
import 'wisp_support.dart';

const String _before = '# Shopping\n\nAlready said, and set.\n';
const String _phrase = 'Buy oat milk on Tuesday';
const Size _page = Size(390, 190);

class _Voice implements RippleSource {
  void Function(double level)? say;

  @override
  void Function() subscribe(void Function(double level) listener) {
    say = listener;
    return () => say = null;
  }
}

/// The page as it stands, held to `shots/<name>.png`.
Future<void> _picture(WidgetTester tester, String name) => expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name.png'));

/// Sets the phrase arriving as one piece, all its letters at one moment, and answers the piece. With `arc`, asks
/// again until the piece's arc is within it.
Future<Moving> _reveal(WidgetTester tester, EditorView view, {({double over, double upTo})? arc}) async {
  for (var tries = 0; tries < 400; tries++) {
    view.dispatch(TransactionSpec(effects: revealWisp.of((from: _before.length, to: view.state.doc.length))));
    final piece = moving(view.state).single;
    expect(view.state.doc.sliceString(piece.from, piece.to), _phrase);
    if (arc == null || (piece.dur > arc.over && piece.dur <= arc.upTo)) {
      await tester.pump();
      return piece;
    }
    view.dispatch(TransactionSpec(effects: settle.of(<int>[piece.id])));
  }
  throw StateError('no arc within $arc in 400 tries');
}

void main() {
  setUpAll(loadAppFonts);
  holdClock();

  for (final theme in const <String>['light', 'dark']) {
    testWidgets('a phrase arriving, moment by moment, $theme', (tester) async {
      await loadWisp(tester);
      final view = await pumpEditor(tester, '$_before$_phrase', more: <Extension>[wispArrivals()], theme: theme, size: _page);
      final piece = await _reveal(tester, view);
      for (final at in const <int>[0, 12, 30, 50, 70]) {
        clock = piece.at + piece.dur * at / 100;
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        final filter = filterNamed(wearing(view).first.filter)!;
        expect(filter.scale, shapeAt(at / 100).scale);
        await _picture(tester, 'arrival-$theme-$at');
      }
      clock = piece.at + piece.dur + 1;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(moving(view.state), isEmpty);
      await _picture(tester, 'arrival-$theme-settled');
      await done(tester);
    });

    testWidgets('a phrase heard, each word a step behind the one before, $theme', (tester) async {
      await loadWisp(tester);
      final view = await pumpEditor(tester, _before, more: <Extension>[wispArrivals()], theme: theme, size: _page);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: _before.length, insert: _phrase), annotations: wisp.of(WispKind.heard)));
      await tester.pump();
      final first = moving(view.state).first;
      for (final at in const <int>[30, 70]) {
        final to = first.at + first.dur * at / 100;
        await advance(tester, to - clock, step: 8);
        await look(tester, 'heard-$theme-$at');
      }
      await done(tester);
    });
  }

  for (final (theme, level) in const <(String, double)>[('light', 0.08), ('light', 0.15), ('light', 0.3), ('dark', 0.3)]) {
    testWidgets('the voice through a phrase at $level, $theme', (tester) async {
      await loadWisp(tester);
      final voice = _Voice();
      final view = await pumpEditor(tester, '$_before$_phrase', more: <Extension>[wispArrivals(), wispRipples(voice)], theme: theme, size: _page);
      // Nine steps of the ripple's loop on, the piece is in the last tenth of its arc: crisp but for the ripple.
      const steps = 9, step = 34.0;
      final piece = await _reveal(tester, view, arc: (over: steps * step, upTo: steps * step / 0.9));
      voice.say!(level);
      for (var i = 0; i < steps; i++) {
        clock += step;
        await tester.pump(const Duration(milliseconds: 34));
      }
      expect(moving(view.state).single.id, piece.id, reason: 'still arriving');
      expect(filterNamed(wearing(view).first.filter)!.plain, isTrue, reason: 'the arrival has nothing left to do');
      final wave = filterNamed(wearing(view).first.ripple)!;
      expect(wave.scale, closeTo(shape(level).scale, shape(level).scale * 0.02 + 0.11));
      await _picture(tester, 'ripple-$theme-${(level * 100).round()}');
      await done(tester);
    });
  }

  testWidgets('the voice through words still mid-arc: both filters on a letter', (tester) async {
    await loadWisp(tester);
    final voice = _Voice();
    final view = await pumpEditor(tester, _before, more: <Extension>[wispArrivals(), wispRipples(voice)], size: _page);
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: _before.length, insert: _phrase), annotations: wisp.of(WispKind.heard)));
    await tester.pump();
    voice.say!(0.3);
    await advance(tester, 204, step: 34);
    expect(wearing(view).any((mark) => !filterNamed(mark.filter)!.plain && filterNamed(mark.ripple)!.scale > 1), isTrue);
    await look(tester, 'ripple-over-arrival');
    await done(tester);
  });
}
