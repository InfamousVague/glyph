/// Whether a note holds to a query's operators (lib/core/search_query.dart): the filter a search puts the notes
/// through before its words rank them (lib/core/search_hits.dart `findNotes`, lib/notes/all_notes.dart
/// `browseNotes`).
///
/// Everything asked of a note here was read once and kept: its marks (lib/core/note_marks.dart: tags, to-dos,
/// pictures, links), its facts (lib/core/note_facts.dart: a ticket, a notebook, a journal, a canvas), its search
/// text (lib/core/note_text.dart), and its own fields (pinned, archived, recorded, when it was made and changed).
/// What depends on the other notes is worked out once for the query, not once a note: which workspaces `in:` names,
/// with the folders inside them, and which notebook's pages ([SearchFilter.of]). So a filter over the library is a
/// few lookups a note at each letter typed.
///
/// `in:` names a workspace (a folder) or a notebook, whatever the case: the one of that name, or where none is, the
/// ones whose name starts with what was typed, so a name being typed already narrows the notes. A workspace takes
/// in the folders inside it; a notebook its pages (a journal its entries), not the notebook itself.
library;

import 'book.dart' show BookPlace, bookIndex, placeOf;
import 'note.dart';
import 'note_facts.dart';
import 'note_marks.dart';
import 'note_text.dart' show hasTape, hasWords, queryWords, searchText;
import 'properties.dart' show StatusCategory;
import 'search_query.dart';
import 'workspaces.dart';

/// What a filter reads beyond the note itself: every note (a notebook's pages are found among them) and the
/// workspaces with their filings.
class SearchScope {
  const SearchScope({this.notes = const [], this.workspaces = const Workspaces(), this.now});

  /// Every note the app shows, for the notebooks `in:` may name.
  final List<Note> notes;
  final Workspaces workspaces;

  /// The moment `today` and `7d` are counted from; the clock's when null.
  final DateTime? now;
}

final RegExp _spaces = RegExp(r'\s+');

/// A query's operators made ready for one search: the names `in:` gave, found.
class SearchFilter {
  SearchFilter._(this.query, this._filed, this._inSpaces, this._notInSpaces, this._inBooks, this._notInBooks, this._scope, this._phrases, this._notPhrases);

  /// [query]'s operators over [scope]; nothing to ask of a query without any.
  factory SearchFilter.of(SearchQuery query, SearchScope scope) {
    Set<String> spaces(List<String> names) {
      final ids = <String>{};
      final list = scope.workspaces.list;
      for (final name in names) {
        final exact = [for (final w in list) if (w.name.toLowerCase().replaceAll(_spaces, ' ') == name) w];
        final found = exact.isNotEmpty ? exact : [for (final w in list) if (w.name.toLowerCase().replaceAll(_spaces, ' ').startsWith(name)) w];
        for (final w in found) {
          ids.addAll(workspaceFamily(list, w.id));
        }
      }
      return ids;
    }

    Set<String> books(List<String> names) {
      if (names.isEmpty) return const {};
      final titles = <String>{};
      final known = <String>{};
      for (final note in scope.notes) {
        final facts = NoteFacts.of(note);
        if (facts.isBook) known.add(facts.title.toLowerCase().replaceAll(_spaces, ' '));
      }
      for (final name in names) {
        if (known.contains(name)) {
          titles.add(name);
        } else {
          titles.addAll(known.where((title) => title.startsWith(name)));
        }
      }
      return titles;
    }

    RegExp phrase(String said) => RegExp(said.split(' ').map(RegExp.escape).join(r'\s+'));
    return SearchFilter._(
      query,
      scope.workspaces.of,
      spaces(query.places),
      spaces(query.notPlaces),
      books(query.places),
      books(query.notPlaces),
      scope,
      [for (final said in query.phrases) (queryWords(said), phrase(said))],
      [for (final said in query.withoutPhrases) (queryWords(said), phrase(said))],
    );
  }

  final SearchQuery query;
  final Map<String, String> _filed;
  final Set<String> _inSpaces;
  final Set<String> _notInSpaces;
  final Set<String> _inBooks;
  final Set<String> _notInBooks;
  final SearchScope _scope;
  final List<(List<String>, RegExp)> _phrases;
  final List<(List<String>, RegExp)> _notPhrases;

  /// The notebook each page is in, read once for the search and only when `in:` asks.
  late final Map<String, BookPlace> _pages = bookIndex(_scope.notes);

  String? _bookOf(Note note) {
    final place = placeOf(_pages, note);
    return place?.title.toLowerCase().replaceAll(_spaces, ' ');
  }

  bool _is(SearchIs flag, Note note) {
    switch (flag) {
      case SearchIs.pinned:
        return note.starred;
      case SearchIs.archived:
        return (note.archivedAt ?? 0) != 0;
      case SearchIs.todo:
        return NoteMarks.of(note).openTodos > 0;
      case SearchIs.done:
        final facts = NoteFacts.of(note);
        if (facts.isTicket) return facts.ticket?.category == StatusCategory.done;
        final marks = NoteMarks.of(note);
        return marks.doneTodos > 0 && marks.openTodos == 0;
      case SearchIs.ticket:
        return NoteFacts.of(note).isTicket;
      case SearchIs.notebook:
        return NoteFacts.of(note).isBook;
      case SearchIs.journal:
        return NoteFacts.of(note).isJournal;
      case SearchIs.canvas:
        return NoteFacts.of(note).isCanvas;
    }
  }

  bool _has(SearchHas what, Note note) => switch (what) {
        SearchHas.todo => NoteMarks.of(note).openTodos > 0,
        SearchHas.image => NoteMarks.of(note).picture,
        SearchHas.link => NoteMarks.of(note).link,
        SearchHas.recording => hasTape(note) || NoteMarks.of(note).clip,
      };

  bool _inPlace(Note note, Set<String> spaces, Set<String> books) {
    final filed = _filed[note.id];
    if (filed != null && spaces.contains(filed)) return true;
    if (books.isEmpty) return false;
    final book = _bookOf(note);
    return book != null && books.contains(book);
  }

  static bool _phrased(Note note, (List<String>, RegExp) phrase) => hasWords(note, phrase.$1) && phrase.$2.hasMatch(searchText(note));

  /// Whether [note] holds to every operator.
  bool admits(Note note) {
    final q = query;
    if (!q.made.holds(note.createdAt) || !q.changed.holds(note.updatedAt)) return false;
    for (final flag in q.isFlags) {
      if (!_is(flag, note)) return false;
    }
    for (final flag in q.notIs) {
      if (_is(flag, note)) return false;
    }
    for (final what in q.has) {
      if (!_has(what, note)) return false;
    }
    for (final what in q.notHas) {
      if (_has(what, note)) return false;
    }
    if (q.tags.isNotEmpty || q.notTags.isNotEmpty) {
      final marks = NoteMarks.of(note);
      for (final tag in q.tags) {
        if (!marks.tagged(tag)) return false;
      }
      for (final tag in q.notTags) {
        if (marks.tagged(tag)) return false;
      }
    }
    if (q.places.isNotEmpty && !_inPlace(note, _inSpaces, _inBooks)) return false;
    if (q.notPlaces.isNotEmpty && _inPlace(note, _notInSpaces, _notInBooks)) return false;
    for (final phrase in _phrases) {
      if (!_phrased(note, phrase)) return false;
    }
    for (final phrase in _notPhrases) {
      if (_phrased(note, phrase)) return false;
    }
    for (final word in q.without) {
      if (hasWords(note, [word])) return false;
    }
    return true;
  }
}
