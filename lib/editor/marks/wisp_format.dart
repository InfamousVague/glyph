/// The look of a plugin formatting whose look is smoke (`plugins/marks.dart` [WispLook]): the Spoiler mark's
/// `||secret||`. Every letter between the delimiters is bent, blurred and half-there, without rest, so the words
/// can't be read until the caret is put in them; then they settle to plain text for editing, and smoke over again
/// when the caret leaves. The delimiters stay as they are, dimmed marks, so the secret can be found. Ports
/// `src/app/editor/wispFormat.ts`.
///
/// A whole line can be hidden the same way, written as a quote whose first character is a bar: `>| the answer`
/// ([spoilerLineLetters]). It is the same spoiler, so it lives and dies with the Spoiler mark.
///
/// The letters keep their places: each is a plain inline mark, so kerning and wrapping don't change. A dozen
/// smokes are shared round the letters so neighbours never move alike, and moved together on the animation clock
/// at about 30 steps a second while any smoke is on screen. With reduced motion the smoke stands still, and still
/// hides. A view that can't be edited (a read-only note) never clears.
///
/// What differs:
/// - The page marks each letter `filter: url(#wispfmt-<n>-<slot>)` and keeps twelve SVG filters beside the editor,
///   whose attributes a frame loop rewrites. Here each letter's mark says its slot and its own text (`data-slot`,
///   `data-text`, which a painter is not otherwise told), and the letter is drawn through the wisp's shader
///   (`lib/art/wisp_kit.dart`: `feTurbulence` into `feDisplacementMap`, then the blur, the lift and the fade) with
///   that slot's numbers at the clock's time: [smokePose] is `pose(t)` of the web file, number for number.
/// - Until the shaders have loaded, and where they cannot (a test without them), a letter is its own blur at the
///   pose's softness and fade: it hides the word as surely, without the bend.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' hide Decoration;

import '../../art/wisp_kit.dart';
import '../../art/wisp_text.dart' show paintWispLetter;
import '../../plugins/marks.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../view/editor_view.dart';
import '../view/line_facts.dart';
import '../view/syntax_tree.dart';
import 'run_paint.dart';
import 'wisp_tables.dart';

/// A letter to smoke.
typedef SmokeLetter = ({int from, int to});

const int smokePool = 12;
const double smokeStepMs = 33;
const double _bend = 36;
const double _bendSway = 14;
const double _soft = 3.2;
const double _softSway = 1.3;
const double _lift = 3;

final RegExp _space = RegExp(r'\s');

/// The letters to smoke in `from`-`to`: every letter, spaces aside, of each node whose name is in `names` (mapped
/// to its delimiter's length), except a node the selection touches while `clearAtCaret`.
///
/// With `marked` (the lines that have one of the names' delimiters, `delimitedLines`), the walk goes only into what
/// touches such a line.
List<SmokeLetter> smokeLetters(EditorState state, Map<String, int> names, int from, int to, bool clearAtCaret, [LineFact<bool>? marked]) {
  final letters = <SmokeLetter>[];
  final holds = marked == null ? null : touching(marked.between(state.doc, state.doc.lineAt(from).number, state.doc.lineAt(to).number));
  syntaxTree(state).iterate(
    from: from,
    to: to,
    enter: (node) {
      final length = names[node.name];
      if (length == null) return holds == null || node.from < from || holds(node.from, node.to) ? null : false;
      if (clearAtCaret && state.selection.ranges.any((r) => r.to >= node.from && r.from <= node.to)) return false;
      final a = node.from + length, b = node.to - length;
      if (b <= a) return false;
      var pos = a;
      for (final rune in state.doc.sliceString(a, b).runes) {
        final ch = String.fromCharCode(rune);
        if (!_space.hasMatch(ch)) letters.add((from: pos, to: pos + ch.length));
        pos += ch.length;
      }
      return false;
    },
  );
  return letters;
}

/// A spoiler line: a quote whose first character is `|`.
final RegExp _spoilerLine = RegExp(r'^(\s{0,3}>\|\s?)');

/// The letters to smoke on spoiler lines in `from`-`to` (a whole line hidden, written `>| the answer`): everything
/// after the `>|`, a run of such lines being one block, which clears together while the selection touches any of
/// it.
List<SmokeLetter> spoilerLineLetters(EditorState state, int from, int to, bool clearAtCaret) {
  final doc = state.doc;
  final letters = <SmokeLetter>[];
  final first = doc.lineAt(from).number, last = doc.lineAt(to).number;
  // The spoiler lines among the ones asked about, from what the tree keeps of them: every line on screen was put
  // to the pattern on every letter and every move of the caret.
  var done = 0;
  for (final found in _spoilers.between(doc, first, last)) {
    final n = found.number;
    if (n <= done) continue;
    // The whole block, even where it runs past the range, so a block half on screen still clears as one.
    var start = n;
    while (start > 1 && _spoilers.at(doc, start - 1) != null) {
      start -= 1;
    }
    var end = n;
    while (end < doc.lines && _spoilers.at(doc, end + 1) != null) {
      end += 1;
    }
    final blockFrom = doc.line(start).from, blockTo = doc.line(end).to;
    final open = clearAtCaret && state.selection.ranges.any((r) => r.to >= blockFrom && r.from <= blockTo);
    if (!open) {
      for (var k = math.max(start, n); k <= math.min(end, last); k += 1) {
        final line = doc.line(k);
        final lead = _spoilerLine.firstMatch(line.text)!.group(1)!.length;
        var pos = line.from + lead;
        for (final rune in line.text.substring(lead).runes) {
          final ch = String.fromCharCode(rune);
          if (!_space.hasMatch(ch)) letters.add((from: pos, to: pos + ch.length));
          pos += ch.length;
        }
      }
    }
    done = end;
  }
  return letters;
}

/// A spoiler line, kept for every line of a document (`LineFact`). It is written with `>|`.
final LineFact<bool> _spoilers = LineFact<bool>((text) => text.contains('>|') && _spoilerLine.hasMatch(text) ? true : null);

/// One smoke at a moment: what `pose(t)` writes into a slot's filter.
class SmokePose {
  const SmokePose({required this.bend, required this.soft, required this.lift, required this.shown, required this.frequency});

  /// `feDisplacementMap scale`, `feGaussianBlur stdDeviation`, `feOffset dy`, `feFuncA slope`, `baseFrequency`.
  final double bend, soft, lift, shown;
  final Offset frequency;
}

/// The seed of slot `k`'s noise.
int smokeSeed(int k) => k * 11 + 3;

/// Slot `k`'s filter at time `t` seconds, each slot on its own phase, so no two letters breathe together. The
/// numbers are rounded as the page writes them into its attributes.
SmokePose smokePose(int k, double t) {
  final phase = k * 0.83;
  double fixed(double value, int digits) => double.parse(value.toStringAsFixed(digits));
  return SmokePose(
    bend: fixed(_bend + _bendSway * math.sin(t * 1.9 + phase), 1),
    soft: fixed(_soft + _softSway * math.sin(t * 1.4 + phase * 1.7), 2),
    lift: fixed(_lift * math.sin(t * 1.1 + phase * 2.3), 2),
    shown: fixed(0.7 + 0.25 * math.sin(t * 2.6 + phase * 3.1), 3),
    frequency: Offset(fixed(0.02 + 0.006 * math.sin(t * 0.7 + phase), 4), fixed(0.07 + 0.02 * math.sin(t * 0.5 + phase * 1.3), 4)),
  );
}

class _SmokeLetter extends LetterLayer {
  const _SmokeLetter(super.text, this.slot, this.still);

  final int slot;
  final bool still;

  @override
  bool get moves => !still;

  /// Smoke is posed anew every 33 ms and no sooner: a line with nothing else moving on it is painted again at that
  /// pace, not at the screen's sixty (or a hundred and twenty) a second for the same picture twice (or four times).
  @override
  double get step => smokeStepMs / 1000;

  @override
  void drawLetter(Canvas canvas, LetterGlyph glyph, Offset at, Size box, RunLook look) {
    // The page's loop poses its filters every 33 ms.
    final t = still ? 0.0 : (MarkClock.now * 1000 / smokeStepMs).floorToDouble() * smokeStepMs / 1000;
    final pose = smokePose(slot, t);
    final seed = smokeSeed(slot);
    final kit = WispKit.maybe;
    final table = kit?.tableNow(seed);
    canvas.translate(0, pose.lift);
    if (kit == null || table == null) {
      final region = Rect.fromLTWH(-3 * box.width, -1.5 * box.height, 7 * box.width, 4 * box.height);
      canvas.saveLayer(
        region,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, pose.shown.clamp(0.0, 1.0))
          ..imageFilter = ui.ImageFilter.blur(sigmaX: pose.soft, sigmaY: pose.soft, tileMode: TileMode.decal),
      );
      glyph.painter.paint(canvas, Offset.zero);
      canvas.restore();
      return;
    }
    final image = glyph.image();
    paintWispLetter(
      canvas,
      kit: kit,
      table: table,
      glyph: image,
      glyphRect: glyph.imageRect,
      box: box,
      smoke: WispSmoke.flat(seed: seed, frequency: pose.frequency, bend: pose.bend, blur: pose.soft),
      opacity: pose.shown,
    );
  }
}

final List<Map<String, Decoration>> _marks = <Map<String, Decoration>>[for (var i = 0; i < smokePool; i++) <String, Decoration>{}];

Decoration _markFor(int slot, String text) => _marks[slot][text] ??= Decoration.mark(
  className: 'cm-wispFormat',
  attributes: <String, String>{'style': 'filter:url(#wispfmt-$slot)', 'data-slot': '$slot', 'data-text': text},
);

// Plain inline spans, so the line's kerning and wrapping are exactly what they are without the smoke.
final LookSheet _theme = LookSheet('editor/wispFormat.ts', <LookRule>[
  LookRule(
    'cm-wispFormat',
    null,
    classes: 2,
    box: (p, e) {
      final attrs = p.element?.attrs ?? const <String, String>{};
      p.painter = MarkPaint.add(p.painter, _SmokeLetter(attrs['data-text'] ?? '', int.tryParse(attrs['data-slot'] ?? '') ?? 0, e.t.reducedMotion));
    },
  ),
]);

final Extension _themed = baseTheme(_theme);

class _WispFormat extends PluginValue {
  _WispFormat(this.view, this.names, this.marked) {
    _redraw(first: true);
  }

  final EditorViewLike view;
  final Map<String, int> names;

  /// The lines with one of the smoked marks' delimiters: where the tree is walked.
  final LineFact<bool>? marked;
  DecorationSet decorations = Decoration.none;
  bool _gone = false;

  /// The shaders and each slot's noise, off the first frame; the letters are their own blur until then. Asked for
  /// when the note first shows a smoked letter (wisp_tables.dart).
  final WispTables _tables = WispTables(<int>[for (var i = 0; i < smokePool; i++) smokeSeed(i)]);

  void _wantTables({required bool atOnce}) => _tables.want(
    atOnce: atOnce,
    gone: () => _gone,
    ready: () {
      final own = view;
      if (own is! EditorView) return;
      for (final line in own.lines) {
        line.markNeedsPaint();
      }
    },
  );

  @override
  void destroy() => _gone = true;

  @override
  void update(ViewUpdate update) {
    if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged || !identical(syntaxTree(update.state), syntaxTree(update.startState))) {
      _redraw();
    }
  }

  void _redraw({bool first = false}) {
    final ranges = view.visibleRanges;
    if (ranges.isEmpty) {
      decorations = Decoration.none;
      return;
    }
    final state = view.state;
    final clear = state.facet(EditorViewLike.editable) && view.hasFocus;
    final from = ranges.first.from, to = ranges.last.to;
    final letters = <SmokeLetter>[...smokeLetters(state, names, from, to, clear, marked), ...spoilerLineLetters(state, from, to, clear)]..sort((a, b) => a.from - b.from);
    if (letters.isNotEmpty) _wantTables(atOnce: first);
    final builder = RangeSetBuilder<Decoration>();
    var i = 0, before = -1;
    for (final letter in letters) {
      if (letter.from == before) continue;
      before = letter.from;
      builder.add(letter.from, letter.to, _markFor(i % smokePool, state.sliceDoc(letter.from, letter.to)));
      i += 1;
    }
    decorations = builder.finish();
  }
}

/// The smoke looks of `formats`, drawn.
Extension wispFormat(Iterable<GlyphFormat> formats) {
  final names = <String, int>{
    for (final format in formats)
      if (format.look is WispLook) format.name: format.delimiter.length,
  };
  if (names.isEmpty) return const Extension.list(<Extension>[]);
  final marked = delimitedLines(<GlyphFormat>[
    for (final format in formats)
      if (format.look is WispLook) format,
  ]);
  return Extension.list(<Extension>[
    // Inside the highlighter's spans, as the style looks are, so a letter's painter is the one its run carries.
    Prec.highest(ViewPlugin.define<_WispFormat>((view) => _WispFormat(view, names, marked), decorations: (value) => value.decorations)),
    _themed,
    markMotion,
  ]);
}
