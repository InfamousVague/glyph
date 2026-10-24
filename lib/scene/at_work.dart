/// The phone at work: a full-screen scene over the note while the models work on a recording, until they are done or
/// it is sent behind. A port of `src/app/scene/AtWork.tsx` and AtWork.module.css.
///
/// Matt: "make the analyzing steps of the AI full screen high contrast SVG iconography with cool effects like a
/// piping hot phone CPU scrolling through the thoughts and transcriptions of the AI etc." After Done on a recording
/// the note opens and the review runs in it: listening again, comparing, then a thinking run of the engine
/// (ai/runs.dart). That was a strip under the header; this is the same work drawn large. The phone
/// (scene/hot_phone.dart) over a pane of what is being read and thought (scene/feed.dart), the steps in the order
/// they happen, a title in the strip's own words (scene/steps.dart), four counters, and two words: Stop, which is
/// the strip's own control, and Back to the note, which drops to the strip.
///
/// It never blocks anything. The strip and the note are under it, the review carries on whether it is up or not, and
/// the moment the run ends it begins to leave, so the findings and the toast are seen landing. One exception: while
/// the summary queue holds a job for this note (ai/summaries.dart), a summary run may follow the review's, and the
/// scene waits the grace for it after an end instead of the settle alone, then follows it as "Reading the recording"
/// and "Writing the summary". It is a child of the note screen on purpose and never navigates: leaving the note
/// mid-review drops the findings, so nothing here does. Back closes it, armed one frame after the note's own handler
/// so the first swipe takes the scene and the second the note.
///
/// The one looped motion is the haze on the words: the app's heat filter idea (editor/marks/text_effects.dart
/// `heat`) at the words' own share, stepped with each report rather than animated on its own clock, so the model
/// keeps its cores. It is worn only with Settings › Appearance's smoke at the edges on, the switch that already
/// means "turbulence costs frames here", and never under reduced motion.
///
/// ## Where the root puts it (lib/root/note_desk.dart)
///
/// The page's NoteScreen.tsx rendered it as a child of the note screen, straight after the AI's strip holder and
/// before the note's line of problems and its page:
///
///     <AtWork noteId={note.id} opening={review?.key ?? null} heard={review?.heard ?? ''} body={note.body}
///             hasJob={Boolean(review?.job)} stage={ai.reviewStage} />
///
/// but its stylesheet took it out of that flow: `position: fixed; inset: 0; z-index: 48`, the whole window, over the
/// tab bar (5), the strip holder (4), the status scrim (40), the drag bar (41) and the floating card (45), and under
/// the find bar (50), Settings (55), the benches (58), sheets and menus (60), launch (90) and the kit's toasts (200),
/// so the landing toast shows over the fading scene. So here it goes in a [Stack] that fills the window, not in the
/// note's own column: above the shell's bar and the open [NoteScreen], below the find bar, Settings, sheets and the
/// toasts. It fills the box it is given while it is up and is nothing (and takes no touch) while it is not, so it
/// can stay in the stack for as long as the note is open:
///
///     Stack(fit: StackFit.expand, children: [
///       // ... the shell's bar and the NoteScreen for `note` ...
///       AtWork(
///         key: ValueKey('at-work ${note.id}'),
///         noteId: note.id,
///         opening: reviewKey,                 // see below; null with no review on this note
///         heard: review?.heard ?? '',         // ReviewHandoff.heard (capture/recorder.dart)
///         body: note.body,                    // the note as it stands, as the page passed `note.body`
///         hasJob: review?.job != null,        // ReviewHandoff.job
///         stage: reviewStage,                 // the review's ReviewStage? (the web's `ai.reviewStage`)
///         refining: refining.refining,        // the app's Refining (capture/refine.dart)
///         summaryDue: summaryDueFor(note.id), // whether lib/ai/summaries.dart holds a job for this note
///       ),
///       // ... the find bar, Settings, sheets, toasts ...
///     ])
///
/// `opening` is the web's `review.key`: a number the root gives each review it hands a note (App.tsx counted them
/// up), so a second recording into the same open note opens the scene again. lib/capture/recorder.dart's
/// `ReviewHandoff` has no such field, so the root keeps the count beside the handoff. It must be mounted in the same
/// frame the note opens with its review, and for no longer than the note is open: it holds what it has seen of that
/// opening, and a new widget would open again. It registers on the nearest [BackScope]'s stack, so it must be
/// inside the same scope as the note's own back handler.
///
/// What differs:
/// - Three things the page imported are parameters: [AtWork.summaryDue] (`useSummaries().pending.has(noteId)`),
///   [AtWork.refining] (`useRefining()`, which is one [Refining]'s store here and not a module's), and
///   [AtWork.haptic] (`fireNativeHaptic`; the kit's motor when left out). [AtWork.now] is `Date.now()`, a parameter
///   so a test's clock can be the one its timers run on.
/// - `useWideScreen()` is lib/shell/wide_screen.dart's [wideScreen] of the window; `usePreferences()` is the app's
///   own store, `preferences`; `prefersStill()` is the platform's reduce-motion switch, read at opening.
/// - `document.visibilityState` is the app's lifecycle: hidden once the app is hidden, paused or detached. A phone
///   that only shows the notification shade over the app (`inactive`) is still seen, as a page under it is.
/// - What React adjusted during render and kept in effects is kept by the state and brought up to date in one place
///   ([AtWorkState._sync]) whenever something it reads changes; the effects' dependency lists are compared there, so
///   the timers start and stop exactly when the page's did.
/// - The grid is a render object of its own (`_SceneGrid`) that lays the rows and the two columns out as the
///   stylesheet's `grid-template` did, the picture taking what is left. A wide window that is short scrolls.
/// - The pane is a scroll view moved from here. The head glides to its line over 320 ms on `--glacier-ease-out`
///   where the page asked the browser for `scroll-behavior: smooth` and took whatever time it chose; the streaming
///   modes and reduced motion snap, as there. The pane's `cqb` padding is a share of the pane's measured height.
/// - The haze is the wisp's bend shader (lib/art/wisp_kit.dart, the same turbulence and displacement the SVG filter
///   named) over the part of the list the pane shows, its noise still pinned to the list so a line keeps its bend
///   as it scrolls. The filter's region reached 5% and 15% past the list; the strip stops at the list's own edge,
///   which at a bend under a pixel and a half loses nothing seen. Until the shader has loaded the words are plain.
///   The budget is asked of the list's box after each layout rather than by a `ResizeObserver`.
/// - The title's numbers were `aria-hidden` spans; here the heading's label for a screen reader is the title without
///   them. The live line is a live region with no size.
/// - The lines, the step rows and the tiles are public widgets ([AtWorkLine], [AtWorkStepRow], [AtWorkTile]) so the
///   tests can read what the page's tests read from attributes.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../ai/backend.dart';
import '../ai/review_stage.dart';
import '../ai/runs.dart';
import '../ai/words.dart';
import '../app/widgets.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/edge_strips.dart';
import '../art/wisp_kit.dart';
import '../capture/refine.dart' show RefineState;
import '../core/back.dart';
import '../core/preferences.dart';
import '../editor/marks/text_effects.dart' show heatNoise, tunedPx;
import '../shell/wide_screen.dart';
import 'feed.dart';
import 'hot_phone.dart';
import 'icons.dart';
import 'steps.dart';

/// What the scene has seen of this opening. Replaced whole when a new key opens it.
@immutable
class _Seen {
  const _Seen({required this.key, required this.shown, required this.leaving, required this.openedAt, required this.ignoreId, required this.compared, required this.sawStage, required this.ended, required this.still});

  final int? key;
  final bool shown;
  final bool leaving;
  final int openedAt;

  /// An ENDED run the note already had at opening, which is not this review's: ignored. A live one is never ignored.
  final String? ignoreId;

  /// What Comparing said, kept after the stage clears.
  final String? compared;
  final bool sawStage;

  /// The review is over with no run (no thinking model): "Done."
  final bool ended;

  /// Reduced motion, read at opening.
  final bool still;

  _Seen copyWith({bool? shown, bool? leaving, String? compared, bool? sawStage, bool? ended}) => _Seen(
        key: key,
        shown: shown ?? this.shown,
        leaving: leaving ?? this.leaving,
        openedAt: openedAt,
        ignoreId: ignoreId,
        compared: compared ?? this.compared,
        sawStage: sawStage ?? this.sawStage,
        ended: ended ?? this.ended,
        still: still,
      );
}

/// Whether a report past loading has come: loading's one sample is a new sampler's, and reads nothing true.
bool _pastLoading(RunState run) {
  if (run.phase == RunPhase.prefill || run.phase == RunPhase.generating) return true;
  return ended(run) && (run.promptTokensDone > 0 || run.outputTokens > 0);
}

/*
 * The haze's numbers: the heat filter's (editor/marks/text_effects.dart `heatNoise`) for 14 px type, the words' own
 * share of the bend, and the noise breathing between its low and high frequencies on `baseFrequency` alone - the seed
 * stays 7, so no letter jumps.
 */
const double _k = 14 / tunedPx;
final List<double> _low = [heatNoise.low[0] / _k, heatNoise.low[1] / _k];
final List<double> _high = [heatNoise.high[0] / _k, heatNoise.high[1] / _k];
final double _bend = heatNoise.bend * _k * hazeOwn;
const int _breathMs = 2500;
const int _hazeSeed = 7;
double _share(Warmth warmth) => switch (warmth) { Warmth.cold => 0, Warmth.warm => 0.5, Warmth.hot => 1 };
double _fixed(double value, int digits) => double.parse(value.toStringAsFixed(digits));

/*
 * Where the current line is kept, as a share of the pane's height: under the die and its pins (the die's bottom pins
 * end at 0.66 of the drawing), in clear paper. The lines already read or thought pass up behind the die and the mark,
 * which hide them; the one being read or written never is. (It was 0.6, which is the die itself, and the review found
 * the head line and each finding cut through by it on the cover screen.) The list's top padding is the same share, so
 * the first line can sit there too.
 */
const double _anchor = 0.72;

int _wallClock() => DateTime.now().millisecondsSinceEpoch;

/// What the phone is drawn from at one moment: held while the app is hidden.
typedef _Picture = ({Warmth warmth, int glowStep, int pins, int litPins, StepId? step});

/// The scene (`AtWork`, `AtWorkProps`).
class AtWork extends StatefulWidget {
  const AtWork({
    super.key,
    required this.noteId,
    required this.opening,
    required this.heard,
    required this.body,
    required this.hasJob,
    required this.stage,
    this.inline = false,
    this.summaryDue,
    this.refining,
    this.haptic,
    this.now,
    this.onGone,
  });

  /// Told once the scene has left after having been up. The page's bench drew "Played." under the scene, where it
  /// showed as the scene went; here the bench is told (lib/diag/scene_bench.dart `SceneBenchPlay.played`).
  final VoidCallback? onGone;

  final String noteId;

  /// The review's key while one is on this note; null with none. A new key opens the scene.
  final int? opening;

  /// Every phrase the fast model heard, in order.
  final String heard;

  /// The note as the prompt read it.
  final String body;

  /// Whether a listen will happen: the recorder kept a recording.
  final bool hasJob;

  /// The review's own stage before its run (the web's editor/useNoteAi.ts `reviewStage`).
  final ReviewStage? stage;

  /// In the bench: in its host under the bench's bar rather than over the app, with no inset padding.
  final bool inline;

  /// Whether a summary run may follow this note's review: the root passes whether lib/ai/summaries.dart holds a job
  /// for this note (the web's `useSummaries().pending.has(noteId)`). Null is never.
  final ValueListenable<bool>? summaryDue;

  /// The better-words queue as a screen follows it (the web's `useRefining()`): the app's `Refining.refining`
  /// (capture/refine.dart), read for the larger voice model's download. Null is no download, ever.
  final ValueListenable<RefineState>? refining;

  /// The phone's motor (the web's `fireNativeHaptic`): `selection` as the scene goes behind the note, `warning` on
  /// Stop. The kit's own ([fireMotor]) when left out.
  final void Function(HapticKind kind)? haptic;

  /// The time now in milliseconds (the web's `Date.now()`). The wall clock when left out.
  final int Function()? now;

  @override
  State<AtWork> createState() => AtWorkState();
}

/// The scene's state. Public for what a test reads of it: every `debug` member is what the page's tests read from
/// the scene's attributes and its filter.
class AtWorkState extends State<AtWork> with WidgetsBindingObserver {
  late _Seen _seen;
  ValueListenable<RunState?>? _run;

  /// Whether the scene was drawn at the last build: its going is told once ([AtWork.onGone]).
  bool _wasUp = false;

  // Hidden: the clock and the haze stop, and the feed and the picture hold their last values.
  bool _hidden = false;

  // Back: armed one frame late, so the note's own handler is under this one and the first swipe takes the scene.
  bool _armed = false;

  final List<Timer> _timers = [];
  Object? _leaveDeps;
  Timer? _beat;
  Object? _clockDeps;
  int _now = 0;

  Object? _feedDeps;
  Feed? _feed;
  _Picture? _picture;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _list = GlobalKey();
  Object? _anchored;
  bool _fits = true;

  final ValueNotifier<int> _kit = ValueNotifier<int>(0);
  ui.Offset _frequency = ui.Offset(_fixed(_low[0], 4), _fixed(_low[1], 4));
  double _lastStep = double.negativeInfinity;
  Object? _hazeDeps;
  int _hazeWrites = 0;
  bool _hazeOn = false;
  Warmth _warmth = Warmth.cold;
  FeedMode _mode = FeedMode.transcript;

  int _clock() => (widget.now ?? _wallClock)();

  /// The scene as the page's root element wore it: `data-leaving`, `data-ended`, `data-wide`, `data-inline`,
  /// `data-still`, `data-warmth`, `data-mode`; null while there is no scene.
  @visibleForTesting
  ({bool leaving, bool ended, bool still, Warmth warmth, FeedMode mode})? get debugScene {
    if (!_seen.shown) return null;
    final live = _live;
    return (leaving: _seen.leaving, ended: (live != null && ended(live)) || _seen.ended, still: _seen.still, warmth: _warmth, mode: _mode);
  }

  /// Whether the list wears the haze (`style.filter`).
  @visibleForTesting
  bool get debugHazeOn => _hazeOn;

  /// The displacement's `scale`, as the page wrote it; null under reduced motion, where there is no filter.
  @visibleForTesting
  String? get debugBend => _seen.still ? null : (_bend * _share(_warmth)).toStringAsFixed(2);

  /// The turbulence's `baseFrequency`, as the page wrote it.
  @visibleForTesting
  String get debugFrequency => '${_frequency.dx.toStringAsFixed(4)} ${_frequency.dy.toStringAsFixed(4)}';

  /// How many times the noise has been stepped.
  @visibleForTesting
  int get debugHazeWrites => _hazeWrites;

  /// How many timers the scene holds: the leave's and the clock's.
  @visibleForTesting
  int get debugTimers => _timers.length + (_beat == null ? 0 : 1);

  /// Where the pane is scrolled to.
  @visibleForTesting
  double get debugScrollTop => _scroll.hasClients ? _scroll.offset : 0;

  _Seen _opened(String noteId, int? key) {
    final had = runFor(noteId);
    return _Seen(
      key: key,
      shown: key != null,
      leaving: false,
      openedAt: _clock(),
      ignoreId: had != null && ended(had) ? had.id : null,
      compared: null,
      sawStage: false,
      ended: false,
      still: WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations,
    );
  }

  RunState? get _live {
    final run = _run?.value;
    return run != null && run.id != _seen.ignoreId ? run : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hidden = _isHidden(WidgetsBinding.instance.lifecycleState);
    _seen = _opened(widget.noteId, widget.opening);
    _now = _clock();
    _run = useRun(widget.noteId)..addListener(_changed);
    widget.refining?.addListener(_changed);
    widget.summaryDue?.addListener(_changed);
    preferences.addListener(_changed);
    _sync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _armed = true);
    });
    // The haze's programs and its noise, off the first frame.
    unawaited(
      WispKit.load(seeds: const [_hazeSeed]).then((_) {
        if (mounted) _kit.value += 1;
      }, onError: (Object _) {}),
    );
  }

  @override
  void didUpdateWidget(AtWork oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.noteId != widget.noteId) {
      _run?.removeListener(_changed);
      _run = useRun(widget.noteId)..addListener(_changed);
    }
    if (!identical(old.refining, widget.refining)) {
      old.refining?.removeListener(_changed);
      widget.refining?.addListener(_changed);
    }
    if (!identical(old.summaryDue, widget.summaryDue)) {
      old.summaryDue?.removeListener(_changed);
      widget.summaryDue?.addListener(_changed);
    }
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _run?.removeListener(_changed);
    widget.refining?.removeListener(_changed);
    widget.summaryDue?.removeListener(_changed);
    preferences.removeListener(_changed);
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _beat?.cancel();
    _beat = null;
    _scroll.dispose();
    _kit.dispose();
    super.dispose();
  }

  static bool _isHidden(AppLifecycleState? state) => state == AppLifecycleState.hidden || state == AppLifecycleState.paused || state == AppLifecycleState.detached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hidden = _isHidden(state);
    if (hidden == _hidden) return;
    setState(() {
      _hidden = hidden;
      _sync();
    });
  }

  void _changed() {
    if (mounted) setState(_sync);
  }

  /// Brings what the scene keeps up to date with what it is given and what it watches: what a stage says is kept, and
  /// the leave and the clock are started or stopped.
  void _sync() {
    // Adjusted before the build, so the first frame with a key already has the scene, and what a stage says is kept.
    var current = _seen;
    final stage = widget.stage;
    if (widget.opening != current.key) current = _opened(widget.noteId, widget.opening);
    if (stage != null && !current.sawStage) current = current.copyWith(sawStage: true);
    if (stage?.what == 'Comparing' && current.compared != stage!.detail) current = current.copyWith(compared: stage.detail);
    _seen = current;
    _syncLeave();
    _syncClock();
  }

  void _later(void Function() fn, int ms) {
    late final Timer timer;
    timer = Timer(Duration(milliseconds: ms), () {
      _timers.remove(timer);
      if (!mounted) return;
      setState(() {
        fn();
        _sync();
      });
    });
    _timers.add(timer);
  }

  void _leave(int hold, [bool Function()? unless]) {
    _later(() {
      if (unless?.call() ?? false) return;
      _seen = _seen.copyWith(leaving: true);
      _later(() => _seen = _seen.copyWith(shown: false, leaving: false), leaveMs);
    }, hold);
  }

  // Leaving: after an end the settle plays, then the fade, then nothing; or the review is taken as over when no run
  // comes after the stage clears; or, having seen nothing at all, the scene leaves quietly. Not while the app is
  // hidden: what ended off screen is settled and left on return, so the findings are still seen landing.
  void _syncLeave() {
    final live = _live;
    final liveId = live?.id;
    final liveEnded = live != null && ended(live);
    final staged = widget.stage != null;
    final shown = _seen.shown;
    final over = _seen.ended;
    final sawStage = _seen.sawStage;
    final summaryDue = widget.summaryDue?.value ?? false;
    final deps = (shown, staged, _hidden, liveId, liveEnded, over, sawStage, _seen.openedAt, _seen.key, summaryDue);
    if (deps == _leaveDeps) return;
    _leaveDeps = deps;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    if (!shown || staged || _hidden) return;
    if (liveEnded || (over && liveId == null)) {
      _leave(liveEnded && summaryDue ? math.max(holdMs, graceMs) : holdMs);
    } else if (liveId == null) {
      if (sawStage) {
        _later(() => _seen = _seen.copyWith(ended: true), graceMs);
      } else {
        // The one leave that fires on nothing having happened, so it asks again as it fires. Seen once in the browser
        // pane and never again: a play after one that had run hidden left at eight seconds, mid-run. The clearing
        // above stops this timer the moment a stage or a run is seen, and no path to a survivor was found; this
        // makes sure.
        _leave(math.max(0, _seen.openedAt + openGraceMs - _clock()), () => widget.stage != null || _live != null || _seen.sawStage);
      }
    }
  }

  // Since Done: wall time from the opening, a second at a time, paused while hidden and true again on return.
  void _syncClock() {
    final deps = (_seen.shown, _hidden, _seen.key);
    if (deps == _clockDeps) return;
    _clockDeps = deps;
    _beat?.cancel();
    _beat = null;
    if (!_seen.shown || _hidden) return;
    _now = _clock();
    _beat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = _clock());
    });
  }

  void _carryOn() {
    setState(() {
      _seen = _seen.copyWith(shown: false, leaving: false);
      _sync();
    });
    (widget.haptic ?? fireMotor)(HapticKind.selection);
  }

  void _stop() {
    unawaited(cancelRun(widget.noteId));
    (widget.haptic ?? fireMotor)(HapticKind.warning);
  }

  // The breath, stepped with each report and no faster than `hazeHz`: the words are drawn again on any change, and
  // every report changes the text, so one drawing carries both. Nothing steps while nothing streams.
  void _stepHaze(int reported, int? percent, bool hazeOn) {
    final deps = (reported, percent, hazeOn);
    if (deps == _hazeDeps) return;
    _hazeDeps = deps;
    if (!hazeOn) return;
    final at = _clock().toDouble();
    if (at - _lastStep < 1000 / hazeHz) return;
    _lastStep = at;
    final breath = 0.5 - 0.5 * math.cos((at % _breathMs) / _breathMs * math.pi * 2);
    _frequency = ui.Offset(_fixed(_low[0] + (_high[0] - _low[0]) * breath, 4), _fixed(_low[1] + (_high[1] - _low[1]) * breath, 4));
    _hazeWrites += 1;
  }

  // After a layout: the current line kept at the anchor, under the die; and the haze held to the filter budget
  // (art/edge_strips.dart), asked again whenever the list's box may have changed - the Fold's unfold changes it.
  void _afterLayout(int? currentAt, int index, bool streaming, bool still, double gap) {
    if (!mounted || !_seen.shown) return;
    final list = _list.currentContext?.findRenderObject();
    if (list is! RenderBox || !list.hasSize) return;
    if (!_seen.still) {
      final fits = withinPictureBudget(list.size.width * 1.1, list.size.height * 1.3, MediaQuery.devicePixelRatioOf(context));
      if (fits != _fits) setState(() => _fits = fits);
    }
    final anchored = (currentAt, _seen.key);
    if (anchored == _anchored || currentAt == null || index < 0 || !_scroll.hasClients) return;
    final column = list is RenderFlex ? list : null;
    if (column == null || index >= column.childCount) return;
    var child = column.firstChild;
    for (var i = 0; i < index; i += 1) {
      child = column.childAfter(child!);
    }
    if (child == null) return;
    _anchored = anchored;
    // host.scrollTop = Math.max(0, el.offsetTop - host.clientHeight * ANCHOR): the list's top padding is that share
    // of the pane, so what is left is the line's place in the list.
    final top = (child.parentData! as BoxParentData).offset.dy + (index > 0 ? gap : 0);
    final to = top.clamp(0.0, _scroll.position.maxScrollExtent);
    // .pane { scroll-behavior: smooth; }
    // .scene[data-mode='thought'] .pane, [data-mode='findings'] .pane, [data-mode='prose'] .pane { scroll-behavior: auto; }
    // .scene[data-still] .pane { scroll-behavior: auto; }
    if (streaming || still || (to - _scroll.offset).abs() < 0.5) {
      _scroll.jumpTo(to);
    } else {
      unawaited(_scroll.animateTo(to, duration: const Duration(milliseconds: 320), curve: context.tokens.curve('glacier-ease-out')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final seen = _seen;
    if (!seen.shown) {
      final gone = widget.onGone;
      if (_wasUp && gone != null) {
        // After the frame: whoever is told may be building.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) gone();
        });
      }
      _wasUp = false;
      return const SizedBox.shrink();
    }
    _wasUp = true;

    final t = context.tokens;
    final media = MediaQuery.of(context);
    final stage = widget.stage;
    final live = _live;
    final liveEnded = live != null && ended(live);
    final staged = stage != null;
    final still = seen.still;
    // The stylesheet's own `@media (prefers-reduced-motion: reduce)` answers the switch as it is now.
    final quiet = still || media.disableAnimations;
    final wide = wideScreen(media.size);
    final inline = widget.inline;

    final input = SceneInput(stage: stage, download: stage != null ? widget.refining?.value.download : null, run: live, hasJob: widget.hasJob, compared: seen.compared, ended: seen.ended && live == null);

    // The part of the run the feed reads, keyed on those fields alone: a report that moves only the clock or the
    // readings (every 120 ms while the model loads) must not split the transcript and the thought again. Split again
    // only when the run's words or the stage change, never on the note's own redraws; and not while hidden.
    final feedRun = live == null ? null : FeedRun.of(live);
    final feedDeps = (stage, feedRun, widget.heard, widget.body, _hidden);
    if (_feed == null || feedDeps != _feedDeps) {
      _feedDeps = feedDeps;
      if (!(_hidden && _feed != null)) _feed = feedOf(stage: stage, run: feedRun, heard: widget.heard, body: widget.body);
    }
    final feed = _feed!;
    final lines = paneWindow(feed);
    final current = feed.current;
    final currentAt = current != null && current < feed.lines.length ? feed.lines[current].at : null;

    final pins = pinsOf(live?.hardware?.cores);
    final hardwareNow = live?.hardware;
    // The pins go out with the rings at an end: an ended run keeps its last sample, but the cores are no longer its.
    final _Picture drawn = (
      warmth: warmthOf(input),
      glowStep: glowStepOf(glowOf(live)),
      pins: pins,
      litPins: live != null && hardwareNow != null && _pastLoading(live) && !ended(live) ? litPinsOf(hardwareNow.cpuPercent, pins) : 0,
      step: workingStep(input),
    );
    final picture = _hidden && _picture != null ? _picture! : drawn;
    _picture = picture;
    _warmth = picture.warmth;
    _mode = feed.mode;

    final hazeOn = !still && !_hidden && _fits && preferences.value.wispEdge && picture.warmth != Warmth.cold;
    _hazeOn = hazeOn;
    _stepHaze(live?.elapsedMs ?? 0, stage?.percent, hazeOn);
    // The bend, which changes only when the warmth does.
    final bend = _fixed(_bend * _share(picture.warmth), 2);

    final steps = stepsOf(input);
    final title = sceneTitle(input);
    final detail = sceneDetail(input);
    final queued = live?.phase == RunPhase.queued;
    final past = live != null && _pastLoading(live);
    final hardware = past ? live.hardware : null;
    final tempC = hardware?.tempC;
    final streaming = feed.mode == FeedMode.thought || feed.mode == FeedMode.findings || feed.mode == FeedMode.prose;
    final over = liveEnded || seen.ended;

    final ink = t.color('app-ink');
    final ink2 = t.color('app-ink-2');
    final ink3 = t.color('app-ink-3');
    final easeOut = t.curve('glacier-ease-out');
    final sm = t.fontSize('sm');
    final xs = t.fontSize('xs');
    final em = t.lenOf('1em');

    // .head { grid-area: head; display: grid; gap: var(--glacier-space-1); }
    final h4 = t.len('app-h4');
    // .title {
    //   margin: 0;
    //   font-size: var(--app-h4);
    //   font-weight: var(--glacier-font-weight-bold);
    //   letter-spacing: var(--app-tracking-title);
    //   line-height: 1.2;
    //   color: var(--app-ink);
    //   font-variant-numeric: tabular-nums;
    // }
    // .titleText { display: block; }
    final titleStyle = _tabular(t.textAt(h4, weight: 'bold', color: ink, height: 1.2, tracking: t.len('app-tracking-title', em: h4)));
    final pieces = titlePieces(title);
    Widget heading = Semantics(
      key: const ValueKey('at-work-heading'),
      header: true,
      // The progress numbers are not read: a heading that changed eight times a second would never be finished.
      label: [for (final piece in pieces) if (!piece.number) piece.text].join(),
      child: ExcludeSemantics(child: Text(title, key: const ValueKey('at-work-title'), style: titleStyle)),
    );
    if (wide) {
      // Two lines' room for the title, its words at the foot of it, so a title that wraps ("is writing what it
      // found.") and one that does not ("is thinking it through.") leave the steps and the counters where they were:
      // the group is centred, and without this it moved half a line between phases.
      // .scene[data-wide] .title { display: grid; align-content: end; min-block-size: 2.4em; }
      heading = ConstrainedBox(constraints: BoxConstraints(minHeight: 2.4 * h4), child: Column(mainAxisAlignment: MainAxisAlignment.end, mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [heading]));
    }
    final head = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        SizedBox(height: t.space(1)),
        // .detail { margin: 0; min-block-size: 1.4em; font-size: var(--glacier-font-size-sm); line-height: 1.4; color: var(--app-ink-2); }
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: 1.4 * sm),
          child: Text(detail, key: const ValueKey('at-work-detail'), style: t.textAt(sm, color: ink2, height: 1.4)),
        ),
        // .unseen { composes: app-unseen from global; margin: 0; }  aria-live="polite"
        Semantics(key: const ValueKey('at-work-live'), liveRegion: true, label: liveWords(input), child: const SizedBox(width: double.infinity)),
      ],
    );

    // The picture: the pane of words filling the box, the phone centred over it. The phone's box is the drawing's
    // own ratio, 240 by 544, its column of stipple inside it, so the heat never reaches the title.
    // .picture { position: relative; display: grid; place-items: center; align-self: center; inline-size: 100%;
    //   block-size: 100%; max-block-size: min(46dvh, 460px); min-block-size: 0; overflow: hidden; }
    final gap = 0.3 * 14;
    final index = currentAt == null ? -1 : lines.indexWhere((line) => line.at == currentAt);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterLayout(currentAt, index, streaming, quiet, gap));
    final pictureBox = ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The pane: the words behind the phone, fading in at the top and out at the bottom. The solid band starts
          // under the column of stipple above the phone (its dots reach a tenth of the drawing), so the first line is
          // not read through the dots.
          // .pane { position: absolute; inset: 0; overflow: hidden; scroll-behavior: smooth; container-type: size;
          //   mask-image: linear-gradient(to bottom, transparent, #000 18%, #000 88%, transparent); }
          Semantics(
            label: 'What is being read and thought',
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                stops: [0, 0.18, 0.88, 1],
              ).createShader(bounds),
              child: LayoutBuilder(
                builder: (context, pane) => SingleChildScrollView(
                  key: const ValueKey('at-work-pane'),
                  controller: _scroll,
                  physics: const NeverScrollableScrollPhysics(),
                  child: AnimatedBuilder(
                    animation: _scroll,
                    // The haze: on the pane's list, the part of it the pane shows.
                    builder: (context, list) => EdgeStrips(
                      strips: hazeOn && bend > 0
                          ? [HazeStrip(rect: Rect.fromLTWH(0, _scroll.hasClients ? _scroll.offset : 0, pane.maxWidth, pane.maxHeight), frequency: _frequency, bend: bend)]
                          : const [],
                      repaint: _kit,
                      child: list,
                    ),
                    // Room above and below, so the first line can sit where the current line is kept (72% down the
                    // pane, under the die's pins) and the last can be scrolled up to it.
                    // .list { display: grid; gap: 0.3em; margin: 0; padding: 72cqb var(--glacier-space-1) 24cqb;
                    //   list-style: none; font-size: 14px; line-height: 1.35; text-align: center; overflow-wrap: anywhere; }
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(t.space(1), _anchor * pane.maxHeight, t.space(1), 0.24 * pane.maxHeight),
                      child: Column(
                        key: _list,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, line) in lines.indexed)
                            Padding(
                              key: ValueKey(line.at),
                              padding: EdgeInsets.only(top: i > 0 ? gap : 0),
                              child: AtWorkLine(
                                line: line,
                                place: currentAt == null || line.at > currentAt ? LinePlace.after : (line.at < currentAt ? LinePlace.before : LinePlace.current),
                                ended: over,
                                streaming: streaming,
                                still: quiet,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // .picture > svg { position: absolute; inset: 0; z-index: 1; margin: auto; block-size: 100%; inline-size: auto; }
          IgnorePointer(child: HotPhone(warmth: picture.warmth, glowStep: picture.glowStep, litPins: picture.litPins, pins: picture.pins, step: picture.step, still: still)),
        ],
      ),
    );

    // .steps { grid-area: steps; display: grid; gap: 0.45em; margin: 0; padding: 0; list-style: none;
    //   font-size: var(--glacier-font-size-sm); line-height: 1.3; }
    final stepList = Semantics(
      container: true,
      label: 'The steps',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, step) in steps.indexed) ...[
            if (i > 0) SizedBox(height: 0.45 * sm),
            AtWorkStepRow(key: ValueKey(step.id), step: step, queued: queued, still: quiet),
          ],
        ],
      ),
    );

    // The counters: four tiles of one height, a label over a value over a bar, a unit, or nothing.
    // .counters { grid-area: counters; display: grid; grid-template-columns: repeat(4, minmax(0, 1fr));
    //   gap: var(--glacier-space-2); margin: 0; }
    final tiles = [
      AtWorkTile(label: 'Heat', value: !past ? '' : (tempC != null ? '${(tempC + 0.5).floor()} °C' : 'No reading'), bar: true, share: tempC != null ? heatShare(tempC) : null, still: quiet),
      AtWorkTile(
        label: 'CPU',
        value: !past ? '' : (hardware != null ? '${(hardware.cpuPercent + 0.5).floor()}%' : 'No reading'),
        bar: true,
        share: hardware != null && hardware.cores != 0 ? cpuShare(hardware.cpuPercent, hardware.cores) : null,
        still: quiet,
      ),
      AtWorkTile(label: 'Pace', value: live != null && past ? paceNumber(live.tokensPerSecond) : '', unit: 'a second', still: quiet),
      AtWorkTile(label: 'Since Done', value: clock(math.max(0, _now - seen.openedAt)), still: quiet),
    ];
    final counters = Semantics(
      container: true,
      label: 'The phone’s readings',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0) SizedBox(width: t.space(2)),
            Expanded(child: tile),
          ],
        ],
      ),
    );

    // .foot { grid-area: foot; margin: 0; font-size: var(--glacier-font-size-xs); line-height: 1.4; text-align: center;
    //   color: var(--app-ink-3); }
    // .scene[data-wide] .foot { text-align: start; }
    final foot = Text('It carries on behind the note. Nothing leaves the phone.', textAlign: wide ? TextAlign.start : TextAlign.center, style: t.textAt(xs, color: ink3, height: 1.4));

    // .words { grid-area: words; display: flex; justify-content: center; gap: var(--glacier-space-6); }
    // .scene[data-wide] .words { justify-content: flex-start; }
    // .word { font-weight: var(--glacier-font-weight-semibold); color: var(--app-ink); }
    final wordStyle = t.textAt(em, weight: 'semibold', color: ink);
    final words = Row(
      mainAxisAlignment: wide ? MainAxisAlignment.start : MainAxisAlignment.center,
      children: [
        if (live != null && !liveEnded && !staged) ...[
          AppWord(key: const ValueKey('at-work-stop'), onPressed: _stop, child: Text('Stop', style: wordStyle)),
          SizedBox(width: t.space(6)),
        ],
        AppWord(key: const ValueKey('at-work-back'), onPressed: _carryOn, child: Text('Back to the note', style: wordStyle)),
      ],
    );

    // A wide window that is short (the cover screen turned landscape, a small window on the Mac): the side's rows do
    // not fit beside the picture, so the scene scrolls rather than clipping the words off its foot.
    // @media (max-height: 520px) { .scene[data-wide] { align-content: start; overflow-y: auto; } }
    final short = wide && media.size.height <= 520;
    final Widget grid;
    if (wide) {
      // A wide screen (the Fold opened out): the picture on the left, everything said on the right, the hinge in the
      // gap. The picture spans both rows and the grid centres the group; the title sits at the end of its row and the
      // rest at the start of theirs, so the two halves meet at the middle of the picture.
      // .scene[data-wide] { grid-template-columns: minmax(0, 1.15fr) minmax(0, 1fr); grid-template-rows: auto auto;
      //   grid-template-areas: 'picture head' 'picture side'; column-gap: var(--glacier-space-10);
      //   row-gap: var(--glacier-space-4); align-content: center; }
      // .scene[data-wide] .head { align-self: end; }
      // .scene[data-wide] .picture { block-size: min(64dvh, 560px); max-block-size: none; }
      // .scene[data-wide] .side { grid-area: side; display: flex; flex-direction: column; align-self: start;
      //   gap: var(--glacier-space-4); min-inline-size: 0; }
      final side = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [stepList, SizedBox(height: t.space(4)), counters, SizedBox(height: t.space(4)), foot, SizedBox(height: t.space(4)), words],
      );
      grid = _SceneGrid(wide: true, rowGap: t.space(4), columnGap: t.space(10), picture: math.min(0.64 * media.size.height, 560), start: short, children: [head, pictureBox, side]);
    } else {
      // .scene { display: grid; grid-template-columns: minmax(0, 1fr);
      //   grid-template-rows: auto minmax(0, 1fr) auto auto auto auto;
      //   grid-template-areas: 'head' 'picture' 'steps' 'counters' 'foot' 'words'; row-gap: var(--glacier-space-3); }
      // On a phone the side is nothing but its children, each in its own row.
      // .side { display: contents; }
      grid = _SceneGrid(wide: false, rowGap: t.space(3), columnGap: 0, picture: math.min(0.46 * media.size.height, 460), start: false, children: [head, pictureBox, stepList, counters, foot, words]);
    }

    // .scene { position: fixed; inset: 0; z-index: 48;
    //   padding: calc(var(--app-inset-top) + var(--glacier-space-4)) var(--app-gutter-end)
    //     calc(var(--app-safe-bottom) + var(--glacier-space-3)) var(--app-gutter-start);
    //   overflow: hidden; background: var(--app-paper); color: var(--app-ink);
    //   transition: opacity 260ms var(--glacier-ease-out); }
    // The bench's: in its host, under the bench's bar, with no status bar to pad for.
    // .scene[data-inline] { position: absolute; padding-block: var(--glacier-space-4) var(--glacier-space-3); }
    final padding = EdgeInsets.fromLTRB(
      t.len('app-gutter-start'),
      (inline ? 0 : t.len('app-inset-top')) + t.space(4),
      t.len('app-gutter-end'),
      (inline ? 0 : t.len('app-safe-bottom')) + t.space(3),
    );
    final padded = Padding(padding: padding, child: grid);
    return OnBack(
      active: _armed,
      onBack: _carryOn,
      child: Semantics(
        container: true,
        label: 'The models at work on this note',
        // .scene[data-leaving] { opacity: 0; pointer-events: none; }
        child: IgnorePointer(
          ignoring: seen.leaving,
          child: AnimatedOpacity(
            opacity: seen.leaving ? 0 : 1,
            duration: quiet ? Duration.zero : const Duration(milliseconds: leaveMs),
            curve: easeOut,
            child: ColoredBox(
              key: const ValueKey('at-work'),
              color: t.color('app-paper'),
              child: SizedBox.expand(
                child: ClipRect(
                  child: DefaultTextStyle(
                    style: t.textAt(em, color: ink),
                    child: short ? SingleChildScrollView(padding: padding, child: grid) : padded,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _tabular(TextStyle style) => style.copyWith(fontFeatures: [...?style.fontFeatures, const ui.FontFeature.tabularFigures()]);

/// Where a line stands against the one being read or written (`data-place`); [name] is the web's word.
enum LinePlace { before, current, after }

/// One line of the pane (`.line`). Public so a test can read its place.
class AtWorkLine extends StatefulWidget {
  const AtWorkLine({super.key, required this.line, required this.place, required this.ended, required this.streaming, required this.still});

  final FeedLine line;
  final LinePlace place;

  /// The settle: with the die cooled and the rings gone back in, the words go to the quiet ink too.
  final bool ended;

  /// The model is streaming: a line arriving rises in.
  final bool streaming;
  final bool still;

  @override
  State<AtWorkLine> createState() => _AtWorkLineState();
}

class _AtWorkLineState extends State<AtWorkLine> with SingleTickerProviderStateMixin {
  // A line arriving while the model streams rises in (LaunchScreen's keyframes); the read modes only move the head.
  // .list[data-streaming] .line { animation: rise 320ms var(--glacier-ease-out) both; }
  // @keyframes rise { from { opacity: 0; transform: translateY(6px); } }
  late final AnimationController _rise = AnimationController(vsync: this, duration: const Duration(milliseconds: 320), value: 1);

  @override
  void initState() {
    super.initState();
    if (widget.streaming && !widget.still) _rise.forward(from: 0);
  }

  @override
  void didUpdateWidget(AtWorkLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    // The list gaining `data-streaming` gives every line it holds the animation, as a new rule does on the page.
    if (widget.streaming && !old.streaming && !widget.still) {
      _rise.forward(from: 0);
    } else if (!widget.streaming || widget.still) {
      _rise.value = 1;
    }
  }

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final line = widget.line;
    // .line { color: var(--app-ink-3); transition: color 600ms var(--glacier-ease-out); }
    // .line[data-place='before'] { color: var(--app-ink-2); }
    // .line[data-place='current'] { color: var(--app-ink); }
    // .line[data-strong] { font-weight: var(--glacier-font-weight-bold); color: var(--app-ink); }
    // .scene[data-ended] .line, ... { color: var(--app-ink-3); }
    final color = widget.ended
        ? t.color('app-ink-3')
        : line.strong
            ? t.color('app-ink')
            : switch (widget.place) { LinePlace.before => t.color('app-ink-2'), LinePlace.current => t.color('app-ink'), LinePlace.after => t.color('app-ink-3') };
    final curve = CurvedAnimation(parent: _rise, curve: t.curve('glacier-ease-out'));
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => curve.value >= 1 ? child! : Opacity(opacity: curve.value, child: Transform.translate(offset: Offset(0, 6 * (1 - curve.value)), child: child)),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        // .scene[data-still] .line { transition: none; }
        duration: widget.still ? Duration.zero : const Duration(milliseconds: 600),
        curve: t.curve('glacier-ease-out'),
        builder: (context, shade, _) => Text(line.text, textAlign: TextAlign.center, style: t.textAt(14, weight: line.strong ? 'bold' : 'regular', color: shade ?? color, height: 1.35)),
      ),
    );
  }
}

/// One step of the list (`.step`): its mark, its words, and what it found. Public so a test can read its state.
class AtWorkStepRow extends StatelessWidget {
  const AtWorkStepRow({super.key, required this.step, required this.queued, required this.still});

  final Step step;

  /// The run is waiting for the model: the load step wears an hourglass and does not turn.
  final bool queued;
  final bool still;

  bool get _working => step.state == StepState.working;

  /// The mark this step wears now.
  LucideIcon get icon => step.state == StepState.done ? Lucide.check : (step.id == StepId.load && _working && queued ? Lucide.hourglass : stepIcons[step.id]!);

  /// Whether the mark turns (`data-turn`): the loader, while the model loads.
  bool get turning => step.id == StepId.load && _working && !queued;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    // .step { display: flex; align-items: baseline; gap: 0.55em; color: var(--app-ink-3); }
    // .step[data-state='working'] { color: var(--app-ink); font-weight: var(--glacier-font-weight-semibold); }
    // .step[data-state='done'] { color: var(--app-ink-2); }
    final color = switch (step.state) { StepState.working => t.color('app-ink'), StepState.done => t.color('app-ink-2'), StepState.waiting || StepState.skipped => t.color('app-ink-3') };
    final style = t.textAt(sm, weight: _working ? 'semibold' : 'regular', color: color, height: 1.3);
    final mark = AppIcon(icon, size: 15, strokeWidth: 2.2, color: color);
    final detail = step.detail;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // On the first line of its words, so a detail that wraps (the listen step's, at 412 wide) leaves the mark
        // where it was.
        // .stepMark { display: inline-grid; place-items: center; flex: none; align-self: flex-start;
        //   margin-block-start: 0.1em; inline-size: 1.1em; block-size: 1.1em; }
        Padding(
          padding: EdgeInsets.only(top: 0.1 * sm),
          child: SizedBox.square(
            dimension: 1.1 * sm,
            // The loader turns while the model loads: the one thing that moves while it does.
            // .stepMark[data-turn] svg { animation: turn 900ms linear infinite; }
            // .scene[data-still] .stepMark[data-turn] svg { animation: none; }
            child: OverflowBox(maxWidth: 15, maxHeight: 15, minWidth: 15, minHeight: 15, child: turning && !still ? _Turn(child: mark) : mark),
          ),
        ),
        SizedBox(width: 0.55 * sm),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: step.words,
              children: [
                // .stepDetail { font-weight: var(--glacier-font-weight-regular); color: var(--app-ink-3); }
                if (detail != null && detail.isNotEmpty) TextSpan(text: ' $detail', style: t.textAt(sm, color: t.color('app-ink-3'), height: 1.3)),
              ],
            ),
            style: style,
          ),
        ),
      ],
    );
  }
}

/// `@keyframes turn { to { transform: rotate(1turn); } }`: once round every 900 ms, for as long as it is shown.
class _Turn extends StatefulWidget {
  const _Turn({required this.child});

  final Widget child;

  @override
  State<_Turn> createState() => _TurnState();
}

class _TurnState extends State<_Turn> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _turn, child: widget.child);
}

/// One counter tile: a label, a value (or a blank of the same height), and a bar, a unit, or nothing under it
/// (`Tile`). Public so a test can read its value.
class AtWorkTile extends StatelessWidget {
  const AtWorkTile({super.key, required this.label, required this.value, this.bar = false, this.share, this.unit, required this.still});

  final String label;
  final String value;

  /// Whether the tile has a bar under it (the page's `share !== undefined`); [share] null is an empty one.
  final bool bar;
  final double? share;
  final String? unit;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final h3 = t.len('app-h3');
    final sm = t.fontSize('sm');
    final xs = t.fontSize('xs');
    final words = value != '' && !RegExp(r'\d').hasMatch(value);
    final filled = share == null ? 0.0 : (share! * 100 + 0.5).floor() / 100;
    // .tileValue { margin: 0; min-block-size: 1.15em; font-size: var(--app-h3);
    //   font-weight: var(--glacier-font-weight-semibold); line-height: 1.15; color: var(--app-ink);
    //   font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; }
    // "No reading" is words, not a number: smaller, the same height, so the row never reflows.
    // .tileValue[data-words] { font-size: var(--glacier-font-size-sm); min-block-size: calc(var(--app-h3) * 1.15);
    //   display: flex; align-items: flex-end; color: var(--app-ink-2); }
    final valueStyle = words ? _tabular(t.textAt(sm, weight: 'semibold', color: t.color('app-ink-2'), height: 1.15)) : _tabular(t.textAt(h3, weight: 'semibold', color: t.color('app-ink'), height: 1.15));
    return Semantics(
      container: true,
      // .tile { display: grid; grid-template-rows: auto auto 1em; gap: 2px; min-inline-size: 0; }
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .tileLabel { composes: app-eyebrow from global; white-space: nowrap; }
          // .app-eyebrow { margin: 0; font-size: var(--glacier-font-size-xs); font-weight: var(--glacier-font-weight-bold);
          //   letter-spacing: var(--app-tracking-caps); text-transform: uppercase; color: var(--app-ink-3); }
          Semantics(
            label: label,
            child: ExcludeSemantics(
              child: Text(label.toUpperCase(), maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: t.textAt(xs, weight: 'bold', color: t.color('app-ink-3'), tracking: t.len('app-tracking-caps', em: xs))),
            ),
          ),
          const SizedBox(height: 2),
          ClipRect(
            child: SizedBox(
              height: 1.15 * h3,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(value, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: valueStyle),
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: t.lenOf('1em'),
            child: bar
                // The bar under a share (format/AiCard.module.css's meter).
                // .tileBar { align-self: center; margin: 0; block-size: 2px; border-radius: 1px;
                //   background: color-mix(in oklch, var(--app-ink) 14%, transparent); overflow: hidden; }
                // .tileBar > span { display: block; block-size: 100%; background: var(--app-ink);
                //   transition: inline-size 300ms ease-out; }
                // .scene[data-still] .tileBar > span { transition: none; }
                ? ExcludeSemantics(
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(1),
                        child: SizedBox(
                          height: 2,
                          width: double.infinity,
                          child: ColoredBox(
                            color: t.colorOf('color-mix(in oklch, var(--app-ink) 14%, transparent)'),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(end: filled),
                              duration: still ? Duration.zero : const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              builder: (context, at, _) => FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: at.clamp(0.0, 1.0), child: ColoredBox(color: t.color('app-ink'))),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                // .tileUnit { margin: 0; font-size: var(--glacier-font-size-xs); line-height: 1; color: var(--app-ink-3); }
                : Align(alignment: Alignment.topLeft, child: Text(unit ?? '', maxLines: 1, softWrap: false, style: t.textAt(xs, color: t.color('app-ink-3'), height: 1))),
          ),
        ],
      ),
    );
  }
}

/// The haze over the part of the list the pane shows: the list's own picture thrown about by two octaves of fractal
/// noise, as the page's filter did it (`feTurbulence` at `seed="7"` into `feDisplacementMap`, red across and green
/// down). [frequency] is `baseFrequency`, [bend] is `scale`. The noise is read at the list's own coordinates, so a
/// line carries its bend with it as the pane scrolls.
class HazeStrip extends EdgeStrip {
  const HazeStrip({required this.rect, required this.frequency, required this.bend});

  @override
  final Rect rect;
  final ui.Offset frequency;
  final double bend;

  /// Half the displacement's scale is the furthest a pixel is thrown.
  @override
  double get reach => (bend / 2).ceilToDouble();

  @override
  bool get ready => WispKit.maybe?.tableNow(_hazeSeed) != null;

  @override
  void paint(Canvas canvas, Rect at, ui.Image view, Rect viewRect, double ratio) {
    final kit = WispKit.maybe!;
    final shader = kit.bend(source: view, sourceRect: viewRect, origin: at.topLeft, smoke: WispSmoke.flat(seed: _hazeSeed, frequency: frequency, bend: bend, blur: 0), table: kit.tableNow(_hazeSeed)!);
    canvas.save();
    canvas.translate(at.left, at.top);
    canvas.drawRect(
      Offset.zero & at.size,
      Paint()
        ..shader = shader
        ..isAntiAlias = false,
    );
    canvas.restore();
  }

  @override
  bool operator ==(Object other) => other is HazeStrip && other.rect == rect && other.frequency == frequency && other.bend == bend;

  @override
  int get hashCode => Object.hash(rect, frequency, bend);
}

/// The scene's grid: `.scene`'s rows on a phone, and `.scene[data-wide]`'s two columns on a wide screen.
///
/// On a phone the children are the head, the picture, the steps, the counters, the foot and the words, one a row with
/// [rowGap] between them: every row is as tall as its child but the picture's, which takes what is left
/// (`minmax(0, 1fr)`), the picture standing in the middle of it no taller than [picture]. On a wide screen they are
/// the head, the picture and the side: the picture [picture] tall in the first column across both rows, the head at
/// the foot of the first row of the second column and the side at the top of its second, the two rows sharing
/// whatever the picture needs past them, and the whole centred, or from the top when [start].
class _SceneGrid extends MultiChildRenderObjectWidget {
  const _SceneGrid({required this.wide, required this.rowGap, required this.columnGap, required this.picture, required this.start, required super.children});

  final bool wide;
  final double rowGap;
  final double columnGap;
  final double picture;
  final bool start;

  @override
  _RenderSceneGrid createRenderObject(BuildContext context) => _RenderSceneGrid(wide: wide, rowGap: rowGap, columnGap: columnGap, picture: picture, start: start);

  @override
  void updateRenderObject(BuildContext context, _RenderSceneGrid renderObject) {
    renderObject
      ..wide = wide
      ..rowGap = rowGap
      ..columnGap = columnGap
      ..picture = picture
      ..start = start;
  }
}

class _GridParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSceneGrid extends RenderBox with ContainerRenderObjectMixin<RenderBox, _GridParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _GridParentData> {
  _RenderSceneGrid({required bool wide, required double rowGap, required double columnGap, required double picture, required bool start})
      : _wide = wide,
        _rowGap = rowGap,
        _columnGap = columnGap,
        _picture = picture,
        _start = start;

  bool _wide;
  set wide(bool value) {
    if (value == _wide) return;
    _wide = value;
    markNeedsLayout();
  }

  double _rowGap;
  set rowGap(double value) {
    if (value == _rowGap) return;
    _rowGap = value;
    markNeedsLayout();
  }

  double _columnGap;
  set columnGap(double value) {
    if (value == _columnGap) return;
    _columnGap = value;
    markNeedsLayout();
  }

  double _picture;
  set picture(double value) {
    if (value == _picture) return;
    _picture = value;
    markNeedsLayout();
  }

  bool _start;
  set start(bool value) {
    if (value == _start) return;
    _start = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridParentData) child.parentData = _GridParentData();
  }

  void _place(RenderBox child, double x, double y) => (child.parentData! as _GridParentData).offset = Offset(x, y);

  @override
  void performLayout() {
    final across = constraints.maxWidth;
    final bounded = constraints.hasBoundedHeight;
    final children = getChildrenAsList();
    if (_wide) {
      final head = children[0], picture = children[1], side = children[2];
      // minmax(0, 1.15fr) minmax(0, 1fr)
      final columns = math.max(0.0, across - _columnGap);
      final first = columns * 1.15 / 2.15;
      final second = columns - first;
      head.layout(BoxConstraints.tightFor(width: second), parentUsesSize: true);
      side.layout(BoxConstraints.tightFor(width: second), parentUsesSize: true);
      picture.layout(BoxConstraints.tightFor(width: first, height: _picture));
      // The picture spans both rows: what it needs past them is shared between the two.
      final more = math.max(0.0, _picture - (head.size.height + _rowGap + side.size.height)) / 2;
      final top = head.size.height + more;
      final whole = top + _rowGap + side.size.height + more;
      final from = _start || !bounded ? 0.0 : (constraints.maxHeight - whole) / 2;
      _place(picture, 0, from + (whole - _picture) / 2);
      _place(head, first + _columnGap, from + top - head.size.height);
      _place(side, first + _columnGap, from + top + _rowGap);
      size = constraints.constrain(Size(across, bounded ? constraints.maxHeight : whole));
      return;
    }
    final picture = children[1];
    var fixed = 0.0;
    for (final child in children) {
      if (identical(child, picture)) continue;
      child.layout(BoxConstraints.tightFor(width: across), parentUsesSize: true);
      fixed += child.size.height;
    }
    fixed += _rowGap * (children.length - 1);
    // grid-template-rows: auto minmax(0, 1fr) auto auto auto auto
    final row = bounded ? math.max(0.0, constraints.maxHeight - fixed) : _picture;
    final tall = math.min(row, _picture);
    picture.layout(BoxConstraints.tightFor(width: across, height: tall));
    var y = 0.0;
    for (final child in children) {
      if (identical(child, picture)) {
        // align-self: center
        _place(child, 0, y + (row - tall) / 2);
        y += row + _rowGap;
      } else {
        _place(child, 0, y);
        y += child.size.height + _rowGap;
      }
    }
    size = constraints.constrain(Size(across, bounded ? constraints.maxHeight : y - _rowGap));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}
