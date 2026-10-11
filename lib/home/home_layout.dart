/// The home page's rules: what it shows, in what order, and the ways it can lay them out. A port of
/// `src/app/home/homeLayout.ts` (docs/DESIGN.md §147, §148, §178), under the web's own names. Pure, so each rule is a
/// test (test/home/home_layout_test.dart, the web's cases).
///
/// The page is the notebooks and the notes, a search over them, and a filter - All, Notebooks, Notes, Pinned, and the
/// workspace - drawn one of four ways: Spotlight, Cards, Timeline and List.
///
/// What differs: [HomeLayout] is declared here (the web's is `core/preferences.ts`'s, whose port takes it from here);
/// moments are milliseconds since the epoch, as a [Note]'s are; and a sort is made stable by hand, since Dart's own is
/// not promised to be and the web's is.
library;

import 'package:flutter/foundation.dart';

import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/note_text.dart';

// How a note starts, on one line (`firstLine`): lib/core/note_text.dart's, where a note's facts read it.
export '../core/note_text.dart' show firstLine;

/// The layouts the page can be drawn in (`HomeLayout`). A layout's `name` is the id Settings keeps.
enum HomeLayout { spotlight, cards, timeline, list }

/// The layout an id from the preferences names; Spotlight, the default, for one this build does not know.
HomeLayout homeLayoutOf(String? id) => HomeLayout.values.asNameMap()[id] ?? HomeLayout.spotlight;

/// The layouts, in the order Settings offers them, each with the sentence that says what it looks like
/// (`HOME_LAYOUTS`): Spotlight, the default, then the two Matt liked, then the list.
const List<({HomeLayout id, String label, String hint})> homeLayouts = [
  (id: HomeLayout.spotlight, label: 'Spotlight', hint: 'Your pinned notes in a list, the four you touched last as cards, then everything else by when.'),
  (id: HomeLayout.cards, label: 'Cards', hint: 'Notebooks and notes as cards, each note drawn small.'),
  (id: HomeLayout.timeline, label: 'Timeline', hint: 'Everything by when you last touched it: today, yesterday, this week and earlier.'),
  (id: HomeLayout.list, label: 'List', hint: 'One line each: the name, how it starts, and when. The most on a screen.'),
];

/// The most cards a layout draws (`CARDS_AT_MOST`); the foot sends the rest to All notes.
const int cardsAtMost = 48;

/// How many cards Spotlight leads with (`SPOTLIT`).
const int spotlit = 4;

/// What the page is showing: everything, only notebooks, only notes and pages, or only what is pinned.
enum HomeFilter { all, books, notes, pinned }

/// The filters, in the panel's order, each with its word (`HOME_FILTERS`).
const List<({HomeFilter id, String label})> homeFilters = [
  (id: HomeFilter.all, label: 'All'),
  (id: HomeFilter.books, label: 'Notebooks'),
  (id: HomeFilter.notes, label: 'Notes'),
  (id: HomeFilter.pinned, label: 'Pinned'),
];

/// A note's kind as the page marks it: a notebook (a journal is one), a canvas, a voice recording (a note with its
/// tape kept), or words. A recording is a note like any other in every list and filter; its kind is only how its row
/// looks.
enum HomeKind { book, canvas, tape, note }

HomeKind kindOf(Note note) {
  // Read once for the note, and kept (lib/core/note_facts.dart): the page asks this of every note it has.
  final facts = NoteFacts.of(note);
  if (facts.isBook) return HomeKind.book;
  if (facts.isCanvas) return HomeKind.canvas;
  if (hasTape(note)) return HomeKind.tape;
  return HomeKind.note;
}

/// What the page lists: the notebooks and the notes, each newest first, pinned ones first within each.
@immutable
class HomeLists {
  const HomeLists({required this.books, required this.notes});
  final List<Note> books;
  final List<Note> notes;
}

/// A sort that keeps the order of what compares equal, as the web's `Array.prototype.sort` does.
List<Note> _sorted(Iterable<Note> notes, int Function(Note a, Note b) compare) {
  final indexed = notes.indexed.toList();
  indexed.sort((a, b) {
    final by = compare(a.$2, b.$2);
    return by != 0 ? by : a.$1.compareTo(b.$1);
  });
  return [for (final (_, note) in indexed) note];
}

int _newestFirst(Note a, Note b) => b.updatedAt.compareTo(a.updatedAt);

int _newestPinnedFirst(Note a, Note b) {
  final pinned = (b.starred ? 1 : 0) - (a.starred ? 1 : 0);
  return pinned != 0 ? pinned : b.updatedAt.compareTo(a.updatedAt);
}

/// The notes the page shows under a search and a filter, never the archive.
HomeLists homeLists(Iterable<Note> all, String query, HomeFilter filter) {
  // The query's words once, not once a note; each note is looked through as it was last read (`searchText`).
  final words = queryWords(query);
  final shown = all.where((n) => n.archivedAt == null && hasWords(n, words) && (filter != HomeFilter.pinned || n.starred)).toList();
  // A notebook is one by its front matter alone: neither list asks whether a note is a canvas.
  final books = filter == HomeFilter.notes ? <Note>[] : _sorted(shown.where((n) => NoteFacts.of(n).isBook), _newestPinnedFirst);
  final notes = filter == HomeFilter.books ? <Note>[] : _sorted(shown.where((n) => !NoteFacts.of(n).isBook), _newestPinnedFirst);
  return HomeLists(books: books, notes: notes);
}

/// How many of each kind there are, for the filter's counts: the archive left out, the search not applied.
Map<HomeFilter, int> homeCounts(Iterable<Note> all) {
  var live = 0, books = 0, pinned = 0;
  for (final note in all) {
    if (note.archivedAt != null) continue;
    live += 1;
    if (NoteFacts.of(note).isBook) books += 1;
    if (note.starred) pinned += 1;
  }
  return {HomeFilter.all: live, HomeFilter.books: books, HomeFilter.notes: live - books, HomeFilter.pinned: pinned};
}

/// The timeline's spans, newest first.
enum Span { today, yesterday, week, month, earlier }

/// Each span's heading (`SPAN_WORDS`).
const Map<Span, String> spanWords = {
  Span.today: 'Today',
  Span.yesterday: 'Yesterday',
  Span.week: 'Earlier this week',
  Span.month: 'This month',
  Span.earlier: 'Earlier',
};

/// Midnight at the start of this device's day [now] is in, as milliseconds.
int _startOfDay(int now) {
  final at = DateTime.fromMillisecondsSinceEpoch(now);
  return DateTime(at.year, at.month, at.day).millisecondsSinceEpoch;
}

/// Which span a moment falls in, counted in this device's days from [now].
Span spanOf(int at, [int? now]) => _spanFrom(at, _startOfDay(now ?? DateTime.now().millisecondsSinceEpoch));

/// [spanOf], from the midnight today began at.
Span _spanFrom(int at, int today) {
  const day = 24 * 60 * 60 * 1000;
  if (at >= today) return Span.today;
  if (at >= today - day) return Span.yesterday;
  if (at >= today - 6 * day) return Span.week;
  if (at >= today - 30 * day) return Span.month;
  return Span.earlier;
}

/// Notes grouped by when each was last touched, newest first within each, the spans in order and empty ones left out.
List<({Span span, List<Note> notes})> spans(Iterable<Note> notes, [int? now]) {
  // Today's midnight is found once, and each note placed once: it was asked of the calendar ten times a note.
  final today = _startOfDay(now ?? DateTime.now().millisecondsSinceEpoch);
  final groups = <Span, List<Note>>{};
  for (final note in _sorted(notes, _newestFirst)) {
    (groups[_spanFrom(note.updatedAt, today)] ??= <Note>[]).add(note);
  }
  return [
    for (final span in Span.values)
      if (groups[span] != null) (span: span, notes: groups[span]!),
  ];
}

/// Notebooks and notes together, newest first: what the timelines draw, and what they stop at.
List<Note> together(HomeLists lists) => _sorted([...lists.books, ...lists.notes], _newestFirst);

/// Notebooks and notes together, grouped by when each was last touched.
List<({Span span, List<Note> notes})> timeline(HomeLists lists, [int? now]) => spans(together(lists), now);

/// Spotlight's cards and rows: the few touched last, as cards, and everything else by when. By when alone, not pinned
/// first: the cards are where the person was.
({List<Note> lead, List<({Span span, List<Note> notes})> rest}) spotlight(HomeLists lists, [int lead = spotlit, int? now]) {
  final every = together(lists);
  final cut = lead < every.length ? lead : every.length;
  return (lead: every.sublist(0, cut), rest: spans(every.sublist(cut), now));
}

/// A section's mark before its heading: a notebook's, a note's, the pin, the clock of the recent ones. A span has none.
enum SectionMark { notebook, note, pinned, recent }

/// How a section draws its notes: as cards, as rows, or as lines - one short line a note, its name and when.
enum SectionDraw { cards, rows, lines }

/// A section under a heading of words: "Notebooks", "Today" (`WordsSection`). [count] is how many in all, where drawn.
@immutable
class HomeSection {
  const HomeSection({required this.key, required this.heading, required this.mark, required this.count, required this.draw, required this.notes});
  final String key;
  final String heading;
  final SectionMark? mark;
  final int? count;
  final SectionDraw draw;
  final List<Note> notes;
}

/// The page in one layout: its sections in order, and how many notes were left for All notes ([cut]).
@immutable
class HomePlan {
  const HomePlan({required this.sections, required this.cut});
  final List<HomeSection> sections;
  final int cut;
}

List<HomeSection> _byWhen(List<({Span span, List<Note> notes})> groups, SectionDraw draw) => [
      for (final group in groups) HomeSection(key: group.span.name, heading: spanWords[group.span]!, mark: null, count: group.notes.length, draw: draw, notes: group.notes),
    ];

/// What the page draws in a layout, as sections. Cards stops at [most] cards; what it left out is `cut`, which the
/// foot counts on its way to All notes. Rows and lines are cheap, and never stop.
///
/// [now] is the moment the spans are counted from: any time today will do, so the page passes the start of the day
/// and makes a new plan when the day turns rather than on every draw.
HomePlan homePlan(HomeLayout layout, HomeLists lists, {int? now, int most = cardsAtMost}) {
  final books = lists.books, notes = lists.notes;
  final moment = now ?? DateTime.now().millisecondsSinceEpoch;
  final sections = <HomeSection>[];
  void add(HomeSection section) {
    if (section.notes.isNotEmpty) sections.add(section);
  }

  void notebooks(SectionDraw draw) => add(HomeSection(key: 'books', heading: 'Notebooks', mark: SectionMark.notebook, count: books.length, draw: draw, notes: books));
  var cut = 0;

  switch (layout) {
    case HomeLayout.cards:
      notebooks(SectionDraw.cards);
      add(HomeSection(key: 'notes', heading: 'Notes', mark: SectionMark.note, count: notes.length, draw: SectionDraw.cards, notes: notes.take(most).toList()));
      cut = notes.length - most > 0 ? notes.length - most : 0;
    case HomeLayout.list:
      notebooks(SectionDraw.rows);
      add(HomeSection(key: 'notes', heading: 'Notes', mark: SectionMark.note, count: notes.length, draw: SectionDraw.rows, notes: notes));
    case HomeLayout.timeline:
      sections.addAll(_byWhen(timeline(lists, moment), SectionDraw.rows));
    case HomeLayout.spotlight:
      // The pinned notes first, a line each, above Recent, and not again below it: a pin is a place of its own.
      final pinned = together(lists).where((n) => n.starred).toList();
      add(HomeSection(key: 'pinned', heading: 'Pinned', mark: SectionMark.pinned, count: pinned.length, draw: SectionDraw.lines, notes: pinned));
      final unpinned = HomeLists(books: books.where((n) => !n.starred).toList(), notes: notes.where((n) => !n.starred).toList());
      final lit = spotlight(unpinned, spotlit < most ? spotlit : most, moment);
      add(HomeSection(key: 'recent', heading: 'Recent', mark: SectionMark.recent, count: null, draw: SectionDraw.cards, notes: lit.lead));
      sections.addAll(_byWhen(lit.rest, SectionDraw.rows));
  }
  return HomePlan(sections: sections, cut: cut);
}

/// Every note a plan draws as a card, in the page's order.
List<Note> cardsIn(HomePlan plan) => [
      for (final section in plan.sections)
        if (section.draw == SectionDraw.cards) ...section.notes,
    ];
