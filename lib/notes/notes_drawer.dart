import 'package:flutter/widgets.dart';

import '../core/note.dart';
import '../core/smart_notebooks.dart';
import '../core/stored.dart';
import '../core/workspaces.dart' show WorkspaceStore;
import 'floating_card.dart';
import 'note_peek.dart';
import 'note_tree.dart';

/// Every note, in a card that floats over the one being read (Matt: "add a sidebar that opens as a floating card,
/// add a sidebar icon on the top left of the page"). The icon is at the left of the tab row; this is what it opens.
/// A port of `src/app/notes/NotesDrawer.tsx`.
///
/// The same tree the docked sidebar is (note_tree.dart), in a card over the note: a close joins its tools. A tap
/// opens a note, which also gives it a tab, so the card is a way between notes rather than a way out of the one
/// open. It closes on a press outside, on Escape or the phone's back gesture, and before it opens the palette; the
/// card itself, and those rules, are [FloatingCard]'s.
///
/// What differs from the web: the icon that opens it is wrapped in a [FloatingCardToggle] named [sidebarToggle]
/// (the page's `[data-sidebar-toggle]`), so that a press on it is the icon's to answer; and everything
/// [NoteTree] asks of its caller here is asked of this one's.
class NotesDrawer extends StatelessWidget {
  const NotesDrawer({
    super.key,
    required this.open,
    required this.notes,
    required this.activeId,
    required this.onOpen,
    required this.onNew,
    required this.onClose,
    required this.workspaces,
    this.onCommands,
    this.onSettings,
    this.onSpeak,
    this.notices = const [],
    this.trashed = const [],
    this.onRestore,
    this.onDestroy,
    this.onEmptyTrash,
    this.onOpenTrash,
    this.onOrganization,
    this.onBrowseFiles,
    this.onGraph,
    this.onNoteMenu,
    this.notesInWorkspace,
    this.onTrashNotes,
    this.stored,
    this.peek = NotePeek.plain,
    this.emptyArt,
    this.smart,
    this.onSmart,
    this.onManageSmart,
    this.onTags,
    this.onMarket,
    this.onTickets,
    this.ticketCount,
    this.simple = false,
  });

  final bool open;
  final List<Note> notes;
  final String? activeId;
  final void Function(String id) onOpen;
  final VoidCallback onNew;
  final VoidCallback onClose;
  final WorkspaceStore workspaces;

  /// The command palette, where a phone has no ⌘K to open it with: the drawer is the one surface that is a tap away
  /// from every route. Absent until the palette is mounted.
  final VoidCallback? onCommands;
  final VoidCallback? onSettings;
  final VoidCallback? onSpeak;

  /// An update waiting, on a wide window where the card stands in for the docked sidebar.
  final List<Widget> notices;

  /// The trash, passed through to the tree.
  final List<Note> trashed;
  final void Function(Note note)? onRestore;
  final void Function(Note note)? onDestroy;
  final VoidCallback? onEmptyTrash;

  /// The Trash's own page, from its folder (lib/notes/note_tree.dart `onOpenTrash`).
  final ValueChanged<String?>? onOpenTrash;

  /// An organization's own screen, from its folder's menu.
  final void Function(String orgId)? onOrganization;
  final VoidCallback? onBrowseFiles;

  /// The graph of the notes and their links (lib/links/graph_view.dart).
  final VoidCallback? onGraph;
  final void Function(String id, Offset at)? onNoteMenu;
  final List<String> Function(String workspaceId)? notesInWorkspace;
  final void Function(List<String> noteIds)? onTrashNotes;
  final Stored? stored;
  final NotePeekBuilder peek;
  final Widget? emptyArt;

  /// The smart notebooks and the Tags page, passed through to the tree.
  final SmartNotebookStore? smart;
  final void Function(String id)? onSmart;
  final void Function(SmartNotebook notebook)? onManageSmart;
  final VoidCallback? onTags;

  /// The Market; its row under Tags is there only with this.
  final VoidCallback? onMarket;

  /// My tickets, and how many are yours: its row over Tags is there only with this.
  final VoidCallback? onTickets;
  final ({int all, int overdue})? ticketCount;

  /// Simple mode (GHST-103), passed through to the tree.
  final bool simple;

  @override
  Widget build(BuildContext context) {
    // Draws nothing while it is shut.
    if (!open) return const SizedBox.shrink();
    final commands = onCommands;
    return FloatingCard(
      label: 'Your notes',
      toggle: sidebarToggle,
      onClose: onClose,
      child: NoteTree(
        notes: notes,
        activeId: activeId,
        onOpen: onOpen,
        onNew: onNew,
        onClose: onClose,
        workspaces: workspaces,
        onCommands: commands == null
            ? null
            : () {
                onClose();
                commands();
              },
        onSettings: onSettings,
        onSpeak: onSpeak,
        notices: notices,
        trashed: trashed,
        onRestore: onRestore,
        onDestroy: onDestroy,
        onEmptyTrash: onEmptyTrash,
        onOpenTrash: onOpenTrash,
        onOrganization: onOrganization,
        onBrowseFiles: onBrowseFiles,
        onGraph: onGraph,
        onNoteMenu: onNoteMenu,
        notesInWorkspace: notesInWorkspace,
        onTrashNotes: onTrashNotes,
        stored: stored,
        peek: peek,
        emptyArt: emptyArt,
        smart: smart,
        onSmart: onSmart,
        onManageSmart: onManageSmart,
        onTags: onTags,
        onMarket: onMarket,
        onTickets: onTickets,
        ticketCount: ticketCount,
        simple: simple,
      ),
    );
  }
}
