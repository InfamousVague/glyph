/// A note as a card: its title, what it is about when the phone has written that, the note itself drawn small, and
/// when it was last touched. A notebook's card is its name, how many pages it has and the first few of them; a
/// journal's, how many entries and the newest few by when each was written. A port of `src/app/notes/NoteCard.tsx`
/// and NoteCard.module.css, with [NoteCards] for the grid it sits in (HomeScreen.module.css `.cards`).
///
/// A note with a tape wears the tape's counter in its foot, "12:40 · Yesterday", in figures and with no icon.
///
/// What differs:
/// - It lives in `lib/home/` beside the page that draws it; the web's is `notes/`, shared with the All notes grid,
///   which is why `dense` is carried though the home page never asks for it.
/// - The preview is [NotePeek], drawn by hand until the editor is ported (see there).
/// - The AI's word in the card's corner (a ring while it writes the note's line, a dot while its changes are still
///   marked) is read by the corner itself, which hears the gists' runner where the page's card is drawn again with
///   its list ([_AiCorner]); a picture hands [working] and [marked] in.
/// - Where a note was written (`core/geotag.ts`, the foot's third fragment) is not read yet.
/// - A mouse's right-click is [onMenu], told where the pointer was (`notes/noteMenu.ts` `onNoteContextMenu`), where
///   the caller has one. A long press asks for nothing, as on the page.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../ai/marks.dart' show hasMarks;
import '../core/book.dart';
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/note_text.dart';
import '../format/gist.dart' show gistWorking;
import '../notes/note_menu.dart' show NoteMenuArea;
import '../notes/swipe_row.dart';
import '../notes/when.dart';
import '../perf/frame_log.dart';
import '../tapes/tape.dart';
import 'home_icons.dart';
import 'home_parts.dart';
import 'home_text.dart';
import 'marks.dart';
import 'note_peek.dart';

/// What a card or a row swipes with: its actions each way, and what a swipe past a detent does.
typedef NoteSwipes = ({List<SwipeAction> start, List<SwipeAction> end, ValueChanged<String> onAction});

/// A note as a card (`src/app/notes/NoteCard.tsx`, NoteCard.module.css). The preview is [NotePeek], drawn by hand
/// until the editor is ported; the AI's corner mark is the card's own to read, unless handed in ([working],
/// [marked]); where a note was written is not read yet; a mouse's right-click is [onMenu].
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.index,
    required this.onOpen,
    this.now,
    this.gist,
    this.place,
    this.notebook,
    this.entries,
    this.dense = false,
    this.fill = false,
    this.swipe,
    this.working,
    this.marked,
    this.onMenu,
    this.since = Duration.zero,
    this.gistSince = Duration.zero,
  });

  final Note note;

  /// How long the card has been on its page (home_parts.dart `Arrivals`), for its entrance: nothing, for a card
  /// made as it arrives. And how long its line of what it is about has, which may come after the card.
  final Duration since;
  final Duration gistSince;

  /// Its place in the run of cards, for the beat it arrives on: the ninth and after arrive together.
  final int index;
  final ValueChanged<String> onOpen;

  /// The moment "20 min ago" is counted from; this one where it is left out.
  final int? now;

  /// What the note is about in a line (`format/gist.ts`), when there is one.
  final String? gist;

  /// The book this note is a page of, when it is one.
  final BookPlace? place;

  /// The body of the notebook it is a page of, whose workflow a ticket's status is placed in; absent, [place]'s.
  final String? notebook;

  /// A journal's entries, newest first, when the note is a journal.
  final JournalCard? entries;

  /// A step smaller, with the pin and the archive said on the card itself.
  final bool dense;

  /// The card is stretched to the height of its row of cards, so the dates of a row line up along their feet.
  final bool fill;
  final NoteSwipes? swipe;

  /// The AI is writing this note's line, and changes from the AI are still marked in this note: the card's corner
  /// says one or the other. Left out, the card hears the gists' runner and reads the marks itself, as the page's
  /// card does (`activeGist() === note.id`, `hasMarks(note.id)`); a picture hands them in.
  final bool? working;
  final bool? marked;
  final void Function(String id, Offset at)? onMenu;

  @override
  Widget build(BuildContext context) {
    if (ghostPerf) Perf.count('home.card');
    final t = context.tokens;
    // The note's words are read once and kept (lib/core/note_facts.dart): nothing of its body is read here.
    final facts = NoteFacts.of(note);
    final title = facts.title;
    final book = facts.isBook;
    final journal = book && facts.isJournal;
    // A journal's newest entries, by when each was written and with no number; else a notebook's first pages.
    final listed = journal ? [for (final entry in entries?.newest ?? const <({String title, String when})>[]) (title: entry.when, depth: 0)] : (book ? [for (final c in facts.chapters) (title: c.title, depth: c.depth)] : const <({String title, int depth})>[]);
    final count = journal ? (entries?.count ?? listed.length) : listed.length;
    final part = journal ? const ['entry', 'entries'] : const ['page', 'pages'];
    final radius = dense ? t.radius('md') : t.radius('lg');
    final pad = dense ? t.space(3) : t.space(4);
    final gap = dense ? t.space(1) : t.space(2);
    final md = t.fontSize('md'), sm = t.fontSize('sm'), xs = t.fontSize('xs');
    final muted = t.color('glacier-text-muted'), subtle = t.color('glacier-text-subtle');
    final place = this.place;
    // A ticket's key and status, placed in the workflow of [notebook], or of the notebook the note is a page of.
    final ticket = book ? null : listedTicket(facts, notebook: notebook, workflow: notebook == null && place != null ? NoteFacts.of(place.book).statuses : null);
    final peek = book ? '' : facts.peek;

    Widget card = GlacierPressable(
      onPressed: () => onOpen(note.id),
      haptic: HapticKind.light,
      semanticLabel: _said(title, book: book, journal: journal),
      excludeSemantics: false,
      builder: (context, state) {
        final children = <Widget>[
          Padding(
            // `.item[data-dense] .title`: room for the ring or the dot in the corner.
            padding: EdgeInsetsDirectional.only(end: dense ? t.space(4) : 0),
            child: CssLines(
              lineHeight: 1.25 * md,
              child: Text(
                title.isNotEmpty ? facts.shownTitle : (journal ? 'Untitled journal' : (book ? 'Untitled notebook' : 'Untitled')),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                // `.card:active .title { color: var(--glacier-text-muted) }`.
                style: pageText(t, md, weight: 'semibold', height: 1.25, color: title.isEmpty ? subtle : (state.pressed ? muted : t.color('glacier-text'))),
              ),
            ),
          ),
        ];
        if (book) {
          children.add(Text(count == 0 ? 'No ${part[1]} yet' : (count == 1 ? '1 ${part[0]}' : '$count ${part[1]}'), style: pageText(t, sm, color: muted)));
          if (listed.isNotEmpty) {
            final shown = dense ? 3 : 4;
            final pages = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var n = 0; n < math.min(listed.length, shown); n += 1)
                  Padding(
                    padding: EdgeInsetsDirectional.only(top: n == 0 ? 0 : 2, start: listed[n].depth == 1 ? 1.2 * sm : 0),
                    child: Row(
                      children: [
                        if (!journal) ...[
                          ConstrainedBox(
                            constraints: BoxConstraints(minWidth: 1.2 * sm),
                            child: Text('${n + 1}', textAlign: TextAlign.end, style: tabular(pageText(t, sm, color: subtle))),
                          ),
                          SizedBox(width: 0.5 * sm),
                        ],
                        // Cut at the card's edge with no ellipsis: the page's line is a flex row (`.bookPages li {
                        // display: flex; overflow: hidden }`), whose words are an item of their own that its
                        // `text-overflow` does not reach. A name half a pixel too long is whole on the page, where
                        // an ellipsis here took its last letters ("Write the welcome pa…" on the Fold).
                        Expanded(child: ClipRect(child: Text(listed[n].title, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: pageText(t, sm, color: muted)))),
                      ],
                    ),
                  ),
                if (count > 4 && !dense)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('and ${count - 4} more', style: pageText(t, sm, color: muted).copyWith(fontStyle: FontStyle.italic)),
                  ),
              ],
            );
            children.add(fill ? Expanded(child: pages) : pages);
          }
        } else {
          // A page of a book says which, and a ticket its key and status.
          if (place != null) children.add(Align(alignment: AlignmentDirectional.centerStart, child: BookPlaceMark(place: place)));
          if (TicketMark.shows(ticket)) children.add(Align(alignment: AlignmentDirectional.centerStart, child: TicketMark.of(ticket!)));
          // What the note is about, when the phone has written it; the preview under it is the note itself.
          if (gist != null && gist!.isNotEmpty) {
            children.add(_Gist(gist!, lines: dense ? 1 : 2, since: gistSince));
          }
          if (peek.isNotEmpty) {
            final drawn = NotePeek(body: note.body, markdown: peek, fill: fill, dense: dense);
            children.add(fill ? Flexible(child: drawn) : drawn);
          }
        }
        children.add(
          Padding(
            padding: EdgeInsetsDirectional.only(top: dense ? t.space(1) : 0, end: dense ? t.space(8) : 0),
            // `.when` is a line of `line-height: normal`: 35 device pixels for its 11.16px words on a phone at
            // 2.625 (13.33px), where the engine's whole pixel is 14 and every card stood 1.75 device pixels tall.
            child: ExactLines.of(
              Text.rich(
                TextSpan(
                  children: [
                    if (hasTape(note)) ...[TextSpan(text: counter(note.recordingMs ?? 0), style: tabular(pageText(t, xs, color: subtle))), const TextSpan(text: ' · ')],
                    TextSpan(text: when(note.updatedAt, now)),
                  ],
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: pageText(t, xs, color: subtle),
              ),
              normal: true,
              dpr: t.css.lineDpr,
            ),
          ),
        );

        final hairline = t.len('glacier-hairline');
        return GlacierFocusRing(
          visible: state.focused,
          radius: radius,
          child: Container(
            // `.card:hover` deepens the wash from 3% of the ink to 6%.
            decoration: BoxDecoration(
              color: t.colorOf('color-mix(in oklch, var(--app-ink) ${state.hovered ? 6 : 3}%, transparent)'),
              border: Border.all(color: t.color('glacier-border-subtle'), width: hairline),
              borderRadius: BorderRadius.circular(radius),
            ),
            padding: EdgeInsets.all(pad),
            // The card is said as one thing, its name and when; what it draws is not read out line by line.
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
                    children: [
                      for (var i = 0; i < children.length; i += 1) ...[if (i > 0) SizedBox(height: gap), children[i]],
                    ],
                  ),
                ),
                // The AI's word in the card's corner: one or the other, never both, and nothing at all otherwise.
                PositionedDirectional(
                  top: t.space(3) - pad + hairline,
                  end: t.space(3) - pad + hairline,
                  child: _AiCorner(noteId: note.id, working: working, marked: marked),
                ),
                if (dense && (note.starred || note.archivedAt != null))
                  PositionedDirectional(
                    bottom: t.space(3) - pad,
                    end: t.space(3) - pad,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (note.starred) Semantics(label: 'Pinned', image: true, child: HomeIcon(HomeGlyph.pin, size: t.lenOf('0.8rem'), color: t.color('app-ink-3'))),
                        if (note.starred && note.archivedAt != null) SizedBox(width: t.space(1)),
                        if (note.archivedAt != null) Semantics(label: 'Archived', image: true, child: HomeIcon(HomeGlyph.archive, size: t.lenOf('0.8rem'), color: t.color('app-ink-3'))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    final swipe = this.swipe;
    if (swipe != null) card = SwipeRow(start: swipe.start, end: swipe.end, onAction: swipe.onAction, radius: t.radius('lg'), child: card);
    if (onMenu != null) card = NoteMenuArea(onMenu: (at) => onMenu!(note.id, at), child: card);
    // Arriving one after another, a beat apart: `animation: arrive 360ms ... both; animation-delay: calc(var(--i) * 40ms)`.
    return Arrive(duration: const Duration(milliseconds: 360), delay: Duration(milliseconds: 40 * math.min(index, 8)), since: since, rise: 6, child: card);
  }

  /// The card said whole to a screen reader, as its button's words were on the page: its name, then when.
  String _said(String title, {required bool book, required bool journal}) {
    final name = title.isNotEmpty ? title : (journal ? 'Untitled journal' : (book ? 'Untitled notebook' : 'Untitled'));
    return '$name, ${when(note.updatedAt, now)}';
  }
}

/// `.gist`: what the note is about in one line, fading in under the title a moment after the card.
class _Gist extends StatelessWidget {
  const _Gist(this.words, {required this.lines, this.since = Duration.zero});
  final String words;
  final int lines;

  /// How long the line has been on its card's page: one that faded in before it was drawn does not fade in again.
  final Duration since;

  static const Duration _fade = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: t.reducedMotion || since >= _fade ? 1 : 0, end: 1),
      duration: _fade,
      curve: t.curve('glacier-ease-out'),
      builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
      child: CssLines(
        lineHeight: t.len('glacier-leading-sm') * sm,
        child: Text(words, maxLines: lines, overflow: TextOverflow.ellipsis, style: pageText(t, sm, color: t.color('app-ink-3'), height: t.len('glacier-leading-sm'))),
      ),
    );
  }
}

/// The AI's word in a card's corner (notes/NoteCard.tsx): the ring while the note's line is being written
/// (format/gist.dart), else the dot while changes of the AI's are still marked in the note (ai/marks.dart). The
/// corner hears the gists' runner itself and is drawn again only when its own note's line starts or ends: nothing
/// above the card is told.
class _AiCorner extends StatefulWidget {
  const _AiCorner({required this.noteId, this.working, this.marked});

  final String noteId;
  final bool? working;
  final bool? marked;

  @override
  State<_AiCorner> createState() => _AiCornerState();
}

class _AiCornerState extends State<_AiCorner> {
  late bool _working = gistWorking.value == widget.noteId;

  @override
  void initState() {
    super.initState();
    gistWorking.addListener(_heard);
  }

  @override
  void didUpdateWidget(_AiCorner old) {
    super.didUpdateWidget(old);
    if (old.noteId != widget.noteId) _working = gistWorking.value == widget.noteId;
  }

  @override
  void dispose() {
    gistWorking.removeListener(_heard);
    super.dispose();
  }

  void _heard() {
    final now = gistWorking.value == widget.noteId;
    if (now != _working && mounted) setState(() => _working = now);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (widget.working ?? _working) {
      return Semantics(label: "The AI is writing this note's line", child: _Turning(child: HomeIcon(HomeGlyph.loader, size: 14, strokeWidth: 2.2, color: t.color('app-ink-3'))));
    }
    if (!(widget.marked ?? hasMarks(widget.noteId))) return const SizedBox.shrink();
    return Semantics(
      label: 'Changes from the AI are marked in this note',
      image: true,
      child: Container(width: 7, height: 7, margin: const EdgeInsets.all(3), decoration: BoxDecoration(color: t.color('app-ink'), shape: BoxShape.circle)),
    );
  }
}

/// `animation: card-working 1.1s linear infinite`: a ring that turns while something is being written.
class _Turning extends StatefulWidget {
  const _Turning({required this.child});
  final Widget child;

  @override
  State<_Turning> createState() => _TurningState();
}

class _TurningState extends State<_Turning> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!context.tokens.reducedMotion) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _controller, child: widget.child);
}

/// The notes as cards (HomeScreen.module.css `.cards`): one to a row on a phone held upright, where a card must be big
/// enough to read, under the app's 600px line; wider, as many as fit a card 12rem across. The cards of a row are one
/// height, so their dates line up along their feet.
///
/// [windowWidth] is the window's, as the page's media query asks it; the columns are counted from the room this is
/// given. [itemBuilder] builds the card at an index, and is told whether its card is stretched to a row.
///
/// Every card is built, whether it is near the screen or not: for a few. A page of many is [SliverNoteCards].
class NoteCards extends StatelessWidget {
  const NoteCards({super.key, required this.count, required this.itemBuilder, this.windowWidth});

  final int count;
  final Widget Function(BuildContext context, int index, bool fill) itemBuilder;
  final double? windowWidth;

  /// How many cards go across a grid [width] wide in a window [window] wide.
  static int columnsFor(double width, double window, {required double gap, required double least}) {
    if (window < 600) return 1;
    // `repeat(auto-fill, minmax(min(100%, 12rem), 1fr))`.
    final track = math.min(width, least);
    if (track <= 0) return 1;
    return math.max(1, ((width + gap) / (track + gap)).floor());
  }

  /// One row of the grid: the card alone where there is one to a row, else [columns] cells of one height
  /// ([CardRow]), the last row's empty cells left empty. Each card is its own layer, so one that changes (its
  /// entrance, a pointer over it) is painted again alone.
  static Widget rowOf(BuildContext context, int row, {required int count, required int columns, required double gap, required Widget Function(BuildContext context, int index, bool fill) itemBuilder}) {
    if (columns == 1) return itemBuilder(context, row, false);
    return CardRow(
      columns: columns,
      gap: gap,
      children: [
        for (var index = row * columns; index < count && index < (row + 1) * columns; index += 1) RepaintBoundary(child: itemBuilder(context, index, true)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(3);
    // The window's width alone: its height is another at every frame of a keyboard's rise (the page under it is
    // told the window ends at the keyboard), and the cards were made again at each of them.
    final window = windowWidth ?? MediaQuery.widthOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final columns = columnsFor(box.maxWidth, window, gap: gap, least: t.lenOf('12rem'));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row * columns < count; row += 1) ...[
              if (row > 0) SizedBox(height: gap),
              rowOf(context, row, count: count, columns: columns, gap: gap, itemBuilder: itemBuilder),
            ],
          ],
        );
      },
    );
  }
}

/// [NoteCards] as a sliver of a page that scrolls: the same grid, with only the rows near the screen built. [width]
/// is the room the grid is given, which whoever lays the page out knows; it is not asked of the sliver, whose own
/// measure changes at every scroll.
///
/// [idOf] names the card at an index. One to a row, a card whose place moves keeps what it holds, as a keyed child
/// of the column the grid was did; across a row it is made again in its new place, as it was there too (a card
/// was its cell's child, and a cell is known by where it stands).
class SliverNoteCards extends StatelessWidget {
  const SliverNoteCards({super.key, required this.count, required this.itemBuilder, required this.width, this.windowWidth, this.idOf});

  final int count;
  final Widget Function(BuildContext context, int index, bool fill) itemBuilder;
  final double width;
  final double? windowWidth;
  final String Function(int index)? idOf;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(3);
    // The window's width alone: its height is another at every frame of a keyboard's rise (the page under it is
    // told the window ends at the keyboard), and the cards were made again at each of them.
    final window = windowWidth ?? MediaQuery.widthOf(context);
    final columns = NoteCards.columnsFor(width, window, gap: gap, least: t.lenOf('12rem'));
    final idOf = columns == 1 ? this.idOf : null;
    final places = idOf == null ? null : <String, int>{for (var index = 0; index < count; index += 1) idOf(index): index};
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, row) {
          final cards = NoteCards.rowOf(context, row, count: count, columns: columns, gap: gap, itemBuilder: itemBuilder);
          final spaced = row == 0 ? cards : Padding(padding: EdgeInsets.only(top: gap), child: cards);
          return idOf == null ? spaced : KeyedSubtree(key: _CardSlot(idOf(row)), child: spaced);
        },
        childCount: (count + columns - 1) ~/ columns,
        findChildIndexCallback: places == null ? null : (key) => key is _CardSlot ? places[key.value] : null,
        addAutomaticKeepAlives: false,
        // The cards are said as they were: no place in a list is added to what a screen reader hears.
        addSemanticIndexes: false,
      ),
    );
  }
}

/// The name a card is kept by where the grid is one card to a row: a key of its own kind, so the card's own key
/// (`card-<id>`) still finds one widget.
class _CardSlot extends ValueKey<String> {
  const _CardSlot(super.value);
}

/// A row of the grid of cards: [columns] cells of one width with [gap] between them, each as tall as the tallest
/// card's own height, the row's empty cells at its end left empty. What the page's grid does with a row
/// (`grid-template-columns: repeat(n, 1fr)`, its items stretched), and what a `Row` of `Expanded` cards inside an
/// `IntrinsicHeight` did here, in one box: each card is asked its own height once and laid out once.
class CardRow extends MultiChildRenderObjectWidget {
  const CardRow({super.key, required this.columns, required this.gap, super.children});

  final int columns;
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderCardRow(columns, gap);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderCardRow)
      ..columns = columns
      ..gap = gap;
  }
}

class _CardRowData extends ContainerBoxParentData<RenderBox> {}

class _RenderCardRow extends RenderBox with ContainerRenderObjectMixin<RenderBox, _CardRowData>, RenderBoxContainerDefaultsMixin<RenderBox, _CardRowData> {
  _RenderCardRow(this._columns, this._gap);

  int _columns;
  set columns(int value) {
    if (value == _columns) return;
    _columns = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CardRowData) child.parentData = _CardRowData();
  }

  /// A cell's width in a row [width] wide: what is left of it after the gaps, shared equally.
  double _cell(double width) {
    final free = width - _gap * (_columns - 1);
    return free > 0 ? free / _columns : 0;
  }

  double _tallest(double width) {
    final cell = _cell(width);
    var tallest = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final height = child.getMaxIntrinsicHeight(cell);
      if (height > tallest) tallest = height;
    }
    return tallest;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _tallest(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _tallest(width);

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(Size(constraints.maxWidth, _tallest(constraints.maxWidth)));

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final cell = _cell(width);
    final height = constraints.hasTightHeight ? constraints.maxHeight : constraints.constrainHeight(_tallest(width));
    final each = BoxConstraints.tightFor(width: cell, height: height);
    var x = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(each);
      (child.parentData! as _CardRowData).offset = Offset(x, 0);
      x += cell;
      x += _gap;
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
