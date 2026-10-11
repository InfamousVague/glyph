// Ports src/app/editor/wispRipples.test.ts (tauri/), case for case and under its names, onto
// lib/editor/ai/wisp_ripples.dart: the stretches that ripple, the level followed, the bend at a level, and the
// ripples drawn in an editor (worn by the arriving words alone, bent with the voice, still and costing nothing in
// silence, gone with the editor, never there with reduced motion).
//
// What is read differently (the Dart file's header, "What differs"):
// - `.cm-wispRipple` in the DOM is the marks the editor draws with that class; a filter's `feDisplacementMap scale`
//   is its `Smoke.scale` (`filtersOf('wispripple-')`).
// - What a ripple's filter is drawn on is the arriving letter, which the arrivals mark with both filters: that is
//   read too (`data-ripple`).
// - `stubMatchMedia(true)` is `wispStill.of(true)` in the editor: the extension is not empty, it is idle.
// - `vi.advanceTimersByTime` is the held clock (`wispNow`) moved on a frame at a time; `requestAnimationFrame` not
//   being called is no transient callback waiting.
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/ai/wisp_arrivals.dart';
import 'package:ghost_md/editor/ai/wisp_filters.dart';
import 'package:ghost_md/editor/ai/wisp_ripples.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/wisp_motion.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

import '../support/render.dart';
import 'wisp_support.dart';

/// The voice's level as the recorder would hand it over, and whether anything is still listening.
class Voice implements RippleSource {
  void Function(double level)? say;

  @override
  void Function() subscribe(void Function(double level) listener) {
    say = listener;
    return () => say = null;
  }
}

TransactionSpec heard(int from, String insert, {int? to, WispKind kind = WispKind.heard}) => TransactionSpec(changes: ChangeSpec(from: from, to: to, insert: insert), annotations: wisp.of(kind));

/// The stretches the editor draws `cm-wispRipple` on.
List<Drawn> rippling(EditorView view) {
  final found = <Drawn>[];
  for (final source in view.state.facet(EditorViewLike.decorations)) {
    found.addAll(drawnBy(EditorViewLike.resolveDecorations(source, view), view.state.doc.length).where((mark) => mark.name == 'cm-wispRipple'));
  }
  return found;
}

void main() {
  setUpAll(loadAppFonts);
  holdClock();

  group('ripples through the arriving words', () {
    test('ripples only the words still arriving, one stretch a phrase, and none of the text already set', () {
      final settled = EditorState.create(doc: 'Already said.\n', extensions: wispArrivals());
      expect(rippledRanges(settled), isEmpty);
      final heardState = settled.update(heard(settled.doc.length, 'oat milk')).state;
      final stretches = rippledRanges(heardState);
      expect(<String>[for (final r in stretches) heardState.doc.sliceString(r.from, r.to)], <String>['oat milk']);
      expect(stretches[0].from, 'Already said.\n'.length);
    });

    test('keeps a phrase on each line its own stretch, and takes no part in text leaving', () {
      final start = EditorState.create(doc: 'one two', extensions: wispArrivals());
      final heardState = start.update(heard(7, '\nthree')).state;
      expect(<String>[for (final r in rippledRanges(heardState)) heardState.doc.sliceString(r.from, r.to)], <String>['three']);
      final rewrite = heardState.update(heard(0, '', to: 3, kind: WispKind.rewrite)).state;
      expect(moving(rewrite).any((m) => m.gone.isNotEmpty), isTrue);
      expect(rippledRanges(rewrite).every((r) => r.to > r.from), isTrue);
      // Two phrases heard on two lines are two stretches, however close.
      final two = EditorState.create(doc: '', extensions: wispArrivals()).update(heard(0, 'one two\nthree')).state;
      expect(<String>[for (final r in rippledRanges(two)) two.doc.sliceString(r.from, r.to)], <String>['one two', 'three']);
    });

    test('follows a voice up quickly and down slowly, and settles to nothing', () {
      final up = follow(0, 0.6);
      expect(up, greaterThan(0.2));
      final down = follow(up, 0);
      expect(down, lessThan(up));
      expect(up - down, lessThan(up * 0.2));
      var level = up;
      for (var i = 0; i < 200; i += 1) {
        level = follow(level, 0);
      }
      expect(level, 0);
    });

    test('bends nothing in silence and a full wave by ordinary talking', () {
      expect(shape(0), (scale: 0.0, blur: 0.0));
      expect(shape(0.15).scale, greaterThan(0));
      expect(shape(0.15).scale, lessThan(shape(0.3).scale));
      expect(shape(0.3), shape(1));
      expect(shape(1).scale, 30);
    });
  });

  group('the ripples drawn in the recorder’s page', () {
    late Voice voice;
    setUp(() => voice = Voice());

    Future<EditorView> open(WidgetTester tester, {List<Extension> more = const <Extension>[]}) async {
      final view = await pumpEditor(tester, 'Already said. ', more: <Extension>[wispArrivals(), wispRipples(voice), ...more]);
      view.dispatch(heard(view.state.doc.length, 'buy oat milk'));
      await tester.pump();
      return view;
    }

    double bend() => filtersOf('wispripple-').first.scale;

    testWidgets('wears its filters on the words still arriving, and none on the text already set', (tester) async {
      final on = await open(tester);
      final rippled = <String>[for (final mark in rippling(on)) on.state.doc.sliceString(mark.from, mark.to)].join();
      expect(rippled, contains('oat'));
      expect(rippled, isNot(contains('Already')));
      expect(rippling(on).every((mark) => filterNamed(mark.filter) != null), isTrue);
      // What draws it: each arriving letter is marked with its stretch's filter over its own.
      expect(wearing(on), isNotEmpty);
      expect(wearing(on).every((mark) => mark.ripple == rippling(on).single.filter), isTrue);
      await done(tester);
    });

    testWidgets('bends them with the voice, and stops drawing altogether once the voice and the words have settled', (tester) async {
      final on = await open(tester);
      voice.say?.call(0.3);
      await advance(tester, 200, step: 40);
      expect(bend(), greaterThan(0));
      voice.say?.call(0);
      await advance(tester, 10000);
      expect(rippling(on), isEmpty);
      expect(moving(on.state), isEmpty);
      // Silence costs nothing: no frame is asked for while nothing moves.
      await advance(tester, 1000);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      await done(tester);
    });

    testWidgets('stops hearing the voice and takes its filters away with the editor', (tester) async {
      final on = await open(tester);
      expect(filtersOf('wispripple-').length, 4);
      expect(voice.say, isNotNull);
      on.destroy();
      expect(voice.say, isNull);
      expect(filtersOf('wispripple-'), isEmpty);
      await done(tester);
    });

    testWidgets('draws no ripples at all where less motion is asked for', (tester) async {
      final on = await open(tester, more: <Extension>[wispStill.of(true)]);
      expect(voice.say, isNull, reason: 'nobody listens');
      expect(filtersOf('wispripple-'), isEmpty);
      expect(rippling(on), isEmpty);
      await tester.pump(const Duration(milliseconds: 50));
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
      await done(tester);
    });

    testWidgets('lays the lines out exactly as with no ripple, and lets a settled page be the plain page', (tester) async {
      const before = 'Already said. ';
      const said = 'buy oat milk and call home';
      final plain = await pumpEditor(tester, '$before$said', size: const Size(390, 160));
      final expected = layoutOf(plain);
      final still = await pixels(tester);
      await done(tester);
      final on = await pumpEditor(tester, before, more: <Extension>[wispArrivals(), wispRipples(voice)], size: const Size(390, 160));
      on.dispatch(heard(before.length, said));
      await tester.pump();
      voice.say?.call(0.3);
      await advance(tester, 240, step: 40);
      expect(bend(), greaterThan(0));
      expect(layoutOf(on), expected, reason: 'rippling');
      expect(await pixels(tester), isNot(still));
      voice.say?.call(0);
      await advance(tester, 4000);
      expect(layoutOf(on), expected, reason: 'settled');
      expect(await pixels(tester), still);
      await done(tester);
    });
  });
}
