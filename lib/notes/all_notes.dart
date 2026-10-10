/// The rules behind the All notes page (lib/notes/all_notes_screen.dart): which notes it shows, in what order, and
/// what a search over them finds. A port of `src/app/notes/allNotes.ts`. Pure, so each rule is a test.
///
/// Matt: "Browsing all notes is super hard there is no good UI it just opens in the sidebar, I'd like a grid view of
/// all the notes in the 'all notes' section." The sidebar is a tree for jumping to a note you know; the page is for
/// looking. So it takes every note the home page's workspace shows, lets the search narrow them, orders them one of
/// two ways, and keeps the archive out unless it is asked for.
///
/// What differs:
/// - `matches` and `hasTape` were ported with the home page and live in lib/core/note_text.dart; they are handed on
///   from here under the web's names. That `matches` finds a priority's sign wherever it is written, where the web
///   reads the to-dos' fields (`core/taskFields.ts` `fieldsIn`), so a `⏫` in inline code is found as "high" here and
///   not there.
/// - By name, the web orders with `localeCompare`, the browser's collation for the device's language. Dart has none,
///   so the names are compared as they are spelled, in lower case: the same order for plain letters and figures, not
///   for accents or for punctuation at the start of a name.
/// - The order kept on the device is read from and written to a [Stored] handed in, the app's own unless given.
/// - **What a search reads of a note is read once and kept** (lib/core/note_text.dart `searchText`, which the home
///   page's search looks through too), where the page makes it for every note at every letter typed. What is
///   found is the same (test/allnotes holds the kept reading to the rule as the page writes it).
library;

import 'package:flutter/foundation.dart';

import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/note_text.dart';
import '../core/stored.dart';

export '../core/note_text.dart' show hasTape, matches, searchText;

/// How the page orders its cards: the last touched first, or by name (`AllNotesSort`).
enum AllNotesSort {
  newest('newest', 'Newest'),
  title('title', 'A to Z');

  const AllNotesSort(this.id, this.label);

  /// The word kept on the device.
  final String id;

  /// The word on the page.
  final String label;
}

/// The two orders, in the order the page offers them (`SORTS`).
const List<AllNotesSort> sorts = AllNotesSort.values;

/// What the page is asked to show (`Browse`).
@immutable
class Browse {
  const Browse({this.query = '', this.sort = AllNotesSort.newest, this.archived = false, this.tapes = false});

  /// Words typed into the search: a note is shown when they all appear somewhere in it. Blank shows every note.
  final String query;
  final AllNotesSort sort;

  /// Whether the archived notes are shown too. They are marked on their cards when they are.
  final bool archived;

  /// Only the notes with a tape: every note with a recording, typed ones included, so nothing with a tape is
  /// unreachable.
  final bool tapes;
}

/// Words that count as having no title, so a note with none sorts after the named ones.
bool _untitled(Note note) => NoteFacts.of(note).title.trim().isEmpty;

/// A title to sort by: the note's own, lower-cased.
String _sortKey(Note note) => NoteFacts.of(note).title.trim().toLowerCase();

/// The notes the page shows, in the order it shows them (`browseNotes`). The list given is not reordered.
List<Note> browseNotes(Iterable<Note> notes, Browse browse) {
  // The query's words once, not once a note; none asked for is every note, with nothing of any read.
  final words = queryWords(browse.query);
  final shown = [
    for (final n in notes)
      if ((browse.archived || n.archivedAt == null) && (!browse.tapes || hasTape(n)) && hasWords(n, words)) n,
  ];
  // A merge sort, which is stable as the page's `Array.sort` is: two notes touched in the same moment keep the order
  // they were given in.
  if (browse.sort == AllNotesSort.title) {
    mergeSort<Note>(shown, compare: (a, b) {
      final blankA = _untitled(a), blankB = _untitled(b);
      if (blankA != blankB) return blankA ? 1 : -1;
      final byName = _sortKey(a).compareTo(_sortKey(b));
      return byName != 0 ? byName : b.updatedAt.compareTo(a.updatedAt);
    });
  } else {
    mergeSort<Note>(shown, compare: (a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
  return shown;
}

/// How many notes are in the archive, for the toggle that shows them (`archivedCount`).
int archivedCount(Iterable<Note> notes) => notes.where((n) => n.archivedAt != null).length;

/// How many of the notes have a tape, for the toggle that shows only them: given the notes less the archive unless
/// it is shown (`tapeCount`).
int tapeCount(Iterable<Note> notes) => notes.where(hasTape).length;

/// The order chosen last time, kept on the device (`SORT_KEY`).
const String allNotesSortKey = 'glyph-all-notes-sort';

/// Nothing kept, or storage that cannot be read: the newest first, as on the home page (`readSort`).
AllNotesSort readSort([Stored? from]) => (from ?? stored).readText(allNotesSortKey) == AllNotesSort.title.id ? AllNotesSort.title : AllNotesSort.newest;

/// Storage that cannot be written: the choice holds for this page, and is asked again next time (`writeSort`).
void writeSort(AllNotesSort sort, [Stored? to]) => (to ?? stored).writeText(allNotesSortKey, sort.id);
