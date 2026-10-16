/// Where a note is filed, on its More sheet: the workspaces to choose from with the note's own ticked, a name for a
/// new one that files the note there as it is made, and a way out of the one it is in. A port of
/// `src/app/editor/WorkspacePicker.tsx`.
///
/// A note filed in an organization's workspace is the team's, so taking it out, or moving it to another workspace,
/// takes it from everyone in the organization: that press is asked twice, armed for four seconds in between.
///
/// What differs: the workspaces are the [WorkspaceStore] it is given, listened to, where the page read a module.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../art/icons.dart';
import '../core/workspaces.dart';
import '../sheet/flow.dart';
import '../sheet/kit.dart';

class WorkspacePicker extends StatefulWidget {
  const WorkspacePicker({super.key, required this.noteId, required this.workspaces, required this.onDone});

  final String noteId;
  final WorkspaceStore workspaces;
  final VoidCallback onDone;

  @override
  State<WorkspacePicker> createState() => _WorkspacePickerState();
}

class _WorkspacePickerState extends State<WorkspacePicker> {
  String _name = '';

  /// The move out of the team armed: which destination, so a second press on the same row goes through.
  String? _armed;
  Timer? _disarm;

  @override
  void initState() {
    super.initState();
    widget.workspaces.addListener(_changed);
  }

  @override
  void dispose() {
    widget.workspaces.removeListener(_changed);
    _disarm?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _arm(String key) {
    _disarm?.cancel();
    setState(() => _armed = key);
    _disarm = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _armed = null);
    });
  }

  void _choose(String? id) {
    final filed = widget.workspaces.workspaceOf(widget.noteId);
    final team = filed != null && isOrgWorkspace(filed.id);
    final key = id ?? 'none';
    if (team && id != filed.id && _armed != key) return _arm(key);
    widget.workspaces.fileNote(widget.noteId, id);
    widget.onDone();
  }

  void _make() {
    final made = widget.workspaces.addWorkspace(_name);
    if (made != null) _choose(made.id);
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.workspaces.value.list;
    final filed = widget.workspaces.workspaceOf(widget.noteId);
    final team = filed != null && isOrgWorkspace(filed.id);
    final sentence = _armed != null
        ? 'This takes the note away from everyone in ${filed?.name ?? 'the organization'}. Press again to go on.'
        : team
            ? 'Filed in ${filed.name}, this note is the team’s: everyone in it reads and edits it.'
            : list.isNotEmpty
                ? 'Notes in a workspace show together on the list. Filed in an organization’s, a note is the team’s.'
                : 'A name to file notes under. The list can then show one workspace at a time.';
    return CssFlow(
      collapse: true,
      children: [
        SheetTitle.text('Workspace'),
        SheetNote(sentence),
        if (list.isNotEmpty)
          SheetGroup(
            children: [
              for (final workspace in list)
                // A folder inside another says where: "Work › Clients".
                SheetRow(key: ValueKey('workspace:${workspace.id}'), icon: const DrawnIconView(AppIcons.workspace, size: 18), label: workspace.parent == null ? workspace.name : workspacePathName(list, workspace.id), chosen: filed?.id == workspace.id, onPress: () => _choose(workspace.id)),
            ],
          ),
        SheetGroup(
          children: [
            SheetField(
              label: 'New workspace',
              value: _name,
              onChange: (text) => setState(() => _name = text),
              autoCapitalize: TextCapitalization.words,
              enterKeyHint: TextInputAction.done,
              onSubmitted: (_) => _make(),
            ),
            SheetRow(label: 'Add it and file this note there', onPress: _make, disabled: _name.trim().isEmpty),
          ],
        ),
        if (filed != null)
          SheetGroup(
            children: [
              SheetRow(label: _armed == 'none' ? 'Press again to take it from the team' : 'Take this note out of ${filed.name}', onPress: () => _choose(null)),
            ],
          ),
      ],
    );
  }
}
