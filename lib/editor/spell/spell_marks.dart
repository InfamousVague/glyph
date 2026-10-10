/// The words the spell checker would have otherwise, kept on the state and drawn: a red wave under each
/// (`cm-misspelled`), as the WebView draws under a misspelled word of the page's editor.
///
/// The marks are a field of the state. [setMisspellings] says "this stretch was asked about, and these are its
/// misspellings": what was marked inside the stretch is replaced, what is outside it stays. A change to the note
/// moves the marks with their words, and takes the mark off a word the change touched: an edited word is not
/// known to be wrong any more, and is asked about again when the checker next looks (spell_watch.dart). That is
/// what the page's marker does, which goes from a word as it is typed in.
///
/// The wave is the one Chromium draws wherever it is not on a Mac (`document_marker_painter.cc`): four pixels to a
/// period, two high, a pixel thick, just under the baseline; in the kit's red here, which the page's theme has
/// for both papers, where Chromium's is pure red.
library;

import 'package:flutter/widgets.dart' hide Decoration;

import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import 'spell_check.dart';

export 'spell_check.dart' show Misspelling;

/// What a look at a stretch of the note found: [from]..[to] was asked about, and [found] are its misspellings, in
/// the note's own positions.
typedef SpellLook = ({int from, int to, List<Misspelling> found});

/// A stretch was asked about (see the header). Mapped through a change made while the checker was out.
final StateEffectType<SpellLook> setMisspellings = StateEffect.define<SpellLook>(
  map: (value, mapping) => (
    from: mapping.mapPos(value.from, -1),
    to: mapping.mapPos(value.to, 1),
    found: <Misspelling>[
      for (final each in value.found)
        if (!_touched(mapping, each.from, each.to)) Misspelling(mapping.mapPos(each.from, 1), mapping.mapPos(each.to, -1), each.suggestions),
    ],
  ),
);

/// Every mark goes: the keyboard's aids were turned off (`spellcheck="false"`).
final StateEffectType<Null> clearMisspellings = StateEffect.define<Null>();

/// Whether [changes] reached the word at [from]..[to], by where they are alone: anything in it or against it.
bool _touched(ChangeDesc changes, int from, int to) {
  var touched = false;
  changes.iterChangedRanges((fromA, toA, fromB, toB) {
    if (fromA <= to && toA >= from) touched = true;
  });
  return touched;
}

final RegExp _letter = RegExp(r"[\p{L}\p{N}\p{M}'’]", unicode: true);

/// Whether [changes] changed the word at [from]..[to]: something in it, or words put against it that run on from
/// it (a letter typed onto its end or its start). Words put before it or after it with a space between leave it
/// the word it was.
bool _rewrote(ChangeSet changes, int from, int to) {
  var rewrote = false;
  changes.iterChanges((fromA, toA, fromB, toB, inserted) {
    if (rewrote || fromA > to || toA < from) return;
    // Inside it, or something of it taken out.
    if (fromA < to && toA > from) {
      rewrote = true;
      return;
    }
    final text = inserted.toString();
    if (fromA == toA) {
      // Put in at one of its ends: only letters that join it are of it.
      if (text.isEmpty) return;
      final joins = fromA == to ? _letter.hasMatch(text.substring(0, 1)) : _letter.hasMatch(text.substring(text.length - 1));
      if (joins) rewrote = true;
      return;
    }
    // Something beside it taken out or replaced: what stood between it and its neighbour may be gone.
    rewrote = true;
  });
  return rewrote;
}

final Decoration _mark = Decoration.mark(className: 'cm-misspelled');

class _Marks {
  _Marks(this.words) : decorations = words.isEmpty ? Decoration.none : Decoration.set(<Range<Decoration>>[for (final word in words) _mark.range(word.from, word.to)]);

  static final _Marks none = _Marks(const <Misspelling>[]);

  /// The misspellings, in order, none overlapping.
  final List<Misspelling> words;
  final DecorationSet decorations;
}

final StateField<_Marks> _marks = StateField.define<_Marks>(
  create: (state) => _Marks.none,
  update: (value, tr) {
    var words = value.words;
    if (tr.docChanged && words.isNotEmpty) {
      words = <Misspelling>[
        for (final word in words)
          if (!_rewrote(tr.changes, word.from, word.to)) Misspelling(tr.changes.mapPos(word.from, 1), tr.changes.mapPos(word.to, -1), word.suggestions),
      ].where((word) => word.from < word.to).toList();
    }
    var changed = !identical(words, value.words);
    for (final effect in tr.effects) {
      if (clearMisspellings.cast(effect) != null) {
        if (words.isNotEmpty) changed = true;
        words = const <Misspelling>[];
        continue;
      }
      final look = setMisspellings.cast(effect)?.value;
      if (look == null) continue;
      final length = tr.newDoc.length;
      final from = look.from.clamp(0, length), to = look.to.clamp(0, length);
      final next = <Misspelling>[
        // A mark that reaches into the stretch was asked about again with it; one wholly outside stays.
        for (final word in words)
          if (word.to <= from || word.from >= to) word,
        for (final word in look.found)
          if (word.from >= from && word.to <= to && word.from < word.to) word,
      ]..sort((a, b) => a.from.compareTo(b.from));
      // Never two marks over one letter: of two that overlap, the first stands.
      final clean = <Misspelling>[];
      for (final word in next) {
        if (clean.isNotEmpty && word.from < clean.last.to) continue;
        clean.add(word);
      }
      words = clean;
      changed = true;
    }
    return changed ? _Marks(words) : value;
  },
  provide: (field) => EditorViewLike.decorations.from<_Marks>(field, (value) => value.decorations),
);

/// The misspellings marked in [state], in order.
List<Misspelling> misspellingsOf(EditorState state) => state.fieldOrNull(_marks)?.words ?? const <Misspelling>[];

/// The marked word at [pos], its ends included, or null: what a menu opened there offers the suggestions of.
Misspelling? misspellingAt(EditorState state, int pos) {
  for (final word in misspellingsOf(state)) {
    if (word.from > pos) break;
    if (pos <= word.to) return word;
  }
  return null;
}

/// [word] written as [suggestion]: one change, the caret after it. The mark goes with the change.
TransactionSpec replaceMisspelling(Misspelling word, String suggestion) => TransactionSpec(
      changes: ChangeSpec(from: word.from, to: word.to, insert: suggestion),
      selection: EditorSelection.single(word.from + suggestion.length),
      userEvent: 'input.spell',
    );

/// The marks as they are drawn, for a test to ask.
DecorationSet spellDecorations(EditorState state) => state.fieldOrNull(_marks)?.decorations ?? Decoration.none;

/// The wave under a misspelled word, over whatever the run was painted with already.
class SpellWave extends RunPainter {
  const SpellWave(this.color, {this.inner});

  final Color color;

  /// The painter the run had before this was laid over it.
  final RunPainter? inner;

  /// One wave's length, its height and its line, in logical pixels: Chromium's marker.
  static const double period = 4, height = 2, stroke = 1;

  /// The wave from [left] to [right] with its top at [top].
  static Path waveOf(double left, double right, double top) {
    final path = Path()..moveTo(left, top + height / 2);
    var x = left;
    var up = true;
    while (x < right) {
      final next = x + period / 2 > right ? right : x + period / 2;
      path.quadraticBezierTo((x + next) / 2, up ? top : top + height, next, top + height / 2);
      x = next;
      up = !up;
    }
    return path;
  }

  @override
  void paintBehind(Canvas canvas, List<Rect> boxes, RunLook look) => inner?.paintBehind(canvas, boxes, look);

  @override
  void paintOver(Canvas canvas, List<Rect> boxes, RunLook look) {
    inner?.paintOver(canvas, boxes, look);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true;
    for (final box in boxes) {
      if (box.width <= 0) continue;
      // A pixel under the baseline, and never below the run's own box.
      final top = (box.top + look.ascent + 1).clamp(box.top, box.bottom - height < box.top ? box.top : box.bottom - height).toDouble();
      canvas.drawPath(waveOf(box.left, box.right, top), paint);
    }
  }

  @override
  bool get drawsWords => inner?.drawsWords ?? true;
}

/// A rule that sorts after the marks' own, so the wave lies over their painting and keeps it.
const int _last = 98;

final LookSheet _theme = LookSheet('editor/spell', <LookRule>[
  LookRule('cm-misspelled', classes: _last, (p, e) {
    p.painter = SpellWave(e.t.color('glacier-red-9'), inner: p.painter);
  }),
  // The words of a mark inside the misspelled word (half of it bold) are runs of their own.
  LookRule.under('cm-misspelled', classes: _last, (p, e) {
    p.painter = SpellWave(e.t.color('glacier-red-9'), inner: p.painter);
  }),
]);

/// The misspellings' field and the theme that draws them. Nothing asks the checker here: spell_watch.dart does.
final Extension spellMarks = Extension.list(<Extension>[_marks, baseTheme(_theme)]);
