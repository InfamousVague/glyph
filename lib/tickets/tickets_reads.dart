/// The library as My tickets, Triage and the sidebar's count read it: the query engine's own records
/// (lib/core/query/records.dart `libraryOf`), read again only when the notes a query reads are another list, and
/// each note's reading kept while its words stay the same, as an editor's queries keep theirs.
library;

import '../core/query/query.dart';
import 'inbox.dart';

class TicketsReads {
  TicketsReads({required this.notes});

  /// The notes a ```query reads (lib/root/library_reads.dart `queryNotes`), the same list until the library changes.
  final List<QueryNote> Function() notes;

  final RecordCache _cache = recordCache();
  List<QueryNote>? _of;
  QueryLibrary? _library;
  ({String today, int all, int overdue})? _count;

  /// The library, read once for each list of notes.
  QueryLibrary get library {
    final now = notes();
    if (!identical(now, _of) || _library == null) {
      _of = now;
      _library = libraryOf(now, _cache);
      _count = null;
    }
    return _library!;
  }

  /// How many tickets are assigned to you on [today], and how many are overdue: the sidebar's row.
  ({int all, int overdue}) count(String today) {
    final lib = library;
    final had = _count;
    if (had != null && had.today == today) return (all: had.all, overdue: had.overdue);
    final counted = myTicketCount(myTickets(lib, today));
    _count = (today: today, all: counted.all, overdue: counted.overdue);
    return counted;
  }

  /// Who `me` is changed: counted again when next asked.
  void forget() => _count = null;
}
