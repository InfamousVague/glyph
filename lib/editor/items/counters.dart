/// Counters: a count and a goal in brackets, anywhere in a line. Ports `src/app/editor/counters.ts`.
///
///     - Water [3/8]
///     - Push-ups [0/50]
///
/// Drawn as a small chip that fills as the count rises. A tap adds one, a hold takes one away; the count never
/// goes below nothing, and a full counter tapped again stays full. Every change is an ordinary edit, one undo
/// each, so the note is still the whole truth and reads the same anywhere: `[3/8]`.
///
/// What differs:
/// - The chip's padding and border are a gap either side of the mark and a painted layer (`inline_box.dart`,
///   `run_paint.dart`), as a tag's are. The page's one `<span>` is three marks of its class here, the brackets
///   apart, because the parser reads `[3/8]` as a link's words and the view paints each of its pieces as a run of
///   its own: each mark says which end of the chip it is. The fill's edge is worked out from the letters' width,
///   which is exact in a face of one width and within a pixel or two in Inter (figures of one width, brackets not).
/// - A chip that starts a wrapped line keeps its leading padding at the end of the line above, where the page
///   starts the line with it: the gap is a thing of its own, and a line may break after it.
/// - The page finds the chip under a press from the DOM (`closest('.cm-counter')`); here it is the counter whose
///   characters the press is on, its padding included.
/// - A finger that lands on the chip and scrolls the note counts nothing: the page is sent `pointercancel` as the
///   scroll begins, and here the press is dropped once the finger has moved a scroll's slop.
/// - `.cm-counter * { color: inherit }` gives what is inside the chip the page's own ink, which is what a counter
///   inherits everywhere but in a heading.
library;

import 'dart:async';
import 'dart:ui' show Offset, PointerDeviceKind;

import 'package:flutter/gestures.dart' show computeHitSlop;
import 'package:glacier/glacier.dart' show HapticKind, haptic;

import '../../core/item_syntax.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../marks/run_paint.dart';
import '../syntax/syntax.dart';
import '../view/syntax_tree.dart';
import 'inline_box.dart';

/// `[3/8]`: not a link's words (`[3/8](…)`), a picture's, or a footnote.
final RegExp _counter = RegExp(counterInWordsPattern);

class Counter {
  const Counter({required this.from, required this.to, required this.count, required this.goal});

  final int from;
  final int to;
  final int count;
  final int goal;

  @override
  bool operator ==(Object other) => other is Counter && other.from == from && other.to == to && other.count == count && other.goal == goal;

  @override
  int get hashCode => Object.hash(from, to, count, goal);

  @override
  String toString() => 'Counter($from, $to, $count/$goal)';
}

List<Counter> countersIn(String text, [int offset = 0]) {
  final found = <Counter>[];
  for (final match in _counter.allMatches(text)) {
    // `[3/8]`: the count and the goal either side of the slash, inside the brackets.
    final whole = match.group(0)!;
    final parts = whole.substring(1, whole.length - 1).split('/');
    final count = int.tryParse(parts.first) ?? 0, goal = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    if (goal < 1) continue;
    found.add(Counter(from: offset + match.start, to: offset + match.end, count: count, goal: goal));
  }
  return found;
}

/// The counter moved by `step`, kept between nothing and its goal.
String stepped(Counter counter, int step) {
  final count = (counter.count + step).clamp(0, counter.goal);
  return '[$count/${counter.goal}]';
}

/// The counters on each line, counted from the line's start, kept for every line of a document (`LineFact`).
final LineFact<List<Counter>> _counted = LineFact<List<Counter>>((text) {
  if (!text.contains('[') || !text.contains('/')) return null;
  final counters = countersIn(text);
  return counters.isEmpty ? null : counters;
});

/// The counters on screen, leaving any in code, an address, front matter, HTML, a comment or maths as written.
List<Counter> _visibleCounters(EditorViewLike view) {
  final out = <Counter>[];
  final doc = view.state.doc;
  final tree = syntaxTree(view.state);
  for (final range in view.visibleRanges) {
    for (final line in _counted.between(doc, doc.lineAt(range.from).number, doc.lineAt(range.to).number)) {
      for (final counter in line.fact) {
        final from = line.from + counter.from;
        if (!inQuietText(tree, from)) out.add(Counter(from: from, to: line.from + counter.to, count: counter.count, goal: counter.goal));
      }
    }
  }
  return out;
}

/// `padding: 0 0.3em` and `border: 1px`, either side of the count.
final Decoration _padBefore = Decoration.widget(widget: const GapWidget(em: 0.3, px: 1), side: -1);
final Decoration _padAfter = Decoration.widget(widget: const GapWidget(em: 0.3, px: 1), side: 1);

DecorationSet _decorate(List<Counter> counters) {
  final found = <Range<Decoration>>[];
  for (final counter in counters) {
    final fill = ((counter.count < counter.goal ? counter.count : counter.goal) / counter.goal * 100).round();
    final total = counter.to - counter.from;
    // One chip in three marks, its brackets apart (see the file's note): each says which end it is and where it
    // stands among the chip's characters.
    Decoration piece(String edge, int before, int own) => Decoration.mark(
      className: counter.count >= counter.goal ? 'cm-counter cm-counterFull' : 'cm-counter',
      attributes: <String, String>{'style': '--fill:$fill%', 'data-counter': '${counter.from}', 'data-edge': edge, 'data-part': '$before/$own/$total'},
    );
    found
      ..add(_padBefore.range(counter.from))
      ..add(piece('start', 0, 1).range(counter.from, counter.from + 1))
      ..add(piece('none', 1, total - 2).range(counter.from + 1, counter.to - 1))
      ..add(piece('end', total - 1, 1).range(counter.to - 1, counter.to))
      ..add(_padAfter.range(counter.to));
  }
  return Decoration.set(found, true);
}

/// How long a press has to last to take one away, ms: about the phone's own long press.
const int _holdMs = 450;

final RegExp _fill = RegExp(r'--fill:\s*(\d+)%');

/// The chip's border and its fill, read from the counter's own element.
void _chip(Props p, LookElement element) {
  final fill = int.tryParse(_fill.firstMatch(element.attrs['style'] ?? '')?.group(1) ?? '') ?? 0;
  final part = (element.attrs['data-part'] ?? '').split('/').map(int.tryParse).toList();
  p.painter = MarkPaint.add(
    p.painter,
    BoxLayer(
      radius: p.em(0.4),
      edge: boxEdgeOf(element.attrs['data-edge']),
      padStart: p.em(0.3) + 1,
      padEnd: p.em(0.3) + 1,
      top: 1,
      bottom: 1,
      border: 1,
      borderColor: element.has('cm-counterFull') ? p.color : inkShare(p.color, 0.35),
      fill: fill / 100,
      fillColor: inkShare(p.color, 0.16),
      fillPart: part.length == 3 && !part.contains(null) ? (before: part[0]!, own: part[1]!, total: part[2]!) : null,
      fillPad: p.em(0.3),
    ),
  );
}

/// The counters round the element being dressed, as `LookRule.when` met them (see `format_looks.dart`).
final List<LookElement> _above = <LookElement>[];

final LookSheet _theme = LookSheet('editor/counters.ts', <LookRule>[
  // '.cm-counter': { padding: '0 0.3em', borderRadius: '0.4em',
  //   border: '1px solid color-mix(in srgb, currentColor 35%, transparent)',
  //   backgroundImage: 'linear-gradient(to right, color-mix(in srgb, currentColor 16%, transparent) var(--fill),
  //     transparent var(--fill))', fontVariantNumeric: 'tabular-nums', cursor: 'pointer', whiteSpace: 'nowrap' }
  // '.cm-counterFull': { borderColor: 'currentColor' }
  LookRule('cm-counter', classes: 2, (p, e) => p.tabular = true, box: (p, e) => _chip(p, p.element!)),
  // Markdown reads `[3/8]` as a link's words; the chip is not a link.
  // '.cm-counter *': { textDecoration: 'none', color: 'inherit' }
  // The link's span is the run that is painted, so the chip is drawn under it.
  LookRule.under(
    'cm-counter',
    classes: 2,
    when: (element, context) {
      _above.add(element);
      return true;
    },
    (p, e) {
      p
        ..underline = false
        ..lineThrough = false
        ..color = e.ink ?? e.t.color('glacier-text');
    },
    box: (p, e) {
      if (_above.isNotEmpty) _chip(p, _above.removeAt(0));
    },
  ),
]);

/// The counter a press at `at` is on: its characters, and the chip's edge round them.
Counter? _chipAt(EditorViewLike view, Offset at) {
  if (view.state.readOnly) return null;
  final pos = view.posAtCoords(at, precise: false);
  if (pos == null) return null;
  final line = view.state.doc.lineAt(pos);
  final tree = syntaxTree(view.state);
  for (final counter in countersIn(line.text, line.from)) {
    if (pos < counter.from || pos > counter.to || inQuietText(tree, counter.from)) continue;
    final start = view.coordsAtPos(counter.from, 1), end = view.coordsAtPos(counter.to, -1);
    if (start == null || end == null) continue;
    final pad = (start.bottom - start.top) * 0.3;
    if (at.dx >= start.left - pad && at.dx <= end.right + pad && at.dy >= start.top - 2 && at.dy <= end.bottom + 2) return counter;
  }
  return null;
}

class _Counters extends PluginValue {
  _Counters(EditorViewLike view) : decorations = _decorate(_visibleCounters(view));

  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    if (update.docChanged || update.viewportChanged || !identical(syntaxTree(update.startState), syntaxTree(update.state))) {
      decorations = _decorate(_visibleCounters(update.view));
    }
  }
}

final Extension _themed = baseTheme(_theme);

/// `[3/8]` counters: a tap adds one, a hold takes one away.
Extension counters() {
  ({int from, Timer timer, bool held, Offset at, bool finger})? press;

  void change(EditorViewLike view, int from, int step) {
    final line = view.state.doc.lineAt(from);
    final counter = countersIn(line.text, line.from).where((c) => c.from == from).firstOrNull;
    if (counter == null) return;
    final insert = stepped(counter, step);
    if (insert == view.state.sliceDoc(counter.from, counter.to)) return;
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: counter.from, to: counter.to, insert: insert), userEvent: 'input.counter'));
    haptic(step > 0 ? HapticKind.selection : HapticKind.light);
  }

  return Extension.list(<Extension>[
    ViewPlugin.define<_Counters>(_Counters.new, decorations: (value) => value.decorations),
    _themed,
    EditorViewLike.eventHandlers(
      EditorEventHandlers(
        // The chip is a control: the caret stays where it was, and a hold is a counter's, not the menu's or the
        // phone's.
        pointerDown: (event, view) {
          final chip = _chipAt(view, event.position);
          if (chip == null) return false;
          press?.timer.cancel();
          final from = chip.from;
          final timer = Timer(const Duration(milliseconds: _holdMs), () {
            final now = press;
            if (now == null) return;
            press = (from: now.from, timer: now.timer, held: true, at: now.at, finger: now.finger);
            change(view, now.from, -1);
          });
          press = (from: from, timer: timer, held: false, at: event.position, finger: event.kind != PointerDeviceKind.mouse);
          return true;
        },
        // The page is sent `pointercancel` when a finger that landed on the chip begins to scroll the note, and
        // the press is forgotten: nothing is counted for a scroll. Flutter cancels no pointer for that, so the
        // press goes when the finger has travelled as far as a scroll takes to begin.
        pointerMove: (event, view) {
          final now = press;
          if (now == null || !now.finger || (event.position - now.at).distance <= computeHitSlop(event.kind, null)) return false;
          now.timer.cancel();
          press = null;
          return false;
        },
        pointerUp: (event, view) {
          final now = press;
          if (now == null) return false;
          now.timer.cancel();
          press = null;
          if (!now.held) change(view, now.from, 1);
          return true;
        },
        pointerCancel: (event, view) {
          press?.timer.cancel();
          press = null;
          return false;
        },
        longPress: (tap, view) => _chipAt(view, tap.global) != null,
        secondaryTap: (tap, view) => _chipAt(view, tap.global) != null,
      ),
    ),
  ]);
}
