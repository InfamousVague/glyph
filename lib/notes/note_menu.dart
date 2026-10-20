/// A note's menu at the pointer. A port of `src/app/notes/NoteMenu.tsx` (with NoteMenu.module.css) and
/// `src/app/notes/noteMenu.ts` (docs/DESIGN.md §172; Matt: "add context menus so i can right click on desktop to
/// delete a note").
///
/// Open, Add a comment, Pin or Unpin, Archive or Unarchive, and Delete in the danger tone. Each does what the card's
/// swipe does through the same actions (lib/notes/note_actions.dart), so a deleted note goes to the Trash with an
/// Undo and a right-click is never a way to lose one. One menu for the whole app ([NoteMenuController]), mounted
/// once ([NoteMenuHost]); a note's place in any list only says which note and where the pointer was.
///
/// Drawn from the kit's menu through lib/shell/pop_menu.dart, as the tab row's menus are, hung from a point of no
/// size where the pointer was. PopMenu closes it on the back gesture and Escape and on a press anywhere else, and
/// holds it to half the window's height, so a right-click near the foot turns it upward whole.
///
/// What differs:
/// - **Who opens it.** A mouse's right-click and nothing else, as on the page ([byMouse], [NoteMenuArea]): a press
///   and hold is a finger's, and belongs to a card's swipe and a tab's drag. Whoever lists the note calls
///   [NoteMenuController.open].
/// - The store is a [NoteMenuController] handed to the host and to whoever opens it, where the page's was a module
///   of its own (`useNoteMenu`, `openNoteMenu`, `closeNoteMenu`, `noteMenuNow`).
/// - The mark the page hung the menu from (`[data-pop-point]`) and the portal to the body are not needed: the kit's
///   menu here takes a point and draws in the app's overlay (see lib/shell/pop_menu.dart).
/// - **Every row the web's menu has is here.** Add a comment takes [NoteMenuHost.onComment] and is left out
///   without it, as on the page; the root gives it (lib/comments/ask.dart: the note is opened, and its desk starts
///   a comment on its first line once its editor is there).
/// - **Move to** (2026-10-20, the port's own), where [NoteMenuHost.workspaces] is given: the folders the note may go
///   to, as carrying it onto one would move it (lib/notes/folder_drag.dart), with the same toast and Undo; a flyout
///   where a mouse has room, else listed in place under its label. Nothing into or out of an organization.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/workspaces.dart';
import 'folder_drag.dart';
import '../shell/pop_menu.dart';

/// Which note's menu is open, and where the pointer was, the menu's corner (`NoteMenuAt`).
@immutable
class NoteMenuAt {
  const NoteMenuAt({required this.id, required this.x, required this.y});

  final String id;
  final double x;
  final double y;

  @override
  bool operator ==(Object other) => other is NoteMenuAt && other.id == id && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(id, x, y);

  @override
  String toString() => 'NoteMenuAt($id, $x, $y)';
}

/// The one note's menu the app has open, or null (`notes/noteMenu.ts`): its value is `noteMenuNow()`, and a
/// listener is `useNoteMenu()`.
class NoteMenuController extends ValueNotifier<NoteMenuAt?> {
  NoteMenuController() : super(null);

  /// The note's menu at a point in the window (`openNoteMenu`).
  void open(String id, Offset at) => value = NoteMenuAt(id: id, x: at.dx, y: at.dy);

  /// Shut (`closeNoteMenu`).
  void close() => value = null;
}

/// Whether a context-menu press came from a mouse: said by the pointer where it says, else by the screen, which is
/// asked whether its pointer is fine and can hover (`byMouse`).
bool byMouse(PointerDeviceKind? kind, {bool? fine}) {
  if (kind != null) return kind == PointerDeviceKind.mouse;
  return fine ?? !coarsePointer;
}

/// The right-click a note's card, row or line answers (`onNoteContextMenu`): [onMenu] is told where the pointer
/// was, for a mouse's other button only. A finger's press and hold asks for nothing here, however long: on the
/// page that event is left to the lists' own gestures. Without [onMenu] this is its child and no more.
class NoteMenuArea extends StatelessWidget {
  const NoteMenuArea({super.key, required this.onMenu, required this.child});

  final ValueChanged<Offset>? onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onMenu = this.onMenu;
    if (onMenu == null) return child;
    return Listener(
      onPointerDown: (event) {
        if (byMouse(event.kind) && event.buttons == kSecondaryMouseButton) onMenu(event.position);
      },
      child: child,
    );
  }
}

/// The note's menu, drawn while the [controller] has one open (`NoteMenuHost`). Nothing for a note no longer in
/// [notes]. What differs from the page is in the library doc: who opens it, and the controller being handed in.
class NoteMenuHost extends StatelessWidget {
  const NoteMenuHost({super.key, required this.controller, required this.notes, required this.onOpen, this.onComment, required this.onPin, required this.onArchive, required this.onDelete, this.coarse, this.workspaces});

  final NoteMenuController controller;

  /// Every note a list may show, the archived among them: the menu finds the one it was opened on here.
  final List<Note> notes;
  final ValueChanged<Note> onOpen;

  /// Opens the note and starts a comment on its first line; absent, the row is not shown.
  final ValueChanged<Note>? onComment;
  final ValueChanged<Note> onPin;

  /// The note, and whether it is to be archived (true) or brought back.
  final void Function(Note note, bool archived) onArchive;
  final ValueChanged<Note> onDelete;

  /// Whether the rows are a finger's; the device's answer unless a test says.
  final bool? coarse;

  /// The workspaces, for Move to; absent, the row is not shown.
  final WorkspaceStore? workspaces;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NoteMenuAt?>(
      valueListenable: controller,
      builder: (context, at, _) {
        if (at == null) return const SizedBox.shrink();
        Note? note;
        for (final each in notes) {
          if (each.id == at.id) {
            note = each;
            break;
          }
        }
        if (note == null) return const SizedBox.shrink();
        final it = note;
        final t = context.tokens;
        final archived = it.archivedAt != null;
        final title = noteTitle(it.body);
        final comment = onComment;
        // `<ExternalLink size={16} />` in the kit's icon slot, which is 1em wide: measured on the page, the svg is
        // drawn in a box 13.92 by 16.02 at a row of 13.93px, so the glyph is the row's own em across, not 16.
        final em = (coarse ?? coarsePointer) ? t.fontSize('md') : t.fontSize('sm');
        Widget icon(LucideIcon which) => AppIcon(which, size: em);
        return PopMenu(
          // A fresh menu for each right-click, so a second one somewhere else opens there.
          key: ValueKey('${at.id}:${at.x}:${at.y}'),
          anchor: GlacierAnchor.point(Offset(at.x, at.y)),
          // Told a microtask after it closes: a right-click elsewhere has opened the next one by then, which stays.
          onDismiss: () {
            if (controller.value == at) controller.close();
          },
          placement: Placement.bottomStart,
          ariaLabel: '${title.isNotEmpty ? title : 'Untitled'}, note',
          coarse: coarse,
          children: [
            GlacierMenuItem(icon: icon(Lucide.externalLink), onSelect: () => onOpen(it), child: const Text('Open')),
            if (comment != null) GlacierMenuItem(icon: icon(Lucide.messageSquarePlus), onSelect: () => comment(it), child: const Text('Add a comment')),
            GlacierMenuItem(icon: icon(it.starred ? Lucide.pinOff : Lucide.pin), onSelect: () => onPin(it), child: Text(it.starred ? 'Unpin' : 'Pin')),
            GlacierMenuItem(icon: icon(archived ? Lucide.archiveRestore : Lucide.archive), onSelect: () => onArchive(it, !archived), child: Text(archived ? 'Unarchive' : 'Archive')),
            if (workspaces != null) ...folderMoveRows(context, workspaces!, FolderCarry.note(it.id, title.isNotEmpty ? title : 'Untitled')),
            const GlacierMenuSeparator(),
            // In the one red the app has (NoteMenu.module.css `.danger`).
            GlacierMenuItem(danger: true, style: dangerRowStyle(t), icon: icon(Lucide.trash2), onSelect: () => onDelete(it), child: const Text('Delete')),
          ],
        );
      },
    );
  }
}
