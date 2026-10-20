/// A note on one line of the home page, two ways: [HomeRow], for every layout that draws rows (its kind's mark, its
/// name, how it starts, and when it was touched, with the pin and its notebook's name where it has them, and a
/// ticket's key and status), and [HomeLine], for Spotlight's pinned notes (its kind's mark, its name, the notebook
/// it is in, the workspace it is filed in, and when). Ports of `HomeRow`, `HomeLine`, `KindMark` and `TapeWords` in
/// `src/app/home/HomeScreen.tsx`, with their rules in HomeLayouts.module.css (`.row`, `.line` and their parts).
///
/// A mouse's right-click asks for the note's menu (`notes/noteMenu.ts`), where the caller has one.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/search_hits.dart';
import '../core/workspaces.dart';
import '../note/byline.dart' show AuthorMarks, ThenIfRoom, authorsOf, spokenNames;
import '../notes/note_menu.dart' show NoteMenuArea;
import '../notes/swipe_row.dart';
import '../notes/when.dart';
import '../perf/frame_log.dart';
import '../tapes/tape.dart';
import 'home_icons.dart';
import 'home_layout.dart';
import 'home_parts.dart';
import 'home_text.dart';
import 'marks.dart';
import '../notes/folder_drag.dart' show NoteCarry, carriedNote, noteCarryActions;
import 'note_card.dart' show NoteSwipes;

/// A note's kind as a mark at the start of its row or line: a notebook, a canvas, a recording's cassette, or a page
/// of words (`KindMark`).
class KindMark extends StatelessWidget {
  const KindMark({super.key, required this.kind});

  final HomeKind kind;

  @override
  Widget build(BuildContext context) {
    final color = context.tokens.color('app-ink-3');
    return switch (kind) {
      // A recording's cassette, a touch larger than a page's mark: its shape is wide and low (`.rowMarkTape`).
      HomeKind.tape => HomeIcon(HomeGlyph.tape, size: 1.1 * 16, color: color),
      HomeKind.book => HomeIcon(HomeGlyph.bookOpen, size: 16, color: color),
      HomeKind.canvas => HomeIcon(HomeGlyph.canvas, size: 16, color: color),
      HomeKind.note => HomeIcon(HomeGlyph.note, size: 16, color: color),
    };
  }
}

/// `.rowLive::before`: a dot of ink that beats while the meeting is being recorded (`animation: live 1.6s
/// ease-in-out infinite`, to 35% at its middle); still under reduced motion.
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final there = t < 0.5 ? Curves.easeInOut.transform(t * 2) : 1 - Curves.easeInOut.transform((t - 0.5) * 2);
        return Opacity(opacity: 1 - 0.65 * there, child: child);
      },
      child: Container(width: widget.size, height: widget.size, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
    );
  }
}

/// What a recording says before its words (`TapeWords`): how long it is, "0:40", or, for the meeting being recorded,
/// that it is. Spans for a line of text at [em]; none for a note that is neither.
List<InlineSpan> _tapeWords(Tokens t, Note note, {required bool live, required double em, bool dot = true}) {
  if (live) {
    return [
      WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: EdgeInsetsDirectional.only(end: 0.35 * em), child: _LiveDot(size: 0.5 * em, color: t.color('app-ink')))),
      TextSpan(text: 'Recording now', style: tabular(pageText(t, em, color: t.color('app-ink')))),
      WidgetSpan(child: SizedBox(width: 0.5 * em)),
    ];
  }
  if (kindOf(note) != HomeKind.tape) return const [];
  return [
    TextSpan(text: counter(note.recordingMs ?? 0), style: tabular(pageText(t, em, color: t.color('app-ink-2')))),
    if (dot) TextSpan(text: ' ·', style: pageText(t, em, color: t.color('app-ink-3'))),
    WidgetSpan(child: SizedBox(width: 0.5 * em)),
  ];
}

/// What a row or a line's button is wrapped in: a swipe's frame, or nothing where the notes do not swipe (`Swiped`).
Widget _swiped(BuildContext context, NoteSwipes? swipe, NoteCarry? carry, {bool compact = false, required Widget child}) {
  final carried = carriedNote(carry, child, swipes: swipe != null);
  return swipe == null ? carried : SwipeRow(start: swipe.start, end: swipe.end, onAction: swipe.onAction, compact: compact, also: noteCarryActions(context, carry), child: carried);
}

/// `.rowItem`: arriving a beat after the one before, `animation: arrive 300ms ... both; animation-delay: calc(var(--i)
/// * 25ms)`, the thirteenth and after together.
Widget _arriving(int index, Duration since, Widget child) =>
    Arrive(duration: const Duration(milliseconds: 300), delay: Duration(milliseconds: 25 * math.min(index, 12)), since: since, rise: 4, child: child);

/// A note on one row (`HomeRow` in `src/app/home/HomeScreen.tsx`, HomeLayouts.module.css `.row`). A mouse's
/// right-click is [onMenu], where the web opened its context menu.
class HomeRow extends StatelessWidget {
  const HomeRow({
    super.key,
    required this.note,
    required this.index,
    required this.onOpen,
    this.now,
    this.bookName,
    this.notebook,
    this.workflow,
    this.entries,
    this.live = false,
    this.swipe,
    this.onMenu,
    this.since = Duration.zero,
    this.carry,
  });

  final Note note;
  final int index;
  final ValueChanged<String> onOpen;
  final int? now;

  /// How long the row has been on its page (home_parts.dart `Arrivals`), for its entrance: nothing, for a row made
  /// as it arrives.
  final Duration since;

  /// The notebook it is a page of, by name.
  final String? bookName;

  /// That notebook's body, whose workflow a ticket's status is placed in.
  final String? notebook;

  /// That notebook's workflow where it was read already (its facts' `statuses`), in place of [notebook].
  final List<String>? workflow;

  /// A journal's entries, from every workspace.
  final int? entries;

  /// The meeting being recorded now is this note.
  final bool live;
  final NoteSwipes? swipe;
  final void Function(String id, Offset at)? onMenu;

  /// The note carried onto a folder (lib/notes/folder_drag.dart): picked up inside its swipe, so a mouse's drag
  /// carries it and a finger's sideways swipe still swipes, with Move to… among the swipes' actions. None, and it is
  /// not carried.
  final NoteCarry? carry;

  static String _counted(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

  @override
  Widget build(BuildContext context) {
    if (ghostPerf) Perf.count('home.row');
    final t = context.tokens;
    // The note's words are read once and kept (lib/core/note_facts.dart): nothing of its body is read here.
    final facts = NoteFacts.of(note);
    final title = facts.title;
    final kind = live ? HomeKind.tape : kindOf(note);
    // A journal counts its entries, a notebook its pages, and a canvas its cards: its first line is JSON.
    final String lead;
    // And as the row writes it, a long address in it cut short.
    final String shownLead;
    if (entries != null) {
      shownLead = lead = _counted(entries!, 'entry', 'entries');
    } else if (kind == HomeKind.book) {
      shownLead = lead = _counted(facts.chapters.length, 'page', 'pages');
    } else if (kind == HomeKind.canvas) {
      final cards = facts.canvasCards ?? 0;
      shownLead = lead = cards > 0 ? _counted(cards, 'card', 'cards') : 'No cards yet';
    } else {
      lead = facts.firstLine;
      shownLead = facts.shownFirstLine;
    }
    final md = t.fontSize('md'), sm = t.fontSize('sm');
    final ink3 = t.color('app-ink-3');
    final marked = listedTicket(facts, notebook: notebook, workflow: workflow);
    final ticket = TicketMark.shows(marked);
    final hasLead = lead.isNotEmpty || bookName != null || kind == HomeKind.tape || ticket;
    // Who wrote it with the person, where anyone did: their marks at the row's end, beside when it was last
    // touched, in what room the name leaves.
    final authors = _authorsOf(note);
    final said = [title.isEmpty ? 'Untitled' : title, if (note.starred) 'pinned', ?bookName, if (lead.isNotEmpty) lead, if (authors.isNotEmpty) 'by ${spokenNames(authors)}', when(note.updatedAt, now)].join(', ');
    final Widget name = Text(
      title.isNotEmpty ? facts.shownTitle : 'Untitled',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: pageText(t, md, weight: 'semibold', color: title.isEmpty ? ink3 : t.color('app-ink')),
    );

    final row = GlacierPressable(
      onPressed: () => onOpen(note.id),
      semanticLabel: said,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: 0,
        child: Container(
          constraints: BoxConstraints(minHeight: t.space(12)),
          padding: EdgeInsets.symmetric(vertical: t.space(3), horizontal: t.space(1)),
          // `.row:hover`: a wash of the ink.
          color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)') : null,
          child: ExcludeSemantics(
            child: Row(
              children: [
                KindMark(kind: kind),
                SizedBox(width: t.space(3)),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                if (note.starred) ...[
                                  // The pin leans, and sits on the name's baseline as a mark in a line does.
                                  BottomBaseline(child: Transform.rotate(angle: -12 * math.pi / 180, child: HomeIcon(HomeGlyph.pin, size: 0.85 * md, color: ink3))),
                                  SizedBox(width: 0.35 * md),
                                ],
                                Flexible(child: authors.isEmpty ? name : ThenIfRoom(first: name, then: AuthorMarks(authors: authors, em: sm), gap: t.space(2), toEnd: true)),
                              ],
                            ),
                            if (hasLead) ...[
                              const SizedBox(height: 2),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    if (bookName != null) ...[
                                      TextSpan(text: '$bookName ·', style: pageText(t, sm, color: t.color('app-ink-2'))),
                                      WidgetSpan(child: SizedBox(width: 0.5 * sm)),
                                    ],
                                    if (ticket) ...[
                                      // A ticket's key and status, before how it starts (`.rowTicket`).
                                      WidgetSpan(alignment: PlaceholderAlignment.bottom, child: TicketMark.of(marked!, after: '·')),
                                      WidgetSpan(child: SizedBox(width: 0.5 * t.fontSize('xs'))),
                                    ],
                                    ..._tapeWords(t, note, live: live, em: sm),
                                    if (lead.isNotEmpty) TextSpan(text: shownLead),
                                  ],
                                ),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: pageText(t, sm, color: ink3),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(width: t.space(3)),
                      Text(when(note.updatedAt, now), softWrap: false, style: tabular(pageText(t, t.fontSize('xs'), color: ink3))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return _arriving(index, since, NoteMenuArea(onMenu: onMenu == null ? null : (at) => onMenu!(note.id, at), child: _swiped(context, swipe, carry, child: row)));
  }
}

/// A note on one short line (`HomeLine` in `src/app/home/HomeScreen.tsx`, HomeLayouts.module.css `.line`): no pin,
/// since the list is the pinned ones, and no line of how it starts. Its parts give way as the page's `flex-shrink`
/// has them ([ShrinkRow]). A mouse's right-click is [onMenu].
class HomeLine extends StatelessWidget {
  const HomeLine({
    super.key,
    required this.note,
    required this.index,
    required this.onOpen,
    this.now,
    this.bookName,
    this.notebook,
    this.workflow,
    this.live = false,
    this.swipe,
    this.space,
    this.onMenu,
    this.since = Duration.zero,
    this.found,
    this.carry,
  });

  final Note note;
  final int index;
  final ValueChanged<String> onOpen;
  final int? now;

  /// What a search matched of the note: its letters are inked in the name, and the line of the note they stand in
  /// is under it. The port's own (lib/core/search_hits.dart).
  final Found? found;

  /// How long the line has been on its page, for its entrance ([HomeRow.since]).
  final Duration since;
  final String? bookName;
  final String? notebook;

  /// The notebook's workflow where it was read already (its facts' `statuses`), in place of [notebook].
  final List<String>? workflow;
  final bool live;
  final NoteSwipes? swipe;

  /// The workspace the note is filed in, for its pill; null while the page is filtered to one.
  final Workspace? space;
  final void Function(String id, Offset at)? onMenu;

  /// The note carried onto a folder (lib/notes/folder_drag.dart): picked up inside its swipe, so a mouse's drag
  /// carries it and a finger's sideways swipe still swipes, with Move to… among the swipes' actions. None, and it is
  /// not carried.
  final NoteCarry? carry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final facts = NoteFacts.of(note);
    final title = facts.title;
    final kind = live ? HomeKind.tape : kindOf(note);
    final marked = listedTicket(facts, notebook: notebook, workflow: workflow);
    final md = t.fontSize('md'), sm = t.fontSize('sm'), xs = t.fontSize('xs');
    final ink3 = t.color('app-ink-3');
    final space = this.space;
    final tape = _tapeWords(t, note, live: live, em: md, dot: false);
    final snippet = found?.snippet;
    final authors = _authorsOf(note);
    final said = [title.isEmpty ? 'Untitled' : title, ?bookName, if (space != null) space.name, if (authors.isNotEmpty) 'by ${spokenNames(authors)}', when(note.updatedAt, now), ?snippet?.text].join(', ');
    final shown = title.isNotEmpty ? facts.shownTitle : 'Untitled';
    final wash = t.colorOf('color-mix(in oklch, var(--app-ink) 18%, transparent)');
    final nameStyle = pageText(t, md, weight: 'medium', color: title.isEmpty ? ink3 : t.color('app-ink'));

    final line = GlacierPressable(
      onPressed: () => onOpen(note.id),
      semanticLabel: said,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: 0,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(1)),
          color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)') : null,
          child: ExcludeSemantics(
            child: _under(
              t,
              snippet,
              wash,
              ShrinkRow(
              gap: t.space(3),
              // `min-block-size: var(--glacier-space-10)`, less the line's own padding.
              minHeight: math.max(0, t.space(10) - t.space(2) * 2),
              children: [
                KindMark(kind: kind),
                Shrink(
                  shrink: 1,
                  child: Text.rich(
                    TextSpan(children: markedSpans(shown, found == null || title.isEmpty ? const [] : marksIn(shown, found!.needles), wash: wash)),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle,
                  ),
                ),
                // Its notebook after the name, quieter, and the first to give way on a narrow line.
                if (bookName != null) Shrink(shrink: 100, child: Text(bookName!, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, sm, color: ink3))),
                if (TicketMark.shows(marked)) Shrink(shrink: 1, child: TicketMark.of(marked!)),
                if (tape.isNotEmpty) Text.rich(TextSpan(children: tape), softWrap: false),
                if (space != null)
                  Shrink(
                    shrink: 50,
                    // No smaller than its mark and the name's few letters: past that the title gives way.
                    minWidth: 0.55 * xs * 2 + 2 + (space.org != null ? 1.25 * xs + t.space(1) : 0) + t.lenOf('4ch', em: xs),
                    child: _LinePlace(space: space),
                  ),
                // Who wrote it, at the line's end beside when: the first thing to give way, a whole mark at a time.
                if (authors.isNotEmpty) Shrink(shrink: 1000, toEnd: true, child: AuthorMarks(authors: authors, em: sm)),
                Shrink(
                  toEnd: authors.isEmpty,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(start: t.space(2)),
                    child: Text(when(note.updatedAt, now), softWrap: false, style: tabular(pageText(t, xs, color: ink3))),
                  ),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
    return _arriving(index, since, NoteMenuArea(onMenu: onMenu == null ? null : (at) => onMenu!(note.id, at), child: _swiped(context, swipe, carry, compact: true, child: line)));
  }

  /// The line with what a search matched in the note under it: two lines at most, quieter, in from the mark, the
  /// matched letters in the page's ink on a wash of it.
  static Widget _under(Tokens t, Snippet? snippet, Color wash, Widget line) {
    if (snippet == null) return line;
    final sm = t.fontSize('sm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        line,
        Padding(
          padding: EdgeInsetsDirectional.only(start: 16 + t.space(3), bottom: t.space(1)),
          child: Text.rich(
            TextSpan(children: markedSpans(snippet.text, snippet.marks, wash: wash, ink: t.color('app-ink'), weight: t.textAt(sm, weight: 'medium').fontWeight)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: pageText(t, sm, color: t.color('app-ink-3')),
          ),
        ),
      ],
    );
  }
}

/// A note's authors (its front matter's `authors:`), read once for the words it has now.
final Expando<({String body, List<String> authors})> _authorsHad = Expando<({String body, List<String> authors})>();

List<String> _authorsOf(Note note) {
  final had = _authorsHad[note];
  if (had != null && identical(had.body, note.body)) return had.authors;
  // Asked of the front matter only where the note has one that names anyone.
  final authors = note.body.startsWith('---') && note.body.contains('authors:') ? authorsOf(note.body) : const <String>[];
  _authorsHad[note] = (body: note.body, authors: authors);
  return authors;
}

/// [text] as spans, the [marks] (ranges, in order) on a [wash], and in [ink] and [weight] where those are given.
List<InlineSpan> markedSpans(String text, List<(int, int)> marks, {required Color wash, Color? ink, FontWeight? weight}) {
  if (marks.isEmpty) return [TextSpan(text: text)];
  final spans = <InlineSpan>[];
  var at = 0;
  for (final (from, to) in marks) {
    if (from < at || to > text.length) continue;
    if (from > at) spans.add(TextSpan(text: text.substring(at, from)));
    spans.add(TextSpan(text: text.substring(from, to), style: TextStyle(backgroundColor: wash, color: ink, fontWeight: weight)));
    at = to;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// `.linePlace`: the workspace a pinned note is filed in, as a small pill in its hue, with the organization's mark
/// when it is an organization's. It gives way before the name does.
class _LinePlace extends StatelessWidget {
  const _LinePlace({required this.space});
  final Workspace space;

  @override
  Widget build(BuildContext context) {
    return GlacierScope(
      attrs: {'hue': space.hue ?? 'ink'},
      child: Builder(
        builder: (context) {
          final t = context.tokens;
          final xs = t.fontSize('xs');
          final color = t.color('app-space');
          return Container(
            padding: EdgeInsets.symmetric(vertical: 0.15 * xs, horizontal: 0.55 * xs),
            decoration: BoxDecoration(
              color: t.colorOf('color-mix(in oklch, var(--app-space) 10%, transparent)'),
              border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-space) 55%, transparent)'), width: 1),
              borderRadius: BorderRadius.circular(t.radius('full')),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (space.org != null) ...[OrgMark(em: xs, color: color), SizedBox(width: t.space(1))],
                Flexible(child: Text(space.name, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, xs, color: color, height: 1.3))),
              ],
            ),
          );
        },
      ),
    );
  }
}
