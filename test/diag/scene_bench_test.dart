import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/diag/scene_bench.dart';

import '../support/render.dart';

/// `diag/SceneBench.test.tsx`, as far as its subject exists. The page's cases are about the scene (scene/AtWork.tsx)
/// played by the pretend model (ai/runs.ts `simulateRuns`); neither is in `lib/` yet, so what is held here is the
/// bench itself: closed it is nothing, open it is a bar over a body, Play again is a new opening, closing takes
/// everything down, and the back gesture closes it. A stand-in scene is given through the bench's own seam
/// ([SceneBench.scene]) where a case needs something that opens, leaves and is taken down.
///
/// Not ported, each for the same reason (no scene and no pretend run to read):
/// - "plays the script to done": the titles as the script plays, the eight pins, the heat tile, the lit die.
/// - "takes the script out the moment its run has started, so the next run reaches the engine".
/// - the run cancelled and put away on close, and a later run reaching the real engine (the second half of "cancels
///   and puts away its run on close").
/// - "stops its stage timers on close, so a play cut short never starts its run": held here only as the bench's own
///   frame clock stopping.
/// - the scene taking the first back gesture before the bench takes the second.

Finder _key(String name) => find.byKey(ValueKey(name));

Future<void> _away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// A scene that only says which opening it is, and counts how often it was taken down.
class _StandIn extends StatefulWidget {
  const _StandIn(this.play, this.log);
  final SceneBenchPlay play;
  final List<String> log;

  @override
  State<_StandIn> createState() => _StandInState();
}

class _StandInState extends State<_StandIn> {
  @override
  void initState() {
    super.initState();
    widget.log.add('opened ${widget.play.script} ${widget.play.opening} on ${widget.play.noteId}');
  }

  @override
  void dispose() {
    widget.log.add('closed ${widget.play.opening}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(onTap: widget.play.played, child: Text('scene ${widget.play.opening}', key: const ValueKey('stand-in')));
}

void main() {
  setUpAll(loadAppFonts);

  group('the scene bench', () {
    testWidgets('is nothing while closed', (tester) async {
      await pumpApp(tester, home: SceneBench(script: null, onClose: () {}));
      expect(find.text('The phone at work'), findsNothing);
      expect(_key('scene-body'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      await _away(tester);
    });

    testWidgets('opens with its body under its bar, and says what the scene will draw while there is none', (tester) async {
      await pumpApp(tester, home: SceneBench(script: 'heat', onClose: () {}));
      expect(find.bySemanticsLabel('The phone at work'), findsWidgets);
      expect(find.text('The phone at work'), findsOneWidget);
      expect(tester.getRect(_key('scene-body')).top, tester.getRect(_key('scene-bar')).bottom);
      expect(find.text('The scene is not in this build yet.'), findsOneWidget);
      // The scene's own steps, in its order, with the titles the page's test reads as it plays.
      for (final step in sceneSteps) {
        expect(find.text(step.step), findsOneWidget);
      }
      expect(sceneSteps.map((step) => step.step), ['Listening again', 'Loading the model', 'Reading the note', 'Thinking it through', 'Writing what it found', 'Done']);
      expect(find.text('Loading Qwen3.5 4B.'), findsOneWidget);
      expect(find.textContaining('With a heat reading.'), findsOneWidget);
      // The frame clock is ready: frames are being read, and said twice a second.
      expect(tester.widget<Text>(_key('scene-frames')).data, '…');
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.widget<Text>(_key('scene-frames')).data, '16.0 · p90 16.0 · worst 16.0');
      // Nothing was played, so nothing says it was.
      expect(_key('scene-played'), findsNothing);
      await _away(tester);
    });

    testWidgets('holds a scene given to it inline, on the bench’s own note, and says it was played once it has left', (tester) async {
      final log = <String>[];
      await pumpApp(tester, home: SceneBench(script: 'cold', onClose: () {}, scene: (context, play) => _StandIn(play, log)));
      expect(log, ['opened cold 0 on scene-bench']);
      expect(benchNote, 'scene-bench');
      final body = tester.getRect(_key('scene-body'));
      expect(body.contains(tester.getCenter(_key('stand-in'))), isTrue);
      await tester.tap(_key('stand-in'));
      await tester.pump();
      expect(_key('stand-in'), findsNothing);
      expect(log.last, 'closed 0');
      // The body says where the play went, rather than standing empty under the bar.
      expect(find.text('Played. Play again to watch it once more.'), findsOneWidget);
      expect(find.text('The phone at work'), findsOneWidget);
      await _away(tester);
    });

    testWidgets('plays again on the word', (tester) async {
      final log = <String>[];
      await pumpApp(tester, home: SceneBench(script: 'cold', onClose: () {}, scene: (context, play) => _StandIn(play, log)));
      await tester.tap(find.text('Play again'));
      await tester.pump();
      await tester.pump();
      // A new opening of the scene, and the earlier one taken down first, which is where its run is cancelled: the
      // new one's run is on the same note, and must not be the one that is put away.
      expect(find.text('scene 1'), findsOneWidget);
      expect(log, ['opened cold 0 on scene-bench', 'closed 0', 'opened cold 1 on scene-bench']);
      // And after a play that ran to its end.
      await tester.tap(_key('stand-in'));
      await tester.pump();
      await tester.tap(find.text('Play again'));
      await tester.pump();
      await tester.pump();
      expect(find.text('scene 2'), findsOneWidget);
      expect(find.text('Played. Play again to watch it once more.'), findsOneWidget, reason: 'under the scene, as on the page');
      await _away(tester);
    });

    testWidgets('takes its scene down on close, and stops its own clock', (tester) async {
      final log = <String>[];
      var closed = 0;
      Widget bench(String? script) => SceneBench(script: script, onClose: () => closed += 1, scene: (context, play) => _StandIn(play, log));
      await pumpApp(tester, home: bench('heat'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(_key('bench-close'));
      expect(closed, 1);
      await pumpApp(tester, home: bench(null));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('The phone at work'), findsNothing);
      expect(log, ['opened heat 0 on scene-bench', 'closed 0']);
      // Its frame clock stopped with it.
      expect(tester.binding.transientCallbackCount, 0);
      await _away(tester);
    });

    testWidgets('closes on the back gesture', (tester) async {
      var closed = 0;
      await pumpApp(tester, home: SceneBench(script: 'none', onClose: () => closed += 1));
      expect(backStack.goBack(), isTrue);
      expect(closed, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 2);
      await _away(tester);
    });
  });
}
