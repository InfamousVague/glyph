/// Settings › Developer › The phone at work: the scene after Done played from a script, so its layout, its pictures
/// and its steps can be looked at without a recording. A port of `src/app/diag/SceneBench.tsx` and
/// `SceneBench.module.css`, **as far as its subject exists**.
///
/// The bench is a bar (its name, Play again, a round X) over a body that holds the scene inline. On the page the
/// scene is `scene/AtWork.tsx` played by `scene/scripted.ts` through the pretend model of `ai/runs.ts`
/// (`simulateRuns`), on the bench's own note, `scene-bench`, whose run is cancelled and put away on close.
///
/// What differs:
/// - **The scene is given** (lib/scene, through lib/root/scene_play.dart). The bar, Play again, close, the back
///   gesture and "Played. Play again to watch it once more." are here as the page has them. In a run given no
///   scene, the body says that it is not here and lists what it would draw ([sceneSteps], from the page's script),
///   with the frame clock running beside the list ([SceneBenchPlay.ring]).
/// - **The seam.** [SceneBench.scene] builds the scene when there is one: it is given a [SceneBenchPlay] (the
///   script, the opening's number, which goes up on Play again, the bench's note id, and `played`, to call when the
///   scene has left). Whoever ports the scene mounts `AtWork(inline: true, noteId: play.noteId, opening:
///   play.opening, …)` there, starts the scripted stages and the pretend run when it is built, and cancels and puts
///   away the run when it is disposed, as the page's effect does. Until then nothing here starts a run, pretend or
///   real.
/// - The page mounted itself with a portal; this fills what it is given, or [showSceneBench] puts it on the
///   navigator with no transition.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/back.dart';
import '../settings/kit/settings_type.dart';
import 'frame_clock.dart';
import 'wisp_bench.dart' show BenchBar;

/// The bench's note (`BENCH_NOTE`): no note has this id, so the run touches nothing.
const String benchNote = 'scene-bench';

/// Which readings the scene plays with (scene/scripted.ts `SceneScript`): `heat`, `cold` or `none`.
const List<String> sceneScripts = ['heat', 'cold', 'none'];

/// What the scene draws, step by step: the six steps of its own list (scene/AtWork.tsx), each with the title the
/// page's test reads while it plays (diag/SceneBench.test.tsx). The list the body shows while the scene itself is not
/// ported; around the steps the page also draws the phone and its chip, the words that were heard, four tiles (Heat,
/// CPU, Pace, Since done), "It carries on behind the note. Nothing leaves the phone." and Back to the note.
const List<({String step, String title, String draws})> sceneSteps = [
  (step: 'Listening again', title: 'Listening again, 40%.', draws: 'The slower speech model hears the recording again, its share done in the title.'),
  (step: 'Loading the model', title: 'Loading Qwen3.5 4B.', draws: 'The run begins, played by the script and not the engine.'),
  (step: 'Reading the note', title: 'Reading the note, 520 of 1040.', draws: 'The prompt read in, counted in the title, with eight pins on the chip.'),
  (step: 'Thinking it through', title: 'Qwen3.5 4B is thinking it through.', draws: 'The Heat tile in °C when the script carries a temperature, and the die lit.'),
  (step: 'Writing what it found', title: '', draws: 'What the model found, as it is written.'),
  (step: 'Done', title: 'Reviewed by Qwen3.5 4B in 0:12.', draws: 'Held a moment; then the scene leaves, and the body says it was played.'),
];

/// One play of the scene, handed to whatever draws it ([SceneBench.scene]).
class SceneBenchPlay {
  SceneBenchPlay({required this.script, required this.opening, required this.played});

  /// `heat`, `cold` or `none`.
  final String script;

  /// Each play is a new opening of the scene (`key`): 0, then one more for each Play again.
  final int opening;

  /// The bench's own note id.
  String get noteId => benchNote;

  /// The scene has left: the body shows that it was played.
  final VoidCallback played;

  /// The frames since this play began, for whoever wants to read them off.
  final FrameRing ring = FrameRing(120);
}

/// Puts the bench over everything, at once, playing [script], and takes it away when it is closed.
Future<void> showSceneBench(BuildContext context, String script, {Widget Function(BuildContext context, SceneBenchPlay play)? scene}) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (route, _, _) => SceneBench(script: script, scene: scene, onClose: () => Navigator.of(route).maybePop()),
      ),
    );

class SceneBench extends StatefulWidget {
  const SceneBench({super.key, required this.script, required this.onClose, this.scene});

  /// Which script to play, or null for a closed bench.
  final String? script;
  final VoidCallback onClose;

  /// The scene itself, once it is ported (see the header); null and the body says what it will draw.
  final Widget Function(BuildContext context, SceneBenchPlay play)? scene;

  @override
  State<SceneBench> createState() => _SceneBenchState();
}

class _SceneBenchState extends State<SceneBench> {
  /// Each play is a new opening of the scene.
  int _opening = 0;
  bool _played = false;

  /// Between two openings: the last scene is being taken down, and the next is not built yet.
  bool _between = false;
  SceneBenchPlay? _play;
  final ValueNotifier<String> _frames = ValueNotifier('…');
  int? _frame;
  double _wrote = 0;

  @override
  void initState() {
    super.initState();
    if (widget.script != null) _begin();
  }

  @override
  void didUpdateWidget(SceneBench old) {
    super.didUpdateWidget(old);
    if (old.script == widget.script) return;
    _stop();
    _opening = 0;
    _between = false;
    if (widget.script != null) _begin();
  }

  @override
  void dispose() {
    _stop();
    _frames.dispose();
    super.dispose();
  }

  void _begin() {
    _played = false;
    _play = SceneBenchPlay(script: widget.script!, opening: _opening, played: _left);
    _frames.value = '…';
    _wrote = 0;
    _frame = SchedulerBinding.instance.scheduleFrameCallback(_tick);
  }

  void _stop() {
    final frame = _frame;
    if (frame != null) SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    _frame = null;
    _play = null;
  }

  void _left() {
    if (!mounted || _played) return;
    final frame = _frame;
    if (frame != null) SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    _frame = null;
    setState(() => _played = true);
  }

  /// Play again: the scene on the screen is taken down in one frame and the new opening built in the next, so the
  /// old one's leaving (where its run is cancelled and put away) is done before the new one starts a run on the same
  /// note. Built in one frame, Flutter would start the new before it took down the old.
  void _again() {
    _stop();
    setState(() {
      _opening += 1;
      _between = true;
    });
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_between || widget.script == null) return;
      setState(() {
        _between = false;
        _begin();
      });
    });
  }

  // The frame clock, ready: every frame of the play marked, and read into words twice a second.
  void _tick(Duration _) {
    final play = _play;
    if (play == null) return;
    final now = realClock.now();
    play.ring.mark(now);
    if (now - _wrote > 500) {
      _wrote = now;
      final read = play.ring.read();
      _frames.value = read.n > 0 ? '${ms(read.median)} · p90 ${ms(read.p90)} · worst ${ms(read.worst)}' : '…';
    }
    _frame = SchedulerBinding.instance.scheduleFrameCallback(_tick);
  }

  @override
  Widget build(BuildContext context) {
    final script = widget.script;
    final play = _play;
    if (script == null || (play == null && !_between)) return const SizedBox.shrink();
    final t = context.tokens;
    final ink = t.color('app-ink'), quiet = t.color('app-ink-3');
    final small = t.fontSize('sm');
    final start = t.len('app-gutter-start'), end = t.len('app-gutter-end');
    final scene = widget.scene;

    return OnBack(
      onBack: widget.onClose,
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
          widget.onClose();
          return KeyEventResult.handled;
        },
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          label: 'The phone at work',
          explicitChildNodes: true,
          child: ColoredBox(
            key: const ValueKey('scene-over'),
            color: t.color('app-paper'),
            child: DefaultTextStyle(
              style: pageText(t, t.lenOf('1rem'), color: ink),
              child: Padding(
                // `padding-block-start: var(--app-inset-top); padding-block-end: var(--app-safe-bottom)`
                padding: EdgeInsets.only(top: t.len('app-inset-top'), bottom: t.len('app-safe-bottom')),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BenchBar(
                      key: const ValueKey('scene-bar'),
                      title: 'The phone at work',
                      onClose: widget.onClose,
                      padding: EdgeInsets.fromLTRB(start, t.space(3), end, t.space(3)),
                      rule: BorderSide(color: t.color('app-rule'), width: t.len('glacier-hairline')),
                      closeColor: quiet,
                      // `.again`: Play again, an icon and its word, in ink, as the strip's own controls are.
                      between: GlacierPressable(
                        key: const ValueKey('scene-again'),
                        onPressed: _again,
                        builder: (context, state) => Container(
                          padding: EdgeInsets.symmetric(vertical: t.space(1), horizontal: t.space(2)),
                          decoration: BoxDecoration(color: state.pressed ? t.color('app-paper-3') : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(Lucide.rotateCcw, size: 15, strokeWidth: 2.2, color: ink, wash: false),
                              SizedBox(width: 0.3 * small),
                              Text('Play again', style: pageText(t, small, weight: 'semibold', color: ink)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // `.body`: the scene's host, the rest of the window, and nothing else in it.
                    Expanded(
                      child: Stack(
                        key: const ValueKey('scene-body'),
                        fit: StackFit.expand,
                        children: [
                          // `.played`: under the scene, so it shows once the scene has left.
                          if (_played || scene != null)
                            Padding(
                              padding: EdgeInsets.fromLTRB(start, t.space(4), end, t.space(4)),
                              child: Center(child: Text('Played. Play again to watch it once more.', key: const ValueKey('scene-played'), textAlign: TextAlign.center, style: pageText(t, small, color: quiet))),
                            ),
                          if (!_played && play != null)
                            KeyedSubtree(
                              key: ValueKey('scene-opening-${play.opening}'),
                              child: scene != null ? scene(context, play) : _NotPorted(script: script, frames: _frames),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the body says while there is no scene to play: that, what it will draw, and the frames of this screen.
class _NotPorted extends StatelessWidget {
  const _NotPorted({required this.script, required this.frames});
  final String script;
  final ValueNotifier<String> frames;

  static const Map<String, String> _readings = {
    'heat': 'With a heat reading.',
    'cold': 'Without a heat reading, as on a phone that hides its thermal zones.',
    'none': 'With no readings at all, as on the Mac.',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink'), quiet = t.color('app-ink-3');
    final small = t.fontSize('sm');
    final words = pageText(t, small, color: quiet, height: 1.5);
    return ColoredBox(
      color: t.color('app-paper'),
      child: ListView(
        key: const ValueKey('scene-not-ported'),
        padding: EdgeInsets.fromLTRB(t.len('app-gutter-start'), t.space(4), t.len('app-gutter-end'), t.space(4)),
        children: [
          Text('The scene is not in this build yet.', style: pageText(t, t.fontSize('md'), weight: 'semibold', color: ink)),
          SizedBox(height: t.space(2)),
          Text('It is the web app’s scene after Done, which stage 8 brings over. ${_readings[script] ?? ''} When it is here it will draw, in this order:', style: words),
          SizedBox(height: t.space(3)),
          for (final (index, step) in sceneSteps.indexed)
            Padding(
              padding: EdgeInsets.only(bottom: t.space(3)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: t.space(6), child: Text('${index + 1}', style: pageText(t, small, color: quiet, mono: true, height: 1.5))),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(step.step, style: pageText(t, small, weight: 'semibold', color: ink, height: 1.5)),
                        if (step.title.isNotEmpty) Text(step.title, style: pageText(t, small, color: ink, height: 1.5)),
                        Text(step.draws, style: words),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: t.space(1)),
          Row(
            children: [
              Expanded(child: Text('This screen’s frames', style: words)),
              SizedBox(width: t.space(3)),
              RepaintBoundary(
                child: ValueListenableBuilder<String>(
                  valueListenable: frames,
                  builder: (context, read, _) => Text(read, key: const ValueKey('scene-frames'), style: pageText(t, t.lenOf('0.75rem'), weight: 'medium', color: quiet, mono: true)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
