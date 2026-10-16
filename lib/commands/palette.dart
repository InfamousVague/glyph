/// Everything Ghost.md can do, as one list to search: a port of the web app's `src/app/commands/palette.ts`.
///
/// The kit's palette takes descriptors and does the searching, grouping and cursor; this file decides WHAT is
/// offered, which is the part that belongs to the app. Pure: it is handed the state of the app and a set of doings,
/// and answers a list. So every rule about what appears when - a note's commands only over a note, a workspace's only
/// where there are workspaces - is a test rather than something to press through.
///
/// The order is the order offered: the palette filters and groups but never reorders, so what is likeliest comes
/// first. Nothing here is a shortcut for something the app cannot already do.
///
/// What differs from the TypeScript:
/// - `NoteView`, `ThemePref` and the AI's `RunKind` are the strings the preferences keep (`mixed` / `formatted`;
///   `system`, `light`, `dark`, `dawn`, `boreal`, `ember`; `fix`, `shape`, `continue`, `fill`), as
///   lib/core/preferences.dart has them.
/// - Seven doings the web requires are optional here, because what they open is not ported yet and a command with
///   nowhere to go is left out rather than offered: [PaletteDoing.newNotebook], [PaletteDoing.setView],
///   [PaletteDoing.cheatSheet], [PaletteDoing.guide], [PaletteDoing.academy], [PaletteDoing.notifications] and
///   [PaletteDoing.organizations]. Given all of them the list is the web's, row for row.
library;

import 'package:flutter/foundation.dart';
import 'package:glacier/glacier.dart' show CommandDescriptor;

/// A note, as little of it as a command needs (`PaletteNote`).
@immutable
class PaletteNote {
  const PaletteNote({required this.id, required this.title, this.journal = false, this.entry = false, this.blanks = 0});

  final String id;
  final String title;

  /// A journal: its mic makes an entry and speaks it.
  final bool journal;

  /// One of a journal's entries: found by name when typed for, and not among the forty offered before a word is typed.
  final bool entry;

  /// How many blanks a press of Fill would take in it, for the note on screen.
  final int blanks;

  @override
  bool operator ==(Object other) => other is PaletteNote && other.id == id && other.title == title && other.journal == journal && other.entry == entry && other.blanks == blanks;

  @override
  int get hashCode => Object.hash(id, title, journal, entry, blanks);

  @override
  String toString() => 'PaletteNote($id, "$title"${journal ? ', journal' : ''}${entry ? ', entry' : ''}${blanks > 0 ? ', $blanks blanks' : ''})';
}

/// Something with an id and a name: a workspace, or a group of tabs.
typedef PaletteNamed = ({String id, String name});

/// The app as it stands, for deciding what can be done right now (`PaletteWorld`).
@immutable
class PaletteWorld {
  const PaletteWorld({
    this.notes = const [],
    this.journals = const [],
    this.tabs = const [],
    this.workspaces = const [],
    this.workspace,
    this.note,
    this.filedIn,
    this.pinned = false,
    this.canBack = false,
    this.canForward = false,
    this.view = 'mixed',
    this.theme = 'dark',
    this.tabGroups = const [],
    this.tabGroup,
    this.smartNotebooks = const [],
  });

  /// Every note, newest first: each is an "Open …".
  final List<PaletteNote> notes;

  /// The journals, the one written in last first, at most three: each is a "New entry in …".
  final List<PaletteNote> journals;

  /// The notes open as tabs.
  final List<PaletteNote> tabs;
  final List<PaletteNamed> workspaces;

  /// The workspace the list is showing, or null for all notes.
  final String? workspace;

  /// The note on screen, if one is.
  final PaletteNote? note;

  /// Which workspace the open note is filed in.
  final String? filedIn;

  /// Whether the open note is pinned, so the command says which way it goes.
  final bool pinned;
  final bool canBack;
  final bool canForward;

  /// `mixed` or `formatted`.
  final String view;
  final String theme;

  /// The tab groups, and which one the open note's tab is in.
  final List<PaletteNamed> tabGroups;
  final String? tabGroup;

  /// The smart notebooks, in the sidebar's order: each is a "Show …" (lib/core/smart_notebooks.dart).
  final List<PaletteNamed> smartNotebooks;
}

/// What the palette can set off (`PaletteDoing`). Every one of these is something the app already does by hand. A
/// doing left null has no command.
@immutable
class PaletteDoing {
  const PaletteDoing({
    required this.openNote,
    this.openNoteWhereLeft,
    required this.newNote,
    this.newNotebook,
    this.newJournal,
    this.newEntry,
    this.speak,
    this.speakInto,
    required this.closeTab,
    required this.showList,
    required this.browseNotes,
    required this.back,
    required this.forward,
    required this.settings,
    this.cheatSheet,
    this.guide,
    this.academy,
    this.notifications,
    this.organizations,
    required this.chooseWorkspace,
    required this.fileNote,
    this.setView,
    required this.setTheme,
    required this.pin,
    required this.archive,
    required this.remove,
    this.noteAi,
    this.groupTab,
    this.joinTabGroup,
    this.leaveTabGroup,
    this.today,
    this.tags,
    this.openSmart,
  });

  final void Function(String id) openNote;

  /// A note opened by name, from outside it: a book where it was left. Absent, [openNote].
  final void Function(String id)? openNoteWhereLeft;
  final VoidCallback newNote;

  /// The New notebook sheet. Required on the web; null until notebooks are ported.
  final VoidCallback? newNotebook;

  /// The same sheet with Journal chosen.
  final VoidCallback? newJournal;

  /// A new entry in that journal.
  final void Function(String journalId)? newEntry;

  /// Speak a new note, and talk into this one: absent where nothing records.
  final VoidCallback? speak;
  final void Function(String id)? speakInto;
  final void Function(String id) closeTab;
  final VoidCallback showList;

  /// The All notes grid.
  final VoidCallback browseNotes;
  final VoidCallback back;
  final VoidCallback forward;
  final VoidCallback settings;

  /// Settings at the cheat sheet. Required on the web.
  final VoidCallback? cheatSheet;

  /// The welcome walkthrough, and the Academy. Required on the web; null until each is ported.
  final VoidCallback? guide;
  final VoidCallback? academy;

  /// The notifications drawer, and Settings › Account › Organizations. Required on the web.
  final VoidCallback? notifications;
  final VoidCallback? organizations;
  final void Function(String? id) chooseWorkspace;
  final void Function(String noteId, String? workspace) fileNote;

  /// The note's marks shown or formatted. Required on the web; null until the editor that reads it is ported.
  final void Function(String view)? setView;
  final void Function(String theme) setTheme;
  final void Function(String id, bool pinned) pin;
  final void Function(String id) archive;
  final void Function(String id) remove;

  /// One of the AI's runs on the note on screen: `fix`, `shape`, `continue` or `fill`.
  final void Function(String id, String kind)? noteAi;

  /// Tab groups, for a phone, which has no right-click to reach a tab's own menu.
  final void Function(String noteId)? groupTab;
  final void Function(String noteId, String group)? joinTabGroup;
  final void Function(String noteId)? leaveTabGroup;

  /// Today's note, the Tags page, and a smart notebook's page (the port's own, 2026-10-16).
  final VoidCallback? today;
  final VoidCallback? tags;
  final void Function(String id)? openSmart;
}

/// A row of the palette and what choosing it does (`PaletteCommand`).
class PaletteCommand {
  const PaletteCommand(this.descriptor, this.run);

  final CommandDescriptor descriptor;
  final VoidCallback run;

  @override
  String toString() => 'PaletteCommand(${descriptor.id}, "${descriptor.label}")';
}

/// How many notes are offered by name (`MOST_NOTES`). Past this the palette would be a list of notes rather than of
/// commands.
const int mostNotes = 40;

String _titleOf(PaletteNote note) => note.title.isEmpty ? 'Untitled' : note.title;

/// What a note's row is found by, besides its label: its group and its keywords, as the kit reads them.
const String _noteGroup = 'Notes by name';
const String _noteKeywords = 'note go to';

final RegExp _spaces = RegExp(r'\s+');

/// The notes offered by name: with nothing typed, the forty changed last, a journal's entries left out; with a
/// query, the forty newest the query finds, in the whole library, entries among them. A note matches as the kit's
/// palette matches a row, every word of the query somewhere in "Open <title>", its group or its keywords, so this
/// only chooses which forty the kit is given.
List<PaletteNote> notesByName(List<PaletteNote> notes, [String query = '']) {
  final words = query.trim().toLowerCase().split(_spaces).where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return notes.where((note) => !note.entry).take(mostNotes).toList();
  final around = '$_noteGroup $_noteKeywords'.toLowerCase();
  final found = <PaletteNote>[];
  for (final note in notes) {
    final label = 'open ${_titleOf(note)}'.toLowerCase();
    if (words.every((word) => label.contains(word) || around.contains(word))) found.add(note);
    if (found.length == mostNotes) break;
  }
  return found;
}

/// The themes the palette offers, in Settings' order, each with the words after "Theme: ".
const List<(String, String)> _themes = [
  ('system', 'Follow the phone'),
  ('light', 'Light'),
  ('dark', 'Dark'),
  // The kit's named themes, as Settings offers them.
  ('dawn', 'Dawn'),
  ('boreal', 'Boreal'),
  ('ember', 'Ember'),
];

/// The commands for the app as it stands (`paletteCommands`). [query], what is typed so far, decides only which
/// notes are offered by name.
List<PaletteCommand> paletteCommands(PaletteWorld world, PaletteDoing doing, [String query = '']) {
  final out = <PaletteCommand>[];
  void add(String id, String label, String group, String keywords, VoidCallback run, {String? shortcut}) =>
      out.add(PaletteCommand(CommandDescriptor(id: id, label: label, group: group, keywords: keywords, shortcut: shortcut), run));

  // ---- the note on screen -----------------------------------------------------------------------------------------
  final note = world.note;
  if (note != null) {
    const here = 'This note';
    final name = _titleOf(note);
    // On a journal the mic is Speak an entry: an entry made and spoken, never words into the index.
    final speakInto = doing.speakInto;
    if (speakInto != null) {
      add('note:speak', note.journal ? 'Speak an entry' : 'Talk into this note', here, note.journal ? 'record voice dictate mic journal diary entry' : 'record voice dictate mic', () => speakInto(note.id));
    }
    final setView = doing.setView;
    if (setView != null) {
      final mixed = world.view == 'mixed';
      add('note:view', mixed ? 'Show it formatted' : 'Show the marks', here, 'markdown formatted preview read', () => setView(mixed ? 'formatted' : 'mixed'));
    }
    // The runs that were only said aloud, and the blanks, typed here as in the More sheet.
    final run = doing.noteAi;
    if (run != null) {
      add('note:fix', 'Fix spelling', here, 'ai spelling grammar punctuation typo correct', () => run(note.id, 'fix'));
      add('note:shape', 'Make a list', here, 'ai list tasks table shape organise', () => run(note.id, 'shape'));
      add('note:continue', 'Continue', here, 'ai carry on write more next', () => run(note.id, 'continue'));
      if (note.blanks > 0) add('note:fill', 'Fill the blanks', here, 'fill blank question answer ask ai square', () => run(note.id, 'fill'));
    }
    add('note:pin', world.pinned ? 'Unpin it from the top' : 'Pin it to the top', here, 'star favourite', () => doing.pin(note.id, !world.pinned));
    add('note:archive', 'Archive this note', here, 'hide file away', () => doing.archive(note.id));
    add('note:delete', 'Delete this note', here, 'remove bin trash', () => doing.remove(note.id));
    add('note:close', 'Close the $name tab', here, 'tab shut', () => doing.closeTab(note.id));
    for (final space in world.workspaces) {
      if (space.id == world.filedIn) continue;
      add('note:file:${space.id}', 'File it in ${space.name}', here, 'workspace move ${space.name}', () => doing.fileNote(note.id, space.id));
    }
    if (world.filedIn != null) {
      add('note:unfile', 'Take it out of its workspace', here, 'unfile workspace none inbox', () => doing.fileNote(note.id, null));
    }
    // Its tab's group: the way in on a phone, where a finger's hold on a tab is the drag, not a menu.
    final isTab = world.tabs.any((tab) => tab.id == note.id);
    final groupTab = doing.groupTab;
    if (isTab && groupTab != null) {
      add('tab:group:new', 'Put this tab in a new group', here, 'tab group new colour', () => groupTab(note.id));
    }
    final join = doing.joinTabGroup;
    if (isTab && join != null) {
      for (final g in world.tabGroups) {
        if (g.id == world.tabGroup) continue;
        add('tab:group:${g.id}', 'Put this tab in ${g.name}', here, 'tab group ${g.name}', () => join(note.id, g.id));
      }
    }
    final leave = doing.leaveTabGroup;
    if (isTab && (world.tabGroup ?? '').isNotEmpty && leave != null) {
      add('tab:group:leave', 'Take this tab out of its group', here, 'tab group ungroup remove', () => leave(note.id));
    }
  }

  // ---- making and going -------------------------------------------------------------------------------------------
  add('new', 'New note', 'Notes', 'write blank create add', doing.newNote, shortcut: '⌘N');
  // "book" and "chapters" stay among its words: a book was a notebook's name once.
  final newNotebook = doing.newNotebook;
  if (newNotebook != null) add('notebook', 'New notebook', 'Notes', 'book index pages chapters create', newNotebook);
  final newJournal = doing.newJournal;
  if (newJournal != null) add('journal', 'New journal', 'Notes', 'diary log dated entries daily', newJournal);
  final newEntry = doing.newEntry;
  if (newEntry != null) {
    for (final journal in world.journals.take(3)) {
      add('entry:${journal.id}', 'New entry in ${_titleOf(journal)}', 'Notes', 'journal diary today write entry', () => newEntry(journal.id));
    }
  }
  final speak = doing.speak;
  if (speak != null) add('speak', 'Speak a new note', 'Notes', 'record voice dictate mic talk', speak);
  add('list', 'Home', 'Notes', 'home list back dashboard start', doing.showList);
  add('notes', 'All notes', 'Notes', 'browse every grid cards library search archive', doing.browseNotes);
  final today = doing.today;
  if (today != null) add('today', 'Today’s note', 'Notes', 'daily day date journal today page', today, shortcut: '⇧⌘D');
  final tags = doing.tags;
  if (tags != null) add('tags', 'Tags', 'Notes', 'tag hashtag labels rename', tags);
  final openSmart = doing.openSmart;
  if (openSmart != null) {
    for (final smart in world.smartNotebooks) {
      add('smart:${smart.id}', 'Show ${smart.name}', 'Smart notebooks', 'smart notebook saved search ${smart.name}', () => openSmart(smart.id));
    }
  }

  // ---- the tabs ---------------------------------------------------------------------------------------------------
  for (final tab in world.tabs) {
    if (note != null && tab.id == note.id) continue;
    add('tab:${tab.id}', 'Go to ${_titleOf(tab)}', 'Open tabs', 'tab switch', () => doing.openNote(tab.id));
  }
  for (final tab in world.tabs) {
    if (note != null && tab.id == note.id) continue;
    add('tab:close:${tab.id}', 'Close ${_titleOf(tab)}', 'Open tabs', 'tab shut', () => doing.closeTab(tab.id));
  }
  if (world.canBack) add('back', 'Back', 'Open tabs', 'history previous', doing.back);
  if (world.canForward) add('forward', 'Forward', 'Open tabs', 'history next', doing.forward);

  // ---- workspaces -------------------------------------------------------------------------------------------------
  if (world.workspaces.isNotEmpty) {
    if (world.workspace != null) add('space:all', 'Show all notes', 'Workspaces', 'workspace every unfiltered', () => doing.chooseWorkspace(null));
    for (final space in world.workspaces) {
      if (space.id == world.workspace) continue;
      add('space:${space.id}', 'Show ${space.name}', 'Workspaces', 'workspace filter ${space.name}', () => doing.chooseWorkspace(space.id));
    }
  }

  // ---- every note -------------------------------------------------------------------------------------------------
  final open = {for (final tab in world.tabs) tab.id};
  for (final each in notesByName(world.notes, query)) {
    if (open.contains(each.id) || each.id == note?.id) continue;
    add('open:${each.id}', 'Open ${_titleOf(each)}', _noteGroup, _noteKeywords, () => (doing.openNoteWhereLeft ?? doing.openNote)(each.id));
  }

  // ---- how it looks -----------------------------------------------------------------------------------------------
  for (final (value, label) in _themes) {
    if (value == world.theme) continue;
    add('theme:$value', 'Theme: $label', 'Look', 'dark light appearance paper', () => doing.setTheme(value));
  }

  // ---- the app ----------------------------------------------------------------------------------------------------
  const app = 'Ghost.md';
  add('settings', 'Settings', app, 'preferences options account sync type animations', doing.settings);
  final notifications = doing.notifications;
  if (notifications != null) add('notifications', 'Notifications', app, 'bell invites invitations inbox feed unread claude', notifications);
  final organizations = doing.organizations;
  if (organizations != null) add('organizations', 'Organizations', app, 'teams team org members invite', organizations);
  final cheatSheet = doing.cheatSheet;
  if (cheatSheet != null) add('cheatsheet', 'Cheat sheet', app, 'marks markdown reference help', cheatSheet);
  final academy = doing.academy;
  if (academy != null) add('academy', 'Ghost.md Academy', app, 'learn lessons markdown teach', academy);
  final guide = doing.guide;
  if (guide != null) add('guide', 'The welcome walkthrough', app, 'guide walkthrough voice help onboarding how to talk', guide);

  return out;
}
