/// The quiet mark on a line that may be out of date, drawn by the editor and never written into the note
/// (docs/NOTE_DECAY.md §2; Matt, 2026-11-02: "get a quiet 'may be out of date' mark with the reason"): a faint wash
/// of the ink behind the line's words and, at its end, a small "May be out of date" chip in the muted ink. A mark for
/// the page as a whole (`stale`) is the same chip at the page's head, under its front matter. A tap opens the reason
/// with Update with AI and Still right (sheets.dart).
///
/// Written to take any kind and reason (signals.dart [DecaySignal]), so the contradiction finder can draw its marks
/// through it. A mark is found again by its line's words, not its number: lines typed above it move it, and a line
/// edited away takes its mark with it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../editor/editor.dart';
import '../../editor/looks/look.dart';
import '../../editor/media/images.dart' show gutterOf;
import '../../editor/looks/sheets.dart';
import '../../editor/view/line.dart' show EditorRunScope;
import '../../core/front_matter.dart' show frontMatterSpan;
import 'signals.dart';

/// What the note's screen gives the marks.
class DecayMarkHooks {
  const DecayMarkHooks({required this.signals, required this.press, this.active, this.changes});

  /// Whether any mark may be drawn now (the plugin on): while not, the page is never read, typing or not. Always,
  /// where unsaid.
  final bool Function()? active;

  /// The signals for the page as it reads now ([body]); none while the plugin is off.
  final List<DecaySignal> Function(String body) signals;

  /// A chip tapped: the signals on its line (or the page's head), and the view to change the page through.
  final void Function(List<DecaySignal> signals, EditorViewLike view, BuildContext context) press;

  /// Told when [signals] may answer otherwise: the marks are drawn again.
  final Listenable? changes;
}

final StateEffectType<Null> _redraw = StateEffect.define<Null>();

/// The marks asked again in the same step as a change of the plugin's own (Still right, an accepted edit).
StateEffect<Null> decayRedraw() => _redraw.of(null);

final Facet<DecayMarkHooks?, DecayMarkHooks?> _hooks = Facet.define<DecayMarkHooks?, DecayMarkHooks?>(combine: (values) => values.where((v) => v != null).firstOrNull);

final Decoration _wash = Decoration.mark(className: 'cm-decayLine');

/// The line of [lines] (from 0) whose words are [quote], nearest [near]; null where none is.
int? _lineOf(List<String> lines, String quote, int? near) {
  if (quote.isEmpty) return null;
  int? best;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() != quote) continue;
    if (best == null || (near != null && (i - near).abs() < (best - near).abs())) best = i;
  }
  return best;
}

/// The marks of the page, read from the hooks: a state field, since the head's chip is a block.
DecorationSet _marksOf(EditorState state) {
  final hooks = state.facet(_hooks);
  if (hooks == null || !(hooks.active?.call() ?? true)) return Decoration.none;
  final doc = state.doc;
  final body = doc.toString();
  final signals = hooks.signals(body);
  if (signals.isEmpty) return Decoration.none;
  final lines = body.split('\n');
  final byLine = <int, List<DecaySignal>>{};
  final head = <DecaySignal>[];
  for (final signal in signals) {
    if (signal.line == null) {
      head.add(signal);
      continue;
    }
    final at = _lineOf(lines, signal.quote, signal.line);
    if (at != null) (byLine[at] ??= []).add(signal);
  }
  final found = <Range<Decoration>>[];
  if (head.isNotEmpty) {
    // Under the front matter, at the start of the page's first line of words: a widget at the end of the folded
    // block is never drawn (lib/editor/tools/tool_chips.dart).
    final first = (frontMatterSpan(body).lines + 1).clamp(1, doc.lines);
    found.add(Decoration.widget(widget: DecayChipWidget(head, page: true), block: true, side: -1).range(doc.line(first).from));
  }
  for (final MapEntry(key: index, value: on) in byLine.entries) {
    final line = doc.line(index + 1);
    final lead = line.text.length - line.text.trimLeft().length;
    final end = line.text.trimRight().length;
    if (end > lead) found.add(_wash.range(line.from + lead, line.from + end));
    found.add(Decoration.widget(widget: DecayChipWidget(on), side: 1).range(line.to));
  }
  return Decoration.set(found, true);
}

/// Made again only when told ([_redraw]): a letter typed moves the marks with the words round them and reads nothing
/// of the page, and the view plugin asks again once typing pauses ([_Heard]), so a keystroke costs the line it is on,
/// never the note (test/root/typing_budget_test.dart).
final StateField<DecorationSet> _marks = StateField.define<DecorationSet>(
  create: _marksOf,
  update: (decorations, tr) {
    if (tr.effects.any((e) => e.isOf(_redraw))) return _marksOf(tr.state);
    if (tr.docChanged) return decorations.map(tr.changes);
    return decorations;
  },
  provide: (field) => EditorViewLike.decorations.from<DecorationSet>(field),
);

/// Hears the hooks' changes and draws the marks again, and asks again once typing has paused: never while the hooks
/// say nothing can be drawn and none is.
class _Heard extends PluginValue {
  _Heard(this.view, this.hooks) {
    hooks.changes?.addListener(_heard);
  }

  final EditorViewLike view;
  final DecayMarkHooks hooks;
  bool _told = false;
  bool _gone = false;
  Timer? _pause;

  /// How long typing rests before the marks are asked again.
  static const Duration pause = Duration(milliseconds: 600);

  bool get _wanted => (hooks.active?.call() ?? true) || !view.state.field(_marks).isEmpty;

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

final LookSheet _theme = LookSheet('editor/noteDecay', <LookRule>[
  // A line that may be out of date: a fainter wash of the ink than a Lovart cue's, quiet enough to read past.
  LookRule('cm-decayLine', classes: 2, (p, e) {
    final wash = e.t.colorOf('color-mix(in oklch, var(--app-ink, currentColor) 5%, transparent)', current: p.color);
    p.background = (_) => wash;
  }),
]);

/// The marks of a note while [hooks] has any (see the header).
Extension noteDecayMarks(DecayMarkHooks hooks) => Extension.list(<Extension>[
      _hooks.of(hooks),
      _marks,
      ViewPlugin.define<_Heard>((view) => _Heard(view, hooks)),
      baseTheme(_theme),
    ]);

/// The chip at a marked line's end, or at the page's head.
class DecayChipWidget extends EditorWidget {
  const DecayChipWidget(this.signals, {this.page = false});

  final List<DecaySignal> signals;
  final bool page;

  @override
  bool eq(DecayChipWidget other) => other.page == page && listEquals(other.signals, signals);

  @override
  Widget build(BuildContext context) {
    final view = EditorViewScope.maybeOf(context);
    final hooks = view?.state.facet(_hooks);
    final chip = DecayChip(signals: signals, onPress: view == null || hooks == null ? null : () => hooks.press(signals, view, context));
    if (!page) return chip;
    final t = context.tokens;
    // In the page's gutter, as a picture under a line is (lib/editor/media/images.dart), less the chip's own lead.
    return Padding(padding: EdgeInsetsDirectional.only(top: t.space(1), bottom: t.space(2), start: gutterOf(context) * 0.85), child: Align(alignment: AlignmentDirectional.centerStart, child: chip));
  }
}

/// "May be out of date", small and in the muted ink, with a faint clock: what a mark says before it is tapped.
class DecayChip extends StatelessWidget {
  const DecayChip({super.key, required this.signals, required this.onPress});

  final List<DecaySignal> signals;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = EditorRunScope.maybeOf(context);
    final em = scope?.look.fontSize ?? t.len('app-body');
    final ink = t.color('glacier-text-muted');
    final size = (em * 0.72).roundToDouble();
    final reason = signals.length == 1 ? signals.first.reason : '${signals.first.reason}, and ${signals.length - 1} more';
    return Semantics(
      button: true,
      label: 'May be out of date: $reason',
      onTap: onPress,
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: em * 0.4),
          child: GestureDetector(
            key: const ValueKey<String>('decay-chip'),
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
                  Text(signals.length == 1 ? 'May be out of date' : 'May be out of date · ${signals.length}', style: (scope?.look.style ?? DefaultTextStyle.of(context).style).copyWith(fontSize: em * 0.68, color: ink, height: 1.2, fontWeight: FontWeight.w400, fontStyle: FontStyle.normal, decoration: TextDecoration.none, background: null)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
