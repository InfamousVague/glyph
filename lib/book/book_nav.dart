/// A chapter's way round the book it is in: the bar under the note's header, and the foot under its last line. A
/// port of `src/app/book/BookNav.tsx` and `BookNav.module.css`. Both read the chapters either side from one
/// [_sides], so the two can never disagree (tauri/docs/DESIGN.md §87), and both open a neighbour through `open`,
/// which the note screen points at the book's one tab (§77).
///
///     BookBar     the book, the note's place in it and the chapters either side, one row under the header
///     BookFoot    the chapters either side as two wide buttons under the last line
///     bookOf      the book a title is a page of (book/book.ts `bookOf`), which the screen asks for a note's place
///
/// What differs:
/// - `bookOf` is here, with the bar it finds a place for: lib/core/book.dart kept the index's readers the lists
///   draw from ([bookIndex], [placeOf]) and left this one to the notebook's own screen.
/// - The bar's three columns (`minmax(0, 1fr) auto minmax(0, 1fr)`) are laid out by hand ([_BarLayout]): the middle
///   as wide as its words, the sides sharing what is left, a side's title cut short with an ellipsis.
/// - `:hover` washes a button at once, where the page has no transition either; `cursor: pointer` is the
///   pressable's.
/// - The foot's `1rem` is 16 px: this port has no root font size (README, "Kit gaps").
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/book.dart';
import '../core/item_syntax.dart' show jsTrim;
import '../core/note.dart';
import '../core/note_text.dart' show noteTitle, sameTitle;
import '../editor/queries/query_layout.dart' show CssItem, CssRow;
import '../sheet/css.dart';
import 'journal_months.dart' show sideName;

/// The book a note is a chapter of, by its title, or null: the first book in the library whose index names it. A
/// book is not a chapter of itself (`bookOf`).
BookPlace? bookOf(Iterable<Note> notes, String title) {
  final clean = jsTrim(title);
  if (clean.isEmpty) return null;
  for (final note in notes) {
    if (!isBookBody(note.body)) continue;
    final bookTitle = noteTitle(note.body);
    if (sameTitle(bookTitle, clean)) continue;
    final chapters = chaptersOf(note.body);
    final at = chapters.indexWhere((c) => sameTitle(c.title, clean));
    if (at >= 0) return BookPlace(book: note, title: bookTitle, chapters: chapters, at: at, journal: isJournalBody(note.body));
  }
  return null;
}

/// What a book's parts are called on the bar and the foot: pages, or a journal's entries (docs/DESIGN.md §142).
({String kind, String part}) _wordsFor(BookPlace place) => place.journal ? (kind: 'journal', part: 'entry') : (kind: 'notebook', part: 'page');

/// The chapters either side of this one: null at either end.
({String? prev, String? next}) _sides(BookPlace place) => (
      prev: place.at > 0 ? place.chapters[place.at - 1].title : null,
      next: place.at < place.chapters.length - 1 ? place.chapters[place.at + 1].title : null,
    );

/// `color-mix(in srgb, var(--glacier-text) 6%, transparent)`.
Color _wash(Tokens t, [double part = 0.06]) {
  final ink = t.color('glacier-text');
  return ink.withValues(alpha: part * ink.a);
}

/// The bar a chapter wears under its header (`BookBar`): the book it is in, its place in it, and the chapters either
/// side. A tap on the book opens the index; the ends open the neighbours. A journal's sides say an entry's time, or
/// its day when it was written on another (lib/book/journal_months.dart [sideName]): its name is a date and a
/// minute, and at a phone's width only the date's first letters, the same on every entry, had room.
class BookBar extends StatelessWidget {
  const BookBar({super.key, required this.place, required this.open});

  final BookPlace place;
  final ValueChanged<String> open;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (:prev, :next) = _sides(place);
    final (:kind, :part) = _wordsFor(place);
    final here = place.at >= 0 && place.at < place.chapters.length ? place.chapters[place.at].title : '';
    String said(String? title) => title == null ? '' : (place.journal ? sideName(title, here) : title);
    // `font-size: var(--glacier-font-size-sm)`, and every em below is of it.
    final em = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    final ink = t.color('glacier-text');
    final line = snapBorder(context, 1);
    // A button's own height: its words' line or its 16 px mark, in `padding: 0.35em 0.5em`.
    final height = math.max(16.0, normalLine(t, em) * em) + 0.7 * em;

    Widget button({required Key key, required String label, required VoidCallback? onPressed, required List<Widget> Function(Color color) children, bool end = false}) {
      return GlacierPressable(
        key: key,
        semanticLabel: label,
        excludeSemantics: true,
        onPressed: onPressed,
        builder: (context, state) {
          final color = state.hovered && !state.disabled ? ink : muted;
          // `.end:disabled { opacity: 0; pointer-events: none }`
          return Opacity(
            opacity: state.disabled ? 0 : 1,
            child: GlacierFocusRing(
              visible: state.focused,
              radius: t.radius('full'),
              child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: state.hovered && !state.disabled ? _wash(t) : null),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 0.35 * em, horizontal: 0.5 * em),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
                    // `gap: 0.35em`
                    spacing: 0.35 * em,
                    children: children(color),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    // A side's arrow and its title, as two items of the page's flex row that both shrink: the title has
    // `min-inline-size: 0` through its `overflow: hidden`, and an svg is an item like any other, so where the two
    // do not fit each gives up room in proportion to its own width and the arrow is drawn smaller in what it is
    // left (measured on a phone: 16px arrows 11.4 and 9.5px wide beside "Plan the first release" and "Write the
    // welcome page"). Held at 16px, the arrow took three letters from each title.
    Widget side(String text, Color color, Widget arrow, {required bool arrowFirst}) => Flexible(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const mark = 16.0;
              final gap = 0.35 * em;
              final style = pageText(t, em, color: color);
              final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: Directionality.of(context), maxLines: 1)..layout();
              final natural = painter.width;
              painter.dispose();
              final room = constraints.maxWidth - gap;
              final by = constraints.maxWidth.isFinite && mark + natural > room ? math.max(0.0, room) / (mark + natural) : 1.0;
              final drawn = SizedBox(width: mark * by, height: mark, child: FittedBox(child: arrow));
              final title = SizedBox(
                width: by < 1 ? natural * by : null,
                // `.endTitle { overflow: hidden; text-overflow: ellipsis; white-space: nowrap }`
                child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style),
              );
              return Row(mainAxisSize: MainAxisSize.min, spacing: gap, children: arrowFirst ? [drawn, title] : [title, drawn]);
            },
          ),
        );

    return Semantics(
      container: true,
      label: place.journal ? 'Journal' : 'Notebook',
      child: DecoratedBox(
        // `border-block-end: 1px solid var(--glacier-border-subtle)`
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('glacier-border-subtle'), width: line))),
        child: Padding(
          // `padding: var(--glacier-space-1) var(--glacier-space-4)`, the line under it inside the box.
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(1), t.space(4), t.space(1) + line),
          child: _BarLayout(
            gap: t.space(2),
            height: height,
            children: [
              button(
                key: const ValueKey('book-bar-prev'),
                label: prev != null ? 'Previous $part: $prev' : 'First $part',
                onPressed: prev == null ? null : () => open(prev),
                children: (color) => [side(said(prev), color, lucide(Lucide.chevronLeft, size: 16, color: color), arrowFirst: true)],
              ),
              button(
                key: const ValueKey('book-bar-book'),
                label: 'Open the $kind ${place.title}',
                onPressed: () => open(place.title),
                children: (color) {
                  // The mark, the book's name and the count are three items of the page's flex row, and all three
                  // give way where the bar is too narrow for them, each in proportion to its own width: the mark
                  // is drawn smaller in what it is left (an svg is an item like any other), the name is cut, and
                  // the count, which may wrap, goes onto lines of its own. In the Fold's narrowest pane, 164px
                  // between a docked sidebar and a docked aside, the page had a mark of 7.9, "Exam…" in 55.6 and
                  // "3 / of / 3" down 20.3; a Row kept the mark and the count whole and left the name "Ex…".
                  final counted = '${place.at + 1} of ${place.chapters.length}';
                  // The kit's own style for a line of `line-height: normal`, which `ExactLines` below makes the
                  // page's to the device pixel.
                  final count = t.textAt(em, color: color).copyWith(fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]);
                  final painter = TextPainter(text: TextSpan(text: counted, style: count), textDirection: Directionality.of(context))..layout();
                  final word = painter.minIntrinsicWidth;
                  painter.dispose();
                  return [
                    Flexible(
                      child: CssRow(
                        gap: 0.35 * em,
                        shrinkWrap: true,
                        children: [
                          CssItem(least: 0, child: SizedBox(height: 15, child: FittedBox(child: lucide(Lucide.bookOpen, size: 15, color: color)))),
                          // `.bookTitle { color: var(--glacier-text); font-weight: medium }`, cut with an ellipsis.
                          CssItem(
                            least: 0,
                            child: Text(place.title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, em, weight: 'medium', color: ink)),
                          ),
                          // `.count { font-variant-numeric: tabular-nums }`
                          // Its lines the page's own height where it wraps (16.76px at the Fold's ratio, not 16).
                          CssItem(least: word, child: ExactLines.of(Text(counted, style: count), normal: true, dpr: t.css.lineDpr)),
                        ],
                      ),
                    ),
                  ];
                },
              ),
              button(
                key: const ValueKey('book-bar-next'),
                label: next != null ? 'Next $part: $next' : 'Last $part',
                onPressed: next == null ? null : () => open(next),
                end: true,
                children: (color) => [side(said(next), color, lucide(Lucide.chevronRight, size: 16, color: color), arrowFirst: false)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `display: grid; grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr); align-items: center; gap`: three
/// children, the middle as wide as its words (and no wider than the bar), the sides sharing what is left. The first
/// fills its column (a grid item stretches), the last sits at its column's far end (`.end[data-next] { justify-self:
/// end }`) and is no wider than it (`max-inline-size: 100%`).
class _BarLayout extends MultiChildRenderObjectWidget {
  const _BarLayout({required this.gap, required this.height, required super.children});

  final double gap;
  final double height;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBarLayout(gap, height);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderBarLayout)
      ..gap = gap
      ..height = height;
  }
}

class _BarParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderBarLayout extends RenderBox with ContainerRenderObjectMixin<RenderBox, _BarParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _BarParentData> {
  _RenderBarLayout(this._gap, this._height);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double _height;
  set height(double value) {
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BarParentData) child.parentData = _BarParentData();
  }

  @override
  double computeMinIntrinsicHeight(double width) => _height;

  @override
  double computeMaxIntrinsicHeight(double width) => _height;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final first = firstChild!;
    final middle = childAfter(first)!;
    final last = childAfter(middle)!;
    final room = math.max(0.0, width - 2 * _gap);
    middle.layout(BoxConstraints(maxWidth: room), parentUsesSize: true);
    final side = math.max(0.0, (room - middle.size.width) / 2);
    first.layout(BoxConstraints.tightFor(width: side), parentUsesSize: true);
    last.layout(BoxConstraints(maxWidth: side), parentUsesSize: true);
    final tall = <double>[_height, first.size.height, middle.size.height, last.size.height].reduce(math.max);
    size = constraints.constrain(Size(width, tall));
    double mid(RenderBox child) => (tall - child.size.height) / 2;
    (first.parentData! as _BarParentData).offset = Offset(0, mid(first));
    (middle.parentData! as _BarParentData).offset = Offset(side + _gap, mid(middle));
    (last.parentData! as _BarParentData).offset = Offset(width - last.size.width, mid(last));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}

/// The foot a chapter wears (`BookFoot`; Matt: "add the book navigation for next and prev buttons at the bottom of
/// the page"): the chapters either side, as two wide buttons under the last line, so a reader who reaches the end of
/// a page goes on from there rather than scrolling back up to the bar. At the first chapter there is only Next, at
/// the last only Previous, and a book of one chapter has no foot.
class BookFoot extends StatelessWidget {
  const BookFoot({super.key, required this.place, required this.open});

  final BookPlace place;
  final ValueChanged<String> open;

  /// Whether a foot is drawn for [place] at all.
  static bool has(BookPlace place) {
    final (:prev, :next) = _sides(place);
    return prev != null || next != null;
  }

  @override
  Widget build(BuildContext context) {
    final (:prev, :next) = _sides(place);
    if (prev == null && next == null) return const SizedBox.shrink();
    final t = context.tokens;
    final gutter = t.len('app-gutter');
    final line = snapBorder(context, 1);
    // `font: inherit` from the page: 1rem.
    const em = 16.0;
    final sm = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    final ink = t.color('glacier-text');
    final rule = t.color('glacier-border-subtle');

    Widget step({required Key key, required String title, required bool forward}) {
      final across = forward ? CrossAxisAlignment.end : CrossAxisAlignment.start;
      final arrow = lucide(forward ? Lucide.chevronRight : Lucide.chevronLeft, size: 14, color: muted);
      final word = Text(forward ? 'Next' : 'Previous', maxLines: 1, softWrap: false, style: pageText(t, sm, color: muted));
      return GlacierPressable(
        key: key,
        semanticLabel: '${forward ? 'Next' : 'Previous'}: $title',
        excludeSemantics: true,
        onPressed: () => open(title),
        builder: (context, state) => GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('md'),
          child: DecoratedBox(
            // `border: 1px solid var(--glacier-border-subtle); border-radius: var(--glacier-radius-md)`
            decoration: BoxDecoration(border: Border.all(color: rule, width: line), borderRadius: BorderRadius.circular(t.radius('md')), color: state.hovered ? _wash(t) : null),
            child: Padding(
              // `padding: 0.7em 0.9em`, inside the border.
              padding: EdgeInsets.symmetric(vertical: 0.7 * em + line, horizontal: 0.9 * em + line),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: across,
                // `gap: 0.2em`
                spacing: 0.2 * em,
                children: [
                  // `.stepLabel { display: inline-flex; align-items: center; gap: 0.25em }`
                  // In a pane too narrow for the word (the note between a docked sidebar and the aside on the Fold),
                  // the word is cut where the page's ran out of its box.
                  Row(mainAxisSize: MainAxisSize.min, spacing: 0.25 * sm, children: forward ? [Flexible(child: word), arrow] : [arrow, Flexible(child: word)]),
                  // `.stepTitle { max-inline-size: 100%; text-overflow: ellipsis; font-weight: medium }`
                  Text(title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, textAlign: forward ? TextAlign.end : TextAlign.start, style: pageText(t, em, weight: 'medium', color: ink)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Previous and next ${_wordsFor(place).part}',
      child: Padding(
        // `margin: var(--glacier-space-4) var(--app-gutter) 0`
        padding: EdgeInsets.fromLTRB(gutter, t.space(4), gutter, 0),
        child: DecoratedBox(
          // `border-block-start: 1px solid var(--glacier-border-subtle)`
          decoration: BoxDecoration(border: Border(top: BorderSide(color: rule, width: line))),
          child: Padding(
            // `padding-block: var(--glacier-space-4) calc(var(--app-safe-bottom) + var(--glacier-space-6))`
            padding: EdgeInsets.only(top: t.space(4) + line, bottom: t.len('app-safe-bottom') + t.space(6)),
            // `grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: var(--glacier-space-3)`: Previous keeps the
            // left and Next the right, whichever is there.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: t.space(3),
              children: [
                Expanded(child: prev == null ? const SizedBox.shrink() : step(key: const ValueKey('book-foot-prev'), title: prev, forward: false)),
                Expanded(child: next == null ? const SizedBox.shrink() : step(key: const ValueKey('book-foot-next'), title: next, forward: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
