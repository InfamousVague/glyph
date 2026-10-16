import 'package:flutter/widgets.dart';

import '../../art/art.dart';
import '../../core/workspaces.dart';
import '../../notes/workspace_sheet.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'pane_parts.dart';
import 'settings_host.dart';

/// What Settings' search finds on Workspaces (`findable`, src/app/settings/WorkspacesPane.findable.ts), by the names
/// the page draws.
const List<SettingsFindable> workspacesFindable = [
  SettingsFindable('Your workspaces', 'workspace rename colour color delete remove'),
  SettingsFindable('New workspace', 'create make add workspace'),
];

/// Workspaces' row in the list: how many there are (SettingsSheet.tsx `workspaceSummary`).
String workspaceSummary(int count) => count == 0
    ? 'None yet'
    : count == 1
        ? '1 workspace'
        : '$count workspaces';

/// Port of `WorkspacesPane` (src/app/settings/WorkspacesPane.tsx): every workspace in one list, each a row that opens
/// its sheet (notes/workspace_sheet.dart) to rename it, colour it, or delete it, which asks what becomes of its
/// notes. An organization's workspace is listed apart: its name and colour are the organization's, and it goes when
/// the person leaves the organization, so its row opens the organization's own screen instead.
///
/// What differs from the web original:
/// - The workspaces are the [store] it is handed (the sheet's, in Settings), where the page's hook read the app's own.
/// - A row's count is of the notes [notesIn] answers, which the caller keeps clear of the trash (the web's
///   `notesInWorkspace`); with none given it is every note filed there. [onTrashNotes] is the sheet's "Delete, and
///   move the notes to Trash", which cannot be pressed without it.
/// - The sheet is the Flutter port's `WorkspaceManageSheet`, built beside the page's cards while it is up; it draws
///   itself over the window.
class WorkspacesPane extends StatefulWidget {
  const WorkspacesPane({super.key, required this.store, this.onOrganization, this.notesIn, this.onTrashNotes});

  final WorkspaceStore store;

  /// Opens an organization's own screen.
  final void Function(String orgId)? onOrganization;
  final List<String> Function(String workspaceId)? notesIn;
  final void Function(List<String> noteIds)? onTrashNotes;

  /// The page as Settings mounts it: the sheet's store and callbacks.
  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return WorkspacesPane(
      store: host?.workspaces ?? WorkspaceStore(),
      onOrganization: host?.onOrganization,
      notesIn: host?.notesInWorkspace,
      onTrashNotes: host?.onTrashNotes,
    );
  }

  @override
  State<WorkspacesPane> createState() => _WorkspacesPaneState();
}

/// Which sheet is up: one workspace's, or a new one's.
class _Manage {
  const _Manage(this.editing);
  final Workspace? editing;
}

class _WorkspacesPaneState extends State<WorkspacesPane> {
  _Manage? _manage;

  String _notes(Workspace space) {
    final asked = widget.notesIn;
    final count = asked != null ? asked(space.id).length : widget.store.value.of.values.where((id) => id == space.id).length;
    return count == 1 ? '1 note' : '$count notes';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final list = widget.store.value.list;
          final personal = [for (final space in list) if (space.org == null) space];
          final teams = [for (final space in list) if (space.org != null) space];
          final manage = _manage;
          // The sheet edits the workspace as it is now, not as it was when its row was pressed.
          final editing = manage?.editing == null ? null : list.where((space) => space.id == manage!.editing!.id).firstOrNull;
          final page = PaneBody(
            children: [
              PaneSection(
                title: 'Your workspaces',
                description: const Text('Notes filed in a workspace show together. A note made while one is chosen goes there.'),
                children: [
                  if (personal.isNotEmpty)
                    for (final space in personal)
                      SettingRow(key: ValueKey(space.id), icon: HueMark(hue: space.hue), label: space.name, hint: Text(_notes(space)), onPress: () => setState(() => _manage = _Manage(space)))
                  else
                    const SettingRow(icon: AppIcon(Lucide.folder, size: 20), label: 'None yet', hint: Text('Make one below.')),
                  SettingRow(icon: const AppIcon(Lucide.plus, size: 20), label: 'New workspace', onPress: () => setState(() => _manage = const _Manage(null))),
                ],
              ),
              if (teams.isNotEmpty)
                PaneSection(
                  title: 'Organizations’ workspaces',
                  description: const Text('Named and coloured after the organization. One goes when you leave its organization.'),
                  children: [
                    for (final space in teams)
                      SettingRow(
                        key: ValueKey(space.id),
                        icon: HueMark(hue: space.hue),
                        label: space.name,
                        hint: Text(_notes(space)),
                        onPress: widget.onOrganization == null ? null : () => widget.onOrganization!(space.org!),
                      ),
                  ],
                ),
              const SettingsFootnote(
                child: Text('Deleting a workspace asks first whether its notes stay, unfiled, or go to the Trash with it. Nothing is deleted for good until the Trash is emptied.'),
              ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              page,
              // Drawn in the app's overlay, over the window; here it takes no room.
              if (manage != null && (manage.editing == null || editing != null))
                WorkspaceManageSheet(
                  store: widget.store,
                  editing: editing,
                  folders: true,
                  onClose: () => setState(() => _manage = null),
                  onOrganization: widget.onOrganization,
                  notesIn: widget.notesIn,
                  onTrashNotes: widget.onTrashNotes,
                ),
            ],
          );
        },
      );
}
