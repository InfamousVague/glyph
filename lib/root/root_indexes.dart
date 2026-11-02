part of 'ghost_root.dart';

/// The self-maintaining indexes, as the root wires them (docs/AI_INDEXES.md; Matt, 2026-11-02: "for any folder or org,
/// the AI keeps an index note (what's here, the key decisions, who owns what) and updates it as notes change. New
/// teammates read one page instead of fifty."): the keeper over the library, writing through `_changeNote` so an open
/// page's editor takes the section as an edit; who writes (Local only the device's model alone, else the assistant's
/// provider, else the device's); a folder's page made where it has none; the card in a folder's menu's sheet and on a
/// teamspace's home.
///
/// One of the files `_GhostRootState` is written in (lib/root/ghost_root.dart says which).
extension _RootIndexes on _GhostRootState {
  /// Who writes an index now.
  IndexAiPick _indexAi() => pickIndexAi(
        localOnly: preferences.value.localOnly,
        cloud: () => cloudIndexAi(appAssistant, claudeSettings),
        device: () => switch (_availability?.availability) {
          Available(:final model) => DeviceIndexAi(model),
          _ => null,
        },
      );

  /// Makes [folder]'s page where it has none: an organization's top its `Home.md` from the template, any other folder
  /// its `index.md` (`# <title>`), filed with the folder as a drag's order files one (lib/core/page_tree.dart).
  Future<Note?> _makeFolderPage(String folder, String title) async {
    final list = _workspaces.value.list;
    for (final space in spacesFor(list)) {
      if (space.folder == folder && space.orgId != null) {
        final made = await PageMover(library: _library, workspaces: _workspaces).createHome(space);
        await _library.refresh().catchError((Object _) {});
        return made;
      }
    }
    final made = await _library.createNote(folderPageBody(title));
    final whole = await _library.get(made.id) ?? made;
    final to = '$folder/index.md';
    final placed = await _library.apply(whole.copyWith(path: () => to));
    if (placed.path != to) return null;
    fileByFolder(_workspaces, made.id, folder);
    await _library.refresh().catchError((Object _) {});
    return placed;
  }

  /// A folder's menu's "Keep an index…": its card in a sheet.
  void _keepIndex(Workspace folder) {
    final dir = folderFor(folder, _workspaces.value.list);
    if (dir == null || !mounted) return;
    showIndexSheet(context, keeper: _indexKeeper, folder: dir, title: folder.name, simple: preferences.value.simple, onOpen: (id) {
      final shell = _shell.currentState;
      if (shell != null) _openWhereLeft(shell, id);
    });
  }

  /// A teamspace's index card, under its home page.
  Widget _indexCardOf(AppShellState shell, Space space) {
    final folder = space.folder;
    if (folder == null) return const SizedBox.shrink();
    return IndexCard(keeper: _indexKeeper, folder: folder, title: space.name, simple: preferences.value.simple, onOpen: (id) => _openWhereLeft(shell, id));
  }
}
