/// Which notes are owed a line under their title: the cards the page on screen begins with, and no others. A port of
/// what the two pages hand `useGists` (src/app/home/HomeScreen.tsx `carded`: the first 16 cards of its plan;
/// src/app/notes/AllNotesScreen.tsx `gisted`: the first 24 it shows).
///
/// The runner (lib/format/gist.dart) writes one line at a time with the smallest model, for the notes it is shown.
/// Shown every note in the library it worked through all of them, on a phone for as long as any had none, and told
/// its listeners twice a turn; shown a page's first cards it is done in a few turns and has nothing more to say.
///
/// What differs: on the page each screen is the one that knows its cards, so a search or a filter changes which
/// notes are asked about. Here the app's root asks for them (the screens are handed a map), and it knows a page as
/// it opens: no words searched for, every kind of note, the order All notes was left in. A card found only by
/// searching has a line if it was written before, and none is written for it while the search stands.
library;

import '../core/note.dart';
import '../core/workspaces.dart';
import '../home/home_layout.dart';
import '../notes/all_notes.dart';

/// How many of the home page's cards have a line (`GISTED`, home/HomeScreen.tsx).
const int homeGisted = 16;

/// How many of All notes' (`GISTED`, notes/AllNotesScreen.tsx; lib/notes/all_notes_screen.dart `allNotesGisted`).
const int allNotesGistedMost = 24;

/// The home page's first cards, as it lays out [notes] in the workspace looked at, on the day of [now].
List<Note> homeCarded(List<Note> notes, WorkspaceStore workspaces, HomeLayout layout, int now) {
  final inSpace = workspaces.inWorkspace(notes, workspaces.value.current?.id, (note) => note.id);
  final at = DateTime.fromMillisecondsSinceEpoch(now);
  final today = DateTime(at.year, at.month, at.day).millisecondsSinceEpoch;
  final plan = homePlan(layout, homeLists(inSpace, '', HomeFilter.all), now: today);
  return cardsIn(plan).take(homeGisted).toList();
}

/// All notes' first cards, in the order it was left in; with [tapes], of the notes with a recording.
List<Note> allNotesCarded(List<Note> notes, WorkspaceStore workspaces, {required AllNotesSort sort, required bool tapes}) {
  final inSpace = workspaces.inWorkspace(notes, workspaces.value.current?.id, (note) => note.id);
  return browseNotes(inSpace, Browse(query: '', sort: sort, archived: false, tapes: tapes)).take(allNotesGistedMost).toList();
}
