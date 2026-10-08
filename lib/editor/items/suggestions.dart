/// Suggestions, inline: a quiet word at the end of a line for what a plugin could do with it, tapped to do it.
/// Ports `src/app/editor/suggestions.ts`.
///
/// Matt: "render suggestions inline for stuff like adding a list item as a Notion task and whatnot; I want the note
/// to feel more alive with the integrations while remaining minimalistic". So: a small outlined word in the
/// faintest ink after the line ("Notion" after a to-do that is not a task yet) and nothing else. It is not on the
/// line being typed (it would sit against the caret and jump with every letter), it says its busy word while it
/// runs, and once the line has become what it offered (a link, for a task) it is gone, because the plugin no longer
/// offers it.
///
/// The words come from `suggest(body)`, read on every change of the document (the plugins' answers are pure and
/// cheap: a regex per line). The widget lives after the line's text as a decoration, so the note's own words are
/// never touched and the swipe on the line (swipe_items.dart) still works.
///
/// What differs:
/// - The page stopped a pointer, a mouse and a touch press differently, because a touch whose default is taken
///   away never becomes a click. Here there is one press: the widget keeps its pointers (`takesPointer`), so the
///   editor never moves the caret for it, and the tap that follows is the word's own. The line is held from the
///   moment a finger goes down until it lifts or is called off, as on the page.
/// - `suggestTheme` is drawn by the word's own widget, each rule cited where it is drawn; a busy word's dashed edge
///   is painted. `cursor`, `user-select` and the tap highlight have no counterpart.
library;

import 'dart:async';
import 'dart:ui' show PathMetric;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../editor.dart';
import '../looks/look.dart';
import '../media/inline_box.dart';
import '../view/line.dart' show EditorRunScope;

/// A word offered on a line (`LineSuggestion`).
class LineSuggestion {
  const LineSuggestion({required this.line, required this.label, required this.busyLabel, required this.run});

  /// 1-based line.
  final int line;
  final String label;
  final String busyLabel;
  final Future<void> Function() run;
}

/// A line's suggestion started or finished running.
final StateEffectType<({int line, bool busy})> _busyChanged = StateEffect.define<({int line, bool busy})>();

/// The word after a line.
class SuggestWidget extends EditorWidget {
  const SuggestWidget(this.label, this.busy, this.press, this.held, this.released);

  final String label;
  final bool busy;
  final VoidCallback press;

  /// Told as a finger goes down on it, so the pill is not taken away before the tap finishes.
  final VoidCallback held;
  final VoidCallback released;

  @override
  bool eq(SuggestWidget other) => other.label == label && other.busy == busy;

  @override
  Widget build(BuildContext context) => SuggestWord(this);
}

/// The word as it is drawn: faint, outlined, a step smaller than the line, and out of the way.
class SuggestWord extends StatefulWidget {
  const SuggestWord(this.word, {super.key});

  final SuggestWidget word;

  @override
  State<SuggestWord> createState() => _SuggestWordState();
}

class _SuggestWordState extends State<SuggestWord> with SingleTickerProviderStateMixin {
  bool _pressed = false;

  // animation: 'cm-suggest-in 220ms ease-out both'
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // '@media (prefers-reduced-motion: reduce)': { '.cm-suggest': { animation: 'none' } }
    if (context.tokens.reducedMotion) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final word = widget.word;
    final scope = EditorRunScope.maybeOf(context);
    final body = t.len('app-body');
    final around = scope?.look.style ?? t.textAt(body, mono: true, color: t.color('app-ink'));
    final em = scope?.look.fontSize ?? body;
    // '.cm-suggest': { appearance: 'none', display: 'inline-block', textIndent: '0', marginInlineStart: '0.6em',
    //   padding: '0 0.6em', border: '1px solid color-mix(in oklch, currentColor 45%, transparent)',
    //   borderRadius: '999px', background: 'transparent', color: 'var(--app-ink-3, currentColor)', font: 'inherit',
    //   fontSize: '0.68em', lineHeight: '1.7', verticalAlign: '0.15em', whiteSpace: 'nowrap' }
    // '.cm-suggest:active': { color: 'var(--app-ink, currentColor)' }
    // '.cm-suggest[data-busy]': { color: 'var(--app-ink-4, currentColor)', borderStyle: 'dashed', cursor: 'default' }
    final size = em * 0.68;
    final color = word.busy ? t.color('app-ink-4') : (_pressed ? t.color('app-ink') : t.color('app-ink-3'));
    final edge = t.colorOf('color-mix(in oklch, currentColor 45%, transparent)', current: color);
    final style = around.copyWith(fontSize: size, color: color, decoration: TextDecoration.none);
    final pad = layoutUnit(size * 0.6);
    final box = CustomPaint(
      key: const ValueKey<String>('cm-suggest'),
      painter: _Edge(edge, dashed: word.busy),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad + 1, vertical: 1),
        child: InlineWords(word.label, key: const ValueKey<String>('cm-suggest-words'), style: style, lineHeight: size * 1.7),
      ),
    );
    return Semantics(
      button: true,
      enabled: !word.busy,
      label: word.label,
      onTap: word.busy ? null : word.press,
      child: ExcludeSemantics(
        child: InlineRaise(
          by: size * 0.15,
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: pad),
            child: Listener(
              onPointerDown: (_) => word.held(),
              onPointerUp: (_) => word.released(),
              onPointerCancel: (_) => word.released(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: word.busy ? null : (_) => setState(() => _pressed = true),
                onTapCancel: word.busy ? null : () => setState(() => _pressed = false),
                onTapUp: word.busy ? null : (_) => setState(() => _pressed = false),
                onTap: word.busy ? null : word.press,
                // '@keyframes cm-suggest-in': { from: { opacity: '0', transform: 'translateX(-2px)' } }
                child: AnimatedBuilder(
                  animation: _enter,
                  builder: (context, child) {
                    final at = Curves.easeOut.transform(_enter.value);
                    return at >= 1 ? child! : Opacity(opacity: at, child: Transform.translate(offset: Offset(-2 * (1 - at), 0), child: child));
                  },
                  child: box,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A hairline of the word's own ink at less than half strength: seen on black paper and on white, never loud.
class _Edge extends CustomPainter {
  const _Edge(this.color, {required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final round = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(size.height / 2));
    if (!dashed) {
      canvas.drawRRect(round, paint);
      return;
    }
    // `border-style: dashed`: dashes three times the edge's width, as far apart.
    final path = Path()..addRRect(round);
    for (final PathMetric metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 6) {
        canvas.drawPath(metric.extractPath(at, at + 3 < metric.length ? at + 3 : metric.length), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Edge old) => old.color != color || old.dashed != dashed;
}

class _Suggestions extends PluginValue {
  _Suggestions(this.view, this.suggest) {
    decorations = _build();
  }

  final EditorViewLike view;
  final List<LineSuggestion> Function(String body) suggest;
  late DecorationSet decorations;
  final Set<int> _busy = <int>{};

  /// The line whose pill a finger is on: kept on screen even once the caret lands on that line.
  int? _held;
  bool _gone = false;

  @override
  void destroy() => _gone = true;

  @override
  void update(ViewUpdate update) {
    final changed = update.transactions.any((tr) => tr.effects.any((effect) => effect.isOf(_busyChanged)));
    if (update.docChanged || update.selectionSet || changed) decorations = _build();
  }

  DecorationSet _build() {
    final state = view.state;
    final doc = state.doc;
    final caret = doc.lineAt(state.selection.main.head).number;
    final marks = <Range<Decoration>>[];
    for (final suggestion in suggest(doc.toString())) {
      final held = _held == suggestion.line || _busy.contains(suggestion.line);
      if (suggestion.line < 1 || suggestion.line > doc.lines || (suggestion.line == caret && !held)) continue;
      final line = doc.line(suggestion.line);
      final busy = _busy.contains(suggestion.line);
      final widget = SuggestWidget(busy ? suggestion.busyLabel : suggestion.label, busy, () => _press(suggestion), () => _held = suggestion.line, () {
        if (_held == suggestion.line) _held = null;
      });
      marks.add(Decoration.widget(widget: widget, side: 1).range(line.to));
    }
    return Decoration.set(marks, true);
  }

  void _press(LineSuggestion suggestion) {
    if (_busy.contains(suggestion.line) || _gone) return;
    _busy.add(suggestion.line);
    view.dispatch(TransactionSpec(effects: _busyChanged.of((line: suggestion.line, busy: true))));
    unawaited(
      Future<void>.sync(suggestion.run).catchError((Object _) {}).whenComplete(() {
        _busy.remove(suggestion.line);
        // The view may be gone by the time a slow send answers.
        if (!_gone) view.dispatch(TransactionSpec(effects: _busyChanged.of((line: suggestion.line, busy: false))));
      }),
    );
  }
}

/// The quiet words after the lines `suggest` offers them on, for the note's words as they are now.
Extension lineSuggestions({required List<LineSuggestion> Function(String body) suggest}) =>
    ViewPlugin.define<_Suggestions>((view) => _Suggestions(view, suggest), decorations: (value) => value.decorations);
