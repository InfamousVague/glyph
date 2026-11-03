/// One "May be out of date" mark for every plugin that knows a line may be stale (Matt, 2026-11-02, asked whether the
/// Contradiction finder's "Out of date?" word and Note decay alerts' chip should be one mark: "Yes, fold them";
/// docs/NOTE_DECAY.md §5, docs/CONTRADICTIONS.md). The Contradiction finder says a newer note disagrees with a line
/// (lib/plugins/contradictions/); Note decay alerts says what the line refers to has changed (lib/plugins/note_decay/).
/// To a reader the two mean the same thing, so they wear one mark and open one sheet.
///
/// - **The mark**: a faint wash of the ink behind the line's words and, at its end, a muted "May be out of date" chip
///   with a clock, drawn by the editor and never written into the note. A mark for the page as a whole is the same chip
///   at its head, under its front matter. A line two sources flag has one chip, which counts its reasons.
/// - **The sheet**: every reason the line has, each with its own source's actions under it (Open the newer note, Mark
///   superseded, Not a conflict; Update with AI, Still right). An action runs once the sheet is put away, with the
///   view and the note's editing, so what it writes is one undo step.
///
/// The mark knows no plugin: each is an [OutOfDateSource] (lib/plugins/out_of_date/sources.dart lists the app's), so
/// a third finder of stale lines joins by being one more.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/front_matter.dart' show frontMatterSpan;
import '../../editor/editor.dart';
import '../../editor/looks/look.dart';
import '../../editor/looks/sheets.dart';
import '../../editor/media/images.dart' show gutterOf;
import '../../editor/tickets/ticket_work.dart' show showWorkSheet;
import '../../editor/view/line.dart' show EditorRunScope;
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../types.dart' show NoteEditing;

/// What an action is handed as it runs: where the sheet was, the open note's view, and its editing.
class OutOfDateUse {
  const OutOfDateUse({required this.context, required this.view, this.editing});
  final BuildContext context;
  final EditorViewLike view;
  final NoteEditing? editing;
}

/// One thing a reason's sheet offers.
@immutable
class OutOfDateAction {
  const OutOfDateAction({required this.key, required this.label, required this.run, this.hint, this.disabled = false});

  /// The row's key: `decay-still-right`, `contradiction-superseded`.
  final String key;
  final String label;
  final String? hint;
  final bool disabled;

  /// Run once the sheet is put away.
  final FutureOr<void> Function(OutOfDateUse use) run;
}

/// One reason a line (or the page) may be out of date, as one source says it.
@immutable
class OutOfDateMark {
  const OutOfDateMark({required this.source, required this.id, required this.line, required this.reason, this.detail, this.actions = const []});

  /// Who says so: `note-decay`, `contradictions`.
  final String source;

  /// The reason across draws, within its source: what the chip is compared by.
  final String id;

  /// The line of the body it is on, from 0; null for the page as a whole.
  final int? line;

  /// What the chip's sheet says first: "GHO-12 was closed on Oct 30".
  final String reason;

  /// More, under it: what the newer note says.
  final String? detail;
  final List<OutOfDateAction> actions;

  @override
  bool operator ==(Object other) => other is OutOfDateMark && other.source == source && other.id == id && other.line == line && other.reason == reason && other.detail == detail;

  @override
  int get hashCode => Object.hash(source, id, line, reason, detail);
}

/// A plugin that finds stale lines.
class OutOfDateSource {
  const OutOfDateSource({required this.id, required this.on, required this.marks});
  final String id;

  /// Whether it may mark anything now (its plugin on). While none is, the page is never read for marks.
  final bool Function() on;

  /// Its marks on [body], the open note [noteId]'s words as the editor has them.
  final List<OutOfDateMark> Function(String noteId, String body) marks;
}

/// What the note's screen gives the marks.
class OutOfDateHooks {
  const OutOfDateHooks({required this.noteId, required this.sources, this.editing, this.changes});
  final String Function() noteId;

  /// The sources, asked at each drawing.
  final List<OutOfDateSource> Function() sources;

  /// The open note's editing, for an action that writes a line (Mark superseded).
  final NoteEditing? Function()? editing;

  /// Told when any source may answer otherwise: the marks are drawn again.
  final Listenable? changes;

  bool get active => sources().any((s) => s.on());

  /// Every source's marks on [body].
  List<OutOfDateMark> marksOn(String body) => [
        for (final source in sources())
          if (source.on()) ...source.marks(noteId(), body),
      ];
}

final StateEffectType<Null> _redraw = StateEffect.define<Null>();

/// The marks asked again in the same step as a change an action makes (Still right, an accepted edit).
StateEffect<Null> outOfDateRedraw() => _redraw.of(null);

final Facet<OutOfDateHooks?, OutOfDateHooks?> _hooks = Facet.define<OutOfDateHooks?, OutOfDateHooks?>(combine: (values) => values.where((v) => v != null).firstOrNull);

final Decoration _wash = Decoration.mark(className: 'cm-outOfDate');

DecorationSet _marksOf(EditorState state) {
  final hooks = state.facet(_hooks);
  if (hooks == null || !hooks.active) return Decoration.none;
  final doc = state.doc;
  final body = doc.toString();
  final marks = hooks.marksOn(body);
  if (marks.isEmpty) return Decoration.none;
  final byLine = <int, List<OutOfDateMark>>{};
  final head = <OutOfDateMark>[];
  for (final mark in marks) {
    final line = mark.line;
    if (line == null) {
      head.add(mark);
    } else if (line >= 0 && line < doc.lines) {
      (byLine[line] ??= []).add(mark);
    }
  }
  final found = <Range<Decoration>>[];
  if (head.isNotEmpty) {
    // Under the front matter, at the start of the page's first line of words: a widget at the end of the folded block
    // is never drawn (lib/editor/tools/tool_chips.dart).
    final first = (frontMatterSpan(body).lines + 1).clamp(1, doc.lines);
    found.add(Decoration.widget(widget: OutOfDateChipWidget(head, page: true), block: true, side: -1).range(doc.line(first).from));
  }
  for (final MapEntry(key: index, value: on) in byLine.entries) {
    final line = doc.line(index + 1);
    final lead = line.text.length - line.text.trimLeft().length;
    final end = line.text.trimRight().length;
    if (end > lead) found.add(_wash.range(line.from + lead, line.from + end));
    found.add(Decoration.widget(widget: OutOfDateChipWidget(on), side: 1).range(line.to));
  }
  return Decoration.set(found, true);
}

/// Made again only when told ([_redraw]): a letter typed moves the marks with the words round them and reads nothing of
/// the page, and the view plugin asks again once typing pauses ([_Heard]), so a keystroke costs the line it is on, never
/// the note (test/root/typing_budget_test.dart).
final StateField<DecorationSet> _marks = StateField.define<DecorationSet>(
  create: _marksOf,
  update: (decorations, tr) {
    if (tr.effects.any((e) => e.isOf(_redraw))) return _marksOf(tr.state);
    if (tr.docChanged) return decorations.map(tr.changes);
    return decorations;
  },
  provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
);

/// Hears the sources' changes and draws the marks again, and asks again once typing has paused: never while no source
/// is on and nothing is drawn.
class _Heard extends PluginValue {
  _Heard(this.view, this.hooks) {
    hooks.changes?.addListener(_heard);
  }

  final EditorViewLike view;
  final OutOfDateHooks hooks;
  bool _told = false;
  bool _gone = false;
  Timer? _pause;

  /// How long typing rests before the marks are asked again.
  static const Duration pause = Duration(milliseconds: 600);

  bool get _wanted => hooks.active || !view.state.field(_marks).isEmpty;

  void _heard() {
    if (_told || !_wanted) return;
    _told = true;
    scheduleMicrotask(() {
      _told = false;
      if (!_gone) view.dispatch(TransactionSpec(effects: _redraw.of(null)));
    });
  }

  @override
  void update(ViewUpdate update) {
    if (!update.docChanged || !_wanted) return;
    _pause?.cancel();
    _pause = Timer(pause, _heard);
  }

  @override
  void destroy() {
    _gone = true;
    _pause?.cancel();
    hooks.changes?.removeListener(_heard);
  }
}

final LookSheet _theme = LookSheet('editor/outOfDate', <LookRule>[
  // A line that may be out of date: a fainter wash of the ink than a Lovart cue's, quiet enough to read past.
  LookRule('cm-outOfDate', classes: 2, (p, e) {
    final wash = e.t.colorOf('color-mix(in oklch, var(--app-ink, currentColor) 5%, transparent)', current: p.color);
    p.background = (_) => wash;
  }),
]);

/// The marks of a note, from every source [hooks] names (see the header).
Extension outOfDateMarks(OutOfDateHooks hooks) => Extension.list(<Extension>[
      _hooks.of(hooks),
      _marks,
      ViewPlugin.define<_Heard>((view) => _Heard(view, hooks)),
      baseTheme(_theme),
    ]);

/// The chip at a marked line's end, or at the page's head.
class OutOfDateChipWidget extends EditorWidget {
  const OutOfDateChipWidget(this.marks, {this.page = false});

  final List<OutOfDateMark> marks;
  final bool page;

  @override
  bool eq(OutOfDateChipWidget other) => other.page == page && listEquals(other.marks, marks);

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.maybeOf(context);
    final hooks = view?.state.facet(_hooks);
    final chip = OutOfDateChip(
      marks: marks,
      onPress: view == null ? null : () => unawaited(showOutOfDate(context, marks, OutOfDateUse(context: context, view: view, editing: hooks?.editing?.call()))),
    );
    if (!page) return chip;
    final t = context.tokens;
    // In the page's gutter, as a picture under a line is (lib/editor/media/images.dart), less the chip's own lead.
    return Padding(padding: EdgeInsetsDirectional.only(top: t.space(1), bottom: t.space(2), start: gutterOf(context) * 0.85), child: Align(alignment: AlignmentDirectional.centerStart, child: chip));
  }
}

/// "May be out of date", small and in the muted ink, with a faint clock: what a mark says before it is tapped.
class OutOfDateChip extends StatelessWidget {
  const OutOfDateChip({super.key, required this.marks, required this.onPress});

  final List<OutOfDateMark> marks;
  final VoidCallback? onPress;

  static const Key chipKey = ValueKey<String>('out-of-date-chip');

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = EditorRunScope.maybeOf(context);
    final em = scope?.look.fontSize ?? t.len('app-body');
    final ink = t.color('glacier-text-muted');
    final size = (em * 0.72).roundToDouble();
    final reason = marks.length == 1 ? marks.first.reason : '${marks.first.reason}, and ${marks.length - 1} more';
    return Semantics(
      button: true,
      label: 'May be out of date: $reason',
      onTap: onPress,
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: em * 0.4),
          child: GestureDetector(
            key: chipKey,
            behavior: HitTestBehavior.opaque,
            onTap: onPress,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: em * 0.4, vertical: em * 0.08),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(em),
                border: Border.all(color: t.colorOf('color-mix(in oklch, currentColor 22%, transparent)', current: ink), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(Lucide.clock, size: size, color: ink, strokeWidth: 1.8),
                  SizedBox(width: em * 0.25),
                  Text(
                    marks.length == 1 ? 'May be out of date' : 'May be out of date · ${marks.length}',
                    style: (scope?.look.style ?? DefaultTextStyle.of(context).style).copyWith(fontSize: em * 0.68, color: ink, height: 1.2, fontWeight: FontWeight.w400, fontStyle: FontStyle.normal, decoration: TextDecoration.none, background: null),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet a chip opens: each reason, its source's actions under it; the action chosen runs once it is put away.
Future<void> showOutOfDate(BuildContext context, List<OutOfDateMark> marks, OutOfDateUse use) async {
  final chosen = await showWorkSheet<OutOfDateAction>(context, (done) => OutOfDateSheet(marks: marks, onAnswer: done));
  if (chosen != null) await chosen.run(use);
}

/// The reasons and their actions (see [showOutOfDate]).
class OutOfDateSheet extends StatelessWidget {
  const OutOfDateSheet({super.key, required this.marks, required this.onAnswer});

  final List<OutOfDateMark> marks;
  final ValueChanged<OutOfDateAction?> onAnswer;

  static const Key sheetKey = ValueKey<String>('out-of-date-sheet');

  @override
  Widget build(BuildContext context) {
    // A key used by two reasons' rows (two of one source's) is the first's alone; the next is numbered.
    final used = <String, int>{};
    Key keyOf(String key) {
      final n = used[key] = (used[key] ?? 0) + 1;
      return ValueKey<String>(n == 1 ? key : '$key-$n');
    }

    return Sheet(
      key: sheetKey,
      label: 'May be out of date',
      onClose: () => onAnswer(null),
      children: [
        SheetTitle.text('May be out of date'),
        for (final mark in marks) ...[
          SheetNote(mark.reason),
          if (mark.detail case final detail? when detail.trim().isNotEmpty) SheetNote(detail.trim()),
          if (mark.actions.isNotEmpty)
            SheetGroup(
              children: [
                for (final action in mark.actions)
                  SheetRow(key: keyOf(action.key), label: action.label, hint: action.hint, disabled: action.disabled, onPress: action.disabled ? null : () => onAnswer(action)),
              ],
            ),
        ],
      ],
    );
  }
}
