import 'package:flutter/services.dart' show TextCapitalization, TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/icons.dart';
import '../core/workspaces.dart' show Workspace, WorkspaceStore, orgOfWorkspace, workspacePathName;
import '../sheet/kit.dart';
import '../sheet/sheet.dart';
import 'org_mark.dart';
import 'workspace_swatch.dart';

/// A workspace's sheet, from its folder in the sidebar, the row on the list or Settings › Workspaces: a name to add,
/// or the name of one to change, a colour for its pill, and Delete under it, which asks what becomes of its notes -
/// kept and unfiled, or put in the Trash with it (Matt: "I need a way to delete workspaces"). A port of
/// `src/app/notes/WorkspaceSheet.tsx`.
///
/// A new one is chosen as it is made, so the list lands in it with nothing in it yet. The colour of one that exists
/// is set as it is tapped, since it is a thing to look at rather than a thing to fill in; a new one carries its
/// colour into the making. An organization's workspace has no name, no swatch and no Remove here, only the way to
/// the organization's own screen.
///
/// What differs from the web:
/// - It is called `WorkspaceManageSheet`: `WorkspaceSheet` is already the kept record in core/workspaces.dart.
/// - Built only while it is open, as [Sheet] is: [editing] is the workspace it changes, or null for a new one (the
///   web's `which` was a workspace, `'new'`, or null for shut).
/// - It works on the [store] it is handed, where the web's module had one of its own.
/// - What touches notes is asked of the caller, since the trash is the library's and is not here yet: [notesIn] says
///   which notes a delete would ask about (the web's `notesInWorkspace`: those filed in it that are not already in
///   the trash; left out, every note filed in it), and [onTrashNotes] puts them in the trash before the workspace
///   goes (the web's `deleteWorkspace(id, { trashNotes: true })`). Without [onTrashNotes] the row that would use it
///   is there and cannot be pressed.
class WorkspaceManageSheet extends StatefulWidget {
  const WorkspaceManageSheet({super.key, required this.store, this.editing, this.parent, this.folders = false, required this.onClose, this.onOrganization, this.notesIn, this.onTrashNotes});

  final WorkspaceStore store;

  /// The workspace to rename, recolour or delete; null makes a new one.
  final Workspace? editing;

  /// For a new one: the workspace it is a folder inside, by id; null at the top (the port's own, 2026-10-16).
  final String? parent;

  /// Whether a workspace's sheet offers New folder inside and Move: the sidebar's and Settings' do; left out, the
  /// sheet is the web page's, row for row, as the tests that hold it to the page draw it.
  final bool folders;
  final VoidCallback onClose;

  /// An organization's own screen, for its workspace's one row.
  final void Function(String orgId)? onOrganization;

  /// The ids of the notes filed in a workspace that deleting it would ask about.
  final List<String> Function(String workspaceId)? notesIn;

  /// Puts these notes in the trash: "Delete, and move the notes to Trash".
  final void Function(List<String> noteIds)? onTrashNotes;

  @override
  State<WorkspaceManageSheet> createState() => _WorkspaceManageSheetState();
}

class _WorkspaceManageSheetState extends State<WorkspaceManageSheet> {
  late String _name = widget.editing?.name ?? '';
  late String _hue = widget.editing?.hue ?? 'ink';

  /// Delete pressed: the sheet asks what becomes of the notes before anything goes.
  bool _deleting = false;

  /// New folder inside pressed: the sheet makes a folder inside the one it is up for.
  bool _making = false;

  /// Move pressed: the sheet lists where the folder can go.
  bool _moving = false;

  @override
  void didUpdateWidget(WorkspaceManageSheet old) {
    super.didUpdateWidget(old);
    // `useEffect(..., [editing, which])`: another workspace in the same sheet starts again from its own.
    if (old.editing != widget.editing) {
      _name = widget.editing?.name ?? '';
      _hue = widget.editing?.hue ?? 'ink';
      _deleting = false;
      _making = false;
      _moving = false;
    }
  }

  List<String> _notesIn(String id) {
    final asked = widget.notesIn;
    if (asked != null) return asked(id);
    return [
      for (final entry in widget.store.value.of.entries)
        if (entry.value == id) entry.key,
    ];
  }

  /// `deleteWorkspace(id, { trashNotes })`, then shut.
  void _delete(Workspace space, List<String> notes, {required bool trashNotes}) {
    if (trashNotes) widget.onTrashNotes?.call(notes);
    widget.store.removeWorkspace(space.id);
    widget.onClose();
  }

  void _submit() {
    final editing = widget.editing;
    final clean = _name.trim();
    if (clean.isEmpty) return;
    if (editing != null && !_making) {
      widget.store.renameWorkspace(editing.id, _name);
    } else {
      final made = widget.store.addWorkspace(_name, _hue, _making ? editing?.id : widget.parent);
      if (made != null) widget.store.chooseWorkspace(made.id);
    }
    widget.onClose();
  }

  /// Where a folder can go: the top, and every personal workspace that is not it nor inside it; for a folder of an
  /// organization's, the organization's workspace and every folder of it (GHST-107), and never the top.
  Widget _moveSheet(Workspace editing) {
    final list = widget.store.value.list;
    final shared = orgOfWorkspace(list, editing.id) != null;
    final places = [for (final w in list) if (w.id != editing.id && widget.store.canMove(editing.id, w.id)) w];
    return Sheet(
      label: 'Move ${editing.name}',
      onBack: () => setState(() => _moving = false),
      onClose: widget.onClose,
      children: [
        SheetTitle.text('Move ${editing.name}'),
        SheetNote(shared ? 'Its notes and the folders inside it go with it, on disk too, and stay the organization’s.' : 'Its notes and the folders inside it go with it, on disk too.'),
        SheetGroup(
          children: [
            if (!shared)
              SheetRow(
                key: const ValueKey('move-top'),
                icon: const DrawnIconView(AppIcons.workspace, size: 18),
                label: 'At the top',
                chosen: editing.parent == null,
                onPress: () {
                  widget.store.moveWorkspace(editing.id, null);
                  widget.onClose();
                },
              ),
            for (final w in places)
              SheetRow(
                key: ValueKey('move-${w.id}'),
                icon: const DrawnIconView(AppIcons.workspace, size: 18),
                label: workspacePathName(list, w.id),
                chosen: editing.parent == w.id,
                onPress: () {
                  widget.store.moveWorkspace(editing.id, w.id);
                  widget.onClose();
                },
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    final org = editing?.org;

    if (editing != null && org != null) {
      final t = context.tokens;
      final size = t.fontSize('lg');
      return Sheet(
        label: editing.name,
        onClose: widget.onClose,
        children: [
          SheetTitle(
            child: Text.rich(
              TextSpan(children: [OrgMark.span(em: size, color: t.color('glacier-text')), TextSpan(text: editing.name)]),
            ),
          ),
          const SheetNote(
            'An organization’s workspace: its name and colour follow the organization, and it is on every member’s device. Notes filed here are the team’s: everyone in it reads and edits them.',
          ),
          SheetGroup(
            children: [
              SheetRow(
                label: 'Organization settings',
                hint: 'Members, invitations, its name and colour.',
                onPress: () {
                  widget.onClose();
                  widget.onOrganization?.call(org);
                },
                disabled: widget.onOrganization == null,
              ),
            ],
          ),
        ],
      );
    }

    if (editing != null && _deleting) {
      final notes = _notesIn(editing.id);
      final count = notes.length == 1 ? 'its 1 note' : 'its ${notes.length} notes';
      return Sheet(
        label: 'Delete ${editing.name}',
        onClose: widget.onClose,
        children: [
          SheetTitle.text('Delete ${editing.name}?'),
          SheetNote(notes.isNotEmpty ? 'What happens to $count?' : 'There are no notes in it.'),
          SheetGroup(
            children: [
              if (notes.isNotEmpty) ...[
                SheetRow(label: 'Delete, keep the notes', hint: 'They stay, just not filed in a workspace.', onPress: () => _delete(editing, notes, trashNotes: false)),
                SheetRow(
                  label: 'Delete, and move the notes to Trash',
                  hint: 'They can be restored from the Trash until it is emptied.',
                  danger: true,
                  onPress: () => _delete(editing, notes, trashNotes: true),
                  // The trash is the caller's: with none to send them to, this cannot be done.
                  disabled: widget.onTrashNotes == null,
                ),
              ] else
                SheetRow(label: 'Delete workspace', danger: true, onPress: () => _delete(editing, notes, trashNotes: false)),
              SheetRow(label: 'Cancel', onPress: () => setState(() => _deleting = false)),
            ],
          ),
        ],
      );
    }

    if (editing != null && _moving) return _moveSheet(editing);

    final clean = _name.trim();
    // A new folder, at the top or inside another: the one the sheet is up for, or the parent it was given.
    final inside = _making ? editing : widget.store.value.list.where((w) => w.id == widget.parent).firstOrNull;
    final making = editing == null || _making;
    final title = !making ? editing.name : (inside != null ? 'New folder in ${inside.name}' : 'New workspace');
    return Sheet(
      label: title,
      onBack: _making ? () => setState(() => _making = false) : null,
      onClose: widget.onClose,
      children: [
        SheetTitle.text(title),
        if (making)
          SheetNote(inside != null
              ? 'A workspace inside ${inside.name}: its folder on disk is inside ${inside.name}’s, and its notes show with ${inside.name}’s too.'
              : 'Notes filed in a workspace show together. A note made while one is chosen goes there.'),
        SheetGroup(
          children: [
            SheetField(
              label: 'Name',
              value: _name,
              onChange: (text) => setState(() => _name = text),
              autoFocus: true,
              autoCapitalize: TextCapitalization.words,
              enterKeyHint: TextInputAction.done,
              // `onKeyDown`: Enter adds or renames.
              onSubmitted: (_) => _submit(),
            ),
            SheetRow(label: !making ? 'Rename' : 'Add', onPress: _submit, disabled: clean.isEmpty || (!making && clean == editing.name)),
          ],
        ),
        const SheetHeading('Colour'),
        SheetGroup(
          children: [
            WorkspaceSwatch(
              hue: _hue,
              onHue: (picked) {
                setState(() => _hue = picked);
                // One that exists changes as it is tapped; a new one wears it when it is made.
                if (!making) widget.store.setWorkspaceHue(editing.id, picked);
              },
            ),
          ],
        ),
        // Folders inside folders: a new one inside this, or this moved into another.
        if (!making && widget.folders)
          SheetGroup(
            children: [
              SheetRow(
                key: const ValueKey('workspace-new-inside'),
                label: 'New folder inside',
                hint: 'A workspace in ${editing.name}.',
                onPress: () => setState(() {
                  _making = true;
                  _name = '';
                  _hue = 'ink';
                }),
              ),
              SheetRow(
                key: const ValueKey('workspace-move'),
                label: 'Move',
                hint: editing.parent == null ? 'At the top now.' : 'In ${workspacePathName(widget.store.value.list, editing.parent!)} now.',
                onPress: () => setState(() => _moving = true),
              ),
            ],
          ),
        if (!making)
          SheetGroup(
            children: [
              SheetRow(
                label: 'Delete workspace',
                hint: widget.store.childrenOf(editing.id).isEmpty ? 'Asks what happens to its notes first.' : 'Asks what happens to its notes first. The folders inside it stay, a level up.',
                danger: true,
                onPress: () => setState(() => _deleting = true),
              ),
            ],
          ),
      ],
    );
  }
}
