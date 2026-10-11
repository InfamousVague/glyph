/// The matches of a search, marked in the note, and the search's commands as the view runs them. Ports the parts of
/// `src/app/editor/find.ts` that `commands/find.dart` left to the view: the decorations its field `provide`s
/// (`cm-findMatch`, `cm-findCurrent`), `findTheme`, and `reveal`, the scroll each command ends with.
///
/// Every match is washed with a fifth of the ink; the current one is printed in reverse, like a selection, and so
/// is everything inside it, since the words there carry colours of their own (a list item, a link).
///
/// What differs:
/// - the marks are a field of their own beside the search's ([findMarks]), made from [findOf], where the web's one
///   field provides them: `commands/find.dart`'s field is private to it. [findBarExtensions] is the two together,
///   which is the web's `findExtension()`.
/// - the commands here ([searchIn], [stepIn], [replaceOneIn], [replaceAllIn], [endSearchIn]) are the web's own
///   (`search(view, …)` and the rest): they dispatch what `commands/find.dart` answers and then [reveal].
///   [replaceOneIn] makes its second transaction from the view's state after the first, not from the first's own,
///   so a host that takes transactions through `onDispatch` and changes them is still followed.
/// - a ground is drawn by a [RunPainter], for the two pixels its corners are rounded by. A match that runs across
///   the edge of another mark (`mi**lk**`) is several runs here, and each is rounded where the page rounds the
///   match's two ends alone; a match that wraps is rounded at the line's end and start as well, where the page's
///   box is cut square.
/// - where a match is inside another mark's span (a heading's words, bold), the page paints the match's own box,
///   as tall as the note's words, and for the current one the inner span's box as well. Here the match's box is
///   worked out from the size of what the inner run is directly in, which is the match unless marks are nested two
///   deep inside it; and the face it is measured in is the inner run's own.
/// - `color: var(--glacier-bg) !important` is a rule that sorts after every other, since nothing else in the
///   editor's sheets is important.
/// - on a line whose leading is tighter than its letters are tall (a heading) no match is marked yet, and the
///   current one keeps its ink: see [groundsOnTightLines].
library;

import 'package:flutter/widgets.dart' hide Decoration;

import '../commands/find.dart' as find;
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';

export '../commands/find.dart' show FindMatch, FindState, currentMatch, findOf, matchesIn, setFind;

final Decoration _match = Decoration.mark(className: 'cm-findMatch');
final Decoration _current = Decoration.mark(className: 'cm-findCurrent');

class _Marks {
  _Marks(this.of) : decorations = _decorate(of);

  /// The search these were made from: the same search, the same marks.
  final find.FindState of;
  final DecorationSet decorations;

  static DecorationSet _decorate(find.FindState value) {
    if (value.matches.isEmpty) return Decoration.none;
    return Decoration.set(<Range<Decoration>>[
      for (var i = 0; i < value.matches.length; i++) (i == value.current ? _current : _match).range(value.matches[i].from, value.matches[i].to),
    ]);
  }
}

/// `provide: (field) => EditorView.decorations.from(field, …)` of find.ts's field.
final StateField<_Marks> _marks = StateField.define<_Marks>(
  create: (state) => _Marks(find.findOf(state)),
  update: (value, tr) {
    final now = find.findOf(tr.state);
    return identical(now, value.of) ? value : _Marks(now);
  },
  provide: (field) => EditorViewLike.decorations.from<_Marks>(field, (value) => value.decorations),
);

/// Whether the view paints a run's ground on a line whose leading is tighter than its letters are tall, which a
/// heading's is. It does not yet: `RenderEditorLine.paint` (view/line.dart, `boxesOf`) finds a run's boxes by
/// `line.top == rect.top`, and `rectsForRange` answers `min(line.top, line.contentTop)` for the top, so on such a
/// line a ground has no boxes and nothing is painted, a [RunPainter]'s or a plain `background`'s alike. While
/// that stands the current match there keeps its own ink, since paper on paper cannot be read; the match is still
/// counted, stepped to and scrolled to. Once the view compares the same top, make this true:
/// test/editor/find_bar/reference_test.dart says so when it is time.
const bool groundsOnTightLines = true;

/// Whether an element's own line box is shorter than its letters: its leading under its face's ascent and descent,
/// each to a whole pixel as the line's are (looks/look.dart `_box`).
bool _tight(Props p) {
  final face = FaceMetrics.of(TextStyle(fontFamily: p.families.isEmpty ? null : p.families.first));
  return lineBoxHeight(p.lineHeight, p.fontSize) < (face.ascent * p.fontSize).roundToDouble() + (face.descent * p.fontSize).roundToDouble();
}

/// A rule that sorts after every other in the editor's sheets: `!important`, and a ground laid under whatever
/// painter a format's own rule set.
const int _last = 99;

/// The ground behind a match, its corners rounded.
class _Ground extends RunPainter {
  const _Ground(this.color, {this.radius = 0, this.outer, this.own = false, this.shift = 0, this.inner});

  final Color color;

  /// `border-radius`, of the match's own box.
  final double radius;

  /// For a run inside another mark in the match: the font size of the match round it, whose box is the one painted.
  /// Null for the match's own words.
  final double? outer;

  /// Whether the run's own box is painted as well (`.cm-findCurrent *`).
  final bool own;

  /// How far the run's baseline is raised above the match's.
  final double shift;

  /// The painter the run had before this was laid under it.
  final RunPainter? inner;

  @override
  void paintBehind(Canvas canvas, List<Rect> boxes, RunLook look) {
    final paint = Paint()..color = color;
    for (final box in boxes) {
      var ground = box;
      if (outer != null) {
        // The match's own inline box: its font's ascent and descent at its size, each to a whole pixel, about the
        // match's baseline. The run's box is the same about its own.
        final face = FaceMetrics.of(look.style);
        final baseline = box.top + look.ascent + shift;
        ground = Rect.fromLTRB(box.left, baseline - (face.ascent * outer!).roundToDouble(), box.right, baseline + (face.descent * outer!).roundToDouble());
        if (own) canvas.drawRect(box, paint);
      }
      if (radius > 0) {
        canvas.drawRRect(RRect.fromRectAndRadius(ground, Radius.circular(radius)), paint);
      } else {
        canvas.drawRect(ground, paint);
      }
    }
    inner?.paintBehind(canvas, boxes, look);
  }

  @override
  void paintOver(Canvas canvas, List<Rect> boxes, RunLook look) => inner?.paintOver(canvas, boxes, look);

  @override
  bool get drawsWords => inner?.drawsWords ?? true;
}

/// `findTheme`: `EditorView.baseTheme({...})` of find.ts. A base theme's selectors carry the theme's own class, so
/// each rule counts one class more than it shows.
final LookSheet _theme = LookSheet('editor/find.ts', <LookRule>[
  // '.cm-findMatch': { backgroundColor: 'color-mix(in srgb, var(--glacier-text) 22%, transparent)',
  //   borderRadius: '2px' }
  LookRule('cm-findMatch', classes: _last, (p, e) {
    p.painter = _Ground(e.t.colorOf('color-mix(in srgb, var(--glacier-text) 22%, transparent)'), radius: 2, inner: p.painter);
  }),
  // The same box behind the words of a mark inside the match, which have no ground of their own.
  LookRule.under('cm-findMatch', classes: _last, (p, e) {
    p.painter = _Ground(e.t.colorOf('color-mix(in srgb, var(--glacier-text) 22%, transparent)'), radius: 2, outer: p.parentSize, shift: p.shift, inner: p.painter);
  }),
  // '.cm-findCurrent, .cm-findCurrent *': { backgroundColor: 'var(--glacier-text)',
  //   color: 'var(--glacier-bg) !important' }
  // '.cm-findCurrent': { borderRadius: '2px' }
  LookRule('cm-findCurrent', classes: _last, (p, e) {
    if (groundsOnTightLines || !_tight(p)) p.color = e.t.color('glacier-bg');
    p.painter = _Ground(e.t.color('glacier-text'), radius: 2, inner: p.painter);
  }),
  LookRule.under('cm-findCurrent', classes: _last, (p, e) {
    if (groundsOnTightLines || !_tight(p)) p.color = e.t.color('glacier-bg');
    p.painter = _Ground(e.t.color('glacier-text'), radius: 2, outer: p.parentSize, own: true, shift: p.shift, inner: p.painter);
  }),
]);

final Extension _themed = baseTheme(_theme);

/// The matches drawn in the note: each one's mark (`cm-findMatch`, the current one `cm-findCurrent`) and the theme
/// that paints them. Needs the search's field beside it (`commands/find.dart` `findExtension`); [findBarExtensions]
/// is both.
final Extension findMarks = Extension.list(<Extension>[_marks, _themed]);

/// What an editor that can be searched takes: the search's field and its marks. The web's `findExtension()`.
final Extension findBarExtensions = Extension.list(<Extension>[find.findExtension(), findMarks]);

/// The marks as they stand, for a test to ask.
DecorationSet findDecorations(EditorState state) => state.fieldOrNull(_marks)?.decorations ?? Decoration.none;

/// `reveal`: brings the current match into view, in the middle of the page.
void reveal(EditorViewLike view) {
  final match = find.currentMatch(view.state);
  if (match != null) view.dispatch(TransactionSpec(effects: EditorViewLike.scrollIntoView(match.from, y: ScrollStrategy.center)));
}

/// Searches for `query`, current at or after the caret, and brings it into view (`search`).
void searchIn(EditorViewLike view, String query) {
  view.dispatch(find.search(view.state, query));
  reveal(view);
}

/// The next match (or the previous, with `by` -1), wrapping round, brought into view (`step`).
void stepIn(EditorViewLike view, int by) {
  final tr = find.step(view.state, by);
  if (tr == null) return;
  view.dispatch(tr);
  reveal(view);
}

/// Replaces the current match and moves on to the next (`replaceOne`).
void replaceOneIn(EditorViewLike view, String replacement) {
  final match = find.currentMatch(view.state);
  final trs = find.replaceOne(view.state, replacement);
  if (match == null || trs.isEmpty) return;
  final query = find.findOf(view.state).query;
  view.dispatch(trs.first);
  // The search again from past what was written, so its own words are not found and replaced again.
  view.dispatch(TransactionSpec(effects: find.setFind.of((query: query, near: match.from + replacement.length))));
  reveal(view);
}

/// Replaces every match in one change, so one undo takes it all back. Answers how many were replaced
/// (`replaceAll`).
int replaceAllIn(EditorViewLike view, String replacement) {
  final all = find.replaceAll(view.state, replacement);
  if (all.tr != null) view.dispatch(all.tr!);
  return all.count;
}

/// Ends the search: no marks, and the caret on what was current, so the note picks up where the search left it
/// (`endSearch`).
void endSearchIn(EditorViewLike view) => view.dispatch(find.endSearch(view.state));
