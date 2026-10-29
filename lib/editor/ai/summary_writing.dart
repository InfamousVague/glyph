/// A meeting's summary being written, drawn where it will land (docs/ACTIVITY.md, In place; Matt, 2026-10-29:
/// ""Writing the summary…" streaming into the meeting note").
///
/// While the note's summary job is live on the app's record of running work (lib/core/background_jobs.dart,
/// `summary:<note>`, this device's or another of the account's), and the note has no `## Summary` section yet, a card
/// stands at the place the section will be written ([summaryPlace]: under the title, above the transcript): the AI's
/// sparkle and "Writing the summary…" in the AI's colour, how far ("2 of 3 parts"), the device where it is another's
/// ("on your Mac"), and the words themselves as they stream in where the job writes as it goes ([Activity.wordsOf]:
/// Claude's stream, or the phone's model's). It gives way to the real section as the write lands, the section being
/// what the note then holds; an open note's run lands its lines into the editor itself, and the card goes with the
/// first of them.
///
/// Nothing of it is in the note: a block drawn between the lines, read from the record, never written into the words
/// or their sync. Calm draws it in ink (the `--activity-*` tokens); where the device asks for less motion the sparkle
/// is still and the words stand as they are, with no caret.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../activity/activity_look.dart';
import '../../core/background_jobs.dart';
import '../../core/summary_text.dart' show summaryHeading, summaryPlace, summarySection;
import '../editor.dart';
import '../media/images.dart' show gutterOf;

/// What the note's screen gives the card: the summary job's id for the note on screen.
class SummaryWritingHooks {
  const SummaryWritingHooks({required this.jobId, this.record});

  /// `summary:<note>`, asked at each drawing (the note on screen may change under the editor).
  final String Function() jobId;

  /// The app's [activity] unless given.
  final Activity? record;

  Activity get _record => record ?? activity;
}

final StateEffectType<Null> _redraw = StateEffect.define<Null>();

final Facet<SummaryWritingHooks?, SummaryWritingHooks?> _hooks = Facet.define<SummaryWritingHooks?, SummaryWritingHooks?>(combine: (values) => values.where((v) => v != null).firstOrNull);

/// The job writing the note's summary, wherever it runs, while it is live.
Job? _writing(SummaryWritingHooks hooks) {
  final id = hooks.jobId();
  for (final job in hooks._record.value) {
    if (job.id == id && job.state.live) return job;
  }
  return null;
}

/// The card, at the section's place, while the job is live and the note has no section yet.
DecorationSet _cardOf(EditorState state) {
  final hooks = state.facet(_hooks);
  if (hooks == null) return Decoration.none;
  final job = _writing(hooks);
  if (job == null) return Decoration.none;
  final body = state.doc.toString();
  if (summarySection(body) != null) return Decoration.none;
  final at = summaryPlace(body).clamp(0, body.length);
  // At the start of the line the section will start on, over it; at the very end, under the last line.
  final end = at >= body.length;
  return Decoration.set([Decoration.widget(widget: SummaryWritingWidget(job.id), block: true, side: end ? 1 : -1).range(at)]);
}

final StateField<DecorationSet> _card = StateField.define<DecorationSet>(
  create: _cardOf,
  update: (decorations, tr) {
    if (tr.docChanged || tr.effects.any((e) => e.isOf(_redraw))) return _cardOf(tr.state);
    return decorations;
  },
  provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
);

/// Hears the record, and draws the card again as the job begins or ends: only then, its words and steps being the
/// card's own to hear.
class _Hearing extends PluginValue {
  _Hearing(this.view, this.hooks) : _was = _writing(hooks) != null {
    hooks._record.addListener(_heard);
  }

  final EditorViewLike view;
  final SummaryWritingHooks hooks;
  bool _was;
  bool _told = false;
  bool _gone = false;

  void _heard() {
    final now = _writing(hooks) != null;
    if (now == _was || _told) return;
    _was = now;
    _told = true;
    scheduleMicrotask(() {
      _told = false;
      if (!_gone) view.dispatch(TransactionSpec(effects: _redraw.of(null)));
    });
  }

  @override
  void update(ViewUpdate update) {}

  @override
  void destroy() {
    _gone = true;
    hooks._record.removeListener(_heard);
  }
}

/// The card where a note's summary is being written ([SummaryWritingHooks]).
Extension summaryWriting(SummaryWritingHooks hooks) => Extension.list(<Extension>[
      _hooks.of(hooks),
      _card,
      ViewPlugin.define<_Hearing>((view) => _Hearing(view, hooks)),
    ]);

/// The card as a block in the editor, at the page's gutter.
class SummaryWritingWidget extends EditorWidget {
  const SummaryWritingWidget(this.jobId);

  final String jobId;

  @override
  bool eq(SummaryWritingWidget other) => other.jobId == jobId;

  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.maybeOf(context);
    final record = view?.state.facet(_hooks)?._record ?? activity;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutterOf(context)),
      child: SummaryWriting(jobId: jobId, record: record),
    );
  }
}

/// What the words so far look like as a section: the model's thinking left out (the phone's model's partial text
/// opens with it, up to `</think>`), and the heading the card says itself.
String summaryWordsSoFar(String sofar) {
  var words = sofar;
  final thought = words.indexOf('</think>');
  if (thought >= 0) {
    words = words.substring(thought + '</think>'.length);
  } else if (words.trimLeft().startsWith('<think>')) {
    return '';
  }
  words = words.trimLeft();
  if (words.startsWith(summaryHeading)) words = words.substring(summaryHeading.length);
  return words.trim();
}

/// How much of the words is drawn: the newest, a few lines' worth.
const int summaryWordsShown = 480;

/// "Writing the summary…" with the sparkle, how far, and the words streaming in: the job [jobId] on [record], drawn
/// again as it changes and as its words come. Nothing once the job has gone.
class SummaryWriting extends StatelessWidget {
  const SummaryWriting({super.key, required this.jobId, this.record});

  final String jobId;
  final Activity? record;

  @override
  Widget build(BuildContext context) {
    final record = this.record ?? activity;
    return ListenableBuilder(
      listenable: record,
      builder: (context, _) {
        final job = record[jobId];
        if (job == null || !job.state.live) return const SizedBox.shrink();
        return ValueListenableBuilder<String>(
          valueListenable: record.wordsOf(jobId),
          builder: (context, sofar, _) => _Card(job: job, words: summaryWordsSoFar(sofar)),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.job, required this.words});

  final Job job;
  final String words;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colour = jobColour(t, JobLook.ai);
    final moves = activityMoves(context);
    final steps = job.steps;
    final where = job.deviceWords;
    final head = [?steps, ?where].join(' · ');
    final shown = words.length > summaryWordsShown ? '…${words.substring(words.length - summaryWordsShown).trimLeft()}' : words;
    final said = ['Writing the summary', ?steps, ?where].join(', ');
    return Semantics(
      key: ValueKey('summary-writing:${job.id}'),
      container: true,
      liveRegion: true,
      label: said,
      child: ExcludeSemantics(
        child: Container(
          margin: EdgeInsets.only(top: t.space(2), bottom: t.space(3)),
          padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(2) + (shown.isEmpty ? 0 : t.space(1))),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: colour.a * 0.07),
            borderRadius: BorderRadius.circular(t.radius('md')),
            border: Border.all(color: colour.withValues(alpha: colour.a * 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  JobGlyph(kind: JobKind.ai, size: 18, moving: job.state == JobState.running && moves),
                  SizedBox(width: t.space(2)),
                  // The words whole; how far gives way first where the room is short.
                  Text('Writing the summary…', maxLines: 1, style: t.text('sm', weight: 'semibold', color: colour)),
                  if (head.isNotEmpty) ...[
                    SizedBox(width: t.space(2)),
                    Flexible(child: Text(head, key: const ValueKey('summary-writing:steps'), maxLines: 1, overflow: TextOverflow.ellipsis, style: _tabular(t.text('xs', color: t.color('glacier-text-muted'))))),
                  ],
                ],
              ),
              if (shown.isNotEmpty) ...[
                SizedBox(height: t.space(2)),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: shown),
                    // A caret at the end while the words come; none where the device asks for less motion.
                    if (moves) WidgetSpan(alignment: PlaceholderAlignment.middle, child: _Caret(colour: colour)),
                  ]),
                  key: const ValueKey('summary-writing:words'),
                  style: t.text('sm', color: t.color('glacier-text-muted')).copyWith(height: 1.45),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The figures of a line set to the same width, so "2 of 3 parts" does not shuffle as it counts.
TextStyle _tabular(TextStyle style) => style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// A thin caret, breathing.
class _Caret extends StatefulWidget {
  const _Caret({required this.colour});

  final Color colour;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _blink,
        child: Container(key: const ValueKey('summary-writing:caret'), width: 2, height: 14, margin: const EdgeInsets.only(left: 2), color: widget.colour),
      );
}
