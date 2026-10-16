/// The palette's world and doings as the app has them: what the web app's `App.tsx` builds inline as `paletteWorld`
/// and `paletteDoing` before handing them to `CommandBar`, here as functions over the shell, the library, the
/// workspaces and the preferences, so lib/root can ask for them in one line each.
///
/// What differs from App.tsx:
/// - There it is two object literals in the component's body; here [paletteWorldFor], [paletteDoingFor] and
///   [commandsFor], which is the two put through [paletteCommands].
/// - What the palette opens that is not ported yet comes in as a callback that may be null, and its command is
///   left out: a new notebook, journal and entry; Speak and Talk into this note; the AI's runs; the Academy; the
///   welcome walkthrough; the note's marks shown or formatted; a note opened where its book was left. Settings' pages (Organizations, the cheat sheet)
///   are the root's to open, since it holds the Settings sheet, so they are callbacks too.
/// - The note on screen is read fresh from the library by its id (its pin, its title), where the page read the
///   copy its screen held.
/// - The notes are put in the web store's order here, newest-changed first ([paletteNotes]).
/// - Pinning and archiving are the root's note actions (`actions.pin`, `actions.archive` in App.tsx: the tick, the
///   toast with its Undo), handed in as `pin` and `archive`; without them the library is asked and nothing is said.
///   Neither closes the note's tab, as on the page.
/// - A note's title and whether it is a journal are asked of what is kept of its words (lib/core/note_facts.dart),
///   and the journals are kept for the list they were found in: the palette asks for its world at every letter
///   typed, and each time read every note's front matter for the journals and the open notes' titles again.
library;

import 'package:flutter/foundation.dart';

import '../core/book.dart';
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/preferences.dart';
import '../core/sample_library.dart' show NoteLibrary;
import '../core/tabs.dart';
import '../core/workspaces.dart';
import '../shell/app_shell.dart';
import '../shell/screen.dart';
import 'palette.dart';

final Expando<List<PaletteNote>> _named = Expando<List<PaletteNote>>('the notes as the palette names them');

/// The notes as the palette names them, newest-changed first: each one's title, and whether it is a journal's entry
/// or a page of a Templates notebook, which are found when typed for and not offered before (`entryIds`, App.tsx).
/// Remembered for a list, since the library hands the same one back until something changes.
///
/// The order is the web store's (`byRecency`, core/store.ts: "the only order the list is ever shown in"), put on
/// here because [NoteLibrary] promises none; notes changed in the same millisecond keep the order they came in.
List<PaletteNote> paletteNotes(List<Note> notes) {
  final held = _named[notes];
  if (held != null) return held;
  final entries = {...entryPages(notes), ...templatePages(notes)};
  final order = [for (var i = 0; i < notes.length; i += 1) i]
    ..sort((a, b) {
      final byRecency = notes[b].updatedAt.compareTo(notes[a].updatedAt);
      return byRecency != 0 ? byRecency : a.compareTo(b);
    });
  return _named[notes] = List.unmodifiable([
    for (final i in order) PaletteNote(id: notes[i].id, title: NoteFacts.of(notes[i]).title, entry: entries.contains(notes[i].id)),
  ]);
}

final Expando<List<PaletteNote>> _journals = Expando<List<PaletteNote>>('the journals as the palette offers them');

/// The journals a new entry is offered in: not archived, the one written in last first, three at most, an unnamed
/// one as "Untitled journal".
List<PaletteNote> paletteJournals(List<Note> notes) {
  final held = _journals[notes];
  if (held != null) return held;
  final journals = [
    for (final note in notes)
      if (note.archivedAt == null && NoteFacts.of(note).isJournal) note,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return _journals[notes] = List.unmodifiable([
    for (final note in journals.take(3))
      PaletteNote(id: note.id, title: NoteFacts.of(note).title.isEmpty ? 'Untitled journal' : NoteFacts.of(note).title, journal: true),
  ]);
}

/// The app as it stands, for the palette (`paletteWorld`, App.tsx): the shell's notes, tabs, screen and trail, the
/// workspaces, and the two preferences a command's words turn on. [blanks] is how many blanks the open note's
/// editor counted, once there is one to count them.
PaletteWorld paletteWorldFor({required AppShellState shell, required Workspaces workspaces, required Preferences prefs, int blanks = 0, List<PaletteNamed> smartNotebooks = const []}) {
  final screen = shell.screen;
  Note? open;
  if (screen is ScreenNote) {
    final shown = screen.note;
    open = shown;
    for (final note in shell.notes) {
      if (note.id == shown.id) open = note;
    }
  }
  final groups = shell.tabs.groups;
  return PaletteWorld(
    notes: paletteNotes(shell.notes),
    journals: paletteJournals(shell.notes),
    tabs: [for (final note in shell.tabs.tabs) PaletteNote(id: note.id, title: NoteFacts.of(note).title)],
    // A folder inside another is named with its parents: "Work › Clients".
    workspaces: [for (final space in workspaces.list) (id: space.id, name: space.parent == null ? space.name : workspacePathName(workspaces.list, space.id))],
    workspace: workspaces.current?.id,
    note: open == null ? null : PaletteNote(id: open.id, title: NoteFacts.of(open).title, journal: NoteFacts.of(open).isJournal, blanks: blanks),
    filedIn: open == null ? null : workspaces.of[open.id],
    pinned: open?.starred ?? false,
    canBack: shell.trail.canBack,
    canForward: shell.trail.canOn,
    view: prefs.noteView,
    theme: prefs.theme,
    tabGroups: [for (final group in groups.list) (id: group.id, name: group.name)],
    tabGroup: open == null ? null : groups.of[open.id],
    smartNotebooks: smartNotebooks,
  );
}

/// What the palette sets off, over the app's own doings (`paletteDoing`, App.tsx).
///
/// The shell does the going (a note, home, All notes, back and on, a tab closed, the notifications, a tab's group),
/// [library] the pinning and archiving, [workspaces] the filing and the list's filter, and [prefs] (the app's own
/// store unless given) the theme. The root gives the rest: [newNote] and [removeNote] as it
/// already makes and deletes one, [settings], and [settingsPage] to open Settings at a section by its id
/// (lib/settings/settings_sections.dart), which the Organizations command and, unless [cheatSheet] is given, the
/// cheat sheet use. Each of the others is the root's to give and left out of the palette while it is null;
/// [setView] among them, which the root gives as the preference every note's editor reads
/// (`(view) => preferences.update((now) => now.copyWith(noteView: view))`, lib/root/root_parts.dart).
PaletteDoing paletteDoingFor({
  required AppShellState shell,
  required NoteLibrary library,
  required WorkspaceStore workspaces,
  PreferencesStore? prefs,
  required VoidCallback newNote,
  required void Function(String id) removeNote,
  required VoidCallback settings,
  void Function(String section)? settingsPage,
  VoidCallback? cheatSheet,
  void Function(String id)? archive,
  void Function(String id, bool pinned)? pin,
  void Function(String view)? setView,
  void Function(String id)? openNoteWhereLeft,
  VoidCallback? newNotebook,
  VoidCallback? newJournal,
  void Function(String journalId)? newEntry,
  VoidCallback? speak,
  void Function(String id)? speakInto,
  VoidCallback? guide,
  VoidCallback? academy,
  void Function(String id, String kind)? noteAi,
  VoidCallback? today,
  VoidCallback? tags,
  void Function(String id)? openSmart,
}) {
  final store = prefs ?? preferences;
  return PaletteDoing(
    openNote: shell.openNote,
    openNoteWhereLeft: openNoteWhereLeft,
    newNote: newNote,
    newNotebook: newNotebook,
    newJournal: newJournal,
    newEntry: newEntry,
    speak: speak,
    speakInto: speakInto,
    closeTab: shell.closeTab,
    showList: shell.backToList,
    browseNotes: shell.showAllNotes,
    back: shell.goBack,
    forward: shell.goOn,
    settings: settings,
    cheatSheet: cheatSheet ?? (settingsPage == null ? null : () => settingsPage('cheatsheet')),
    guide: guide,
    academy: academy,
    notifications: shell.showNotifications,
    organizations: settingsPage == null ? null : () => settingsPage('organizations'),
    chooseWorkspace: workspaces.chooseWorkspace,
    fileNote: workspaces.fileNote,
    setView: setView,
    setTheme: (theme) => store.update((now) => themeChoice(theme, now)),
    pin: pin ?? (id, pinned) => library.pin(id, pinned: pinned),
    archive: archive ?? (id) => library.archive(id, archived: true),
    remove: removeNote,
    noteAi: noteAi,
    groupTab: (id) => shell.tabs.setGroups(newGroup(shell.tabs.groups, id).groups),
    joinTabGroup: (id, group) => shell.tabs.setGroups(joinGroup(shell.tabs.groups, id, group)),
    leaveTabGroup: (id) => shell.tabs.setGroups(leaveGroup(shell.tabs.groups, id)),
    today: today,
    tags: tags,
    openSmart: openSmart,
  );
}

/// The whole list for the app as it stands: [paletteWorldFor] and [paletteDoingFor] through [paletteCommands].
/// [query] is what is typed so far, which decides only which notes are offered by name.
List<PaletteCommand> commandsFor({required PaletteWorld world, required PaletteDoing doing, String query = ''}) => paletteCommands(world, doing, query);
