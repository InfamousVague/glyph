/// Where a book was left, so it opens there again (Matt: "When opening a book re open to the same spot it was last
/// opened"). The logic half of `src/app/book/bookSpot.ts`. A book is read in one of three places, and the spot is
/// whichever it was last:
///
/// - **its index**, the book note itself;
/// - **a chapter**, the chapter's own note, opened from the index, the chapter bar or the foot's Next. The note
///   keeps its own place on the page, so a book that goes back to the chapter goes back to the line;
/// - **reading straight through**, at a chapter and how far into it the page was scrolled.
///
/// Opening the book from outside it - the home page's Library, the sidebar, the notes list, search, a `[[link]]` -
/// goes to that spot ([whereLeft]): a chapter opens in the book's place, and the read-through opens where it was.
/// From inside the book it does not: the chapter bar's book button, a tab, Back and Forward go to the index as they
/// always did, or there would be no way back to it from a chapter.
///
/// A chapter is kept by its title, the way the book finds it, so a chapter moved in the index is still the spot; one
/// taken out of the book, or whose note is gone, is not, and the book opens at its index. Kept on the device under
/// one key, for the most recently read books only.
///
/// What differs:
/// - The spots are kept in lib/core/stored.dart's [stored] (the page's `localStorage`), or the [Stored] handed in.
/// - **The read-through's place is arithmetic here and no more**: [readingPlaceOf] and [readingScroll] take the
///   tops the page measured (the scroller's, and each chapter's section's, in one frame of reference) where the web
///   asks the DOM for them, and [readingScroll] answers how far to scroll rather than scrolling. The hook that
///   watches a scroller and writes the spot as it settles (`useBookSpot`, with `SAVE_AFTER_MS` and `WAIT_MS`, here
///   [saveAfter] and [waitFor]) is the notebook's view's to write (5G).
library;

import '../core/book.dart' show chaptersOf, isBookBody, isJournalBody;
import '../core/note.dart';
import '../core/note_text.dart' show noteTitle;
import '../core/stored.dart';
import '../core/title_key.dart' show sameTitle;

/// Where a book was left (`BookSpot`).
sealed class BookSpot {
  const BookSpot();

  /// The object the page keeps for it, key for key.
  Map<String, Object?> toJson();

  @override
  bool operator ==(Object other) => other is BookSpot && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;

  @override
  String toString() => 'BookSpot(${toJson()})';
}

class IndexSpot extends BookSpot {
  const IndexSpot();
  @override
  Map<String, Object?> toJson() => {'kind': 'index'};
}

class ChapterSpot extends BookSpot {
  const ChapterSpot(this.title);
  final String title;
  @override
  Map<String, Object?> toJson() => {'kind': 'chapter', 'title': title};
}

class ReadingSpot extends BookSpot {
  const ReadingSpot(this.title, this.offset);
  final String title;

  /// How far into the chapter the page was scrolled, in pixels.
  final num offset;
  @override
  Map<String, Object?> toJson() => {'kind': 'reading', 'title': title, 'offset': offset};
}

/// The key the spots are kept under (`KEY`): the web app's own.
const String bookSpotsKey = 'glyph-book-spots';

/// Books remembered; the least recently read are forgotten first (`KEEP`).
const int _keep = 100;

/// Scrolling settles for this long before the read-through's place is written (`SAVE_AFTER_MS`).
const Duration saveAfter = Duration(milliseconds: 400);

/// How long an opening read-through is waited on for its chapters to lay out before it is left where it is
/// (`WAIT_MS`).
const Duration waitFor = Duration(milliseconds: 2500);

/// A spot as it was read back: another build's shape, or a half-written store, is no spot.
BookSpot? _spotFrom(Object? value) {
  if (value is! Map) return null;
  final kind = value['kind'], title = value['title'], offset = value['offset'];
  if (kind == 'index') return const IndexSpot();
  if (kind == 'chapter' && title is String) return ChapterSpot(title);
  if (kind == 'reading' && title is String && offset is num && offset.isFinite) return ReadingSpot(title, offset);
  return null;
}

Map<String, Object?> _readAll(Stored on) => {...on.read<Map<String, Object?>>(bookSpotsKey, const {}, (raw) => raw is Map ? raw.cast<String, Object?>() : null)};

BookSpot? readBookSpot(String bookId, {Stored? on}) => _spotFrom(_readAll(on ?? stored)[bookId]);

void writeBookSpot(String bookId, BookSpot spot, {int? now, Stored? on}) {
  final store = on ?? stored;
  final all = _readAll(store);
  all[bookId] = {...spot.toJson(), 'at': now ?? DateTime.now().millisecondsSinceEpoch};
  num? at(Object? each) => each is Map && each['at'] is num && (each['at'] as num).isFinite ? each['at'] as num : null;
  final entries = [
    for (final entry in all.entries)
      if (at(entry.value) != null) entry,
  ];
  // The newest first, two written in the same millisecond as they were kept: the page's sort leaves ties alone.
  final order = [for (var i = 0; i < entries.length; i += 1) i]
    ..sort((a, b) {
      final by = at(entries[b].value)!.compareTo(at(entries[a].value)!);
      return by != 0 ? by : a - b;
    });
  store.write(bookSpotsKey, {for (final i in order.take(_keep)) entries[i].key: entries[i].value});
}

/// The note to show for [note] opened from outside its book: the chapter the book was left in, while that chapter is
/// still in the book and still a note, and not already the note on screen (where opening the book is asking for its
/// index); otherwise [note] itself. Only a book is ever swapped, and never a journal: opened, a journal is where New
/// entry is, not yesterday's entry with New entry two taps away (docs/DESIGN.md §142).
Note whereLeft(Note note, Iterable<Note> notes, String? showing, {Stored? on}) {
  if (!isBookBody(note.body) || isJournalBody(note.body)) return note;
  final spot = readBookSpot(note.id, on: on);
  if (spot is! ChapterSpot) return note;
  if (!chaptersOf(note.body).any((c) => sameTitle(c.title, spot.title))) return note;
  for (final n in notes) {
    if (n.id != note.id && n.archivedAt == null && sameTitle(noteTitle(n.body), spot.title)) return n.id != showing ? n : note;
  }
  return note;
}

/// Where the read-through is scrolled to: the chapter at the top of the page and how far into it, in pixels. Above
/// the first chapter (the bar of chapters, or the very top) it is the first chapter, at its start. [pageTop] is the
/// scroller's top and [sectionTops] each chapter's section's, in the index's order, as they are drawn now.
BookSpot? readingPlaceOf(double pageTop, List<double> sectionTops, List<String> titles) {
  var at = -1;
  for (var i = 0; i < sectionTops.length; i += 1) {
    if (sectionTops[i] <= pageTop + 1) {
      at = i;
    } else {
      break;
    }
  }
  final index = at < 0 ? 0 : at;
  if (index >= titles.length) return null;
  final into = at < 0 ? 0.0 : pageTop - sectionTops[index];
  // The page's Math.round: a half goes up.
  final offset = into <= 0 ? 0 : (into + 0.5).floor();
  return ReadingSpot(titles[index], offset);
}

/// How far to scroll the page so the read-through is back at [title]'s chapter, [offset] into it; null while that
/// chapter is not drawn, or is not in the book (`scrollToReading`, which scrolls by this and answers whether it did).
double? readingScroll(double pageTop, List<double> sectionTops, List<String> titles, String title, num offset) {
  final index = titles.indexWhere((t) => sameTitle(t, title));
  if (index < 0 || index >= sectionTops.length) return null;
  return sectionTops[index] - pageTop + offset;
}
