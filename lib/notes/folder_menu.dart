/// A folder's menu at the pointer (Matt, 2026-10-23: "add a right click context menu to files and folders to delete
/// them"). The port's own, beside a note's (lib/notes/note_menu.dart), which every list of notes already had.
///
/// A mouse's right-click on a folder - its tile in the icon view (lib/notes/icon_browser.dart), its chip on a
/// folders' strip (lib/notes/folder_strip.dart), its row in the sidebar (lib/notes/note_tree.dart) - opens Open,
/// Rename…, Move to (the folders it may go to, as carrying it would move it: lib/notes/folder_drag.dart, never into
/// or out of an organization), then Remove folder, keep its notes… and, in the one red, Delete folder and its
/// notes… (Matt, 2026-11-01: "add ability to context menu delete folders and items inside them"). Rename… and both
/// deletes are the folder's own sheet (lib/notes/workspace_sheet.dart): Remove opened at its question of what becomes
/// of the notes, Delete at the question of deleting everything in it, which counts the folders and the notes under it
/// ("Delete Plans, 3 folders and 24 notes?") and says where they go: a personal folder's notes to the Trash, with an
/// Undo after; an organization's deleted for every member, which cannot be undone (lib/notes/note_actions.dart
/// `deleteFolder`). So nothing is deleted from a menu without being asked, and a folder of an organization's goes by
/// the same rules and the same moves as from its sheet. An organization's own workspace has no menu: it is not
/// renamed, moved or deleted by hand. Simple mode (GHST-103) has the same rows: deleting is basic. On a desktop, Show in
/// Finder (Explorer, Files) comes after Move to, where the folder's directory is on the disk (Matt, 2026-11-01: "also
/// add an 'open in finder' option"; lib/core/show_in_files.dart), from the scope's [FolderMenuScope.show].
///
/// A finger's press and hold on a folder is the drag that carries it (folder_drag.dart `FolderCarrySource`); let go
/// where it was held, without carrying it anywhere, it opens this menu where the tiles and the chips are (the icon
/// view, All notes by folder; Matt, 2026-11-01), and on a phone a folder's sheet is its row's More in the sidebar,
/// and its pill's on the list, as before. The rows are the root's, through a [FolderMenuScope] over the app: where none is, a right-click does
/// nothing, as in a test of a screen alone. The scope also carries a note's menu, for a list that was handed none
/// (an organization's page's icon view).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/note_folders.dart' show folderFor;
import '../core/preferences.dart' show preferences;
import '../core/show_in_files.dart';
import '../core/workspaces.dart';
import '../plugins/cleanup/manifest.dart' show cleanupManifest;
import '../plugins/registry.dart' show pluginOn;
import '../shell/pop_menu.dart';
import 'folder_drag.dart';
import 'note_menu.dart' show byMouse, showInFilesRows;

/// What a folder's menu does, from the root: its sheet to rename it, or at Delete.
class FolderMenuScope extends InheritedWidget {
  const FolderMenuScope({super.key, required this.store, required this.onRename, required this.onDelete, this.onDeleteAll, this.deleteAll, this.noteExists, this.onSetTemplate, this.onNoteMenu, this.show, this.onKeepIndex, this.onCleanup, required super.child});

  final WorkspaceStore store;
  final ValueChanged<Workspace> onRename;

  /// Remove folder, keep its notes…: the folder's sheet at its question of what becomes of the notes.
  final ValueChanged<Workspace> onDelete;

  /// Delete folder and its notes…: the folder's sheet at the question of deleting everything in it. Left out, no row.
  final ValueChanged<Workspace>? onDeleteAll;

  /// The delete itself, once a sheet has asked: for the sheets the sidebar and the list open of their own.
  final ValueChanged<Workspace>? deleteAll;

  /// Whether a note is really there and out of the trash, for the counts a question says.
  final bool Function(String noteId)? noteExists;

  /// Set template…: the template every new note made in the folder starts from (lib/notes/place_templates.dart).
  final ValueChanged<Workspace>? onSetTemplate;

  /// A note's menu at a point in the window, for a list that was handed none of its own.
  final void Function(String noteId, Offset at)? onNoteMenu;

  /// Show in Finder, Explorer or Files, for a folder's directory and a page's file; absent, or on a phone, no row.
  final ShowInFiles? show;

  /// Keep an index…: the folder's index card in a sheet (docs/AI_INDEXES.md; Matt, 2026-11-02: "for any folder or org,
  /// the AI keeps an index note"). Absent, no row.
  final ValueChanged<Workspace>? onKeepIndex;

  /// Clean up with AI…: the Cleanup plugin's page at the folder (lib/plugins/cleanup; Matt, 2026-11-02). A row only
  /// while the plugin is on ([folderCleanupRows]).
  final ValueChanged<Workspace>? onCleanup;

  static FolderMenuScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<FolderMenuScope>();

  @override
  bool updateShouldNotify(FolderMenuScope old) => old.store != store || old.onRename != onRename || old.onDelete != onDelete || old.onDeleteAll != onDeleteAll || old.deleteAll != deleteAll || old.noteExists != noteExists || old.onSetTemplate != onSetTemplate || old.onNoteMenu != onNoteMenu || old.show != show || old.onKeepIndex != onKeepIndex || old.onCleanup != onCleanup;
}

/// The right-click a folder's tile, chip or row answers: its menu at the pointer, a mouse's other button only. An
/// organization's own workspace, a folder the store no longer has, or no [FolderMenuScope]: [child] and no more.
class FolderMenuArea extends StatelessWidget {
  const FolderMenuArea({super.key, required this.folderId, this.onOpen, required this.child});

  final String folderId;

  /// Open, the first row: what a press on the folder does where it is.
  final VoidCallback? onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = FolderMenuScope.maybeOf(context);
    if (scope == null || isOrgWorkspace(folderId)) return child;
    return Listener(
      onPointerDown: (event) {
        if (byMouse(event.kind) && event.buttons == kSecondaryMouseButton) showFolderMenu(context, scope, folderId, event.position, onOpen: onOpen);
      },
      child: child,
    );
  }
}

/// The two deletes a folder's menu ends with: Remove folder, keep its notes…, and Delete folder and its notes… in the
/// one red where the scope has it. A page's menu in the spaces' tree ends with the same (lib/notes/note_tree_spaces.dart).
List<Widget> folderDeleteRows(FolderMenuScope scope, Workspace folder, {required Widget Function(LucideIcon which) icon, required Tokens t}) => [
      GlacierMenuItem(key: const ValueKey('folder-menu-remove'), icon: icon(Lucide.folder), onSelect: () => scope.onDelete(folder), child: const Text('Remove folder, keep its notes…')),
      if (scope.onDeleteAll != null)
        GlacierMenuItem(
          key: const ValueKey('folder-menu-delete-all'),
          danger: true,
          style: dangerRowStyle(t),
          icon: icon(Lucide.trash2),
          onSelect: () => scope.onDeleteAll!(folder),
          child: const Text('Delete folder and its notes…'),
        ),
    ];

/// Opens [folderId]'s menu at [at], over the app, until a row is chosen or it is dismissed.
void showFolderMenu(BuildContext context, FolderMenuScope scope, String folderId, Offset at, {VoidCallback? onOpen}) {
  final store = scope.store;
  final folder = store.value.list.where((w) => w.id == folderId).firstOrNull;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (folder == null || overlay == null || isOrgWorkspace(folder.id)) return;
  late final OverlayEntry entry;
  var gone = false;
  void close() {
    if (gone) return;
    gone = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (overlayContext) {
      final t = overlayContext.tokens;
      final em = coarsePointer ? t.fontSize('md') : t.fontSize('sm');
      Widget icon(LucideIcon which) => AppIcon(which, size: em);
      return PopMenu(
        anchor: GlacierAnchor.point(at),
        onDismiss: close,
        placement: Placement.bottomStart,
        ariaLabel: '${folder.name}, folder',
        children: [
          if (onOpen != null) GlacierMenuItem(key: const ValueKey('folder-menu-open'), icon: icon(Lucide.folderOpen), onSelect: onOpen, child: const Text('Open')),
          GlacierMenuItem(key: const ValueKey('folder-menu-rename'), icon: icon(Lucide.pencil), onSelect: () => scope.onRename(folder), child: const Text('Rename…')),
          // A template for the folder's new notes (Matt, 2026-10-30): simple mode keeps it on the folder's sheet,
          // behind its More.
          if (scope.onSetTemplate != null && !preferences.value.simple) GlacierMenuItem(key: const ValueKey('folder-menu-template'), icon: icon(Lucide.copyPlus), onSelect: () => scope.onSetTemplate!(folder), child: const Text('Set template…')),
          if (scope.onKeepIndex != null) GlacierMenuItem(key: const ValueKey('folder-menu-index'), icon: icon(Lucide.listTree), onSelect: () => scope.onKeepIndex!(folder), child: const Text('Keep an index…')),
          // Clean up with AI… before Move to, whose rows are places (lib/plugins/cleanup; 2026-11-02).
          ...folderCleanupRows(scope, folder, icon: icon(Lucide.brushCleaning)),
          if (context.mounted) ...folderMoveRows(context, store, FolderCarry.folder(folder.id, folder.name)),
          ...folderShowRows(scope.show, folder, store.value.list, icon: icon(Lucide.hardDrive)),
          const GlacierMenuSeparator(),
          ...folderDeleteRows(scope, folder, icon: icon, t: t),
        ],
      );
    },
  );
  overlay.insert(entry);
}

/// Show in Finder (Explorer, Files) for [folder]'s directory, the one filing names (lib/core/note_folders.dart
/// `folderFor`, [all] for its parents'), where it is on the disk.
List<Widget> folderShowRows(ShowInFiles? show, Workspace folder, List<Workspace> all, {required Widget icon}) =>
    showInFilesRows(show, folderFor(folder, all), key: const ValueKey('folder-menu-show'), icon: icon, directory: true);

/// Clean up with AI… for [folder], where the scope can open Cleanup's page and the plugin is on (docs/CLEANUP.md; Matt,
/// 2026-11-02: "spawn a task making a 'cleanup' plugin that allows us to use whatever AI we choose that's connected to
/// clean up and sort the notes in a given folder"). Simple mode has it too: the plugin is added only by someone who
/// wants it.
List<Widget> folderCleanupRows(FolderMenuScope? scope, Workspace folder, {required Widget icon}) => [
      if (scope?.onCleanup != null && pluginOn(cleanupManifest))
        GlacierMenuItem(key: const ValueKey('folder-menu-cleanup'), icon: icon, onSelect: () => scope!.onCleanup!(folder), child: const Text('Clean up with AI…')),
    ];
