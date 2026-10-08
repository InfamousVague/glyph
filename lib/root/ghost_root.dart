import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../commands/app_commands.dart';
import '../commands/command_bar.dart';
import '../core/core_library.dart';
import '../core/kept_trash.dart';
import '../core/kept_workspaces.dart';
import '../core/native/core.dart';
import '../core/note.dart';
import '../core/note_folders.dart';
import '../core/preferences.dart';
import '../core/sample_library.dart';
import '../core/stored.dart';
import '../core/trash.dart';
import '../core/workspaces.dart';
import '../home/home_layout.dart';
import '../home/home_screen.dart';
import '../launch/launch_screen.dart';
import '../notes/all_notes_screen.dart';
import '../notes/note_actions.dart';
import '../notes/note_menu.dart';
import '../notes/note_tree.dart';
import '../notes/notes_drawer.dart';
import '../notes/notifications_drawer.dart';
import '../notes/workspace_sheet.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_sheet.dart';
import '../shell/app_shell.dart';
import '../shell/top_bar.dart';

/// The app, put together: what the web app's `App.tsx` does once its screens exist. The launch screen over the
/// shell (lib/shell/app_shell.dart); in the shell the home page, the notes' sidebar as a card or docked, and the
/// notifications; over it Settings and a workspace's sheet; and the art in the seams each of them left for it.
///
/// What it stands on:
/// - **The library** is the Rust core's ([core], lib/core/core_library.dart): the notes are Markdown files in the app's
///   own folder, as the Tauri app keeps them; the workspaces and the trash are preferences; a fresh library is given
///   the starter notes once. Without a core (a test, a picture) it is the store screenshots' invented library in memory.
/// - **A note's own screen** is the shell's stand-in, its title over its Markdown as written (stage 4).
/// - **Speak**, organizations and the notifications' feed are not here yet (stages 7 and 8).
class GhostRoot extends StatefulWidget {
  const GhostRoot({super.key, this.sheet, this.core, this.library, this.workspaces, this.stored, this.clock, this.launch = true});

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
  late final Listenable _all = Listenable.merge([_library, _workspaces, _trash, preferences]);

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
    _made?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _smoke();
    preferences.addListener(_smoke);
    _open();
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
        return Stack(
          fit: StackFit.expand,
          children: [
            AppShell(
              key: _shell,
              sheet: widget.sheet ?? context.tokens.sheet,
              notes: _shown,
              topBar: TopBarStyle.parse(prefs.topBar),
              sidebarStyle: prefs.sidebarStyle == 'docked' ? SidebarStyle.docked : SidebarStyle.popover,
              workspaces: _workspaces.value,
              openNotes: prefs.openNotes,
              tabGroups: prefs.tabGroups,
              onOpenNotesChanged: (open) => preferences.update((now) => now.copyWith(openNotes: open)),
              onTabGroupsChanged: (groups) => preferences.update((now) => now.copyWith(tabGroups: groups)),
              onSettings: () => setState(() => _settings = true),
              onNew: () => _new(_shell.currentState!),
              onDeleteNote: _delete,
              onRefresh: () => _library.refresh(),
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
              notificationsBuilder: (context, shell, close) => NotificationsDrawer(
                notifications: const [],
                prefs: prefs.notifications,
                signedIn: false,
                onClose: close,
                onOpenNote: (id, at) {
                  close();
                  shell.openNote(id, at: at);
                },
                onOpenOrganization: (_) => close(),
                onAccount: () {
                  close();
                  setState(() => _settings = true);
                },
              ),
            ),
            SettingsSheet(
              open: _settings,
              toPage: _settingsPage,
              onClose: () => setState(() => _settings = false),
              workspaces: _workspaces,
              notesInWorkspace: _notesIn,
              onTrashNotes: (ids) => ids.forEach(_trash.trashNote),
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
            if (_launching) LaunchScreen(loading: !_read, notes: _shown.length, onDone: () => setState(() => _launching = false)),
          ],
        );
      },
    );
  }
}
