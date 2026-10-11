/// The status strip: one line under the header while the model works on the note, and for a while after. A port of
/// `src/app/ai/AiStrip.tsx` and `AiStrip.module.css`.
///
/// Matt chose this over the full card: "a one-line strip under the header, an icon for the phase, the verb, tokens a
/// second, a thin progress bar; tap it for the full AI card with the hardware meters". So the line is the phase's
/// icon (ai/icons.dart), the sentence (ai/words.dart) and a hairline bar that fills as the note is read and then as
/// the answer is written; Stop sits at its end while it runs. Once the run has ended the line says what happened and
/// how long it took, with Undo when the run changed the note and the note still reads as it left it, and a cross to
/// put the line away. Tapping the line opens the card (format/ai_card.dart) - the model, its size, the phone's
/// readings - and under it the note's log (ai/log.dart): every run, newest first, each with its own Undo.
///
/// It draws nothing at all for a note with no run to speak of, so a note looks as it always did until the AI is
/// asked.
///
/// The strip: paper-2 with a hairline, one line of the quiet ink, a bar along its foot, and the card under it when
/// opened. It floats under the header and over the page (the note's screen), so it is never in the smoke.
///
/// What differs:
/// - `useReportedHeight` is done here: [AiStrip.onHeight] is told the strip's height after each layout that changed
///   it, and 0 once it draws nothing or is gone. The height is the laid-out one, where the page's `offsetHeight`
///   was rounded to a whole pixel.
/// - What the card shows of the phone (`useDeviceFacts`) is [AiStrip.deviceFacts], which the app's root makes once
///   (format/device_facts.dart `DeviceFactsController`); without it the card shows the engine's own readings alone.
/// - Each part of the page's `data-phase` is a key for a test: `ValueKey('ai-strip-<phase>')` on the strip.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/widgets.dart' show AppWord;
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../format/ai_card.dart';
import '../format/device_facts.dart';
import '../notes/when.dart';
import '../sheet/css.dart' show snapBorder;
import 'icons.dart';
import 'kinds.dart';
import 'log.dart';
import 'review_stage.dart';
import 'runs.dart';
import 'words.dart';

/// The AI's changes still marked in the note, and the way to keep them all at once (the page's `marks`).
@immutable
class StripMarks {
  const StripMarks({required this.count, required this.keepAll});

  final int count;
  final VoidCallback keepAll;
}

/// See the header (`AiStrip`).
class AiStrip extends StatefulWidget {
  const AiStrip({super.key, required this.noteId, this.onUndo, this.onHeight, this.marks, this.stage, this.deviceFacts, this.now});

  final String noteId;

  /// The review's own stages before its run - listening again, comparing - said while no run is on
  /// (ai/note_review.dart).
  final ReviewStage? stage;

  /// The AI's changes still marked in the note, and the way to keep them all at once; absent with none.
  final StripMarks? marks;

  /// Puts the note back as it was before a run, if the note still reads as the run left it; answers whether it did.
  /// Absent where the note cannot be written (a shared page).
  final bool Function(RunRecord record)? onUndo;

  /// How tall the strip is, told as it changes, so the page can make room under it.
  final void Function(double height)? onHeight;

  /// What the app knows of the phone, for the card (see the header).
  final ValueListenable<DeviceFacts>? deviceFacts;

  /// The moment a log's "when" is said against (`Date.now()`), for a test to hold.
  final int Function()? now;

  @override
  State<AiStrip> createState() => _AiStripState();
}

class _AiStripState extends State<AiStrip> with TickerProviderStateMixin {
  late ValueListenable<RunState?> _run;
  late ValueListenable<List<RunRecord>> _log;
  bool _open = false;
  String? _runId;
  double _told = 0;

  // animation: strip-in 220ms var(--glacier-ease-out) both;
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  // .icon[data-spin] { animation: strip-spin 1.1s linear infinite; }
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  // .words { animation: strip-breathe 1.8s ease-in-out infinite; }
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  // .bar[data-going] > span { animation: strip-going 1.4s ease-in-out infinite alternate; }
  late final AnimationController _going = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool _wasShown = false;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  void _follow() {
    _run = useRun(widget.noteId)..addListener(_changed);
    _log = useRunLog(widget.noteId)..addListener(_changed);
    widget.deviceFacts?.addListener(_changed);
    _runId = _run.value?.id;
  }

  void _unfollow(AiStrip from) {
    _run.removeListener(_changed);
    _log.removeListener(_changed);
    from.deviceFacts?.removeListener(_changed);
  }

  @override
  void didUpdateWidget(AiStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId || !identical(oldWidget.deviceFacts, widget.deviceFacts)) {
      _unfollow(oldWidget);
      _follow();
      _open = false;
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      // A new run closes the card: the line is what matters while it works.
      final id = _run.value?.id;
      if (id != _runId) {
        _runId = id;
        _open = false;
      }
    });
  }

  @override
  void dispose() {
    _unfollow(widget);
    _enter.dispose();
    _spin.dispose();
    _breath.dispose();
    _going.dispose();
    // The page never keeps room for something that is not there.
    final tell = widget.onHeight;
    if (tell != null && _told != 0) WidgetsBinding.instance.addPostFrameCallback((_) => tell(0));
    super.dispose();
  }

  void _tell(double height) {
    if (height == _told) return;
    _told = height;
    final tell = widget.onHeight;
    if (tell == null) return;
    // After the frame: the page pads itself by this, which is a change to what it lays out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _told == height) tell(height);
    });
  }

  /// One motion going while it should, and stopped where it stands otherwise.
  void _run_(AnimationController motion, bool on, {bool reverse = false}) {
    if (on && !motion.isAnimating) {
      motion.repeat(reverse: reverse);
    } else if (!on && motion.isAnimating) {
      motion.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final run = _run.value;
    final stage = widget.stage;
    final marks = widget.marks;
    // The page makes room under the strip: its height, as it changes, and 0 once it is gone.
    final shown = run != null || stage != null || (marks != null && marks.count > 0);
    if (!shown) {
      _wasShown = false;
      _tell(0);
      for (final motion in [_spin, _breath, _going]) {
        motion.stop();
      }
      return const SizedBox.shrink();
    }
    final still = t.reducedMotion;
    if (!_wasShown) {
      _wasShown = true;
      // @media (prefers-reduced-motion: reduce) { .strip { animation: none; } }
      if (still) {
        _enter.value = 1;
      } else {
        _enter.forward(from: 0);
      }
    }

    final ink = t.color('app-ink'), ink2 = t.color('app-ink-2'), ink3 = t.color('app-ink-3'), ink4 = t.color('app-ink-4');
    final over = run != null && ended(run);
    final double? share;
    final String phase;
    final Widget row;
    Widget? card;
    var going = false;
    var breathes = false;
    // .row { gap: var(--glacier-space-1); }
    final gap = SizedBox(width: t.space(1));

    // .line { flex: 1; min-inline-size: 0; display: flex; align-items: center; gap: var(--glacier-space-2);
    //   margin: 0; padding: var(--glacier-space-1) 0; font-size: var(--glacier-font-size-sm);
    //   line-height: var(--glacier-leading-sm); color: var(--app-ink-2); text-align: start; }
    Widget line(LucideIcon icon, String sentence, {bool spin = false, bool chevron = false, bool live = true}) {
      // .icon { flex: none; color: var(--app-ink); }
      Widget drawn = AppIcon(icon, size: 16, strokeWidth: 2.2, color: ink);
      if (spin && !still) drawn = RotationTransition(turns: _spin, child: drawn);
      // .words { flex: 1; min-inline-size: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      Widget words = Text(sentence, key: const ValueKey<String>('ai-strip-words'), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: t.text('sm', color: ink2));
      // A run in progress: the words breathe, so a slow phone still looks alive.
      // @keyframes strip-breathe { 50% { opacity: 0.5; } }
      if (breathes && !still) {
        words = AnimatedBuilder(animation: _breath, builder: (context, child) => Opacity(opacity: breathing(_breath.value, 0.5), child: child), child: words);
      }
      return Padding(
        padding: EdgeInsets.symmetric(vertical: t.space(1)),
        child: Row(
          children: [
            drawn,
            SizedBox(width: t.space(2)),
            Expanded(child: Semantics(liveRegion: live, child: words)),
            if (chevron) ...[
              SizedBox(width: t.space(2)),
              // .chevron { flex: none; color: var(--app-ink-4); }
              AppIcon(_open ? Lucide.chevronUp : Lucide.chevronDown, size: 16, strokeWidth: 2.2, color: ink4),
            ],
          ],
        ),
      );
    }

    if (run == null && stage != null) {
      // The review listening again or comparing: the stage as a line of its own, with its percent along the foot.
      phase = 'stage';
      final percent = stage.percent;
      share = percent == null ? null : percent / 100;
      going = percent == null;
      row = Expanded(child: line(Lucide.ear, '${stage.what}${percent != null && percent > 0 ? ', $percent%' : ''}. ${stage.detail}'));
    } else if (run == null) {
      // No run to speak of, only marks left in the note: one line saying so, with Keep all.
      phase = 'marks';
      share = 0;
      row = Expanded(
        child: Row(children: [Expanded(child: line(Lucide.penLine, marksSentence(marks?.count ?? 0), live: false)), gap, _KeepAll(onKeep: marks?.keepAll)]),
      );
    } else {
      phase = run.phase.name;
      breathes = !over;
      final progress = progressOf(run);
      share = progress;
      going = !over && progress == null;
      final log = _log.value;
      RunRecord? newest;
      for (final record in log) {
        if (record.id == run.id) {
          newest = record;
          break;
        }
      }
      final onUndo = widget.onUndo;
      final undoable = over && newest?.before != null && onUndo != null;
      row = Expanded(
        child: Row(
          children: [
            // The line is a button: the whole of it opens the card.
            Expanded(
              child: GlacierPressable(
                onPressed: () => setState(() => _open = !_open),
                haptic: HapticKind.selection,
                builder: (context, state) => line(Lucide.all[phaseIcons[run.phase]]!, runSentence(run), spin: spins(run.phase), chevron: true),
              ),
            ),
            if (over && marks != null && marks.count > 0) ...[gap, _KeepAll(onKeep: marks.keepAll)],
            if (!over) ...[gap, _Action(key: const ValueKey<String>('ai-strip-stop'), icon: Lucide.square, size: 14, word: 'Stop', label: 'Stop', onPressed: () => cancelRun(widget.noteId))],
            if (undoable && newest != null) ...[gap, _Action(key: const ValueKey<String>('ai-strip-undo'), icon: Lucide.undo2, size: 15, word: 'Undo', label: 'Undo this run', onPressed: () => onUndo(newest!))],
            if (over) ...[
              gap,
              // .dismiss { flex: none; display: grid; place-items: center; inline-size: var(--glacier-space-8);
              //   block-size: var(--glacier-space-8); border-radius: var(--glacier-radius-sm); color: var(--app-ink-3); }
              // .dismiss:active { background: var(--app-paper-3); }
              GlacierPressable(
                key: const ValueKey<String>('ai-strip-dismiss'),
                onPressed: () => dismissRun(widget.noteId),
                semanticLabel: 'Put this away',
                builder: (context, state) => Container(
                  width: t.space(8),
                  height: t.space(8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: state.pressed ? t.color('app-paper-3') : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
                  child: AppIcon(Lucide.x, size: 15, strokeWidth: 2.4, color: ink3),
                ),
              ),
            ],
          ],
        ),
      );
      if (_open) {
        final facts = widget.deviceFacts?.value;
        // .card { border-block-start: var(--glacier-hairline) solid var(--app-rule); }
        card = DecoratedBox(
          key: const ValueKey<String>('ai-strip-card'),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('app-rule'), width: snapBorder(context, t.len('glacier-hairline'))))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (run.thought.isNotEmpty) _Thought(text: run.thought, live: !over),
              if (!over)
                AiCard(
                  model: run.model,
                  phase: cardPhase(run),
                  doing: kindWords(run.kind).doing,
                  promptTokens: run.promptTokens,
                  promptTokensDone: run.promptTokensDone,
                  outputTokens: run.outputTokens,
                  tokensPerSecond: run.tokensPerSecond,
                  elapsedMs: run.elapsedMs,
                  hardware: run.hardware,
                  facts: facts ?? const DeviceFacts(cores: null, memoryGb: null, battery: null),
                  inStrip: true,
                ),
              _RunLog(records: log, onUndo: onUndo, now: widget.now),
            ],
          ),
        );
      }
    }

    _run_(_spin, !still && run != null && spins(run.phase));
    _run_(_breath, !still && breathes);
    _run_(_going, !still && going, reverse: true);

    // The bar along the foot: a hairline track, ink filling it. Without a share to draw, a short run of ink goes to
    // and fro.
    // .bar { position: relative; block-size: 2px; background: color-mix(in oklch, var(--app-ink) 12%, transparent);
    //   overflow: hidden; }
    // .strip[data-phase='failed'] .bar, [data-phase='stopped'] .bar, [data-phase='marks'] .bar { background: transparent; }
    // .strip[data-phase='done'] .bar > span { background: var(--app-ink-3); }
    final Widget? bar = phase == 'marks'
        ? null
        : _Bar(
            track: phase == 'failed' || phase == 'stopped' ? const Color(0x00000000) : t.colorOf('color-mix(in oklch, var(--app-ink) 12%, transparent)'),
            ink: phase == 'done' ? ink3 : ink,
            share: share,
            going: going,
            motion: _going,
            still: still,
          );

    // .row { display: flex; align-items: center; gap: var(--glacier-space-1); min-block-size: 2.25rem;
    //   padding-inline: var(--glacier-space-3) var(--glacier-space-2); }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: t.lenOf('2.25rem')),
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: t.space(3), end: t.space(2)),
            child: Row(children: [row]),
          ),
        ),
        ?bar,
        ?card,
      ],
    );

    // .strip { position: relative; margin: 0 var(--app-gutter-end) 0 var(--app-gutter-start);
    //   border-radius: var(--glacier-radius-md); background: var(--app-paper-2);
    //   border: var(--glacier-hairline) solid var(--app-rule);
    //   box-shadow: 0 6px 18px -12px color-mix(in srgb, var(--app-ink) 40%, transparent); overflow: hidden; }
    final hairline = snapBorder(context, t.len('glacier-hairline'));
    final radius = BorderRadius.circular(t.radius('md'));
    final strip = Padding(
      padding: EdgeInsetsDirectional.only(start: t.len('app-gutter-start'), end: t.len('app-gutter-end')),
      child: _Measured(
        onHeight: _tell,
        child: DecoratedBox(
          key: ValueKey<String>('ai-strip-$phase'),
          decoration: BoxDecoration(
            color: t.color('app-paper-2'),
            borderRadius: radius,
            border: Border.all(color: t.color('app-rule'), width: hairline),
            boxShadow: [BoxShadow(color: t.colorOf('color-mix(in srgb, var(--app-ink) 40%, transparent)'), offset: const Offset(0, 6), blurRadius: 18, spreadRadius: -12)],
          ),
          child: Padding(
            padding: EdgeInsets.all(hairline),
            child: ClipRRect(borderRadius: radius.subtract(BorderRadius.circular(hairline)).resolve(TextDirection.ltr), child: content),
          ),
        ),
      ),
    );

    // @keyframes strip-in { from { opacity: 0; transform: translateY(-4px); } }
    final ease = t.curve('glacier-ease-out');
    return Semantics(
      container: true,
      label: 'The AI on this note',
      child: AnimatedBuilder(
        animation: _enter,
        builder: (context, child) {
          final at = ease.transform(_enter.value);
          return at >= 1 ? child! : Opacity(opacity: at, child: Transform.translate(offset: Offset(0, -4 * (1 - at)), child: child));
        },
        child: strip,
      ),
    );
  }
}

/// Tells its child's height after each layout.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onHeight, required super.child});

  final void Function(double height) onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasured(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) => renderObject.onHeight = onHeight;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onHeight);

  void Function(double height) onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}

/// The bar's fill: as wide as the share, or a short run going to and fro with none to draw.
class _Bar extends StatelessWidget {
  const _Bar({required this.track, required this.ink, required this.share, required this.going, required this.motion, required this.still});

  final Color track;
  final Color ink;
  final double? share;
  final bool going;
  final Animation<double> motion;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final Widget fill;
    if (going) {
      // .bar[data-going] > span { inline-size: 28%; animation: strip-going 1.4s ease-in-out infinite alternate; }
      // @keyframes strip-going { from { transform: translateX(-100%); } to { transform: translateX(360%); } }
      // Reduced motion: .bar[data-going] > span { inline-size: 100%; opacity: 0.35; }
      fill = still
          ? ColoredBox(color: ink.withValues(alpha: ink.a * 0.35), child: const SizedBox.expand())
          : LayoutBuilder(
              builder: (context, constraints) {
                final run = constraints.maxWidth * 0.28;
                return AnimatedBuilder(
                  animation: motion,
                  builder: (context, child) => Transform.translate(offset: Offset(run * (-1 + 4.6 * Curves.easeInOut.transform(motion.value)), 0), child: child),
                  child: Align(alignment: AlignmentDirectional.centerStart, child: SizedBox(width: run, height: 2, child: ColoredBox(color: ink))),
                );
              },
            );
    } else {
      // .bar > span { display: block; block-size: 100%; inline-size: 0; background: var(--app-ink);
      //   transition: inline-size 300ms ease-out; }
      // style={{ inlineSize: `${Math.round(share * 100)}%` }}
      final wide = ((share ?? 0) * 100 + 0.5).floor() / 100;
      fill = TweenAnimationBuilder<double>(
        tween: Tween<double>(end: wide.clamp(0, 1).toDouble()),
        duration: still ? Duration.zero : const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        builder: (context, at, _) => FractionallySizedBox(alignment: AlignmentDirectional.centerStart, widthFactor: at, child: ColoredBox(key: const ValueKey<String>('ai-strip-fill'), color: ink)),
      );
    }
    return ExcludeSemantics(
      child: ClipRect(
        child: SizedBox(key: const ValueKey<String>('ai-strip-bar'), height: 2, child: ColoredBox(color: track, child: fill)),
      ),
    );
  }
}

/// Stop and Undo: an icon and its word, in ink.
class _Action extends StatelessWidget {
  const _Action({super.key, required this.icon, required this.size, required this.word, required this.label, required this.onPressed});

  final LucideIcon icon;
  final double size;
  final String word;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final ink = t.color('app-ink');
    // .action { flex: none; display: inline-flex; align-items: center; gap: 0.3em; margin: 0;
    //   padding: var(--glacier-space-1) var(--glacier-space-2); border-radius: var(--glacier-radius-sm);
    //   font-size: var(--glacier-font-size-sm); font-weight: var(--glacier-font-weight-semibold); color: var(--app-ink); }
    // .action:active { background: var(--app-paper-3); }
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => DecoratedBox(
        decoration: BoxDecoration(color: state.pressed ? t.color('app-paper-3') : null, borderRadius: BorderRadius.circular(t.radius('sm'))),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: size, strokeWidth: 2.4, color: ink),
              SizedBox(width: sm * 0.3),
              Text(word, style: t.textAt(sm, weight: 'semibold', color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keep all: every change the AI has marked in the note, kept at once, from the strip's line (`KeepAll`).
class _KeepAll extends StatelessWidget {
  const _KeepAll({required this.onKeep});

  final VoidCallback? onKeep;

  @override
  Widget build(BuildContext context) => _Action(key: const ValueKey<String>('ai-strip-keep-all'), icon: Lucide.check, size: 15, word: 'Keep all', label: 'Keep every change', onPressed: onKeep);
}

/// The model's own thinking, raw, in a quiet pane that follows the newest line while it streams (Matt: "show the AI
/// reasoning") (`Thought`).
class _Thought extends StatefulWidget {
  const _Thought({required this.text, required this.live});

  final String text;
  final bool live;

  @override
  State<_Thought> createState() => _ThoughtState();
}

class _ThoughtState extends State<_Thought> {
  final ScrollController _pane = ScrollController();

  void _toNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.live && _pane.hasClients) _pane.jumpTo(_pane.position.maxScrollExtent);
    });
  }

  @override
  void initState() {
    super.initState();
    _toNewest();
  }

  @override
  void didUpdateWidget(_Thought oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.live != widget.live) _toNewest();
  }

  @override
  void dispose() {
    _pane.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // The thinking: monospace, small, the quiet ink, a few lines tall and scrolling, following the newest while it
    // streams.
    // .thought { margin: var(--glacier-space-2) var(--glacier-space-3) 0;
    //   padding: var(--glacier-space-2) var(--glacier-space-3); max-block-size: 9rem; overflow-y: auto;
    //   border-radius: var(--glacier-radius-sm); background: var(--app-paper-3);
    //   font: var(--glacier-font-size-xs) / 1.45 var(--glacier-font-mono); color: var(--app-ink-2);
    //   white-space: pre-wrap; overflow-wrap: anywhere; }
    return Semantics(
      label: 'The model\'s thinking',
      child: Container(
        key: const ValueKey<String>('ai-strip-thought'),
        margin: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), 0),
        constraints: BoxConstraints(maxHeight: t.lenOf('9rem')),
        decoration: BoxDecoration(color: t.color('app-paper-3'), borderRadius: BorderRadius.circular(t.radius('sm'))),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          controller: _pane,
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: Text(widget.text, style: t.textAt(t.fontSize('xs'), mono: true, color: t.color('app-ink-2'), height: 1.45)),
          ),
        ),
      ),
    );
  }
}

/// The note's runs, newest first: each its kind's icon, one sentence, when, and Undo where it still applies
/// (`RunLog`).
class _RunLog extends StatelessWidget {
  const _RunLog({required this.records, required this.onUndo, required this.now});

  final List<RunRecord> records;
  final bool Function(RunRecord record)? onUndo;
  final int Function()? now;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    // .none { margin: 0; padding: var(--glacier-space-3); font-size: var(--glacier-font-size-sm); color: var(--app-ink-3); }
    if (records.isEmpty) {
      return Padding(padding: EdgeInsets.all(t.space(3)), child: Text('Nothing yet.', style: t.textAt(sm, color: t.color('app-ink-3'))));
    }
    final undo = onUndo;
    final words = t.text('sm', color: t.color('app-ink-2'));
    // .log { margin: 0; padding: var(--glacier-space-2) var(--glacier-space-3) var(--glacier-space-3);
    //   list-style: none; display: flex; flex-direction: column; gap: var(--glacier-space-2); }
    return Semantics(
      container: true,
      label: 'What the AI did to this note',
      child: Padding(
        key: const ValueKey<String>('ai-strip-log'),
        padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(3)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, record) in records.indexed) ...[
              if (index > 0) SizedBox(height: t.space(2)),
              // .entry { display: flex; align-items: baseline; gap: var(--glacier-space-2);
              //   font-size: var(--glacier-font-size-sm); line-height: var(--glacier-leading-sm); color: var(--app-ink-2); }
              Row(
                key: ValueKey<String>('ai-strip-entry-${record.id}'),
                children: [
                  // .entryIcon { flex: none; align-self: center; color: var(--app-ink); }
                  // .entry[data-outcome='failed'] .entryIcon, [data-outcome='stopped'] .entryIcon { color: var(--app-ink-4); }
                  AppIcon(Lucide.all[kindIcons[record.kind]]!, size: 15, strokeWidth: 2.2, color: record.outcome == RunOutcome.done ? t.color('app-ink') : t.color('app-ink-4')),
                  SizedBox(width: t.space(2)),
                  // .entryWords { flex: 1; min-inline-size: 0; }  .entryWhen { color: var(--app-ink-4); }
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [TextSpan(text: '${recordSentenceOf(record)} '), TextSpan(text: when(record.at, now?.call()), style: TextStyle(color: t.color('app-ink-4')))]),
                      style: words,
                    ),
                  ),
                  if (record.before != null && undo != null) ...[
                    SizedBox(width: t.space(2)),
                    // .entryUndo { min-block-size: 0; padding: 0; font-size: inherit;
                    //   font-weight: var(--glacier-font-weight-semibold); color: var(--app-ink); }
                    AppWord(onPressed: () => undo(record), child: Text('Undo', style: t.textAt(sm, weight: 'semibold', color: t.color('app-ink')))),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
