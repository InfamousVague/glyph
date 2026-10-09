/// Blanks, drawn: a question in curly brackets as the square Matt asked for (docs/DESIGN.md §145, 3). A port of
/// `src/app/editor/blanks.ts`.
///
/// The parser makes no node for `{?…}` (editor/language.ts takes only symmetric delimiter runs), so this reads the
/// lines on screen with the pattern (core/blanks.dart) and draws what the parser calls words: never in code, maths,
/// HTML, a comment, a link's address or front matter. The square is a dashed hairline of the words' own ink, in both
/// inks, round the question, with an icon at its end that says what will happen before anything is pressed: a
/// calculator, a calendar or a globe where the app works it out (core/fill_facts.dart, its answer after the square
/// like a sum's), a question in a speech bubble where the model will answer, a signal where the phone will look it
/// up (ai/fills/web.dart), and a crossed-out signal where it can't be known. In the Markdown view the braces stay in
/// the marks' dim ink; in the Formatted view they go, but on the lines being written.
///
/// A tap on the square places the caret, as on any words: filling is always a separate press, so a tap meant for
/// the caret never wakes the model. The press is the Fill pill at the end of the line (the suggestion pill's look
/// and touch handling, editor/items/suggestions.dart), Fill the blanks in the More sheet, or the palette. On the
/// line being typed the icon, the words after the square and the pill wait until the hands have stopped for 700 ms
/// with the caret outside the braces, so nothing jumps with each letter; a worked-out answer shows at once, as a
/// sum's does.
///
/// A press is handed to the fills' queue (ai/fills/queue.dart), which knows each blank by its question and its order
/// among blanks with that question, and by its range here, mapped through every edit ([blanksField]), while the
/// note is open.
///
/// **What a note's editor adds.** Three things, the first two among its extensions:
///
///     blanks(hooks, still: false)   // this file: the squares, the tracked ranges, the pause, the look
///     fillPanel()                   // fill_panel.dart: the panel a tap on an answer opens
///
/// and the note's screen makes a `FillLanding(noteId, view, wisp: …, owner: …)` (lib/ai/fills/fill_landing.dart)
/// once it has the editor, disposing of it as the note is left, and stacks `EditorFillPanel(view: view)` over the
/// editor (fill_panel.dart), calling `closeFillPanel(view)` when the note scrolls. `hooks` is null where a note is
/// only read; `still: true` is a card's small note.
///
/// **In a drawn table** (lib/editor/tables/table_box.dart, which leaves these out): for each cell, with the cell's
/// text as written `raw` and where it starts in the note `at`, the table calls
/// `drawCell(view, raw, at, plainCell)` and, where the answer is not null, puts that widget in the cell in place of
/// the cell's words; after the last row it puts `tablePill(view, from, to)` where that is not null (`from` and `to`
/// the table's own span); and it draws its cells again when `state.field(blankStamp)` has changed, which counts
/// every redraw asked of the squares.
///
/// What differs:
/// - The square's border is drawn by a widget of its own (blanks_paint.dart), since the view paints a mark run by
///   run and no run knows where its square ends: a piece at each end of the mark, inside it, is the room the border
///   and `padding: 0 0.25em` take there, and the one at the start draws a closed, round-cornered dashed box for
///   each visual line the square is on, as `box-decoration-break: clone` does. Where the square wraps, the page
///   gives each part its own padding in the line (the words move over by it); here the box is drawn that far
///   outside the words at the wrap, and the words stay where they were.
/// - The icon is drawn in the closing brace's place, by one widget that draws the icon, the brace (where the braces
///   show) and the square's end, where the page has a widget before the brace. A line may break either side of a
///   widget here, and the page never breaks one before a `}`; as one widget they stay together. The brace is still
///   the note's own character: the caret stands either side of it, and with the caret inside the braces there is
///   no icon and it is words again. A line may still break between a square's start and its `{?`, or leave an end
///   by itself; such an end is room and no box. An empty blank, `{?}`, with its icon is one widget in the place of
///   all three characters, border and all, so none of it is ever left on another line; with the caret between its
///   braces it is words again.
/// - A widget in a heading's square (the ends, the icon) takes the heading's size by being told the heading's level,
///   since the view gives a widget only the marks of whoever drew it, not the highlighter's. The words after a
///   square and the pill are the line's own size on a heading too, where the page's are the heading's when words
///   follow the square.
/// - `.cm-blank[data-short] { white-space: nowrap }` is not kept: the mark says `data-short` as on the page, and the
///   view has no property that keeps a mark's words on one line (the same as a tag's, lib/editor/items/tags.dart).
/// - A blank being filled does not breathe (`cm-blank-breathe`, 0.45 to 0.8 over 1.6 s): it stands at the 0.6 the
///   stylesheet gives it under `prefers-reduced-motion`, since a run's ink is resolved once, not per frame. The
///   loading icon does turn.
/// - A press on the words after a square or on the pill is the widget's alone (`takesPointer`), where the page
///   stopped a pointer, a mouse and a touch press each its own way (`keepFromEditor`). The icon lets the press
///   through to the editor (`ignoreEvent: false`), as on the page.
/// - `BlankHooks` is a class of functions, `blankHooks.of(hooks)`; `Lookups` is ai/fills/lane.dart's enum.
/// - `editorBlanks(state, whole)`: the state's tree is always the whole note's here (view/syntax_tree.dart parses
///   it whole, in step), so `whole` changes nothing and no parse is cut short.
/// - `openNoteBlanks` is a `ValueNotifier` in place of `externalStore`.
/// - The timers are `Timer`s, and "the view is still in the page" (`view.dom.isConnected`) is the plugin not yet
///   destroyed.
/// - `drawCell` answers a widget (a [BlankCell]) or null, where the page filled the cell's element and answered
///   whether it had; `plain` is the table's own reading of a cell's words. `tablePill` answers a widget or null.
///   Neither is called yet: see above.
/// - The theme is a [LookSheet] for the marks' inks, and the widgets draw their own rules, each cited where it is
///   drawn. `cursor`, `appearance` and the tap highlight have no counterpart.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../ai/fills/lane.dart';
import '../../ai/fills/queue.dart';
import '../../ai/fills/web.dart' show sourceName;
import '../../ai/runs.dart';
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/blanks.dart';
import '../../core/fill_facts.dart';
import '../../core/front_matter.dart';
import '../../core/maths.dart';
import '../../core/preferences.dart';
import '../editor.dart';
import '../items/suggestions.dart' show SuggestWidget, SuggestWord;
import '../items/sums.dart' show AnswerWidget;
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../media/inline_box.dart';
import '../syntax/syntax.dart';
import '../syntax/tree.dart' show Tree;
import '../view/editor_view.dart' show EditorView;
import '../view/line.dart' show EditorRunScope, RenderEditorLine;
import '../view/projection.dart' show SegmentKind;
import '../view/lines.dart';
import '../view/syntax_tree.dart';
import '../view/view_mode.dart';
import 'blanks_paint.dart';

export '../../ai/fills/lane.dart' show Lane, Lookups;
export '../../ai/fills/queue.dart' show FillAgain, FillTarget;

// ---- what the editor knows -----------------------------------------------------------------------------------

/// What the screen gives the squares: whose note, whether the model can run here, and what a press does.
class BlankHooks {
  const BlankHooks({required this.noteId, required this.canFill, required this.learntUntil, required this.lookups, required this.fill, required this.say, this.now, this.zone});

  final String Function() noteId;

  /// The model can run here (ai/available.dart): the Fill pill is drawn. A browser, iOS and a read-only page have
  /// none.
  final bool Function() canFill;

  /// The chosen model's horizon (ai/backend.dart `learntUntil`).
  final int Function() learntUntil;

  /// Whether live blanks may be looked up here (ai/fills/queue.dart `lookupsHere`).
  final Lookups Function() lookups;

  /// A press: the queue takes these.
  final void Function(List<FillTarget> targets) fill;

  /// A sentence to say, for a press that runs nothing.
  final void Function(String message) say;

  /// The clock, for tests.
  final DateTime Function()? now;
  final String Function()? zone;
}

/// The hooks, read by the widgets and the panel. Absent where a note is only read.
final Facet<BlankHooks?, BlankHooks?> blankHooks = Facet.define<BlankHooks?, BlankHooks?>(combine: (values) => values.where((value) => value != null).firstOrNull);

/// A card's small, still note (notes/peek.ts): the square with no icon.
final Facet<bool, bool> _stillSquares = Facet.define<bool, bool>(combine: (values) => values.any((value) => value));

/// Redraw: the queue moved, the pause ended, a minute turned.
final StateEffectType<Null> blanksRedraw = StateEffect.define<Null>();

/// Counts every redraw, so a drawn table knows to draw its cells again (editor/tables.ts).
final StateField<int> blankStamp = StateField.define<int>(create: (_) => 0, update: (stamp, tr) => tr.effects.any((e) => e.isOf(blanksRedraw)) ? stamp + 1 : stamp);

/// A blank's range, as it is tracked.
typedef BlankRange = ({int from, int to});

/// A blank a press took, with the key it is known by.
typedef TrackedBlank = ({String key, int from, int to});

/// Blanks a press took, tracked by their identity while the note is open.
final StateEffectType<List<TrackedBlank>> trackBlanks = StateEffect.define<List<TrackedBlank>>();

/// Each tracked blank's range, mapped through every edit, as the landing is (editor/ai/ai_changes.dart).
final StateField<Map<String, BlankRange>> blanksField = StateField.define<Map<String, BlankRange>>(
  create: (_) => const <String, BlankRange>{},
  update: (ranges, tr) {
    var next = ranges;
    if (tr.docChanged && ranges.isNotEmpty) {
      final moved = <String, BlankRange>{};
      for (final MapEntry(:key, value: range) in ranges.entries) {
        final from = tr.changes.mapPos(range.from, 1);
        final to = tr.changes.mapPos(range.to, -1);
        if (to > from) moved[key] = (from: from, to: to);
      }
      next = moved;
    }
    for (final effect in tr.effects) {
      final tracked = trackBlanks.cast(effect);
      if (tracked == null) continue;
      final added = Map<String, BlankRange>.of(next);
      for (final (:key, :from, :to) in tracked.value) {
        added[key] = (from: from, to: to);
      }
      next = added;
    }
    return next;
  },
);

/// Whether a blank starting at `from` sits in words the editor draws: not front matter (the parser makes no node
/// for it, editor/view/extended.dart draws it by its own rule), code, a comment, an address or maths.
bool _inWords(EditorState state, int from, [Tree? tree]) {
  final doc = state.doc;
  if (from < frontMatterOffset(state.sliceDoc(0, math.min(doc.length, 4000)))) return false;
  if (inQuietText(tree ?? syntaxTree(state), from)) return false;
  final line = doc.lineAt(from);
  if (wikiLinkPattern.allMatches(line.text).any((m) => from >= line.from + m.start && from < line.from + m.end)) return false;
  return !mathsIn(line.text, line.from).any((m) => from >= m.from && from < m.to);
}

/// The blanks the editor draws, offers and fills: every match of the pattern outside the parser's quiet places. For
/// the whole note (Fill the blanks, its count in the More sheet, the palette) the whole tree is asked for first, on
/// the press or when the sheet opens, never per keystroke. The tree that answers is the one read: a state keeps the
/// tree it was made with, so a parse cut short at its making (a long note, or a busy phone) would leave a fence's
/// blank as words.
List<Blank> editorBlanks(EditorState state, [bool whole = true]) {
  final text = state.doc.toString();
  if (!text.contains('{?')) return const <Blank>[];
  final tree = syntaxTree(state);
  return <Blank>[
    for (final blank in blankMatches(text))
      if (_inWords(state, blank.from, tree)) blank,
  ];
}

/// A blank's identity among `all`: its question and its order among blanks with that question.
String keyOf(List<Blank> all, Blank blank) => blankKey(blank.question, all.where((b) => b.question == blank.question && b.from < blank.from).length);

/// A key's order: the number after its question.
int _orderOf(String key) => int.parse(key.split('\u0000')[1]);

/// The options a lane is worked out with, from the hooks.
LaneOptions _laneOptions(BlankHooks? hooks) => LaneOptions(
  clock: FactClock(now: hooks?.now?.call() ?? DateTime.now(), zone: hooks?.zone?.call()),
  learntUntil: hooks?.learntUntil() ?? 2024,
  lookups: hooks?.lookups() ?? Lookups.off,
);

/// A blank's lane in this state.
Lane laneAt(EditorState state, Blank blank) => laneOf(blank, state.doc.toString(), _laneOptions(state.facet(blankHooks)));

/// A press of these blanks: the title blank with too little under it says so and runs nothing, the rest are tracked
/// from here and handed to the queue. Answers how many went.
int pressBlanks(EditorViewLike view, List<Blank> blanks, [List<Blank>? all]) {
  final hooks = view.state.facet(blankHooks);
  if (hooks == null) return 0;
  final every = all ?? editorBlanks(view.state);
  final targets = <FillTarget>[];
  final tracked = <TrackedBlank>[];
  var tooShort = false;
  for (final blank in blanks) {
    final lane = laneAt(view.state, blank);
    if (!fillable(lane)) continue;
    if (lane is ModelLane && lane.info.tooShort) {
      tooShort = true;
      continue;
    }
    final key = keyOf(every, blank);
    targets.add(FillTarget(key: key, question: blank.question, order: _orderOf(key)));
    tracked.add((key: key, from: blank.from, to: blank.to));
  }
  if (tooShort && targets.isEmpty) hooks.say('Write a few lines first. The title is made from them.');
  if (targets.isEmpty) return 0;
  view.dispatch(TransactionSpec(effects: trackBlanks.of(tracked)));
  hooks.fill(targets);
  return targets.length;
}

/// Every blank in the note a press of Fill would take, for Fill the blanks and its count.
List<Blank> fillableBlanks(EditorState state) {
  final hooks = state.facet(blankHooks);
  final text = state.doc.toString();
  final options = _laneOptions(hooks);
  return <Blank>[
    for (final blank in editorBlanks(state))
      if (fillable(laneOf(blank, text, options))) blank,
  ];
}

/// What a press of Fill the blanks would do, for the More sheet's hint: how many it takes, and the public sources
/// the live ones would be looked up at. The hint says "Nothing leaves" only when that list is empty.
({int count, List<String> online}) fillPlanOf(EditorState state) {
  final hooks = state.facet(blankHooks);
  final text = state.doc.toString();
  final options = _laneOptions(hooks);
  final online = <String>{};
  var count = 0;
  for (final blank in editorBlanks(state)) {
    final lane = laneOf(blank, text, options);
    if (!fillable(lane)) continue;
    count += 1;
    if (lane is LiveLane) {
      final name = sourceName(lane.plan);
      if (name != null && name.isNotEmpty) online.add(name == 'Wikipedia' ? 'Wikipedia and Wikidata' : name);
    }
  }
  return (count: count, online: online.toList());
}

/// Fill the blanks: every blank the model or a lookup can answer, top to bottom. Answers how many went.
int fillAll(EditorViewLike view) {
  final all = editorBlanks(view.state);
  return pressBlanks(view, fillableBlanks(view.state), all);
}

/// The blanks the idle auto-fill would press now (`autoFill`, [pauseSettleMs] after the hands stop): every blank
/// the phone can answer that hasn't been run, hasn't a past outcome, and isn't the one the caret still sits in,
/// less a model blank with too little under it for a title (which a press would only refuse, with a sentence).
/// `tried` are the keys this note has already auto-pressed while open, so a blank the person cleared by hand is
/// left alone. Empty - nothing waiting, or auto-fill is off, or the pill would not draw here - tells the timer to
/// stand down.
({List<Blank> blanks, List<Blank> all}) idleFillable(EditorViewLike view, Set<String> tried) {
  final state = view.state;
  final hooks = state.facet(blankHooks);
  final text = state.doc.toString();
  if (hooks == null || !hooks.canFill() || !state.facet(EditorViewLike.editable) || !preferences.value.autoFill || !text.contains('{?')) {
    return (blanks: const <Blank>[], all: const <Blank>[]);
  }
  final all = editorBlanks(state);
  final noteId = hooks.noteId();
  final options = _laneOptions(hooks);
  final head = state.selection.main.head;
  final caretInside = state.facet(EditorViewLike.editable) && view.hasFocus;
  final blanks = <Blank>[
    for (final blank in all)
      if (() {
        final key = keyOf(all, blank);
        if (tried.contains(key) || fillStatus(noteId, key) != null || fillOutcome(noteId, key) != null) return false;
        if (caretInside && head > blank.from + 1 && head < blank.to) return false;
        final lane = laneOf(blank, text, options);
        return fillable(lane) && !(lane is ModelLane && lane.info.tooShort);
      }())
        blank,
  ];
  return (blanks: blanks, all: all);
}

// ---- how each blank is drawn -----------------------------------------------------------------------------------

const Map<FactIcon, LucideIcon> _factIcons = <FactIcon, LucideIcon>{FactIcon.calculator: Lucide.calculator, FactIcon.calendar: Lucide.calendarDays, FactIcon.globe: Lucide.globe};

/// The icon a blank wears: what will happen, or, once pressed, the run's phase.
({LucideIcon icon, bool spin}) _iconFor(Lane lane, FillStatus? status, String? noteId) {
  if (status?.phase == FillPhase.filling) {
    final phase = (noteId != null ? runFor(noteId)?.phase : null) ?? RunPhase.queued;
    if (phase == RunPhase.loading) return (icon: Lucide.loaderCircle, spin: true);
    if (phase == RunPhase.prefill) return (icon: Lucide.bookOpenText, spin: false);
    if (phase == RunPhase.generating) return (icon: Lucide.penLine, spin: false);
    return (icon: Lucide.hourglass, spin: false);
  }
  if (status?.phase == FillPhase.waiting) return (icon: Lucide.hourglass, spin: false);
  if (status?.phase == FillPhase.looking) return (icon: Lucide.wifi, spin: false);
  if (status?.phase == FillPhase.paused) return (icon: Lucide.wifiOff, spin: false);
  return switch (lane) {
    WorkedLane(:final worked) => (icon: _factIcons[worked.icon]!, spin: false),
    CannotLane(:final cannot) => (icon: _factIcons[cannot.icon]!, spin: false),
    LiveLane(:final can) => (icon: can == LiveCan.look ? Lucide.wifi : Lucide.wifiOff, spin: false),
    ModelLane() => (icon: Lucide.messageCircleQuestionMark, spin: false),
  };
}

/// The quiet words after a blank, if any: a refusal, a pause, what came of a press.
String? wordsAfter(Lane lane, FillStatus? status, FillOutcome? outcome) {
  if (status?.phase == FillPhase.paused) return status!.why == PausedWhy.offline ? 'Waiting for a connection' : 'Paused';
  if (status?.phase == FillPhase.looking) return 'Looking it up';
  if (status != null) return null;
  if (outcome != null) {
    return switch (outcome.why) {
      FillWhy.unknown => 'Not known',
      FillWhy.none => 'No answer came',
      FillWhy.didntFit => 'Didn’t fit',
      FillWhy.nothing => 'Not found online',
    };
  }
  if (lane is CannotLane) return 'Can’t work out';
  if (lane is LiveLane && lane.can == LiveCan.localOnly) return 'Paused';
  // No public source answers it (a fare, opening hours): the phone being online would not help, so it says that.
  if (lane is LiveLane && lane.can == LiveCan.none) return 'No source to ask';
  if (lane is LiveLane && lane.can != LiveCan.look) return 'Can’t know offline';
  return null;
}

/// A blank's name for a screen reader: its outcome, then what it asks.
String _label(Lane lane, Blank blank, String text) {
  final lineStart = blank.from <= 0 ? 0 : text.lastIndexOf('\n', blank.from - 1) + 1;
  final asked = blank.question.isNotEmpty ? blank.question : text.substring(lineStart, blank.from).trim();
  if (lane is WorkedLane) return 'Worked out: $asked';
  if (lane is CannotLane) return "Can't work out: $asked";
  if (lane is LiveLane && lane.can == LiveCan.none) return 'No source to ask: $asked';
  if (lane is LiveLane && lane.can != LiveCan.look) return "Can't know offline: $asked";
  if (lane is LiveLane) return 'Looked up online when pressed: $asked';
  return blank.question.isNotEmpty ? 'A blank for the AI: ${blank.question}' : 'A blank for the AI';
}

/// The line a widget stands in: its words' style and its size, which is what an `em` is. In the editor's lines it
/// is the run's own; in a table's cell, the words' round it. On a heading's line (`heading` its level) the size is
/// the heading's: the page wraps a widget in every mark round it, the highlighter's `h1` among them, and the view
/// gives a widget only the marks of whoever drew it.
///
/// With `mark`, the look is that of words in that mark of the square's (`cm-blankMark`): what a brace the widget
/// draws itself is set in.
({TextStyle style, double em, RunLook? look}) _around(BuildContext context, {int heading = 0, String? mark}) {
  final t = context.tokens;
  final scope = EditorRunScope.maybeOf(context);
  if (scope != null) {
    var look = scope.look;
    final view = EditorViewScope.maybeOf(context);
    final sheets = view is EditorView ? view.look : null;
    if ((heading > 0 || mark != null) && sheets != null) {
      look = sheets.run(scope.line, <LookElement>[?look.props.element, if (mark != null) LookElement(mark), if (heading > 0) LookElement('h$heading')]);
    }
    return (style: look.style, em: look.fontSize, look: look);
  }
  final given = DefaultTextStyle.of(context).style;
  final em = given.fontSize ?? t.len('app-body');
  return (style: given.fontSize == null ? t.textAt(em, color: t.color('app-ink')) : given, em: em, look: null);
}

/// The style a brace is drawn in on the line a widget is in: that of the first `cm-blankMark` words on it, or null
/// where there are none (the Formatted view, whose braces are hidden). Every brace on a line is in the line's own
/// marks, so one is as good as another.
TextStyle? _openingBrace(BuildContext context) {
  final line = context.findAncestorRenderObjectOfType<RenderEditorLine>();
  if (line == null) return null;
  final segments = line.spec.projection.segments;
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (segment.kind == SegmentKind.text && segment.marks.any((mark) => mark.attrs['class'] == 'cm-blankMark')) return line.spec.runs[i].style;
  }
  return null;
}

/// `border: 1px …` as the page draws it: down to a whole device pixel, never under one (`LookEnv.border`).
double _hairline(BuildContext context) {
  final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
  final device = ratio.floorToDouble();
  return (device < 1 ? 1 : device) / ratio;
}

/// `border: 1px dashed color-mix(in oklch, currentColor 45%, transparent)`, of the ink `current`; a blank that is
/// being filled stands at `opacity: 0.6`.
Color _edgeColor(Tokens t, Color current, {bool busy = false}) {
  final edge = t.colorOf('color-mix(in oklch, currentColor 45%, transparent)', current: current);
  return busy ? edge.withValues(alpha: edge.a * _busyOpacity) : edge;
}

/// '@media (prefers-reduced-motion: reduce)': { '.cm-blank[data-busy]': { animation: 'none', opacity: '0.6' } }
const double _busyOpacity = 0.6;

/// The square's ends: `padding: 0 0.25em` and the border as the room each takes, and at the start the border itself,
/// drawn round the whole square with `borderRadius: '0.2em'` (blanks_paint.dart).
class BlankEndWidget extends EditorWidget {
  const BlankEndWidget(this.end, {this.heading = 0});

  final BlankEnd end;

  /// The level of the heading the square is in, or zero.
  final int heading;

  @override
  bool eq(BlankEndWidget other) => other.end == end && other.heading == heading;

  @override
  bool get isHidden => true;

  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final around = _around(context, heading: heading);
    final look = around.look;
    final busy = EditorRunScope.maybeOf(context)?.look.props.element?.attrs.containsKey('data-busy') ?? false;
    final area = look == null ? contentArea(around.style) : (ascent: look.ascent, descent: look.descent);
    return InlineFlat(
      child: BlankPiece(
        key: ValueKey<String>('cm-blank-${end.name}'),
        end: end,
        ascent: area.ascent,
        descent: area.descent,
        color: _edgeColor(t, look?.color ?? around.style.color ?? t.color('app-ink'), busy: busy),
        width: _hairline(context),
        room: layoutUnitFloor(around.em * 0.25),
        radius: around.em * 0.2,
      ),
    );
  }
}

/// The icon at the end of the square (`IconWidget`), and with it what the square ends in: the closing brace where
/// the braces show, then the square's own end. They are one widget because a line may break either side of a
/// widget, and the page never breaks one before a `}` or inside a padding.
class IconWidget extends EditorWidget {
  const IconWidget(this.icon, this.spin, {this.brace = false, this.busy = false, this.whole = false, this.heading = 0});

  final LucideIcon icon;
  final bool spin;

  /// Whether the braces are drawn: the Markdown view, and the line being written.
  final bool brace;

  /// `data-busy` on the square.
  final bool busy;

  /// An empty blank, `{?}`, drawn whole: both ends, the braces and the icon, and the border round them. It has no
  /// words for a line to break between, and as one widget none of it is ever left on another line (the page's
  /// `.cm-blank[data-short] { white-space: nowrap }`, for the shortest blank there is).
  final bool whole;

  /// The level of the heading the square is in, or zero.
  final int heading;

  @override
  bool eq(IconWidget other) => identical(other.icon, icon) && other.spin == spin && other.brace == brace && other.busy == busy && other.whole == whole && other.heading == heading;

  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) => BlankIcon(icon, spin: spin, brace: brace, busy: busy, whole: whole, heading: heading);
}

/// `.cm-blankIcon`: the icon as it is drawn, at the end of the editor's own square, as the whole of an empty one,
/// or, in a table's cell, in one drawn whole.
class BlankIcon extends StatelessWidget {
  const BlankIcon(this.icon, {super.key, required this.spin, this.inSquare = true, this.brace = false, this.busy = false, this.whole = false, this.heading = 0});

  final LucideIcon icon;
  final bool spin;

  /// Whether it ends the editor's own square: a box as tall as the square's border box, with the end's room.
  final bool inSquare;
  final bool brace;
  final bool busy;
  final bool whole;
  final int heading;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final around = _around(context, heading: heading);
    final look = around.look;
    final em = around.em;
    // '.cm-blankIcon': { display: 'inline-block', inlineSize: '0.9em', blockSize: '0.9em',
    //   marginInline: '0.2em 0.05em', verticalAlign: '-0.08em', color: 'var(--app-ink-3, currentColor)',
    //   minInlineSize: '0.9em' }
    // '.cm-blankIcon svg': { inlineSize: '0.9em', blockSize: '0.9em', display: 'block' }
    final ink = t.color('app-ink-3');
    final color = busy ? ink.withValues(alpha: ink.a * _busyOpacity) : ink;
    // `iconElement(Icon)`: the stroke 2.2 of the icon's own units (editor/iconDom.ts).
    Widget drawn = AppIcon(icon, key: ValueKey<String>('cm-blankIcon-${icon.name}'), size: em * 0.9, strokeWidth: 2.2, color: color);
    if (spin) drawn = _Turning(child: drawn);
    // A box with no words: its foot is its baseline, and `vertical-align: -0.08em` sets that under the line's.
    final Widget box = InlineRaise(
      from: em * 0.9,
      by: -em * 0.08,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: layoutUnitFloor(em * 0.2), end: layoutUnitFloor(em * 0.05)),
        child: SizedBox.square(key: const ValueKey<String>('cm-blankIcon'), dimension: em * 0.9, child: drawn),
      ),
    );
    final area = look == null ? contentArea(around.style) : (ascent: look.ascent, descent: look.descent);
    // The braces are the note's own. One this widget draws is set exactly as a brace in the line's words is,
    // whatever marks the highlighter has round it (a list's, a heading's); with none on the line to read (only
    // empty blanks, drawn whole), as the words of '.cm-blankMark' are; and in a table's cell, where no sheet says it,
    // '.cm-blankMark': { color: 'var(--app-ink-4, currentColor)' }.
    final dim = t.color('app-ink-4');
    final marks = look == null
        ? around.style.copyWith(color: busy ? dim.withValues(alpha: dim.a * _busyOpacity) : dim)
        : _openingBrace(context) ?? _around(context, heading: heading, mark: 'cm-blankMark').style;
    final hair = _hairline(context), room = layoutUnitFloor(em * 0.25);
    if (whole) {
      return ExcludeSemantics(
        child: InlineFlat(
          child: CustomPaint(
            key: const ValueKey<String>('cm-blank-whole'),
            painter: BlankBoxPainter(
              color: _edgeColor(t, look?.color ?? around.style.color ?? ink, busy: busy),
              width: hair,
              radius: em * 0.2,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hair + room, vertical: hair),
              child: BlankPiece(
                end: BlankEnd.middle,
                ascent: area.ascent,
                descent: area.descent,
                color: const Color(0x00000000),
                width: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    if (brace) InlineWords('{?', style: marks),
                    box,
                    if (brace) InlineWords('}', style: marks),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final piece = BlankPiece(
      end: inSquare ? BlankEnd.end : BlankEnd.middle,
      ascent: area.ascent,
      descent: area.descent,
      color: const Color(0x00000000),
      width: inSquare ? hair : 0,
      room: inSquare ? room : 0,
      child: brace
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                box,
                InlineWords('}', key: const ValueKey<String>('cm-blankMark-end'), style: marks),
              ],
            )
          : box,
    );
    return ExcludeSemantics(child: inSquare ? InlineFlat(child: piece) : piece);
  }
}

/// '.cm-blankIcon[data-spin] svg': { animation: 'cm-blank-spin 1.2s linear infinite' }
/// '@keyframes cm-blank-spin': { to: { transform: 'rotate(360deg)' } }
class _Turning extends StatefulWidget {
  const _Turning({required this.child});

  final Widget child;

  @override
  State<_Turning> createState() => _TurningState();
}

class _TurningState extends State<_Turning> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // '@media (prefers-reduced-motion: reduce)': { '.cm-blankIcon[data-spin] svg': { animation: 'none' } }
    if (!context.tokens.reducedMotion) _turn.repeat();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _turn, child: widget.child);
}

/// What follows a blank: a worked-out answer drawn as a sum's, or quiet words; either opens the panel on a tap
/// (`AfterWidget`).
class AfterWidget extends EditorWidget {
  const AfterWidget(this.text, this.answer, this.at);

  final String text;
  final bool answer;
  final int at;

  @override
  bool eq(AfterWidget other) => other.text == text && other.answer == answer && other.at == at;

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.maybeOf(context);
    return BlankAfter(text, answer: answer, onPress: view == null ? null : () => _openPanelAt(view, at));
  }
}

/// `.cm-sumAnswer.cm-blankAnswer`, or `.cm-blankWords`: what stands after a square.
class BlankAfter extends StatelessWidget {
  const BlankAfter(this.text, {super.key, required this.answer, required this.onPress});

  final String text;
  final bool answer;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final around = _around(context);
    final Widget words;
    if (answer) {
      // button.className = 'cm-sumAnswer cm-blankAnswer': the sum's own answer (editor/items/sums.dart), with
      // '.cm-blankAnswer': { appearance: 'none', border: 'none', background: 'transparent', padding: '0',
      //   font: 'inherit', cursor: 'pointer' }
      // button.setAttribute('aria-label', `equals ${this.text}`)
      words = KeyedSubtree(key: const ValueKey<String>('cm-blankAnswer'), child: AnswerWidget(text).build(context));
    } else {
      // '.cm-blankWords': { appearance: 'none', border: 'none', background: 'transparent', padding: '0',
      //   marginInlineStart: '0.6em', font: 'inherit', fontSize: '0.8em',
      //   color: 'var(--app-ink-3, currentColor)', verticalAlign: '0.08em', whiteSpace: 'nowrap',
      //   cursor: 'pointer', WebkitTapHighlightColor: 'transparent' }
      final size = around.em * 0.8;
      final style = Tokens.resized(around.style, size).copyWith(color: t.color('app-ink-3'), decoration: TextDecoration.none);
      words = Semantics(
        button: true,
        label: text,
        onTap: onPress,
        child: ExcludeSemantics(
          child: InlineRaise(
            by: size * 0.08,
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: layoutUnitFloor(size * 0.6)),
              // `font: inherit` brings the line's own leading, 1.6 of the words' size.
              child: InlineWords(text, key: const ValueKey<String>('cm-blankWords'), style: style, lineHeight: size * 1.6),
            ),
          ),
        ),
      );
    }
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onPress, child: words);
  }
}

/// The Fill pill at the end of a line: its blanks, and how busy they are (`PillWidget`).
class PillWidget extends EditorWidget {
  const PillWidget(this.label, this.busy, this.froms, this.aria);

  final String label;
  final bool busy;
  final List<int> froms;
  final String aria;

  @override
  bool eq(PillWidget other) => other.label == label && other.busy == busy && other.froms.join(',') == froms.join(',');

  /// What a press does: its line's blanks, as they stand now.
  void press(EditorViewLike view) {
    if (busy) return;
    final all = editorBlanks(view.state);
    pressBlanks(view, <Blank>[
      for (final b in all)
        if (froms.contains(b.from)) b,
    ], all);
  }

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.maybeOf(context);
    return FillPill(label, busy: busy, aria: aria, onPress: view == null ? null : () => press(view));
  }
}

/// `button.cm-suggest.cm-fillPill`: the suggestion pill's own look (editor/items/suggestions.dart draws it, each
/// rule of `.cm-suggest` cited there), with the pill's own name for a screen reader and `disabled` while busy.
class FillPill extends StatelessWidget {
  const FillPill(this.label, {super.key, required this.busy, required this.aria, required this.onPress});

  final String label;
  final bool busy;
  final String aria;
  final VoidCallback? onPress;

  static void _nothing() {}

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: !busy,
    label: aria,
    onTap: busy ? null : onPress,
    child: ExcludeSemantics(
      child: KeyedSubtree(key: const ValueKey<String>('cm-fillPill'), child: SuggestWord(SuggestWidget(label, busy, onPress ?? _nothing, _nothing, _nothing))),
    ),
  );
}

/// Opens the fill panel for what sits at `at` (editor/ai/fill_panel.dart), through the facet it registers.
void _openPanelAt(EditorViewLike view, int at) => view.state.facet(panelOpener)?.call(view, at);

/// What opens the panel: the view, and where.
typedef PanelOpener = void Function(EditorViewLike view, int at);

/// The panel's opener, given by editor/ai/fill_panel.dart, so the two modules do not import each other.
final Facet<PanelOpener, PanelOpener?> panelOpener = Facet.define<PanelOpener, PanelOpener?>(combine: (values) => values.firstOrNull);

/// The square round a blank, named for a screen reader by its outcome, and breathing while it fills. A short one is
/// kept on one line: the shots showed `{?` closing a square at a line's end and `weather}` opening another under it.
const int _shortBlank = 28;
Decoration _boxFor(String name, bool busy, bool short) =>
    Decoration.mark(className: 'cm-blank', attributes: <String, String>{'role': 'group', 'aria-label': name, if (busy) 'data-busy': '', if (short) 'data-short': ''}, inclusiveStart: true, inclusiveEnd: true);
final Decoration _brace = Decoration.mark(className: 'cm-blankMark');
final Decoration _question = Decoration.mark(className: 'cm-blankQuestion');
final Decoration _hidden = Decoration.replace();

/// The square's own ends, each inside the mark: after the caret at its start, before the caret at its end.
Decoration _startEnd(int heading) => Decoration.widget(widget: BlankEndWidget(BlankEnd.start, heading: heading), side: 1);
Decoration _endEnd(int heading) => Decoration.widget(widget: BlankEndWidget(BlankEnd.end, heading: heading), side: 0);

final RegExp _headingLine = RegExp(r'^\s{0,3}(#{1,6})\s');

typedef _Drawn = ({DecorationSet decorations, bool minutely});

class _Pill {
  final List<int> froms = <int>[];
  final List<String> questions = <String>[];

  /// `'filling'`, `'waiting'` or null.
  String? busy;
}

/// The squares on screen, their icons, the words after them and the pills. `minutely` is whether a worked-out
/// answer that changes each minute is on screen: the minute timer runs only then.
_Drawn _draw(EditorViewLike view, bool idle) {
  final state = view.state;
  final text = state.doc.toString();
  if (!text.contains('{?')) return (decorations: Decoration.none, minutely: false);
  final hooks = state.facet(blankHooks);
  final noteId = hooks?.noteId();
  final formatted = state.facet(formattedView);
  final still = state.facet(_stillSquares);
  final caretLines = view.hasFocus ? selectedLines(state) : const <int>{};
  final editable = state.facet(EditorViewLike.editable);
  final tree = syntaxTree(state);
  final all = <Blank>[
    for (final blank in blankMatches(text))
      if (_inWords(state, blank.from, tree)) blank,
  ];
  final options = _laneOptions(hooks);
  final marks = <Range<Decoration>>[];
  final pills = <int, _Pill>{};
  var minutely = false;
  final head = state.selection.main.head;
  for (final DocRange(:from, :to) in view.visibleRanges) {
    for (final blank in all) {
      if (blank.to < from || blank.from > to) continue;
      final line = state.doc.lineAt(blank.from);
      final lane = laneOf(blank, text, options);
      final key = keyOf(all, blank);
      final status = noteId != null ? fillStatus(noteId, key) : null;
      final outcome = noteId != null ? fillOutcome(noteId, key) : null;
      final typing = caretLines.contains(line.number) && !idle;
      final caretInside = view.hasFocus && head > blank.from + 1 && head < blank.to;
      final busy = status?.phase == FillPhase.filling || status?.phase == FillPhase.looking;
      // Kept on one line only in words at body size: a heading's square must wrap, or at 412 it runs off the column.
      final level = _headingLine.firstMatch(line.text)?.group(1)?.length ?? 0;
      final heading = level > 0;
      marks.add(_boxFor(_label(lane, blank, text), busy, !heading && blank.to - blank.from <= _shortBlank).range(blank.from, blank.to));
      final showBraces = !formatted || caretLines.contains(line.number);
      final showIcon = !caretInside && !typing && !still;
      // `{?}` with its icon is one widget, in the place of all three characters (see `IconWidget.whole`).
      final whole = showIcon && blank.to - blank.from == 3;
      if (showBraces) {
        marks.add(_brace.range(blank.from, blank.from + 2));
        marks.add(_brace.range(blank.to - 1, blank.to));
      } else if (!whole) {
        marks.add(_hidden.range(blank.from, blank.from + 2));
        if (!showIcon) marks.add(_hidden.range(blank.to - 1, blank.to));
      }
      if (blank.to - 1 > blank.from + 2) marks.add(_question.range(blank.from + 2, blank.to - 1));
      if (whole) {
        final (:icon, :spin) = _iconFor(lane, status, noteId);
        marks.add(
          Decoration.replace(
            widget: IconWidget(icon, spin, brace: showBraces, busy: busy, whole: true, heading: level),
          ).range(blank.from, blank.to),
        );
      } else {
        marks.add(_startEnd(level).range(blank.from));
        if (showIcon) {
          // On the page a widget before the brace (`side: -1` at `blank.to - 1`); here it stands in the brace's
          // place and draws it, with the square's end (see `IconWidget`).
          final (:icon, :spin) = _iconFor(lane, status, noteId);
          marks.add(
            Decoration.replace(
              widget: IconWidget(icon, spin, brace: showBraces, busy: busy, heading: level),
            ).range(blank.to - 1, blank.to),
          );
        } else {
          marks.add(_endEnd(level).range(blank.to));
        }
      }
      if (lane is WorkedLane && status == null) {
        marks.add(Decoration.widget(widget: AfterWidget(lane.worked.answer, true, blank.from), side: 1).range(blank.to));
        if (lane.worked.changes == Changes.minute) minutely = true;
      } else if (!typing) {
        final words = wordsAfter(lane, status, outcome);
        if (words != null) marks.add(Decoration.widget(widget: AfterWidget(words, false, blank.from), side: 1).range(blank.to));
      }
      // The pill: blanks the model or a lookup will answer, where the model can run.
      if (editable && (hooks?.canFill() ?? false) && (fillable(lane) || status != null) && !typing) {
        final pill = pills.putIfAbsent(line.number, _Pill.new);
        if (status?.phase == FillPhase.filling || status?.phase == FillPhase.looking) {
          pill.busy = 'filling';
        } else if (status?.phase == FillPhase.waiting && pill.busy != 'filling') {
          pill.busy = 'waiting';
        } else if (status == null && fillable(lane)) {
          pill.froms.add(blank.from);
          pill.questions.add(blank.question);
        }
      }
    }
  }
  for (final MapEntry(key: number, value: pill) in pills.entries) {
    final line = state.doc.line(number);
    if (pill.busy != null) {
      final word = pill.busy == 'filling' ? 'Filling' : 'Waiting';
      marks.add(Decoration.widget(widget: PillWidget(word, true, const <int>[], word), side: 2).range(line.to));
    } else if (pill.froms.isNotEmpty) {
      final n = pill.froms.length;
      final aria = n == 1 ? (pill.questions[0].isNotEmpty ? 'Fill the blank: ${pill.questions[0]}' : 'Fill the blank') : 'Fill $n blanks';
      marks.add(Decoration.widget(widget: PillWidget(n == 1 ? 'Fill' : 'Fill $n', false, pill.froms, aria), side: 2).range(line.to));
    }
  }
  return (decorations: Decoration.set(marks, true), minutely: minutely);
}

/// How many blanks the open note has for a press of Fill, for the palette's Fill the blanks (commands/palette.ts):
/// counted a moment after the typing stops, never per keystroke.
final ValueNotifier<({String noteId, int count})?> openNoteBlanks = ValueNotifier<({String noteId, int count})?>(null);

/// How long the hands rest on the caret's line before its icon, words and pill come back (`PAUSE_MS`).
const int pauseMs = 700;

/// How long the whole note rests, after the pause, before the blanks that can answer fill themselves (`autoFill`)
/// (`PAUSE_SETTLE_MS`).
const int pauseSettleMs = 2500;

class _Blanks extends PluginValue {
  _Blanks(this.view) {
    final drawn = _draw(view, _idle);
    decorations = drawn.decorations;
    _tick(drawn.minutely);
    _unsubscribe = subscribeFills(() => scheduleMicrotask(_redraw));
    _count();
    _rest();
  }

  final EditorViewLike view;
  late DecorationSet decorations;
  bool _idle = true;
  Timer? _pause;
  Timer? _minute;
  late final VoidCallback _unsubscribe;

  Timer? _counting;
  Timer? _settle;
  bool _gone = false;

  /// Keys this note has already auto-pressed while open, so a cleared blank is not filled again under the person.
  final Set<String> _autoTried = <String>{};

  /// The idle auto-fill, set going whenever the note changes and when it opens: once the whole note has rested past
  /// the pause, every blank the phone can answer and hasn't been asked is pressed in the background
  /// ([idleFillable]). A press that fails leaves an outcome, and a blank the person clears is remembered in
  /// `_autoTried`, so neither is pressed again - auto-fill is a one-off hand, not a nag.
  void _rest() {
    _settle?.cancel();
    if (!view.state.facet(EditorViewLike.editable) || !preferences.value.autoFill) return;
    _settle = Timer(const Duration(milliseconds: pauseMs + pauseSettleMs), () {
      if (_gone) return;
      final (:blanks, :all) = idleFillable(view, _autoTried);
      if (blanks.isEmpty) return;
      for (final blank in blanks) {
        _autoTried.add(keyOf(all, blank));
      }
      pressBlanks(view, blanks, all);
    });
  }

  /// The open note's count of blanks for Fill, told half a second after the typing stops.
  void _count() {
    final hooks = view.state.facet(blankHooks);
    if (hooks == null || !view.state.facet(EditorViewLike.editable)) return;
    _counting?.cancel();
    _counting = Timer(const Duration(milliseconds: 500), () {
      if (_gone) return;
      final state = view.state;
      final text = state.doc.toString();
      final options = _laneOptions(hooks);
      final count = text.contains('{?') ? blankMatches(text).where((b) => _inWords(state, b.from) && fillable(laneOf(b, text, options))).length : 0;
      final was = openNoteBlanks.value;
      if (was == null || was.noteId != hooks.noteId() || was.count != count) openNoteBlanks.value = (noteId: hooks.noteId(), count: count);
    });
  }

  void _redraw() {
    if (!_gone) view.dispatch(TransactionSpec(effects: blanksRedraw.of(null)));
  }

  /// The minute timer, running only while a time-now answer is on screen.
  void _tick(bool minutely) {
    _minute?.cancel();
    _minute = null;
    if (!minutely) return;
    _minute = Timer(Duration(milliseconds: 60000 - (DateTime.now().millisecondsSinceEpoch % 60000) + 50), _redraw);
  }

  @override
  void update(ViewUpdate update) {
    if (update.docChanged && update.transactions.any((tr) => tr.isUserEvent('input') || tr.isUserEvent('delete'))) {
      _idle = false;
      _pause?.cancel();
      _pause = Timer(const Duration(milliseconds: pauseMs), () {
        _idle = true;
        _redraw();
      });
    }
    if (update.docChanged) {
      _count();
      _rest();
    }
    final asked = update.transactions.any((tr) => tr.effects.any((e) => e.isOf(blanksRedraw)));
    final viewFlipped = update.startState.facet(formattedView) != update.state.facet(formattedView);
    if (update.docChanged || update.selectionSet || update.viewportChanged || update.focusChanged || asked || viewFlipped || !identical(syntaxTree(update.startState), syntaxTree(update.state))) {
      final drawn = _draw(update.view, _idle);
      decorations = drawn.decorations;
      _tick(drawn.minutely);
    }
  }

  @override
  void destroy() {
    _gone = true;
    _pause?.cancel();
    _minute?.cancel();
    _counting?.cancel();
    _settle?.cancel();
    _unsubscribe();
    final hooks = view.state.facet(blankHooks);
    if (hooks != null && openNoteBlanks.value?.noteId == hooks.noteId()) openNoteBlanks.value = null;
  }
}

final ViewPlugin<_Blanks> _plugin = ViewPlugin.fromClass<_Blanks>(_Blanks.new, decorations: (value) => value.decorations);

bool _busy(LookElement element, LineContext _) => element.attrs.containsKey('data-busy');

final LookSheet _theme = LookSheet('editor/blanks.ts', <LookRule>[
  // The suggestion pill's hairline, dashed, round the whole blank: no hue, right on black paper and white.
  // '.cm-blank': { border: '1px dashed color-mix(in oklch, currentColor 45%, transparent)', borderRadius: '0.2em',
  //   padding: '0 0.25em', boxDecorationBreak: 'clone', WebkitBoxDecorationBreak: 'clone' }
  // is `BlankEndWidget`'s to draw: the border, and the padding as the room its two ends take.
  // '.cm-blank[data-short]': { whiteSpace: 'nowrap' }: not kept (see the header).
  // '.cm-blank[data-busy]': { animation: 'cm-blank-breathe 1.6s ease-in-out infinite alternate' }
  // '@keyframes cm-blank-breathe': { from: { opacity: '0.45' }, to: { opacity: '0.8' } }
  // '@media (prefers-reduced-motion: reduce)': { '.cm-blank[data-busy]': { animation: 'none', opacity: '0.6' } }
  // The square stands at the second of these, whatever the motion (see the header): `opacity` on the square
  // reaches the words inside it, whatever ink their own mark gave them, and its widgets read it from the mark.
  LookRule.under('cm-blank', classes: 3, when: _busy, (p, e) => p.color = p.color.withValues(alpha: p.color.a * _busyOpacity)),
  // '.cm-blankMark': { color: 'var(--app-ink-4, currentColor)' }
  LookRule('cm-blankMark', classes: 2, (p, e) => p.color = e.t.color('app-ink-4')),
  // '.cm-blankQuestion': { color: 'var(--app-ink-3, currentColor)' }
  LookRule('cm-blankQuestion', classes: 2, (p, e) => p.color = e.t.color('app-ink-3')),
]);

// ---- in a drawn table ------------------------------------------------------------------------------------------

/// A piece of a drawn table's cell.
sealed class CellPiece {
  const CellPiece();
}

/// The cell's own words, as the table reads them.
final class CellWords extends CellPiece {
  const CellWords(this.text);

  final String text;
}

/// A blank: its square, with its icon and what follows it.
final class CellBlank extends CellPiece {
  const CellBlank({required this.blank, required this.label, required this.icon, required this.spin, required this.busy, required this.after, required this.answer});

  final Blank blank;
  final String label;
  final LucideIcon icon;
  final bool spin;
  final bool busy;

  /// The words after the square, or the worked-out answer where [answer]; null where nothing follows.
  final String? after;
  final bool answer;
}

/// A filled answer: its words with the dotted line, the bracket hidden. A tap opens the panel at [at].
final class CellFill extends CellPiece {
  const CellFill({required this.words, required this.at});

  final String words;
  final int at;
}

/// A drawn table's cell (editor/tables.ts), with its blanks and its fills: a blank as its square with its icon and
/// the words after it, a filled answer as its words with the dotted line and the bracket hidden, a tap on either
/// opening the panel. `raw` is the cell's text as written and `at` where it starts in the note. Answers null where
/// it has nothing of its own to draw; the table draws the cell's words as it always did then.
BlankCell? drawCell(EditorViewLike view, String raw, int at, String Function(String text) plain) {
  if (!raw.contains('{?') && !raw.contains('??(')) return null;
  final state = view.state;
  final hooks = state.facet(blankHooks);
  final text = state.doc.toString();
  final tree = syntaxTree(state);
  final all = <Blank>[
    for (final blank in blankMatches(text))
      if (_inWords(state, blank.from, tree)) blank,
  ];
  final options = _laneOptions(hooks);
  final noteId = hooks?.noteId();
  final pieces = <({int from, int to, CellPiece piece})>[];
  for (final blank in blankMatches(raw, at)) {
    final lane = laneOf(blank, text, options);
    final key = keyOf(all, blank);
    final status = noteId != null ? fillStatus(noteId, key) : null;
    final outcome = noteId != null ? fillOutcome(noteId, key) : null;
    final (:icon, :spin) = _iconFor(lane, status, noteId);
    final worked = lane is WorkedLane && status == null;
    pieces.add((
      from: blank.from,
      to: blank.to,
      piece: CellBlank(
        blank: blank,
        label: _label(lane, blank, text),
        icon: icon,
        spin: spin,
        busy: status?.phase == FillPhase.filling || status?.phase == FillPhase.looking,
        after: lane is WorkedLane && status == null ? lane.worked.answer : wordsAfter(lane, status, outcome),
        answer: worked,
      ),
    ));
  }
  for (final fill in fillsIn(raw, at)) {
    pieces.add((from: fill.from, to: fill.to, piece: CellFill(words: fill.words, at: fill.from + 2)));
  }
  pieces.sort((a, b) => a.from - b.from);
  final out = <CellPiece>[];
  var cursor = at;
  for (final piece in pieces) {
    if (piece.from < cursor) continue;
    if (piece.from > cursor) out.add(CellWords(plain(raw.substring(cursor - at, piece.from - at))));
    out.add(piece.piece);
    cursor = piece.to;
  }
  if (cursor < at + raw.length) out.add(CellWords(plain(raw.substring(cursor - at))));
  return BlankCell(view: view, pieces: out);
}

/// What [drawCell] draws: the cell's words with its squares and its filled answers among them, in the style the
/// table gives its cells (the `DefaultTextStyle` round it, or [style]).
class BlankCell extends StatelessWidget {
  const BlankCell({super.key, required this.view, required this.pieces, this.style});

  final EditorViewLike view;
  final List<CellPiece> pieces;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final words = style ?? DefaultTextStyle.of(context).style;
    final em = words.fontSize ?? t.len('app-body');
    WidgetSpan inline(Widget child) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: DefaultTextStyle(style: words, child: child),
    );
    final spans = <InlineSpan>[];
    for (final piece in pieces) {
      switch (piece) {
        case CellWords(:final text):
          spans.add(TextSpan(text: text));
        case CellBlank():
          final ink = t.color('app-ink-3');
          final question = piece.busy ? ink.withValues(alpha: ink.a * _busyOpacity) : ink;
          final area = contentArea(words);
          final hair = _hairline(context);
          // The square in one piece: '.cm-blank' and, inside it, '.cm-blankQuestion' and the icon.
          spans.add(
            inline(
              Semantics(
                container: true,
                label: piece.label,
                child: CustomPaint(
                  key: const ValueKey<String>('cm-blank'),
                  painter: BlankBoxPainter(
                    color: _edgeColor(t, words.color ?? t.color('app-ink'), busy: piece.busy),
                    width: hair,
                    radius: em * 0.2,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: hair + layoutUnitFloor(em * 0.25), vertical: hair),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        if (piece.blank.question.isNotEmpty)
                          InlineWords(
                            piece.blank.question,
                            style: words.copyWith(color: question),
                            lineHeight: area.ascent + area.descent,
                          ),
                        BlankIcon(piece.icon, spin: piece.spin, inSquare: false, busy: piece.busy),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          if (piece.after != null) spans.add(inline(BlankAfter(piece.after!, answer: piece.answer, onPress: () => _openPanelAt(view, piece.blank.from))));
        case CellFill(:final words, :final at):
          // A filled answer in a drawn table: its words with the Unsure mark's dotted line, a tap opening its panel.
          // '.cm-fillWords': { appearance: 'none', border: 'none', background: 'transparent', padding: '0',
          //   font: 'inherit', color: 'inherit', textAlign: 'inherit', textDecoration: 'underline dotted',
          //   textDecorationColor: 'var(--glacier-text-subtle, currentColor)', textUnderlineOffset: '0.22em',
          //   textDecorationThickness: '0.09em', cursor: 'pointer' }
          spans.add(
            inline(
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openPanelAt(view, at),
                child: Text(
                  words,
                  key: const ValueKey<String>('cm-fillWords'),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted, decorationColor: t.color('glacier-text-subtle'), decorationThickness: math.max(1, em * 0.09)),
                ),
              ),
            ),
          );
      }
    }
    return Text.rich(
      TextSpan(children: spans),
      style: words,
      textScaler: TextScaler.noScaling,
    );
  }
}

/// The Fill pill after a drawn table with blanks for the model: Fill 3, or Filling while they go. Null where none.
/// '.cm-glyphTableWrap .cm-fillPill': { display: 'inline-block', marginBlockStart: '0.3em' } is the table's to give
/// it: a line of its own under the last row, 0.3em of the pill's own size down.
Widget? tablePill(EditorViewLike view, int from, int to) {
  final state = view.state;
  final hooks = state.facet(blankHooks);
  if (hooks == null || !hooks.canFill() || !state.facet(EditorViewLike.editable)) return null;
  final text = state.doc.toString();
  final tree = syntaxTree(state);
  final all = <Blank>[
    for (final blank in blankMatches(text))
      if (_inWords(state, blank.from, tree)) blank,
  ];
  final mine = all.where((b) => b.from >= from && b.to <= to).toList();
  if (mine.isEmpty) return null;
  final options = _laneOptions(hooks);
  final noteId = hooks.noteId();
  String? busy;
  final froms = <int>[];
  for (final blank in mine) {
    final status = fillStatus(noteId, keyOf(all, blank));
    if (status?.phase == FillPhase.filling || status?.phase == FillPhase.looking) {
      busy = 'filling';
    } else if (status?.phase == FillPhase.waiting && busy != 'filling') {
      busy = 'waiting';
    } else if (status == null && fillable(laneOf(blank, text, options))) {
      froms.add(blank.from);
    }
  }
  final PillWidget pill;
  if (busy != null) {
    final word = busy == 'filling' ? 'Filling' : 'Waiting';
    pill = PillWidget(word, true, const <int>[], word);
  } else if (froms.isEmpty) {
    return null;
  } else {
    pill = PillWidget(froms.length == 1 ? 'Fill' : 'Fill ${froms.length}', false, froms, froms.length == 1 ? 'Fill the blank' : 'Fill ${froms.length} blanks');
  }
  return FillPill(pill.label, busy: pill.busy, aria: pill.aria, onPress: () => pill.press(view));
}

/// The squares, the tracked ranges and their look, with `hooks` where a note is the person's to fill.
Extension blanks(BlankHooks? hooks, {bool still = false}) => Extension.list(<Extension>[blankHooks.of(hooks), _stillSquares.of(still), blanksField, blankStamp, _plugin, baseTheme(_theme)]);

/// A class and a sample for the brisk setup's line, so a change of look reaches it (docs/DESIGN.md §146)
/// (`BLANK_CLASS`).
const String blankClass = 'cm-blank';
