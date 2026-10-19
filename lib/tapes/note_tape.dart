/// The tape at the top of a note that has a recording: the cassette, Play and where the playhead is, and the things
/// to do with the audio: Add (talk more into the note, the new take appended to the tape), Remove, and Summarize
/// where there is a model. A port of `NoteTape` in `src/app/tapes/NoteTape.tsx`, with `.tape`, `.cassette`,
/// `.side`, `.time`, `.play`, `.edits`, `.edit`, `.warning` and `.problem` of NoteTape.module.css.
///
/// Remove asks a second time on a note with voice memos in it, since the marks stay in the words while the audio
/// they play goes. Summarize asks before writing over a section the person edited, "You edited the summary. Replace
/// it?", and nothing is written until Replace is tapped. Only a spoken note has a tape: with nothing recorded this
/// draws nothing. The cassette plays and pauses when tapped; its reels turn while it plays and the tape winds
/// across, so the picture is the progress bar.
///
/// What differs: the page read three queues itself (`useSummaries`, `useRefining`, `useRun`), and the summary queue
/// is not ported; the strip is handed what they say of this note as a [TapeQueue], and whoever wires the note's
/// screen fills it. The transcript's words are `transcript_words.dart`. The summary word's `title` is its tooltip
/// in semantics; nothing shows it on a phone, as nothing did on the page. Play's pill is drawn here, since
/// `AppPill` is the pill at its own size and `.play` makes it smaller.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../ai/kinds.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/note.dart';
import '../home/home_text.dart' show tabular;
import 'player.dart';
import 'shelf.dart' show tapeDate;
import 'tape.dart';
import 'tape_art.dart';

/// The label's first line is cut to this many letters (`CLIP`).
const int _clip = 22;

/// The recording's summary (`TapeSummary`): how to ask for it, whether the section was edited, and whether the tape
/// has grown since.
@immutable
class TapeSummary {
  const TapeSummary({required this.ask, required this.edited, this.behind = false});

  /// Asks the queue for the summary; with `replace`, over a section the person edited.
  final void Function(bool replace) ask;

  /// Whether the section in the note is no longer the one the app wrote.
  final bool Function() edited;

  /// Whether a take was added since the summary was written.
  final bool behind;
}

/// What the queues say of this note (the page's `useSummaries()`, `useRefining()` and `useRun(note.id)`, each
/// asked about the one note).
@immutable
class TapeQueue {
  const TapeQueue({this.pending = false, this.needsModel = false, this.failed = false, this.refining = false, this.running = false, this.claudeHeld = false, this.failedWhy});

  /// A summary of this note is queued or being written (`summaries.pending.has(id)`).
  final bool pending;

  /// The summary waits for a model to be downloaded (`summaries.needsModel.has(id)`).
  final bool needsModel;

  /// The summary was given up on (`summaries.failed.has(id)`).
  final bool failed;

  /// The meeting is Claude's to write up and waits while Local only is on (ai/summaries.dart `claudeHeld`). The
  /// port's own.
  final bool claudeHeld;

  /// Why the summary was given up on, in Claude's words, where it said (ai/summaries.dart `reasons`). The port's own.
  final String? failedWhy;

  /// The note's better words are still to come (`refining.pending.has(id)`).
  final bool refining;

  /// A summarize run is on this note and has not ended (`run.kind === 'summarize' && !ended(run)`).
  final bool running;

  /// A queued job waits for the note's better words first; only past them is it "Summarizing".
  bool get held => pending && refining;
  bool get summarizing => (pending && !held) || running;
}

/// The strip (`NoteTape`). Draws nothing for a tape with no length.
class NoteTape extends StatefulWidget {
  const NoteTape({super.key, required this.note, required this.title, required this.tape, this.onSpeak, required this.onRemove, required this.hasMemos, this.summary, this.queue = const TapeQueue()});

  final Note note;

  /// The note's name as typed; "Untitled" where it has none.
  final String title;
  final Tape tape;

  /// Record more into the note; left out where nothing records, and Add with it.
  final VoidCallback? onSpeak;

  /// Take the recording off the note (the screen offers Undo).
  final VoidCallback onRemove;

  /// The note holds voice memos, which play from this recording: Remove asks first, and says so.
  final bool hasMemos;

  /// Null where there is no model, and Summarize with it.
  final TapeSummary? summary;
  final TapeQueue queue;

  @override
  State<NoteTape> createState() => _NoteTapeState();
}

class _NoteTapeState extends State<NoteTape> {
  // Remove, on a note with voice memos in it: the word asks once, since the memos go quiet with the recording.
  bool _asking = false;
  Timer? _askingTimer;
  // Summarize, over a section the person edited: the word asks once.
  bool _replacing = false;
  Timer? _replacingTimer;

  void _setAsking(bool on) {
    _askingTimer?.cancel();
    _askingTimer = on ? Timer(const Duration(seconds: 5), () => _setAsking(false)) : null;
    if (mounted) setState(() => _asking = on);
  }

  void _setReplacing(bool on) {
    _replacingTimer?.cancel();
    _replacingTimer = on ? Timer(const Duration(seconds: 8), () => _setReplacing(false)) : null;
    if (mounted) setState(() => _replacing = on);
  }

  @override
  void dispose() {
    _askingTimer?.cancel();
    _replacingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.tape, builder: (context, _) => _strip(context));

  Widget _strip(BuildContext context) {
    final tape = widget.tape;
    if (tape.length <= 0) return const SizedBox.shrink();
    final t = context.tokens;
    final queue = widget.queue;
    final summary = widget.summary;
    final summarizing = queue.summarizing;
    final held = queue.held;
    final summaryLine = queue.needsModel
        ? 'Needs a model.'
        : queue.claudeHeld
            ? 'The summary waits for Claude: Local only is on.'
        : queue.failed
            ? (queue.failedWhy != null ? 'The summary didn’t come. ${queue.failedWhy}' : 'The summary didn’t come.')
            : held
                ? 'The summary comes after the better words.'
                : summarizing
                    ? null
                    : (summary?.behind ?? false)
                        ? 'Summary is from before the last take.'
                        : null;
    final title = widget.title.isEmpty ? 'Untitled' : widget.title;
    final label = title.length > _clip ? '${title.substring(0, _clip - 1).trimRight()}…' : title;
    final moved = tape.playing || tape.at > 0;
    final md = t.fontSize('md');
    final warning = t.text('sm', color: t.color('glacier-text-muted'));

    final edits = <Widget>[
      if (widget.onSpeak != null) _Edit(label: 'Record more into this note', icon: Lucide.mic, word: 'Add', onPressed: widget.onSpeak),
      if (_asking) _Edit(label: "Keep this note's recording", word: 'Keep', onPressed: () => _setAsking(false)),
      _Edit(
        label: _asking ? 'Remove the recording and stop its voice memos' : "Remove this note's recording",
        icon: Lucide.trash2,
        word: 'Remove',
        asking: _asking,
        onPressed: () {
          if (widget.hasMemos && !_asking) {
            _setAsking(true);
          } else {
            _setAsking(false);
            widget.onRemove();
          }
        },
      ),
      if (summary != null && !_replacing)
        _Edit(
          label: 'Summarize the recording',
          tooltip: 'The recording, summarized under the title.',
          icon: summarizing ? Lucide.loaderCircle : Lucide.sparkles,
          working: summarizing,
          word: summarizing ? kindWords(RunKind.summarize).doing : kindWords(RunKind.summarize).label,
          onPressed: summarizing || held
              ? null
              : () {
                  if (summary.edited()) {
                    _setReplacing(true);
                  } else {
                    summary.ask(false);
                  }
                },
        ),
      if (summary != null && _replacing) ...[
        _Edit(
          label: 'Replace the summary you edited',
          word: 'Replace',
          asking: true,
          onPressed: () {
            _setReplacing(false);
            summary.ask(true);
          },
        ),
        _Edit(label: 'Keep the summary as you edited it', word: 'Keep mine', onPressed: () => _setReplacing(false)),
      ],
    ];

    final lines = <Widget>[
      if (_asking) Padding(padding: EdgeInsets.only(top: t.space(1)), child: Text('The voice memos in this note play from this recording. They’ll stop until you undo.', style: warning)),
      if (_replacing) Padding(padding: EdgeInsets.only(top: t.space(1)), child: Text('You edited the summary. Replace it?', style: warning)),
      if (summaryLine != null && !_replacing) Padding(padding: EdgeInsets.only(top: t.space(1)), child: Text(summaryLine, style: warning)),
      if (tape.problem != null) Text(tape.problem!, style: t.textAt(t.fontSize('sm'), color: t.color('app-ink-3'))),
    ];

    return Semantics(
      container: true,
      label: 'Recording',
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start'), t.space(3), t.len('app-gutter-end'), t.space(1)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // `grid-template-columns: minmax(0, 9.5rem) 1fr`, the two set at the middle of the row.
            Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: t.lenOf('9.5rem')),
                  child: GlacierPressable(
                    onPressed: tape.toggle,
                    haptic: null,
                    pressScale: PressScale.control,
                    semanticLabel: tape.playing ? 'Pause the recording' : 'Play the recording',
                    builder: (context, state) => GlacierFocusRing(
                      visible: state.focused,
                      radius: t.radius('md'),
                      offset: 3,
                      child: TapeArt(
                        positionMs: moved ? tape.at : tape.length,
                        // A tape longer than five minutes winds across its whole length in playback, rather than
                        // sitting full from the fifth minute on.
                        lengthMs: math.max(tapeMs, tape.length),
                        playing: tape.playing,
                        title: label,
                        side: tapeDate(widget.note.createdAt).toUpperCase(),
                        counter: counter(tape.length),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: t.space(4)),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: tabular(t.textAt(md, weight: 'semibold', color: t.color('app-ink'))),
                          children: [
                            TextSpan(text: '${counter(tape.at)} '),
                            TextSpan(text: '/ ${counter(tape.length)}', style: tabular(t.textAt(md, color: t.color('app-ink-3')))),
                          ],
                        ),
                      ),
                      SizedBox(height: t.space(2)),
                      _Play(playing: tape.playing, onPressed: tape.toggle),
                      SizedBox(height: t.space(2)),
                      Wrap(spacing: t.space(4), runSpacing: t.space(1), crossAxisAlignment: WrapCrossAlignment.center, children: edits),
                    ],
                  ),
                ),
              ],
            ),
            for (final line in lines) ...[SizedBox(height: t.space(2)), line],
          ],
        ),
      ),
    );
  }
}

/// Play and Pause: `.app-pill` (ink.css) at `.play`'s size, ten of the scale tall with four of it either side and a
/// 16px mark two of it before the word.
class _Play extends StatelessWidget {
  const _Play({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-paper');
    final size = t.fontSize('md');
    return GlacierPressable(
      onPressed: onPressed,
      // The tape gives the touch its own feel.
      haptic: null,
      semanticLabel: playing ? 'Pause' : 'Play',
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        offset: 3,
        color: t.color('app-ink'),
        child: AnimatedScale(
          scale: state.pressed ? 0.98 : 1,
          duration: t.duration('glacier-duration-fast'),
          curve: t.curve('glacier-ease-out'),
          child: Container(
            constraints: BoxConstraints(minHeight: t.space(10)),
            padding: EdgeInsets.symmetric(horizontal: t.space(4)),
            decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('full'))),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(playing ? Lucide.pause : Lucide.play, size: 16, color: ink),
                  SizedBox(width: t.space(2)),
                  Text(playing ? 'Pause' : 'Play', style: t.text('md', weight: 'semibold', color: ink).copyWith(letterSpacing: -0.005 * size, height: 1.2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the quiet words under Play (`.app-word` with `.edit`): its mark and its word, muted until pressed, in the
/// first ink and bold while it is [asking].
class _Edit extends StatelessWidget {
  const _Edit({required this.label, required this.word, required this.onPressed, this.icon, this.asking = false, this.working = false, this.tooltip});

  final String label;
  final String word;
  final VoidCallback? onPressed;
  final LucideIcon? icon;

  /// `data-asking`: the word itself says what goes.
  final bool asking;

  /// The mark turns, once a second (`.working`).
  final bool working;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final button = GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) {
        final color = state.disabled
            ? t.color('glacier-text-subtle')
            : asking || state.pressed
                ? t.color('glacier-text')
                : t.color('glacier-text-muted');
        final mark = icon == null ? null : AppIcon(icon!, size: 15, strokeWidth: 2.2, color: color);
        return GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('sm'),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: t.space(8)),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(1)),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (mark != null) ...[working ? _Turning(child: mark) : mark, SizedBox(width: t.space(1))],
                    Text(word, style: t.text('sm', weight: asking ? 'bold' : 'semibold', color: color)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    return tooltip == null ? button : Semantics(tooltip: tooltip, child: button);
  }
}

/// `.working`: one turn a second, for as long as it is drawn; still under reduced motion.
class _Turning extends StatefulWidget {
  const _Turning({required this.child});
  final Widget child;

  @override
  State<_Turning> createState() => _TurningState();
}

class _TurningState extends State<_Turning> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!context.tokens.reducedMotion) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _controller, child: widget.child);
}
