part of 'ghost_root.dart';

/// Ask, as the root wires it (docs/ASK_THE_ORG.md; Matt, 2026-11-02: "'Ask the org' with receipts: questions answered
/// only from your notes, every claim linked to the note and line it came from; when notes disagree, it shows both
/// instead of guessing"): the sheet over the app, its scopes from the workspaces (My notes, each organization this
/// device has a workspace for, the folders), the notes read from the library on the device, who answers from the AI
/// choice and Local only, a receipt opening its note at its lines, and Save as note filed where the scope is.
///
/// One of the files `_GhostRootState` is written in (lib/root/ghost_root.dart says which), as root_claude.dart is.
extension _RootAsk on _GhostRootState {
  /// The organizations this device has a workspace for, by id and name.
  List<({String id, String name})> get _askOrgs => [
        for (final w in _workspaces.value.list)
          if (orgIdOf(w.id) case final id?) (id: id, name: w.name),
      ];

  /// What a scope is read against: the filing, and an unfiled note's path under `orgs/` (root_teamspaces.dart).
  AskWorld get _askWorld => AskWorld.of(_workspaces.value, orgOfPath: (note) => _orgOfNoteForTools(note.id));

  /// The scope the note on screen is in, else My notes: Ask from inside a team's page asks that team.
  AskScope _askScopeHere() {
    final screen = _shell.currentState?.screen;
    if (screen is ScreenNote) {
      final org = _orgOfNoteForTools(screen.note.id);
      if (org != null) {
        final named = _askOrgs.where((o) => o.id == org).firstOrNull;
        if (named != null) return AskScope.org(named.id, named.name);
      }
    }
    return const AskScope.mine();
  }

  /// Opens the sheet on [scope] (the note on screen's, where none is given).
  void _openAsk([AskScope? scope]) {
    _shell.currentState?.closeSidebar();
    _told(() => _askSheet = (scope: scope ?? _askScopeHere()));
  }

  /// Ask an organization, by id: its teamspace home's Ask, and the palette's.
  void _openAskOrg(String orgId) {
    final named = _askOrgs.where((o) => o.id == orgId).firstOrNull;
    if (named != null) _openAsk(AskScope.org(named.id, named.name));
  }

  /// The palette's Ask commands: My notes, and each organization.
  List<({String key, String title, VoidCallback run})> get _askCommands => [
        (key: 'mine', title: 'Ask my notes', run: () => _openAsk(const AskScope.mine())),
        for (final org in _askOrgs) (key: 'org:${org.id}', title: 'Ask ${org.name}', run: () => _openAsk(AskScope.org(org.id, org.name))),
      ];

  /// Who answers now (lib/ask/ask_model.dart).
  AskModel? _askModel() {
    final prefs = preferences.value;
    return askModelFor(choice: appAssistant, claude: claudeSettings, localOnly: prefs.localOnly, deviceModel: prefs.formatModel, deviceRuns: engine.aiBackend.available);
  }

  /// Files [result] as a note where its scope is: the organization's workspace, the folder, or, for your own notes,
  /// the personal workspace chosen (never an organization's, which would hand your notes' answer to the team).
  Future<String?> _saveAsk(AskResult result) async {
    final made = await _library.createNote(askNoteBody(result));
    final scope = result.scope;
    final spaces = _workspaces.value;
    switch (scope.kind) {
      case AskScopeKind.org:
        _workspaces.fileNote(made.id, orgWorkspaceId(scope.orgId!));
      case AskScopeKind.folder:
        _workspaces.fileNote(made.id, scope.workspaceId);
      case AskScopeKind.mine:
        final current = spaces.current;
        if (current != null && orgOfWorkspace(spaces.list, current.id) == null) _workspaces.fileNote(made.id, current.id);
    }
    await _library.refresh().catchError((Object _) {});
    return askNoteTitle(result.question);
  }

  Widget _askPart(BuildContext context) {
    final sheet = _askSheet;
    if (sheet == null) return _RootParts._nothing;
    final world = _askWorld;
    return AskSheet(
      key: ValueKey('ask-sheet:${sheet.scope.key}'),
      scope: sheet.scope,
      scopes: askScopes(_askOrgs),
      folders: askFolders(_workspaces.value.list),
      notesOf: (scope) => notesInScope(_library.value, scope, world),
      model: _askModel,
      onOpen: (noteId, at) {
        _told(() => _askSheet = null);
        _shell.currentState?.openNote(noteId, at: at);
      },
      onSave: _saveAsk,
      onClose: () => _told(() => _askSheet = null),
      simple: preferences.value.simple,
      now: () => widget.clock?.call() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
