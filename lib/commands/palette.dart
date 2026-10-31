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
/// - Settings and the plugins are found here too, once something is typed (Matt, 2026-10-29: "Add the ability to
///   search settings and plugins from the command search"; settings_places.dart): under Settings and Plugins, in
///   bands of their own after every note and command ([CommandDescriptor.band]), each with where it is or how it
///   stands beside it. Given no [PaletteWorld.settings] or no [PaletteDoing.settingsAt], there are none, and the list
///   is the web's.
library;

import 'package:flutter/foundation.dart';
import 'package:glacier/glacier.dart' show CommandDescriptor;

import 'settings_places.dart';

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
    this.simple = false,
    this.focusMode = false,
    this.settings,
    this.tickets = const [],
    this.timing,
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

  /// Simple mode (GHST-103; Matt, 2026-10-17: "fancy features hidden behind more"): the palette keeps a new note,
  /// Speak, Home, All notes, Today's note, the tabs, Back, every note by name, the themes, Settings, the cheat
  /// sheet, the Academy and the walkthrough, and leaves out what simple mode has no page or icon for: a new
  /// notebook, journal or entry, the graph and a note's links, Ask Claude, Tags, the smart notebooks, a workspace's
  /// filter, a tab's groups, Forward, Notifications and Organizations. The doings are still given; the rule is
  /// here, so it is one rule and a test.
  final bool simple;

  /// Whether focus mode is on (lib/editor/focus/focus_mode.dart), so the command says which way it goes.
  final bool focusMode;

  /// What there is to find in Settings and among the plugins (settings_places.dart), asked for only once something
  /// is typed: the index reads every page's line and every setting the page lists.
  final ValueGetter<SettingsIndex>? settings;

  /// The tickets a timer can be started on (lib/book/timers.dart; Matt, 2026-10-31: "Start timer on HT-12"), newest
  /// first, and the one this device's timer runs on, if one does.
  final List<PaletteTicket> tickets;
  final PaletteTicket? timing;
}

/// A ticket, as a timer's command names it.
typedef PaletteTicket = ({String noteId, String key, String title});

/// What the palette can set off (`PaletteDoing`). Every one of these is something the app already does by hand. A
/// doing left null has no command.
@immutable
class PaletteDoing {
  const PaletteDoing({
    required this.openNote,
    this.openNoteWhereLeft,
    required this.newNote,
    this.newFromTemplate,
    this.newNotebook,
    this.newJournal,
    this.newEntry,
    this.speak,
    this.speakInto,
    required this.closeTab,
    this.startTimer,
    this.stopTimer,
    this.backUpNow,
    required this.showList,
    required this.browseNotes,
    required this.back,
    required this.forward,
    required this.settings,
    this.cheatSheet,
    this.changelog,
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
    this.graph,
    this.localGraph,
    this.noteLinks,
    this.today,
    this.askClaude,
    this.tags,
    this.market,
    this.trash,
    this.myTickets,
    this.triage,
    this.openSmart,
    this.setFocusMode,
    this.settingsAt,
    this.marketPlugin,
  });

  final void Function(String id) openNote;

  /// A note opened by name, from outside it: a book where it was left. Absent, [openNote].
  final void Function(String id)? openNoteWhereLeft;
  final VoidCallback newNote;

  /// New from template…: one of your templates chosen, and a note made from it (Matt, 2026-10-30). Absent, no command.
  final VoidCallback? newFromTemplate;

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

  /// A timer started on a ticket, and this device's stopped and logged (lib/book/timers.dart): absent where the app
  /// has no timers. Offered in simple mode too.
  final void Function(String noteId)? startTimer;
  final VoidCallback? stopTimer;

  /// Back up to git now (lib/plugins/git_backup; Matt, 2026-10-31), once the plugin is set up.
  final VoidCallback? backUpNow;
  final VoidCallback showList;

  /// The All notes grid.
  final VoidCallback browseNotes;
  final VoidCallback back;
  final VoidCallback forward;
  final VoidCallback settings;

  /// Settings at the cheat sheet. Required on the web.
  final VoidCallback? cheatSheet;

  /// Settings at the Changelog, every release and what changed in it (lib/changelog).
  final VoidCallback? changelog;

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

  /// The graph of every note and its links, a note's own local graph, and the notes that link to it (lib/links).
  final VoidCallback? graph;
  final void Function(String noteId)? localGraph;
  final void Function(String noteId)? noteLinks;
  /// Today's note, the Tags page, and a smart notebook's page (the port's own, 2026-10-16).
  final VoidCallback? today;

  /// Ask Claude (lib/claude/claude_chat.dart): the app's own Claude, with the person's API key.
  final VoidCallback? askClaude;
  final VoidCallback? tags;

  /// The Market: plugins, themes and fonts (lib/market/market_screen.dart); advanced mode's.
  final VoidCallback? market;
  final void Function(String id)? openSmart;

  /// The Trash, as a section of its own (lib/notes/trash_sheet.dart, 2026-10-23); offered in simple mode too.
  final VoidCallback? trash;

  /// My tickets, offered in simple mode too, and Triage (lib/tickets/ui/tickets_screen.dart; Matt, 2026-10-31).
  final VoidCallback? myTickets;
  final VoidCallback? triage;

  /// Focus mode on or off (Matt, 2026-10-27: "build ... focus mode"); offered in simple mode too, being one switch.
  final void Function(bool on)? setFocusMode;

  /// Settings at a page, and at a setting on it, brought into view and lit: what is found there (settings_places.dart).
  final void Function(String page, String? setting)? settingsAt;

  /// A plugin's page in the Market, for a plugin with no page in Settings; advanced mode's, as the Market is.
  final void Function(String id)? marketPlugin;
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
  ('sakura', 'Sakura'),
  ('meadow', 'Meadow'),
  ('tide', 'Tide'),
  ('dusk', 'Dusk'),
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
    final noteLinks = world.simple ? null : doing.noteLinks;
    if (noteLinks != null) add('note:links', 'Links to this note', here, 'backlinks linked from mentions references', () => noteLinks(note.id));
    final localGraph = world.simple ? null : doing.localGraph;
    if (localGraph != null) add('note:graph', 'Local graph of this note', here, 'graph links network neighbours map', () => localGraph(note.id));
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
    // Simple mode keeps tabs and leaves their groups out, as the tab's own menu does.
    final isTab = world.tabs.any((tab) => tab.id == note.id) && !world.simple;
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

  // ---- timers -----------------------------------------------------------------------------------------------------
  // The open ticket's first, then any ticket by its key or its title once "timer" or a key is typed.
  final startTimer = doing.startTimer;
  final timing = world.timing;
  final stopTimer = doing.stopTimer;
  if (timing != null && stopTimer != null) add('timer:stop', 'Stop the timer on ${timing.key}', 'Timers', 'timer stop log time tracking ${timing.title}', stopTimer);
  if (startTimer != null) {
    final open = note == null ? null : world.tickets.where((each) => each.noteId == note.id).firstOrNull;
    if (open != null && open.noteId != timing?.noteId) add('timer:start:${open.noteId}', 'Start timer on ${open.key}', 'Timers', 'timer start clock time tracking ${open.title}', () => startTimer(open.noteId));
    final typed = query.trim().toLowerCase();
    if (typed.contains('timer') || RegExp(r'[a-z][a-z0-9]{1,9}-\d').hasMatch(typed)) {
      var offered = 0;
      for (final each in world.tickets) {
        if (each.noteId == open?.noteId || each.noteId == timing?.noteId) continue;
        add('timer:start:${each.noteId}', 'Start timer on ${each.key} ${each.title}', 'Timers', 'timer start clock time tracking', () => startTimer(each.noteId));
        if ((offered += 1) == mostNotes) break;
      }
    }
  }

  // ---- making and going -------------------------------------------------------------------------------------------
  add('new', 'New note', 'Notes', 'write blank create add', doing.newNote, shortcut: '⌘N');
  if (doing.newFromTemplate case final fromTemplate?) add('new:template', 'New from template…', 'Notes', 'template pattern start bug meeting', fromTemplate);
  // "book" and "chapters" stay among its words: a book was a notebook's name once.
  final simple = world.simple;
  final newNotebook = simple ? null : doing.newNotebook;
  if (newNotebook != null) add('notebook', 'New notebook', 'Notes', 'book index pages chapters create', newNotebook);
  final newJournal = simple ? null : doing.newJournal;
  if (newJournal != null) add('journal', 'New journal', 'Notes', 'diary log dated entries daily', newJournal);
  final newEntry = simple ? null : doing.newEntry;
  if (newEntry != null) {
    for (final journal in world.journals.take(3)) {
      add('entry:${journal.id}', 'New entry in ${_titleOf(journal)}', 'Notes', 'journal diary today write entry', () => newEntry(journal.id));
    }
  }
  final speak = doing.speak;
  if (speak != null) add('speak', 'Speak a new note', 'Notes', 'record voice dictate mic talk', speak);
  add('list', 'Home', 'Notes', 'home list back dashboard start', doing.showList);
  add('notes', 'All notes', 'Notes', 'browse every grid cards library search archive', doing.browseNotes);
  final trash = doing.trash;
  if (trash != null) add('trash', 'Trash', 'Notes', 'deleted bin restore empty delete for good', trash);
  final myTickets = doing.myTickets;
  if (myTickets != null) add('my-tickets', 'My tickets', 'Tickets', 'assigned to me inbox mine tasks issues due overdue', myTickets);
  final triage = doing.triage;
  if (triage != null) add('triage', 'Triage', 'Tickets', 'new tickets inbox untriaged look at assign queue', triage);
  final graph = simple ? null : doing.graph;
  if (graph != null) add('graph', 'Graph of your notes', 'Notes', 'graph links network map backlinks', graph);
  final today = doing.today;
  if (today != null) add('today', 'Today’s note', 'Notes', 'daily day date journal today page', today, shortcut: '⇧⌘D');
  final askClaude = simple ? null : doing.askClaude;
  if (askClaude != null) add('ask-claude', 'Ask Claude', 'Ghost.md', 'claude ai anthropic assistant write chat ask', askClaude);
  // Back up to git now (lib/plugins/git_backup; Matt, 2026-10-31), in Simple too: a backup is never advanced.
  final backUpNow = doing.backUpNow;
  if (backUpNow != null) add('git-backup-now', 'Back up to git now', 'Ghost.md', 'git backup push commit repository github save', backUpNow);
  final tags = simple ? null : doing.tags;
  if (tags != null) add('tags', 'Tags', 'Notes', 'tag hashtag labels rename', tags);
  final openSmart = simple ? null : doing.openSmart;
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
  if (world.canForward && !simple) add('forward', 'Forward', 'Open tabs', 'history next', doing.forward);

  // ---- workspaces -------------------------------------------------------------------------------------------------
  // Simple mode has no workspace filter on its home page, so none here; filing a note in one stays, above.
  if (world.workspaces.isNotEmpty && !simple) {
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
  final setFocusMode = doing.setFocusMode;
  if (setFocusMode != null) {
    final on = world.focusMode;
    add('focus', on ? 'Leave focus mode' : 'Focus mode', 'Look', 'focus typewriter dim zen distraction free writing concentrate centre center', () => setFocusMode(!on));
  }

  // ---- the app ----------------------------------------------------------------------------------------------------
  const app = 'Ghost.md';
  add('settings', 'Settings', app, 'preferences options account sync type animations', doing.settings);
  final market = simple ? null : doing.market;
  if (market != null) add('market', 'Market', app, 'plugins plugin extensions integrations add-ons store browse install themes fonts typeface', market);
  final notifications = simple ? null : doing.notifications;
  if (notifications != null) add('notifications', 'Notifications', app, 'bell invites invitations inbox feed unread claude', notifications);
  final organizations = simple ? null : doing.organizations;
  if (organizations != null) add('organizations', 'Organizations', app, 'teams team org members invite', organizations);
  final cheatSheet = doing.cheatSheet;
  if (cheatSheet != null) add('cheatsheet', 'Cheat sheet', app, 'marks markdown reference help', cheatSheet);
  final changelog = doing.changelog;
  if (changelog != null) add('changelog', 'What’s new', app, "changelog what's new whats new releases updates version history", changelog);
  final academy = doing.academy;
  if (academy != null) add('academy', 'Ghost Academy', app, 'learn lessons markdown teach', academy);
  final guide = doing.guide;
  if (guide != null) add('guide', 'The welcome walkthrough', app, 'guide walkthrough voice help onboarding how to talk', guide);

  // ---- Settings and the plugins -----------------------------------------------------------------------------------
  // Only for something typed, in bands after everything above, so a setting named as a command is put after it.
  final index = world.settings;
  final settingsAt = doing.settingsAt;
  if (index != null && settingsAt != null && query.trim().isNotEmpty) {
    final market = simple ? null : doing.marketPlugin;
    for (final place in findPlaces(index(), query, market: market != null)) {
      final group = place.ofPlugins ? settingsPluginsGroup : settingsGroup;
      final page = place.page;
      final plugin = place.plugin;
      final VoidCallback run = page != null ? () => settingsAt(page, place.setting) : () => market!(plugin!);
      out.add(PaletteCommand(
        CommandDescriptor(id: place.id, label: place.label, group: group, keywords: placeKeywords(place, group, query), band: place.ofPlugins ? 2 : 1, detail: place.detail),
        run,
      ));
    }
  }

  return out;
}

/// The headings of what is found in Settings and among the plugins.
const String settingsGroup = 'Settings';
const String settingsPluginsGroup = 'Plugins';
