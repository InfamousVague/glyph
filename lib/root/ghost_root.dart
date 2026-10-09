import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/ui_state.dart';
import '../art/art.dart';
import '../book/book_spot.dart' show whereLeft;
import '../book/entry_starts.dart' show pageBody;
import '../book/journal.dart' as journal;
import '../book/journal_view.dart' show JournalPages;
import '../book/new_book_sheet.dart';
import '../book/tickets.dart';
import '../canvas/json_canvas.dart' show Canvas, canvasNoteBody;
import '../commands/app_commands.dart';
import '../commands/command_bar.dart';
import '../core/book.dart';
import '../core/canvas_body.dart';
import '../core/core_library.dart';
import '../core/images.dart';
import '../core/kept_trash.dart';
import '../core/kept_workspaces.dart';
import '../core/native/core.dart';
import '../core/native/files.dart';
import '../core/note.dart';
import '../core/note_folders.dart';
import '../core/note_text.dart';
import '../core/preferences.dart';
import '../core/properties.dart';
import '../core/query/query.dart' show TicketDraft;
import '../core/sample_library.dart';
import '../core/stored.dart';
import '../core/trash.dart';
import '../core/untouched.dart';
import '../core/versions_record.dart';
import '../core/versions_store.dart';
import '../core/workspaces.dart';
import '../editor/queries/queries.dart' show NoteChange;
import '../home/home_layout.dart';
import '../home/home_screen.dart';
import '../launch/launch_screen.dart';
import '../note/note_builder.dart';
import '../note/note_screen.dart' show withFrontMatterTitle;
import '../notes/all_notes_screen.dart';
import '../notes/new_sheet.dart';
import '../notes/note_actions.dart';
import '../notes/note_menu.dart';
import '../notes/note_templates.dart';
import '../notes/own_templates.dart' hide templateOf;
import '../notes/note_tree.dart';
import '../notes/notes_drawer.dart';
import '../notes/notifications_drawer.dart';
import '../notes/workspace_sheet.dart';
import '../orgs/ui/fed_notifications.dart';
import '../orgs/ui/join_sheet.dart';
import '../orgs/ui/new_organization_sheet.dart';
import '../orgs/ui/org_news.dart';
import '../orgs/ui/organization_log.dart';
import '../orgs/ui/organization_screen.dart';
import '../settings/organization_sheet.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_sheet.dart';
import '../shell/account_gate.dart';
import '../shell/app_shell.dart';
import '../shell/screen.dart';
import '../shell/top_bar.dart';
import 'account_wiring.dart';
import 'library_reads.dart';
import 'note_desk.dart';
import 'take_back.dart';

/// The app, put together: what the web app's `App.tsx` does once its screens exist. The launch screen over the
/// shell (lib/shell/app_shell.dart); in the shell the home page, the notes' sidebar as a card or docked, and the
/// notifications; over it Settings and a workspace's sheet; and the art in the seams each of them left for it.
///
/// What it stands on:
/// - **The library** is the Rust core's ([core], lib/core/core_library.dart): the notes are Markdown files in the app's
///   own folder, as the Tauri app keeps them; the workspaces and the trash are preferences; a fresh library is given
///   the starter notes once. Without a core (a test, a picture) it is the store screenshots' invented library in memory.
/// - **A note's own screen** is lib/note's, over the editor (lib/editor) with every piece of it, put together for
///   each open note by lib/root/note_desk.dart: its boards, queries and tickets, and the canvas, the notebook's index
///   and the journal's entries that take the page for a note that is not words. What those read of the library is
///   lib/root/library_reads.dart; what they ask of the app (a title opened in a notebook's tab, a page, a ticket or
///   a canvas made from an index, a journal's new entry, another note written from a query) is here, as it is in
///   App.tsx.
/// - **The +** opens the sheet of what it makes (lib/notes/new_sheet.dart): a note, opened ready to type on a blank
///   page that offers names and templates, a canvas, a notebook or a journal (lib/book/new_book_sheet.dart), or an
///   entry in the journal written in last.
/// - **The account** is made only where the build was told its service ([account], lib/root/account_wiring.dart):
///   then the shell, Settings and a note's sharing are under one [AccountScope], the organizations have their
///   pages, the notifications are the feed's, and the way in is the first thing on screen once. With none there
///   is no account object anywhere, and every screen is the signed-out one.
/// - **Speak** is not here yet (stage 8), nor a link that opens the app (no `LinkSource`: an invite is joined
///   from its notification or by its code held from before).
class GhostRoot extends StatefulWidget {
  const GhostRoot({super.key, this.sheet, this.core, this.library, this.workspaces, this.stored, this.clock, this.launch = true, this.account, this.services, this.untouched});

  /// The app's token sheet, which the shell stamps its layout over: the theme's own unless given.
  final TokenSheet? sheet;

  /// The Rust core (lib/core/native): given, the notes are the real library's files, and the workspaces and the
  /// trash are kept in the preferences as on the web. Absent, everything is in memory over the invented library.
  final CoreInvoke? core;

  /// The notes, where a test brings its own.
  final NoteLibrary? library;
  final WorkspaceStore? workspaces;

  /// Where this device keeps how its sidebar was left; the app's own (core/stored.dart) unless given.
  final Stored? stored;

  /// The time, for a picture that must say the same "2 hr ago" every day.
  final int Function()? clock;

  /// Whether the app opens behind its launch screen. A test's picture of a screen does not.
  final bool launch;

  /// Where this build's account service is, with the crypto to reach it (lib/root/account_wiring.dart). Absent,
  /// as in every build not given `GHOST_API`, there is no account at all. It needs the [core].
  final AccountMaking? account;

  /// The account's objects, where a test brings its own; then nothing is made from [account].
  final AccountServices? services;

  /// The records of the notes nobody has written in yet (core/untouched.dart); the app's own unless a test brings
  /// its own.
  final UntouchedNotes? untouched;

  @override
  State<GhostRoot> createState() => _GhostRootState();
}

class _GhostRootState extends State<GhostRoot> {
  late final bool _real = widget.core != null && widget.library == null;
  late final NoteLibrary _library = widget.library ?? (_real ? CoreLibrary(widget.core!) : SampleLibrary.seeded(now: DateTime.now().millisecondsSinceEpoch));
  late final Trash _trash = _real ? KeptTrash() : MemoryTrash();
  late final WorkspaceStore _workspaces = widget.workspaces ??
      (_real
          ? WorkspaceStore(storage: KeptWorkspaceStorage(), trash: _trash, onFiled: NoteFolders(_library).fileNotesInFolder)
          : WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces()), trash: _trash));
  late final VersionsStore _versionsStore = VersionsStore(widget.core, kept: _stored);
  late final VersionsRecord _versions = VersionsRecord(store: _versionsStore, preferences: preferences, workspaces: _workspaces);

  /// The kept pictures, where there is a core to keep them.
  late final CorePictureStore? _pictures = widget.core == null ? null : CorePictureStore(CoreFiles(widget.core!));

  /// The account made for this build, where it was told its service and has a library of its own to sync.
  late final WiredAccount? _wired = widget.services == null && widget.account != null && _real
      ? WiredAccount.make(
          making: widget.account!,
          core: widget.core!,
          workspaces: _workspaces,
          versions: _versionsStore,
          touched: _library is CoreLibrary ? (_library).touched : null,
          refresh: _library.refresh,
          shownNotes: () => _shown,
          kept: _stored,
          onPicture: (name) => _pictures?.arrived(name),
        )
      : null;
  late final AccountServices? _services = widget.services ?? _wired?.services;

  /// Whether the way into an account is up (shell/account_gate.dart): made once what this device kept is read.
  AccountGateState? _gate;
  AppLifecycleListener? _life;

  /// An organization's settings, and the sheet a new one is named in.
  ({String id, OrganizationFrom from})? _organization;
  bool _newOrganization = false;

  void _say(BuildContext context, String message) => GlacierToast.of(context).toast(message: Text(message));

  /// What the note on screen reads of the library, read once per change to the notes (lib/root/library_reads.dart).
  late final LibraryReads _reads = LibraryReads(shown: () => _shown, all: () => _library.value);
  late final Listenable _libraryChanges = Listenable.merge([_library, _trash]);

  /// The journal on screen, writing its own index (`journalWriter`), and New entry's half of the library.
  journal.JournalWriter? _journalWriter;
  late final UntouchedNotes _untouched = widget.untouched ?? untouchedNotes;
  late final JournalPages _pages = JournalPages(
    _library,
    untouched: _untouched,
    write: (journalId, change) {
      final writer = _journalWriter;
      if (writer == null || writer.id != journalId || _shell.currentState?.shown != journalId) return false;
      writer.write(change);
      return true;
    },
  );

  /// An entry, or a new note given a name or a template, that nobody wrote in, taken back once it is left
  /// (lib/root/take_back.dart). It stays while it is the note on screen, while a capture is aimed at it, and while
  /// its tab is open behind another note, a capture or a meeting (`stays`).
  late final TakeBack _takeBack = TakeBack(
    library: _library,
    trash: _trash,
    untouched: _untouched,
    stays: (id) {
      final shell = _shell.currentState;
      if (shell == null) return false;
      final now = shell.screen;
      if (now is ScreenNote && now.note.id == id) return true;
      if (now is ScreenCapture && now.noteId == id) return true;
      return shell.tabs.open.contains(id) && (now is ScreenNote || now is ScreenCapture || now is ScreenMeeting);
    },
    writeJournal: _pages.writeJournal,
    dropTab: (id) => _shell.currentState?.dropTab(id),
  )..making = _pages.making;

  /// The + sheet, the workspace it makes into where it was an organization's +, and the New notebook sheet with its
  /// own.
  bool _newSheet = false;
  String? _newInto;
  NewBookKind? _bookSheet;
  String? _bookInto;

  static final Canvas _emptyCanvas = Canvas(nodes: const [], edges: const []);

  /// The note on screen, as the library has it.
  Note? get _onScreen {
    final id = _shell.currentState?.shown;
    return id == null ? null : _library.noteOf(id);
  }

  /// Once the shell has been handed the library as it is now: it opens only what it has.
  void _afterFrame(void Function(AppShellState shell) then) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shell = _shell.currentState;
      if (mounted && shell != null) then(shell);
    });
    if (mounted) setState(() {});
  }

  /// A note just made (`showMade`): filed in the workspace being looked at, and in [into] where it was made from an
  /// organization's +, and shown, in a tab of its own or, [within], in the tab of the note on screen. [fresh] is a
  /// new note of the person's own, whose blank page offers names and templates until they write in it.
  Note _showMade(String body, {Caret? caret, String? into, bool within = false, bool fresh = false}) {
    final note = _library.create(body);
    if (fresh) _untouched.markFresh(note.id);
    _workspaces.fileNewNote(note.id);
    if (into != null) _workspaces.fileNote(note.id, into);
    _afterFrame((shell) => within ? shell.openNoteWithin(note.id, caret: caret) : shell.openNote(note.id, caret: caret));
    return note;
  }

  /// `[[A title]]` tapped (`openTitle`): the note by that title, or a new note that starts with it as its heading.
  /// A link to a notebook, from outside it, goes back to where the notebook was left.
  void _openTitle(String title, [String? anchor]) {
    final shell = _shell.currentState;
    if (shell == null) return;
    final found = anchor == null ? _reads.titled(title) : null;
    final there = found == null ? null : whereLeft(found, _shown, shell.shown, on: _stored);
    if (there != null && found != null && there.id != found.id) return shell.openNote(there.id);
    _openTitleFrom(title, at: anchor);
  }

  /// [make] is what a note made for a title nobody has written yet starts as: a heading, or an empty canvas
  /// (`openTitleFrom`).
  void _openTitleFrom(String title, {String? at, String Function(String named)? make, bool within = false}) {
    final shell = _shell.currentState;
    if (shell == null) return;
    final found = _reads.titled(title);
    if (found != null) return within ? shell.openNoteWithin(found.id) : shell.openNote(found.id, at: at);
    final named = title.trim();
    if (named.isEmpty) return;
    _showMade(make?.call(named) ?? '# $named\n\n', within: within);
  }

  /// A title opened from inside a notebook: in the current tab's place. Inside a Templates notebook a line is a
  /// template's page, the marked note of its name, and never a note of the person's that shares it
  /// (`openTitleWithin`).
  void _openTitleWithin(String title) {
    final on = _onScreen;
    if (on != null && isTemplatesBody(on.body)) return _openTemplatePage(title);
    _openTitleFrom(title, within: true);
  }

  /// A template's page by its name, the oldest of it, made where there is none: marked, named by its `title:`, its
  /// heading left open for a note's name (`openTemplatePage`).
  void _openTemplatePage(String title) {
    Note? found;
    for (final note in _shown) {
      if ((note.archivedAt ?? 0) != 0 || !isTemplatePageBody(note.body) || !sameTitle(noteTitle(note.body), title)) continue;
      if (found == null || note.createdAt < found.createdAt) found = note;
    }
    if (found != null) return _shell.currentState?.openNoteWithin(found.id);
    _showMade(newTemplatePageBody(title), within: true);
  }

  /// A notebook's new page from a template, opened from its index in the notebook's tab (`openPageWithin`).
  void _openPageWithin(String title, String template) {
    final on = _onScreen;
    if (on != null && isTemplatesBody(on.body)) return _openTemplatePage(title);
    final notebook = on == null ? '' : noteTitle(on.body);
    _openTitleFrom(title, within: true, make: (named) => pageBody(named, template, notebook));
  }

  /// Every other note's title key, archived and in the Trash too (`takenTitles`).
  Set<String> get _takenTitles {
    final shown = _shell.currentState?.shown;
    return {
      for (final note in _library.value)
        if (note.id != shown) titleKey(noteTitle(note.body)),
    }..remove('');
  }

  /// A ticket made in a notebook, from its index's New ticket (`openTicketWithin`): the notebook's next key, read
  /// across every note the store has, the Trash's too, so no number is given twice; its workflow's first open
  /// status; and its template filled for it, or its title alone.
  void _openTicketWithin(String title, String notebook, NoteTemplate? template) {
    final id = nextTicketId(notebook, [for (final note in _library.value) note.body]);
    final words = template == null ? null : fillNoteTemplate(template, DateTime.now(), _takenTitles, nextId: id, title: title).body;
    _openTitleFrom(title, within: true, make: (named) => newTicketBody(named, id: id, statuses: statusesOf(notebook), words: words));
  }

  /// A canvas by that title opened from a notebook's index, made first if there is none (`openCanvasWithin`).
  void _openCanvasWithin(String title) => _openTitleFrom(title, within: true, make: (named) => canvasNoteBody(named, _emptyCanvas));

  /// A change to another note's words, from a query or a notebook's index (`tickFromQuery`, `moveFromQuery`): the
  /// note as the store has it now, changed, and the notes read again. A line or a note gone is left alone.
  Future<void> _writeNote(String id, NoteChange change) async {
    try {
      final note = await _library.get(id);
      final next = note == null ? null : change(note.body);
      if (note == null || next == null || next == note.body) return;
      await _library.update(id, next, note.revision);
      await _library.refresh();
    } catch (_) {
      // Another writer got there first: the query is drawn again from what the store has.
      await _library.refresh().catchError((Object _) {});
    }
  }

  /// A ticket typed at the + of a lane of a query's board (`addFromQuery`). Its notebook is the one `from: [[…]]`
  /// names, else the one the board's own note is in: the notebook's next key and its workflow, then the lane's value
  /// and what the query insists on, so it lands in the lane it was typed in. Its page goes in the notebook's index
  /// and it is filed where the notebook is. It is not opened. Answers true where the board's own note is the
  /// notebook, whose index the board's editor writes.
  Future<bool> _addFromQuery(TicketDraft draft, String title, String? from) async {
    final live = [
      for (final note in _shown)
        if ((note.archivedAt ?? 0) == 0) note,
    ];
    if (live.any((note) => sameTitle(noteTitle(note.body), title))) {
      _say(context, 'There is already a note called “$title”.');
      return false;
    }
    final link = draft.link;
    final linked = link == null ? null : live.where((note) => sameTitle(noteTitle(note.body), link)).firstOrNull;
    final board = from == null ? null : live.where((note) => note.id == from).firstOrNull;
    final notebook = linked != null && isBookBody(linked.body) ? linked : (board == null ? null : notebookFinder(live)(board));
    final id = notebook != null && notebookKey(notebook.body) != null ? nextTicketId(notebook.body, [for (final note in _library.value) note.body]) : null;
    var body = newTicketBody(title, id: id, statuses: statusesOf(notebook?.body));
    for (final (field, value) in draft.fields) {
      body = withProperty(body, field, value);
    }
    if (draft.labels.isNotEmpty) body = withProperty(body, 'labels', draft.labels);
    // `from: [[A note]]` that is no notebook lists the notes linking to it: so this one does.
    if (linked != null && linked.id != notebook?.id) body = '${body.replaceFirst(RegExp(r'\n*$'), '')}\n\n[[${noteTitle(linked.body)}]]\n';
    final made = await _library.createNote(body);
    final space = (notebook == null ? null : _workspaces.workspaceOf(notebook.id)) ?? (from == null ? null : _workspaces.workspaceOf(from));
    if (space != null) {
      _workspaces.fileNote(made.id, space.id);
    } else {
      _workspaces.fileNewNote(made.id);
    }
    final here = notebook != null && notebook.id == from;
    if (notebook != null && !here) {
      final fresh = await _library.get(notebook.id);
      if (fresh != null) await _library.update(fresh.id, withChapter(fresh.body, title), fresh.revision).then<void>((_) {}, onError: (Object _) {});
    }
    await _library.refresh();
    return here;
  }

  /// A journal's New entry (`newEntry`): a note named by the minute, started from the template chosen or the
  /// journal's own, its line put last in the journal's index, opened with the caret at its end: in the journal's
  /// tab from inside the journal, a tab of its own from anywhere else.
  Future<void> _newEntry(String journalId, [String? template]) async {
    final within = _shell.currentState?.shown == journalId;
    final note = await _pages.newEntry(journalId, template: template);
    if (note == null) return;
    if (!mounted) {
      _pages.making.remove(note.id);
      return;
    }
    _workspaces.fileNewNote(note.id);
    // Being made until it is on screen: the take-back leaves it alone meanwhile.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pages.making.remove(note.id));
    _afterFrame((shell) => within ? shell.openNoteWithin(note.id, caret: const Caret.end()) : shell.openNote(note.id, caret: const Caret.end()));
  }

  /// The + sheet's row for a new entry (`entryRow`): in the journal on screen, or the journal of the entry on
  /// screen, before the one written in last.
  NewSheetEntry? _entryRow() {
    final journals = _reads.journals;
    if (journals.isEmpty) return null;
    final on = _onScreen;
    final place = on == null ? null : _reads.placeInBook(on);
    final chosen = journals.where((note) => note.id == on?.id).firstOrNull ??
        (place != null && place.journal ? journals.where((note) => note.id == place.book.id).firstOrNull : null) ??
        journals.first;
    final usual = journal.templateOf(chosen.body);
    final name = noteTitle(chosen.body);
    return NewSheetEntry(
      journal: name.isEmpty ? 'Untitled journal' : name,
      hint: journal.templateSentence(usual),
      usual: usual,
      // The usual row sends no template: the entry is made from the journal as the store has it now.
      onPress: (template) => unawaited(_newEntry(chosen.id, template)),
    );
  }

  /// What can be a page of a new notebook (`pageTitles`): every note's title but the notebooks' own, and none of a
  /// journal's entries, which belong to their journal.
  List<String> _pageTitles({bool books = true}) => [
        for (final note in _shown)
          if ((books || !isBookBody(note.body)) && !_reads.entryIds.contains(note.id) && noteTitle(note.body).trim().isNotEmpty) noteTitle(note.body),
      ];

  /// Your templates, the blank page's last card (`openTemplates`): the Templates notebook, opened in the blank
  /// note's tab. The first time there is none, and it is made with the built-ins as its pages, the pages first and
  /// the notebook last, so a press cut short makes only what is missing the next time. Not filed: they are the
  /// app's pages until the person changes them. A second press while it is being made is the same press.
  bool _seeding = false;
  Future<void> _openTemplates() async {
    if (_seeding) return;
    _seeding = true;
    try {
      final plan = seedPlan(outOfTrash(_library.value, _trash.value));
      final open = plan.open;
      if (open != null) return _shell.currentState?.openNoteWithin(open.id);
      for (final template in plan.pages.reversed) {
        await _library.createNote(templatePageBody(template));
      }
      final book = await _library.createNote(plan.index!);
      await _library.refresh();
      _afterFrame((shell) => shell.openNoteWithin(book.id));
    } catch (_) {
      await _library.refresh().catchError((Object _) {});
      if (mounted) _say(context, 'Your templates could not be made. Try again.');
    } finally {
      _seeding = false;
    }
  }

  late final NoteDeskWorld _desk = NoteDeskWorld(
    titles: () => [
      for (final note in _shown)
        if (noteTitle(note.body).isNotEmpty) noteTitle(note.body),
    ],
    known: (title) => _reads.titled(title) != null,
    open: _openTitle,
    bodyOf: (title) => _reads.titled(title)?.body,
    pictures: _pictures,
    services: _services,
    changes: _libraryChanges,
    queryNotes: () => _reads.queryNotes,
    // A note a query listed, opened: the note itself, or a to-do's note at its line.
    openAt: (id, line) => _shell.currentState?.openNote(id, at: line == null ? null : 'line:${line + 1}'),
    write: (id, change) => unawaited(_writeNote(id, change)),
    addTicket: _addFromQuery,
    // `[[GHO-12]]` finds the ticket by its key too.
    tickets: (id) => _reads.ticketOptions(id, open: _openTitle),
    openWithin: _openTitleWithin,
    openCanvas: _openCanvasWithin,
    openPage: _openPageWithin,
    openTicket: _openTicketWithin,
    ticketTemplates: () => _reads.ticketTemplates,
    pageTitles: _pageTitles,
    noteOf: (title) => _reads.titled(title),
    newEntry: (id, template) => unawaited(_newEntry(id, template)),
  );

  /// A note's screen with its editor: one desk to an open note (lib/root/note_desk.dart).
  Widget _note(BuildContext context, AppShellState shell, ScreenNote screen) => NoteDesk(
        key: ValueKey('desk:${screen.note.id}'),
        noteId: screen.note.id,
        title: noteTitle(screen.note.body),
        world: _desk,
        readOnly: _trash.isTrashed(screen.note.id),
        say: (message) => _say(context, message),
        builder: (context, editor, seams) => noteScreenBuilder(
          library: _library,
          workspaces: _workspaces,
          actions: () => _actions,
          versions: _versions,
          trash: _trash,
          device: _stored,
          untouched: _untouched,
          editor: editor,
          seams: seams,
          say: _say,
          bookOf: _reads.placeInBook,
          templates: () => _reads.ownTemplates,
          onTemplates: () => unawaited(_openTemplates()),
          // Taken back by the next journal's own: one screen is gone only after the next has come.
          onJournal: (writer) => _journalWriter = writer ?? _journalWriter,
        )(context, shell, screen),
      );
  NoteActions? _made;

  /// Pin, archive, delete and their Undo (notes/note_actions.dart); made once there is a toast to say them with.
  NoteActions get _actions => _made ??= NoteActions(library: _library, workspaces: _workspaces, trash: _trash, say: NoteActions.toaster(context))..addListener(_changed);

  void _changed() {
    _reads.changed();
    if (mounted) setState(() {});
  }

  List<Note> get _shown => [
        for (final note in outOfTrash(_library.value, _trash.value))
          if (!(_made?.hidden.contains(note.id) ?? false)) note,
      ];
  List<Note> get _trashed => inTrash(_library.value, _trash.value);
  late final Stored _stored = widget.stored ?? stored;
  late final Listenable _all = Listenable.merge([_library, _workspaces, _trash, preferences, _services?.changes]);

  final GlobalKey<AppShellState> _shell = GlobalKey<AppShellState>();
  final GlobalKey<CommandBarState> _commands = GlobalKey<CommandBarState>();

  /// Settings asked for at a page, by when it was asked (settings/settings_sheet.dart `toPage`).
  SettingsTarget? _settingsPage;

  void _search() => _commands.currentState?.show();

  /// A note's menu, from a long press or a right-click on it in any list (notes/note_menu.dart).
  final NoteMenuController _menu = NoteMenuController();

  late bool _launching = widget.launch;
  bool get _read => !_library.loading;
  bool _settings = false;

  /// The workspace sheet: shut, a new one, or one to change.
  ({Workspace? editing})? _workspace;

  /// The smoke at the edges is the art's own switch (lib/art/wisp_settings.dart), which follows the preference.
  void _smoke() => WispSettings.instance.wanted = preferences.value.wispEdge;

  @override
  void dispose() {
    preferences.removeListener(_smoke);
    _libraryChanges.removeListener(_reads.changed);
    _life?.dispose();
    _gate?.dispose();
    _wired?.dispose();
    _pictures?.dispose();
    _made?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _smoke();
    preferences.addListener(_smoke);
    _libraryChanges.addListener(_reads.changed);
    _open();
    unawaited(_account());
  }

  /// What this device kept of an account, then the sync for as long as the app is open, and the way in where it is
  /// due. Nothing at all in a build with no account.
  Future<void> _account() async {
    final services = _services;
    if (services == null) return;
    final wired = _wired;
    if (wired != null) {
      await wired.start();
      _life = AppLifecycleListener(onResume: wired.resumed);
    }
    if (!mounted) return;
    setState(() => _gate = AccountGateState(services: services, kept: _stored)..addListener(_changed));
  }

  void _toAccount() => setState(() {
        _settings = true;
        _settingsPage = SettingsTarget('account', nonce: DateTime.now().microsecondsSinceEpoch);
      });

  /// A canvas or a notebook renamed from its tab: its `title:` written, as the More sheet's name does.
  void _rename(String id, String title) {
    final note = _library.noteOf(id);
    if (note == null) return;
    final named = withFrontMatterTitle(note.body, title);
    if (named != note.body) unawaited(_library.save(id, named).then<void>((_) {}, onError: (Object _) {}));
  }

  Widget _organizationPage(BuildContext context, AppShellState shell, ScreenOrganization screen) {
    final id = screen.orgId;
    final wisp = preferences.value.wispEdge;
    if (screen.page == OrganizationPage.log) {
      return OrganizationLog(services: _services, orgId: id, notes: shell.notes, onBack: () => shell.openOrganization(id), onOpenNote: shell.openNote, record: _versions, wisp: wisp);
    }
    return OrganizationScreen(
      services: _services,
      orgId: id,
      notes: shell.notes,
      onBack: shell.backToList,
      onOpenNote: shell.openNote,
      onNew: () => _plus(orgWorkspaceId(id)),
      onAllNotes: () {
        _workspaces.chooseWorkspace(orgWorkspaceId(id));
        shell.backToList();
      },
      onSettings: () => setState(() => _organization = (id: id, from: OrganizationFrom.dashboard)),
      onOpenOrganization: shell.openOrganization,
      onLog: () => shell.openOrganizationLog(id),
      onAccount: _toAccount,
      wisp: wisp,
    );
  }

  /// Reads the library, and gives a fresh one the starter notes once (core/seed.ts: `glyph-sample-note`).
  Future<void> _open() async {
    await _library.load();
    // At launch, which opens on the home page: what the phone let go of before it was left.
    if (mounted) unawaited(_takeBack.look());
    if (!_real || !mounted) return;
    final seeded = _stored.flag('glyph-sample-note', unreadable: true);
    if (seeded.isMarked) return;
    seeded.mark();
    if (_library.value.isNotEmpty) return;
    for (final note in starterNotes(DateTime.now().millisecondsSinceEpoch)) {
      await _library.createNote(note.body);
    }
  }

  /// The screen or the open tabs changed: a look at what was left (`takeBack`'s effect). After the frame, when the
  /// shell says where the person is now.
  bool _looking = false;
  void _left() {
    if (_looking) return;
    _looking = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _looking = false;
      if (mounted) unawaited(_takeBack.look());
    });
  }

  void _delete(String id) {
    final note = _library.noteOf(id);
    if (note != null) _actions.remove(note);
  }

  /// The + (`setNewSheet(true)`): the sheet of what it makes, one for every +, so the choice reads the same
  /// wherever it is offered. From an organization's +, what is made is filed in its workspace ([into]).
  void _plus([String? into]) => setState(() {
        _newInto = into;
        _newSheet = true;
      });

  /// A new note (`newNote`): opened ready to type, the caret in line 1 and the editor focused, and fresh, so its
  /// blank page offers names and templates until the person writes in it.
  void _new([String? into]) => _showMade('', caret: const Caret.at(0), fresh: true, into: into);

  /// A canvas from the + (`newCanvas`).
  void _newCanvas([String? into]) => _showMade(canvasNoteBody('Untitled canvas', _emptyCanvas), into: into);

  /// A notebook from the +, or a journal from the same sheet with Journal chosen (`newBook`, `newJournal`).
  void _newBook(NewBookKind kind, [String? into]) => setState(() {
        _bookInto = into;
        _bookSheet = kind;
      });

  List<String> _notesIn(String workspaceId) => [
        for (final note in _library.value)
          if (_workspaces.value.of[note.id] == workspaceId) note.id,
      ];

  Widget _tree(AppShellState shell, {VoidCallback? onClose}) {
    return NoteTree(
      notes: shell.notes,
      activeId: shell.shown,
      workspaces: _workspaces,
      stored: _stored,
      onOpen: (id) {
        onClose?.call();
        shell.openNote(id);
      },
      onNew: () {
        onClose?.call();
        _plus();
      },
      onClose: onClose,
      onCommands: _search,
      onSettings: () {
        onClose?.call();
        setState(() => _settings = true);
      },
      trashed: _trashed,
      onRestore: _actions.restore,
      onDestroy: _actions.destroy,
      onEmptyTrash: () => _actions.emptyTrash(_trashed),
      notesInWorkspace: _notesIn,
      onTrashNotes: (ids) => ids.forEach(_trash.trashNote),
      emptyArt: const Ghost(scene: GhostScene.noNotes),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _all,
      builder: (context, _) {
        final prefs = preferences.value;
        final services = _services;
        final signedIn = services?.signedIn ?? false;
        final gate = _gate;
        // The organization the home page is filtered to, for its news.
        final chosen = _workspaces.value.current?.id;
        String? chosenOrg;
        for (final org in services?.joined ?? const []) {
          if (orgWorkspaceId(org.id) == chosen) chosenOrg = org.id;
        }
        return AccountScope(
          services: services,
          child: Stack(
          fit: StackFit.expand,
          children: [
            AppShell(
              key: _shell,
              sheet: widget.sheet ?? context.tokens.sheet,
              notes: _shown,
              topBar: TopBarStyle.parse(prefs.topBar),
              sidebarStyle: prefs.sidebarStyle == 'docked' ? SidebarStyle.docked : SidebarStyle.popover,
              workspaces: _workspaces.value,
              organizations: signedIn ? services!.joined : const [],
              organizationBuilder: services == null ? null : _organizationPage,
              onRenameNote: _rename,
              openNotes: prefs.openNotes,
              tabGroups: prefs.tabGroups,
              // The screen and the tabs are what an entry is left by.
              onOpenNotesChanged: (open) {
                preferences.update((now) => now.copyWith(openNotes: open));
                _left();
              },
              onScreenChanged: (_) => _left(),
              untouchedEntryOf: (id) => _untouched.recordOf(id)?.journalId,
              onTabGroupsChanged: (groups) => preferences.update((now) => now.copyWith(tabGroups: groups)),
              onSettings: () => setState(() => _settings = true),
              // The people icon with no organization joined, and the picker's last row: Settings › Organizations.
              onOrganizations: () => setState(() {
                _settings = true;
                _settingsPage = SettingsTarget('organizations', nonce: DateTime.now().microsecondsSinceEpoch);
              }),
              onNew: _plus,
              onDeleteNote: _delete,
              onRefresh: () => _library.refresh(),
              noteBuilder: _note,
              homeBuilder: (context, shell) => HomeScreen(
                notes: shell.notes,
                loading: !_read,
                workspaces: _workspaces,
                layout: homeLayoutOf(prefs.homeLayout),
                onOpen: shell.openNote,
                onNew: _plus,
                clock: widget.clock,
                onAllNotes: shell.showAllNotes,
                onSearch: _search,
                onSwipe: _actions.swipe,
                onRefresh: _library.refresh,
                onNoteMenu: (id) => _menu.open(id, MediaQuery.sizeOf(context).center(Offset.zero)),
                onManageWorkspace: (workspace) => setState(() => _workspace = (editing: workspace)),
                organizations: homeOrganizations(services),
                orgNews: homeOrgNews(services, chosenOrg),
                onOrganization: services == null ? null : shell.openOrganization,
                onOrganizationSettings: services == null ? null : (id) => setState(() => _organization = (id: id, from: OrganizationFrom.settings)),
                onNewOrganization: signedIn ? () => setState(() => _newOrganization = true) : null,
                headerEdge: (context, edge, scroller) => WispEdge(under: edge.under, foot: true, child: scroller),
                dockHalo: (context, it) => DockSmoke(behind: it.behind, dock: it.dock, alignment: it.alignment, padding: it.padding),
                ghost: (context, it) => Ghost(
                  scene: switch (it.scene) {
                    HomeGhostScene.noNotes => GhostScene.noNotes,
                    HomeGhostScene.emptyWorkspace => GhostScene.emptyWorkspace,
                    HomeGhostScene.searchNothing => GhostScene.searchNothing,
                  },
                  size: it.lead ? GhostSize.lead : GhostSize.small,
                  heightShare: it.heightShare,
                ),
              ),
              allNotesBuilder: (context, shell, screen) => AllNotesScreen(
                notes: shell.notes,
                loading: !_read,
                workspaces: _workspaces,
                stored: _stored,
                tapes: screen.tapes,
                clock: widget.clock,
                onOpen: shell.openNote,
                onBack: shell.backToList,
                onRefresh: _library.refresh,
                onNoteMenu: (note, at) => _menu.open(note.id, at),
                notesInWorkspace: _notesIn,
                onTrashNotes: (ids) => ids.forEach(_trash.trashNote),
                wisp: prefs.wispEdge,
              ),
              sidebarBuilder: (context, shell, close) => NotesDrawer(
                open: true,
                notes: shell.notes,
                activeId: shell.shown,
                workspaces: _workspaces,
                stored: _stored,
                onOpen: (id) {
                  close();
                  shell.openNote(id);
                },
                onNew: () {
                  close();
                  _plus();
                },
                onClose: close,
                onCommands: _search,
                onSettings: () {
                  close();
                  setState(() => _settings = true);
                },
                trashed: _trashed,
                onRestore: _actions.restore,
                onDestroy: _actions.destroy,
                onEmptyTrash: () => _actions.emptyTrash(_trashed),
                notesInWorkspace: _notesIn,
                onTrashNotes: (ids) => ids.forEach(_trash.trashNote),
                emptyArt: const Ghost(scene: GhostScene.noNotes),
              ),
              dockedSidebarBuilder: (context, shell) => _tree(shell),
              notificationsBuilder: (context, shell, close) {
                void openNote(String id, String? at) {
                  close();
                  shell.openNote(id, at: at);
                }

                void account() {
                  close();
                  _toAccount();
                }

                if (services != null) {
                  return FedNotificationsDrawer(
                    services: services,
                    onClose: close,
                    onOpenNote: openNote,
                    onOpenOrganization: (id) {
                      close();
                      shell.openOrganization(id);
                    },
                    onAccount: account,
                  );
                }
                return NotificationsDrawer(notifications: const [], prefs: prefs.notifications, signedIn: false, onClose: close, onOpenNote: openNote, onOpenOrganization: (_) => close(), onAccount: account);
              },
            ),
            SettingsSheet(
              open: _settings,
              toPage: _settingsPage,
              onClose: () => setState(() => _settings = false),
              workspaces: _workspaces,
              notesInWorkspace: _notesIn,
              onTrashNotes: (ids) => ids.forEach(_trash.trashNote),
              // A build with no service says so where a way in is pressed; one with an account takes it from the scope.
              features: SettingsFeatures(onWayIn: services == null ? noServiceWayIn : null),
              onOrganization: services == null ? null : (id) => setState(() => _organization = (id: id, from: OrganizationFrom.settings)),
            ),
            CommandBar.over(
              key: _commands,
              world: () => paletteWorldFor(shell: _shell.currentState!, workspaces: _workspaces.value, prefs: preferences.value),
              doing: () => paletteDoingFor(
                shell: _shell.currentState!,
                library: _library,
                workspaces: _workspaces,
                newNote: _new,
                newNotebook: () => _newBook(NewBookKind.notebook),
                newJournal: () => _newBook(NewBookKind.journal),
                newEntry: (id) => unawaited(_newEntry(id)),
                openNoteWhereLeft: (id) {
                  final note = _library.noteOf(id);
                  final shell = _shell.currentState;
                  if (note != null && shell != null) shell.openNote(whereLeft(note, _shown, shell.shown, on: _stored).id);
                },
                archive: (id) {
                  final note = _library.noteOf(id);
                  if (note == null) return;
                  _shell.currentState?.dropTab(id);
                  _actions.archive(note, archived: true);
                },
                removeNote: _delete,
                settings: () => setState(() => _settings = true),
                settingsPage: (id) => setState(() {
                  _settings = true;
                  _settingsPage = SettingsTarget(id, nonce: DateTime.now().microsecondsSinceEpoch);
                }),
              ),
            ),
            NoteMenuHost(
              controller: _menu,
              notes: _shown,
              onOpen: (note) => _shell.currentState?.openNote(note.id),
              onPin: _actions.pin,
              onArchive: (note, archived) => _actions.archive(note, archived: archived),
              onDelete: (note) => _delete(note.id),
            ),
            // What the + makes (notes/NewSheet.tsx). The rows read where to make it as they are pressed, since the
            // sheet closes first.
            Builder(builder: (context) {
              final into = _newInto;
              return NewSheet(
                open: _newSheet,
                onClose: () => setState(() {
                  _newSheet = false;
                  _newInto = null;
                }),
                onNote: () => _new(into),
                onCanvas: () => _newCanvas(into),
                onBook: () => _newBook(NewBookKind.notebook, into),
                // A journal's entry is the account's own, and is not offered from an organization's +.
                entry: into != null || !_newSheet ? null : _entryRow(),
              );
            }),
            NewBookSheet(
              open: _bookSheet != null,
              kind: _bookSheet ?? NewBookKind.notebook,
              onClose: () => setState(() => _bookSheet = null),
              titles: _bookSheet == null ? const [] : _pageTitles(books: false),
              isCanvas: (title) => isCanvasBody(_reads.titled(title)?.body ?? ''),
              onCreate: (title, pages) => _showMade(bookNoteBody(title, pages), into: _bookInto),
              onCreateJournal: (title, template, place) => _showMade(journal.journalNoteBody(title, template, place)),
            ),
            if (_workspace case final sheet?)
              WorkspaceManageSheet(
                store: _workspaces,
                editing: sheet.editing,
                onClose: () => setState(() => _workspace = null),
                notesIn: _notesIn,
                onTrashNotes: (ids) => ids.forEach(_trash.trashNote),
              ),
            if (services != null) ...[
              if (_organization case final sheet? when services.orgs != null)
                OrganizationSheet(
                  key: ValueKey('organization-sheet:${sheet.id}'),
                  services: services,
                  orgId: sheet.id,
                  from: sheet.from,
                  landOnMembers: sheet.from != OrganizationFrom.dashboard,
                  onClose: () => setState(() => _organization = null),
                  onNotes: () {
                    setState(() => _organization = null);
                    _workspaces.chooseWorkspace(orgWorkspaceId(sheet.id));
                    _shell.currentState?.backToList();
                  },
                ),
              NewOrganizationSheet(
                services: services,
                open: _newOrganization,
                onClose: () => setState(() => _newOrganization = false),
                onMade: (id) {
                  setState(() => _newOrganization = false);
                  _shell.currentState?.openOrganization(id);
                },
              ),
              // An invite's code held on this device is asked about once someone is signed in; a link cannot open the
              // app yet, so nothing new arrives here.
              JoinInvites(services: services, request: null, hold: gate?.open ?? true, onOpen: (id) => _shell.currentState?.openOrganization(id), onAccount: _toAccount),
              // The way in, the first thing on screen once, on an open that is signed out.
              if (gate != null && gate.open) AccountGate(services: services, onDone: gate.close),
            ],
            if (_launching) LaunchScreen(loading: !_read, notes: _shown.length, onDone: () => setState(() => _launching = false)),
          ],
          ),
        );
      },
    );
  }
}
