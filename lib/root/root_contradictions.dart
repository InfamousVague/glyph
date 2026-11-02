part of 'ghost_root.dart';

/// The contradiction finder as the app wires it (lib/ai/contradictions/, lib/plugins/contradictions/;
/// docs/CONTRADICTIONS.md; Matt, 2026-11-02: "Contradiction finder: spots when a newer note disagrees with an older one
/// … and flags the stale one inline"): the runner made over the library, its books kept beside the notes in the
/// Library's `.glyph/` (an organization's in `orgs/<Org>/.glyph/`), and in the device's storage where the library has no
/// folder Dart can reach; the library's changes heard for When a note is saved; a found or settled finding asks the
/// open note's line words again and the home page's notices again.
class _RootContradictions {
  _RootContradictions(this._root);

  final _GhostRootState _root;

  ContradictionRunner? _runner;
  String? _folderRoot;

  Future<void> start() async {
    final library = _root._library;
    final folder = _root._libraryFolder;
    if (folder != null && !kIsWeb) {
      try {
        final status = await folder.status();
        final root = status.kind == 'folder' && status.reachable && status.path != null ? status.path : status.own;
        if (status.kind != 'tree' && root != null && root.isNotEmpty) _folderRoot = root;
      } catch (_) {
        _folderRoot = null;
      }
    }
    final root = _folderRoot;
    final runner = _runner = ContradictionRunner(
      notes: () => library.value,
      pickAi: appContradictionAi,
      fileFor: root == null ? null : (scope) => DiskFindingsFile(scope.fileIn(root)),
      enabled: () => plugins.isEnabled(contradictions.manifest.id),
      onOpen: () => _root._openSettingsAt(pluginPageId(contradictions.manifest.id)),
      writeNote: (id, change) async {
        final note = await library.get(id);
        if (note == null) return;
        final next = change(note.body);
        if (next != note.body) await library.save(id, next);
      },
    );
    runner.onFindings = () {
      plugins.offersChanged();
      if (_root.mounted) _root._told(() {});
    };
    contradictionOpenNote = (id) => unawaited(_root._openNoteFromLink(id));
    contradictionRunner.value = runner;
    library.addListener(runner.notesChanged);
    runner.start();
  }

  /// The home page's line while anything may be out of date and the plugin is on.
  Widget? notice() {
    final runner = _runner;
    if (runner == null || runner.staleNotes == 0 || !plugins.isEnabled(contradictions.manifest.id)) return null;
    return ContradictionsNotice(runner: runner, onOpen: () => _root._openSettingsAt(pluginPageId(contradictions.manifest.id)));
  }

  void dispose() {
    final runner = _runner;
    if (runner == null) return;
    _root._library.removeListener(runner.notesChanged);
    if (identical(contradictionRunner.value, runner)) contradictionRunner.value = null;
    contradictionOpenNote = null;
    runner.dispose();
  }
}
