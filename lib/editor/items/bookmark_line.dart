/// The bookmark, written in the note. Ports `src/app/editor/bookmarkLine.ts`.
///
/// It is two section signs at the end of the bookmarked line's words:
///
///     The deposit is four hundred. §§
///     - [ ] Ship the pricing page §§ [notion](…) ^pricing-page
///
/// `§§` is almost never typed, reads as a mark anywhere the note is opened, and travels with the note. A note
/// holds one: putting it on a line takes it off every other. On a list item it goes before the item's mark,
/// counters and anchor, which have to stay last, and it is never part of what the item says.
///
/// Drawn as a small ribbon in place of the two signs, and a line down the bookmarked line's leading edge, so
/// scrolling past it shows where it is. The signs come back as text while the caret is right at them. A bookmark
/// from before this, kept on the device, is still shown, with [showBookmark], until the button next puts one in
/// the note.
///
/// What differs:
/// - The ribbon is the kit's own bookmark icon (`lib/art`, the path Lucide draws and the wash the app gives a
///   closed silhouette), so there is no path to copy here and none to drift.
/// - `.cm-bookmarked::before`, the gold line down the edge, is drawn by the ribbon's own box, reaching out over
///   its line: a line's look has a ground and corners but no place for a bar set in from its edge. Where no ribbon
///   stands in the line (a bookmark kept on the device, which has no signs, and a line whose signs the caret is
///   at) a box of no size at the line's end draws it instead ([BookmarkEdgeWidget]), so the edge line is there
///   whatever stands in the line, as the page's is.
library;

import 'package:flutter/rendering.dart' hide Decoration;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/item_syntax.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../view/line.dart' show EditorRunScope, RenderEditorLine;

/// The mark and the space before it, wherever it sits on a line.
const String _spaced = '[ \\t]*$bookmarkPattern';

/// Every mark on a line, for taking them all off; the first, for drawing it; the mark alone, for finding it.
final RegExp _mark = RegExp(_spaced);
final RegExp _signs = RegExp(bookmarkPattern);

/// The line (from 1) holding the note's bookmark, or null.
int? bookmarkLineIn(String text) {
  final at = text.indexOf(_signs);
  if (at < 0) return null;
  return '\n'.allMatches(text.substring(0, at)).length + 1;
}

/// A line the bookmark's signs stand on as a word, kept for every line of a document (`LineFact`).
final LineFact<bool> _signLines = LineFact<bool>((text) => text.contains(bookmarkSigns) && _signs.hasMatch(text) ? true : null);

/// The line (from 1) holding a document's bookmark, or null: [bookmarkLineIn] of its words, from the lines the
/// tree keeps, so a letter typed and a caret moved read nothing of the note again. (The signs stand as a word where
/// whitespace or the end follows them, and a line's break is whitespace: the note's first such signs are on its
/// first such line.)
int? bookmarkLineOf(Doc doc) {
  final lines = _signLines.of(doc);
  return lines.isEmpty ? null : lines.first.number;
}

final RegExp _endsInSpace = RegExp(r'\s$');

/// The changes that put the bookmark on line `number` (from 1), taking it off everywhere else; with null, only
/// taking it off. One transaction, so it is one undo.
TransactionSpec placeBookmark(EditorState state, int? number) {
  final changes = <ChangeSpec>[];
  final doc = state.doc;
  for (var n = 1; n <= doc.lines; n += 1) {
    final line = doc.line(n);
    for (final found in _mark.allMatches(line.text)) {
      changes.add(ChangeSpec(from: line.from + found.start, to: line.from + found.end));
    }
  }
  if (number != null && number >= 1 && number <= doc.lines) {
    final line = doc.line(number);
    final clean = withoutBookmark(line.text);
    // The words end before a list item's mark, counters and anchor; elsewhere, at the end of the line.
    final end = wordsEnd(clean);
    // Positions in the clean line map onto the real one because the marks taken out all sit at or after the
    // words' end.
    final at = line.from + (end < line.text.length ? end : line.text.length);
    final before = clean.substring(0, end);
    changes.add(ChangeSpec(from: at, insert: '${before.isNotEmpty && !_endsInSpace.hasMatch(before) ? ' ' : ''}$bookmarkSigns'));
  }
  return TransactionSpec(changes: changes, userEvent: 'input.bookmark');
}

/// A bookmark kept on the device, shown until the note carries its own: the position, or null.
final StateEffectType<int?> showBookmark = StateEffect.define<int?>();

/// `app-gold` gives the line the bookmark's gold (ink.css), for its edge and its mark; its words stay the page's
/// ink.
final Decoration _ribbon = Decoration.line(className: 'cm-bookmarked app-gold', attributes: const <String, String>{'data-bookmark': 'The bookmark in this note'});

/// The button's own line weight (NoteScreen.tsx `strokeWidth={2.1}`), so the two are drawn with one pen.
const double _stroke = 2.1;

/// The gold of the element that wears `app-gold` (ink.css).
Color _gold(Tokens t) => t.child(classes: const <String>{'app-gold'}).color('app-gold');

class RibbonWidget extends EditorWidget {
  const RibbonWidget();

  @override
  bool eq(RibbonWidget other) => true;

  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final em = EditorRunScope.maybeOf(context)?.look.fontSize ?? t.len('app-body');
    final gold = _gold(t);
    // '.cm-bookmarkMark': { display: 'inline-block', marginInlineStart: '0.35em', verticalAlign: '-0.15em',
    //   lineHeight: '0', color: 'var(--app-gold, currentColor)' }, '.cm-bookmarkMark svg': 1em square
    return Semantics(
      label: 'Bookmark',
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: 0.35 * em),
        child: _RibbonBox(
          em: em,
          gold: gold,
          child: AppIcon(Lucide.bookmark, size: em, strokeWidth: _stroke, color: gold),
        ),
      ),
    );
  }
}

/// The ribbon's box: the icon an em square, 0.15em under the baseline; and the line down its line's leading edge.
class _RibbonBox extends SingleChildRenderObjectWidget {
  const _RibbonBox({required this.em, required this.gold, required Widget super.child});

  final double em;
  final Color gold;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRibbon(em, gold);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderRibbon)
      ..em = em
      ..gold = gold;
  }
}

class _RenderRibbon extends RenderProxyBox {
  _RenderRibbon(this.em, this.gold);

  double em;
  Color gold;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => size.height - 0.15 * em;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _paintEdge(context, offset, this, gold);
  }
}

/// The line down a bookmarked line's leading edge, drawn from a box that stands in that line ([from], painted at
/// [offset]): '.cm-bookmarked::before': { position: 'absolute', insetInlineStart: '0.4em', insetBlock: '0.1em',
/// inlineSize: '3px', borderRadius: '2px', background: 'var(--app-gold, currentColor)' }
void _paintEdge(PaintingContext context, Offset offset, RenderBox from, Color gold) {
  RenderObject? line = from.parent;
  while (line != null && line is! RenderEditorLine) {
    line = line.parent;
  }
  if (line is! RenderEditorLine || !line.hasSize) return;
  final origin = offset - from.localToGlobal(Offset.zero, ancestor: line);
  final lineEm = line.spec.look.base.fontSize;
  final bar = Rect.fromLTRB(origin.dx + 0.4 * lineEm, origin.dy + 0.1 * lineEm, origin.dx + 0.4 * lineEm + 3, origin.dy + line.size.height - 0.1 * lineEm);
  context.canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(2)), Paint()..color = gold);
}

/// The line down the edge by itself, for a bookmarked line with no ribbon in it to draw it: while the caret is at
/// the signs, which are then words to edit, and for a bookmark kept on the device, which has no signs. On the page
/// the line is the line's own (`.cm-bookmarked::before`), whatever stands in it. A box of no size at the line's end,
/// which takes no caret and no press.
class BookmarkEdgeWidget extends EditorWidget {
  const BookmarkEdgeWidget();

  @override
  bool eq(BookmarkEdgeWidget other) => true;

  @override
  bool takesPointer(_) => false;

  @override
  bool get isHidden => true;

  @override
  Widget build(BuildContext context) => _EdgeBox(key: const ValueKey<String>('cm-bookmarkEdge'), gold: _gold(context.tokens));
}

class _EdgeBox extends LeafRenderObjectWidget {
  const _EdgeBox({super.key, required this.gold});

  final Color gold;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderEdge(gold);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) => (renderObject as _RenderEdge).gold = gold;
}

class _RenderEdge extends RenderBox {
  _RenderEdge(this._gold);

  Color _gold;
  set gold(Color value) {
    if (value == _gold) return;
    _gold = value;
    markNeedsPaint();
  }

  @override
  void performLayout() => size = constraints.smallest;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  // On the baseline, as the line's own spacer is: it changes nothing of the line it stands in.
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => 0;

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) => _paintEdge(context, offset, this, _gold);
}

final Decoration _hidden = Decoration.replace(widget: const RibbonWidget());
final Decoration _edge = Decoration.widget(widget: const BookmarkEdgeWidget(), side: 1);

class _Marks {
  const _Marks(this.kept, this.decorations);

  /// The device's own bookmark, for a note without one written in.
  final int? kept;
  final DecorationSet decorations;
}

DecorationSet _decorate(EditorState state, int? kept) {
  final written = bookmarkLineOf(state.doc);
  final number = written ?? (kept == null ? null : markedLine(state, kept));
  if (number == null) return Decoration.none;
  final line = state.doc.line(number);
  final ranges = <Range<Decoration>>[_ribbon.range(line.from)];
  final found = written != null ? _mark.firstMatch(line.text) : null;
  var ribboned = false;
  if (found != null) {
    final from = line.from + found.start, to = line.from + found.end;
    // The signs as text only while the caret is at them, so they can be edited; a caret elsewhere on the line
    // leaves the ribbon.
    final editing = state.selection.ranges.any((range) => range.from <= to && range.to >= to - bookmarkSigns.length);
    if (!editing) {
      ranges.add(_hidden.range(from, to));
      ribboned = true;
    }
  }
  // The line down the edge is the line's, with a ribbon in it or not: with none, it is drawn by itself.
  if (!ribboned) ranges.add(_edge.range(line.to));
  return Decoration.set(ranges, true);
}

final StateField<_Marks> _bookmarkField = StateField.define<_Marks>(
  create: (state) => _Marks(null, _decorate(state, null)),
  update: (value, tr) {
    var kept = value.kept == null ? null : tr.changes.mapPos(value.kept!);
    var touched = false;
    for (final effect in tr.effects) {
      final shown = showBookmark.cast(effect);
      if (shown != null) {
        kept = shown.value;
        touched = true;
      }
    }
    if (!touched && !tr.docChanged && tr.selection == null) return value;
    return _Marks(kept, _decorate(tr.state, kept));
  },
  provide: (field) => EditorViewLike.decorations.from<_Marks>(field, (value) => value.decorations),
);

final LookSheet _theme = LookSheet('editor/bookmarkLine.ts', <LookRule>[
  // '.cm-bookmarked': { position: 'relative', borderRadius: '0.25em',
  //   background: 'color-mix(in oklch, var(--app-gold, currentColor) 7%, transparent)' }
  LookRule(
    'cm-bookmarked',
    null,
    classes: 2,
    box: (p, e) {
      final gold = _gold(e.t);
      final wash = e.t.colorOf('color-mix(in oklch, currentColor 7%, transparent)', current: gold);
      final corner = Radius.circular(p.em(0.25));
      p
        ..background = ((current) => wash)
        ..topStart = corner
        ..topEnd = corner
        ..bottomStart = corner
        ..bottomEnd = corner;
    },
  ),
]);

/// How much of the bookmarked line is said back, so the words fit a toast.
const int _say = 32;

/// Lines looked at from the bookmark before giving up on finding words: a place can land on a blank line.
const int _look = 5;

final RegExp _lineLead = RegExp(r'^\s*(?:#{1,6}\s+|>\s+)');
final RegExp _inlineMarks = RegExp(r'[*_`~]');

/// The words on a line, without the marks that make them a heading, a quote, a list item or a to-do, the
/// bookmark, or the anchor naming an item.
String _wordsOn(EditorState state, int number) {
  final line = withoutBookmark(state.doc.line(number).text);
  final lead = listLead(line);
  final words = lead != null ? line.substring(lead.wordsAt) : line.replaceFirst(_lineLead, '');
  return jsTrim(withoutAnchor(words).replaceAll(_inlineMarks, ''));
}

/// Which line a place stands for: the one it is on, or the next with words on it. A place is often the blank
/// line between two paragraphs, and a bookmark on a blank line marks nothing a person can see. A list item with
/// no words yet is passed over the same way, whatever its box.
int markedLine(EditorState state, int pos) {
  final first = state.doc.lineAt(pos < 0 ? 0 : (pos > state.doc.length ? state.doc.length : pos)).number;
  final until = first + _look < state.doc.lines + 1 ? first + _look : state.doc.lines + 1;
  for (var number = first; number < until; number += 1) {
    if (_wordsOn(state, number).isNotEmpty) return number;
  }
  return first;
}

/// The words the bookmark sits on, said the way they read. Null where there is nothing to say, so the message
/// can leave the place out rather than quote an empty line.
String? markedWords(EditorState state, int pos) {
  final words = _wordsOn(state, markedLine(state, pos));
  if (words.isEmpty) return null;
  if (words.length <= _say) return words;
  // Cut at a space rather than through a word, so the quote reads as words and not as a broken one.
  final cut = words.substring(0, _say);
  final space = cut.lastIndexOf(' ');
  return '${(space > _say / 2 ? cut.substring(0, space) : cut).trimRight()}…';
}

final Extension _bookmarkRibbon = Extension.list(<Extension>[_bookmarkField, baseTheme(_theme)]);

/// The bookmarked line, shown as one.
Extension bookmarkRibbon() => _bookmarkRibbon;
