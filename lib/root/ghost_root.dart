import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/ui_state.dart';
import '../art/art.dart';
import '../commands/app_commands.dart';
import '../commands/command_bar.dart';
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
import '../core/sample_library.dart';
import '../core/stored.dart';
import '../core/trash.dart';
import '../core/untouched.dart';
import '../core/versions_record.dart';
import '../core/versions_store.dart';
import '../core/workspaces.dart';
import '../home/home_layout.dart';
import '../home/home_screen.dart';
import '../launch/launch_screen.dart';
import '../note/note_builder.dart';
import '../note/note_screen.dart' show withFrontMatterTitle;
import '../notes/all_notes_screen.dart';
import '../notes/note_actions.dart';
import '../notes/note_menu.dart';
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
import 'note_desk.dart';

/// The app, put together: what the web app's `App.tsx` does once its screens exist. The launch screen over the
/// shell (lib/shell/app_shell.dart); in the shell the home page, the notes' sidebar as a card or docked, and the
/// notifications; over it Settings and a workspace's sheet; and the art in the seams each of them left for it.
///
/// What it stands on:
/// - **The library** is the Rust core's ([core], lib/core/core_library.dart): the notes are Markdown files in the app's
///   own folder, as the Tauri app keeps them; the workspaces and the trash are preferences; a fresh library is given
///   the starter notes once. Without a core (a test, a picture) it is the store screenshots' invented library in memory.
/// - **A note's own screen** is lib/note's, over the editor (lib/editor) with every piece of it, put together for
///   each open note by lib/root/note_desk.dart.
/// - **The account** is made only where the build was told its service ([account], lib/root/account_wiring.dart):
///   then the shell, Settings and a note's sharing are under one [AccountScope], the organizations have their
///   pages, the notifications are the feed's, and the way in is the first thing on screen once. With none there
///   is no account object anywhere, and every screen is the signed-out one.
/// - **Speak** is not here yet (stage 8), nor a link that opens the app (no `LinkSource`: an invite is joined
///   from its notification or by its code held from before).
class GhostRoot extends StatefulWidget {
  const GhostRoot({super.key, this.sheet, this.core, this.library, this.workspaces, this.stored, this.clock, this.launch = true, this.account, this.services});

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

  /// A note by its title, among those not in the Trash.
  Note? _titled(String title) {
    final key = titleKey(title);
    if (key.isEmpty) return null;
    for (final note in _shown) {
      if (titleKey(noteTitle(note.body)) == key) return note;
    }
    return null;
  }

  /// `[[A title]]` tapped: the note by that name, made first where there is none.
  void _openTitle(String title, [String? anchor]) {
    final shell = _shell.currentState;
    if (shell == null) return;
    final found = _titled(title);
    if (found != null) return shell.openNote(found.id, at: anchor);
    final made = _library.create('# ${title.trim()}\n\n');
    _workspaces.fileNewNote(made.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) shell.openNote(made.id);
    });
  }

  late final NoteDeskWorld _desk = NoteDeskWorld(
    titles: () => [
      for (final note in _shown)
        if (noteTitle(note.body).isNotEmpty) noteTitle(note.body),
    ],
    known: (title) => _titled(title) != null,
    open: _openTitle,
    bodyOf: (title) => _titled(title)?.body,
    pictures: _pictures,
    services: _services,
  );

  /// A note's screen with its editor: one desk to an open note (lib/root/note_desk.dart).
  Widget _note(BuildContext context, AppShellState shell, ScreenNote screen) => NoteDesk(
        key: ValueKey('desk:${screen.note.id}'),
        noteId: screen.note.id,
        title: noteTitle(screen.note.body),
        world: _desk,
        say: (message) => _say(context, message),
        builder: (context, editor, seams) => noteScreenBuilder(
          library: _library,
          workspaces: _workspaces,
          actions: () => _actions,
          versions: _versions,
          trash: _trash,
          device: _stored,
          editor: editor,
          seams: seams,
          say: _say,
        )(context, shell, screen),
      );
  NoteActions? _made;

  /// Pin, archive, delete and their Undo (notes/note_actions.dart); made once there is a toast to say them with.
  NoteActions get _actions => _made ??= NoteActions(library: _library, workspaces: _workspaces, trash: _trash, say: NoteActions.toaster(context))..addListener(_changed);

  void _changed() {
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

  /// A new note filed in an organization's workspace, opened ready to type.
  void _newIn(AppShellState shell, String orgId) {
    final note = _library.create('');
    untouchedNotes.markFresh(note.id);
    _workspaces.fileNote(note.id, orgWorkspaceId(orgId));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) shell.openNote(note.id);
    });
  }

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
      onNew: () => _newIn(shell, id),
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
    if (!_real || !mounted) return;
    final seeded = _stored.flag('glyph-sample-note', unreadable: true);
    if (seeded.isMarked) return;
    seeded.mark();
    if (_library.value.isNotEmpty) return;
    for (final note in starterNotes(DateTime.now().millisecondsSinceEpoch)) {
      await _library.createNote(note.body);
    }
  }

  void _delete(String id) {
    final note = _library.noteOf(id);
    if (note != null) _actions.remove(note);
  }

  void _new(AppShellState shell) {
    final note = _library.create('');
    untouchedNotes.markFresh(note.id);
    _workspaces.fileNewNote(note.id);
    // Once the shell has been handed the library with the note in it: it opens only what it has.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) shell.openNote(note.id);
    });
  }

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
        _new(shell);
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
              onOpenNotesChanged: (open) => preferences.update((now) => now.copyWith(openNotes: open)),
              onTabGroupsChanged: (groups) => preferences.update((now) => now.copyWith(tabGroups: groups)),
              onSettings: () => setState(() => _settings = true),
              // The people icon with no organization joined, and the picker's last row: Settings › Organizations.
              onOrganizations: () => setState(() {
                _settings = true;
                _settingsPage = SettingsTarget('organizations', nonce: DateTime.now().microsecondsSinceEpoch);
              }),
              onNew: () => _new(_shell.currentState!),
              onDeleteNote: _delete,
              onRefresh: () => _library.refresh(),
              noteBuilder: _note,
              homeBuilder: (context, shell) => HomeScreen(
                notes: shell.notes,
                loading: !_read,
                workspaces: _workspaces,
                layout: homeLayoutOf(prefs.homeLayout),
                onOpen: shell.openNote,
                onNew: () => _new(shell),
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
                  _new(shell);
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
                newNote: () => _new(_shell.currentState!),
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
