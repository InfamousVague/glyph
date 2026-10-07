import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/note.dart';
import '../core/preferences.dart';
import '../core/sample_library.dart';
import '../core/stored.dart';
import '../core/swipe.dart';
import '../core/workspaces.dart';
import '../home/home_layout.dart';
import '../home/home_screen.dart';
import '../launch/launch_screen.dart';
import '../notes/note_tree.dart';
import '../notes/notes_drawer.dart';
import '../notes/notifications_drawer.dart';
import '../notes/workspace_sheet.dart';
import '../settings/settings_sheet.dart';
import '../shell/app_shell.dart';
import '../shell/top_bar.dart';

/// The app, put together: what the web app's `App.tsx` does once its screens exist. The launch screen over the
/// shell (lib/shell/app_shell.dart); in the shell the home page, the notes' sidebar as a card or docked, and the
/// notifications; over it Settings and a workspace's sheet; and the art in the seams each of them left for it.
///
/// What it stands on until the stages that bring the real things:
/// - **The library** is [SampleLibrary], the invented notes the store's screenshots are taken over, held in memory:
///   pinning, archiving, deleting to a trash and making a note all work and none of it is kept (stage 3).
/// - **A note's own screen** is the shell's stand-in, its title over its Markdown as written (stage 4).
/// - **Search and commands**, **Speak**, organizations and the notifications' feed are not here yet: the dock and
///   the sidebar leave those buttons out, and the bell opens an empty card (stages 5, 7 and 8).
class GhostRoot extends StatefulWidget {
  const GhostRoot({super.key, this.sheet, this.library, this.workspaces, this.stored, this.launch = true});

  /// The app's token sheet, which the shell stamps its layout over: the theme's own unless given.
  final TokenSheet? sheet;

  /// The notes; the store screenshots' library unless a test brings its own.
  final NoteLibrary? library;
  final WorkspaceStore? workspaces;

  /// Where this device keeps how its sidebar was left; the app's own (core/stored.dart) unless given.
  final Stored? stored;

  /// Whether the app opens behind its launch screen. A test's picture of a screen does not.
  final bool launch;

  @override
  State<GhostRoot> createState() => _GhostRootState();
}

class _GhostRootState extends State<GhostRoot> {
  late final NoteLibrary _library = widget.library ?? SampleLibrary.seeded(now: DateTime.now().millisecondsSinceEpoch);
  late final WorkspaceStore _workspaces = widget.workspaces ?? WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces()));
  late final Stored _stored = widget.stored ?? stored;
  late final Listenable _all = Listenable.merge([_library, _workspaces, preferences]);

  final GlobalKey<AppShellState> _shell = GlobalKey<AppShellState>();

  /// The trash: what was deleted, newest first, until it is emptied.
  final List<Note> _trashed = [];
  late bool _launching = widget.launch;
  bool _read = false;
  bool _settings = false;

  /// The workspace sheet: shut, a new one, or one to change.
  ({Workspace? editing})? _workspace;

  @override
  void initState() {
    super.initState();
    // The notes are in memory, so reading them is no wait; a beat, so the launch's first line is seen to be done.
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _read = true);
    });
  }

  void _delete(String id) {
    final note = _library.delete(id);
    if (note == null) return;
    _workspaces.forgetNote(id);
    setState(() => _trashed.insert(0, note));
  }

  void _restore(Note note) {
    _library.restore(note);
    setState(() => _trashed.remove(note));
  }

  void _swipe(Note note, NoteSwipe action) {
    switch (action) {
      case NoteSwipe.pin:
        _library.pin(note.id, pinned: !note.starred);
      case NoteSwipe.archive:
        _library.archive(note.id, archived: note.archivedAt == null);
      case NoteSwipe.delete:
        _delete(note.id);
    }
  }

  void _new(AppShellState shell) {
    final note = _library.create('');
    _workspaces.fileNewNote(note.id);
    shell.openNote(note.id);
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
      onSettings: () {
        onClose?.call();
        setState(() => _settings = true);
      },
      trashed: _trashed,
      onRestore: _restore,
      onDestroy: (note) => setState(() => _trashed.remove(note)),
      onEmptyTrash: () => setState(_trashed.clear),
      notesInWorkspace: _notesIn,
      onTrashNotes: (ids) => ids.forEach(_delete),
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
              notes: _library.value,
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
                onAllNotes: shell.showAllNotes,
                onSwipe: _swipe,
                onRefresh: _library.refresh,
                onManageWorkspace: (workspace) => setState(() => _workspace = (editing: workspace)),
                headerEdge: prefs.wispEdge ? (context, edge, scroller) => WispEdge(under: edge.under, foot: true, child: scroller) : null,
                dockHalo: prefs.wispEdge ? (context, it) => DockSmoke(behind: it.behind, dock: it.dock, alignment: it.alignment, padding: it.padding) : null,
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
                onSettings: () {
                  close();
                  setState(() => _settings = true);
                },
                trashed: _trashed,
                onRestore: _restore,
                onDestroy: (note) => setState(() => _trashed.remove(note)),
                onEmptyTrash: () => setState(_trashed.clear),
                notesInWorkspace: _notesIn,
                onTrashNotes: (ids) => ids.forEach(_delete),
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
            SettingsSheet(open: _settings, onClose: () => setState(() => _settings = false)),
            if (_workspace case final sheet?)
              WorkspaceManageSheet(
                store: _workspaces,
                editing: sheet.editing,
                onClose: () => setState(() => _workspace = null),
                notesIn: _notesIn,
                onTrashNotes: (ids) => ids.forEach(_delete),
              ),
            if (_launching) LaunchScreen(loading: !_read, notes: _library.value.length, onDone: () => setState(() => _launching = false)),
          ],
        );
      },
    );
  }
}
