/// A folder's menu at the pointer (Matt, 2026-10-23: "add a right click context menu to files and folders to delete
/// them"). The port's own, beside a note's (lib/notes/note_menu.dart), which every list of notes already had.
///
/// A mouse's right-click on a folder - its tile in the icon view (lib/notes/icon_browser.dart), its chip on a
/// folders' strip (lib/notes/folder_strip.dart), its row in the sidebar (lib/notes/note_tree.dart) - opens Open,
/// Rename…, Move to (the folders it may go to, as carrying it would move it: lib/notes/folder_drag.dart, never into
/// or out of an organization), and Delete folder… in the one red. Rename… and Delete folder… are the folder's own
/// sheet (lib/notes/workspace_sheet.dart), Delete opened at its question of what becomes of the notes: kept, or put
/// in the Trash with it, where they wait to be restored. So nothing is deleted from a menu without being asked, and
/// a folder of an organization's goes by the same rules and the same moves as from its sheet. An organization's own
/// workspace has no menu: it is not renamed, moved or deleted by hand.
///
/// A finger's press and hold on a folder is the drag that carries it (folder_drag.dart `FolderCarrySource`), so it
/// opens nothing here; on a phone a folder's sheet is its row's More in the sidebar, and its pill's on the list, as
/// before. The rows are the root's, through a [FolderMenuScope] over the app: where none is, a right-click does
/// nothing, as in a test of a screen alone. The scope also carries a note's menu, for a list that was handed none
/// (an organization's page's icon view).
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/workspaces.dart';
import '../shell/pop_menu.dart';
import 'folder_drag.dart';
import 'note_menu.dart' show byMouse;

/// What a folder's menu does, from the root: its sheet to rename it, or at Delete.
class FolderMenuScope extends InheritedWidget {
  const FolderMenuScope({super.key, required this.store, required this.onRename, required this.onDelete, this.onNoteMenu, required super.child});

  final WorkspaceStore store;
  final ValueChanged<Workspace> onRename;
  final ValueChanged<Workspace> onDelete;

  /// A note's menu at a point in the window, for a list that was handed none of its own.
  final void Function(String noteId, Offset at)? onNoteMenu;

  static FolderMenuScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<FolderMenuScope>();

  @override
  bool updateShouldNotify(FolderMenuScope old) => old.store != store || old.onRename != onRename || old.onDelete != onDelete || old.onNoteMenu != onNoteMenu;
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
          if (context.mounted) ...folderMoveRows(context, store, FolderCarry.folder(folder.id, folder.name)),
          const GlacierMenuSeparator(),
          GlacierMenuItem(
            key: const ValueKey('folder-menu-delete'),
            danger: true,
            style: dangerRowStyle(t),
            icon: icon(Lucide.trash2),
            onSelect: () => scope.onDelete(folder),
            child: const Text('Delete folder…'),
          ),
        ],
      );
    },
  );
  overlay.insert(entry);
}
