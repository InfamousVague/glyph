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
///   marked) waits for the AI's port: [working] and [marked] are its two states, handed in.
/// - Where a note was written (`core/geotag.ts`, the foot's third fragment) is not read yet.
/// - A long press stands in for the web's context menu (`notes/noteMenu.ts`): [onMenu], where the caller has one.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/book.dart';
import '../core/note.dart';
import '../core/note_text.dart';
import '../notes/swipe_row.dart';
import '../notes/when.dart';
import '../tapes/tape.dart';
import 'home_icons.dart';
import 'home_parts.dart';
import 'home_text.dart';
import 'marks.dart';
import 'note_peek.dart';

/// What a card or a row swipes with: its actions each way, and what a swipe past a detent does.
typedef NoteSwipes = ({List<SwipeAction> start, List<SwipeAction> end, ValueChanged<String> onAction});

/// A note as a card (`src/app/notes/NoteCard.tsx`, NoteCard.module.css). The preview is [NotePeek], drawn by hand
/// until the editor is ported; the AI's corner mark is handed in ([working], [marked]); where a note was written is
/// not read yet; a long press is [onMenu].
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
    this.working = false,
    this.marked = false,
    this.onMenu,
  });

  final Note note;

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

  /// The AI is writing this note's line.
  final bool working;

  /// Changes from the AI are still marked in this note.
  final bool marked;
  final ValueChanged<String>? onMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final title = noteTitle(note.body);
    final book = isBookBody(note.body);
    final journal = book && isJournalBody(note.body);
    // A journal's newest entries, by when each was written and with no number; else a notebook's first pages.
    final listed = journal ? [for (final entry in entries?.newest ?? const <({String title, String when})>[]) (title: entry.when, depth: 0)] : (book ? [for (final c in chaptersOf(note.body)) (title: c.title, depth: c.depth)] : const <({String title, int depth})>[]);
    final count = journal ? (entries?.count ?? listed.length) : listed.length;
    final part = journal ? const ['entry', 'entries'] : const ['page', 'pages'];
    final radius = dense ? t.radius('md') : t.radius('lg');
    final pad = dense ? t.space(3) : t.space(4);
    final gap = dense ? t.space(1) : t.space(2);
    final md = t.fontSize('md'), sm = t.fontSize('sm'), xs = t.fontSize('xs');
    final muted = t.color('glacier-text-muted'), subtle = t.color('glacier-text-subtle');
    final place = this.place;

    Widget card = GlacierPressable(
      onPressed: () => onOpen(note.id),
      onLongPress: onMenu == null ? null : () => onMenu!(note.id),
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
                title.isNotEmpty ? shortenUrls(title) : (journal ? 'Untitled journal' : (book ? 'Untitled notebook' : 'Untitled')),
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
                        Expanded(child: Text(listed[n].title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, sm, color: muted))),
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
          final workflow = notebook ?? place?.book.body;
          if (TicketMark.has(note.body, notebook: workflow)) children.add(Align(alignment: AlignmentDirectional.centerStart, child: TicketMark(body: note.body, notebook: workflow)));
          // What the note is about, when the phone has written it; the preview under it is the note itself.
          if (gist != null && gist!.isNotEmpty) {
            children.add(_Gist(gist!, lines: dense ? 1 : 2));
          }
          if (NotePeek.has(note.body)) {
            final peek = NotePeek(body: note.body, fill: fill);
            children.add(fill ? Flexible(child: peek) : peek);
          }
        }
        children.add(
          Padding(
            padding: EdgeInsetsDirectional.only(top: dense ? t.space(1) : 0, end: dense ? t.space(8) : 0),
            child: Text.rich(
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
                if (working || marked)
                  PositionedDirectional(
                    top: t.space(3) - pad + hairline,
                    end: t.space(3) - pad + hairline,
                    child: working
                        ? Semantics(label: "The AI is writing this note's line", child: _Turning(child: HomeIcon(HomeGlyph.loader, size: 14, color: t.color('app-ink-3'))))
                        : Semantics(
                            label: 'Changes from the AI are marked in this note',
                            image: true,
                            child: Container(width: 7, height: 7, margin: const EdgeInsets.all(3), decoration: BoxDecoration(color: t.color('app-ink'), shape: BoxShape.circle)),
                          ),
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
    // Arriving one after another, a beat apart: `animation: arrive 360ms ... both; animation-delay: calc(var(--i) * 40ms)`.
    return Arrive(duration: const Duration(milliseconds: 360), delay: Duration(milliseconds: 40 * math.min(index, 8)), rise: 6, child: card);
  }

  /// The card said whole to a screen reader, as its button's words were on the page: its name, then when.
  String _said(String title, {required bool book, required bool journal}) {
    final name = title.isNotEmpty ? title : (journal ? 'Untitled journal' : (book ? 'Untitled notebook' : 'Untitled'));
    return '$name, ${when(note.updatedAt, now)}';
  }
}

/// `.gist`: what the note is about in one line, fading in under the title a moment after the card.
class _Gist extends StatelessWidget {
  const _Gist(this.words, {required this.lines});
  final String words;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: t.reducedMotion ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: t.curve('glacier-ease-out'),
      builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
      child: CssLines(
        lineHeight: t.len('glacier-leading-sm') * sm,
        child: Text(words, maxLines: lines, overflow: TextOverflow.ellipsis, style: pageText(t, sm, color: t.color('app-ink-3'), height: t.len('glacier-leading-sm'))),
      ),
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

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(3);
    final window = windowWidth ?? MediaQuery.sizeOf(context).width;
    return LayoutBuilder(
      builder: (context, box) {
        final columns = columnsFor(box.maxWidth, window, gap: gap, least: t.lenOf('12rem'));
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < count; i += 1) ...[if (i > 0) SizedBox(height: gap), itemBuilder(context, i, false)],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row * columns < count; row += 1) ...[
              if (row > 0) SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column += 1) ...[
                      if (column > 0) SizedBox(width: gap),
                      Expanded(child: row * columns + column < count ? itemBuilder(context, row * columns + column, true) : const SizedBox.shrink()),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
