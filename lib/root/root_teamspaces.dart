part of 'ghost_root.dart';

/// A team's pages, as the root wires them (docs/TEAMSPACES.md; Matt, 2026-10-31: "Build first: all four: the sidebar
/// and page tree, the doc page UI, the teamspace home and members, presence"): the teamspace home on the
/// organization's dashboard (its drawing, Create the home page, Pages open in), a member's page, Follow and the
/// first edit's following on a team page's desk, a mention's following, and the changes to followed pages in the
/// Updates inbox.
///
/// One of the files `_GhostRootState` is written in (lib/root/ghost_root.dart says which), as root_tickets.dart is.
extension _RootTeamspaces on _GhostRootState {
  /// What a note's desk is handed for a team's pages (lib/team/follow.dart).
  TeamPageSeams get _teamPageSeams => TeamPageSeams(
        me: () => _me,
        teamPage: _teamNote,
        ledger: _followLedger,
        openMember: (orgId, handle) => _shell.currentState?.openOrganizationMember(orgId, handle),
      );

  /// The changes to the pages this account follows, made the first time the bell asks and kept from then on.
  DocUpdatesFeed get _docUpdates => _docUpdatesMade ??= DocUpdatesFeed(
        notes: _library,
        changes: _followedChanges,
        watch: _followedChanges.watch,
        me: () => _me,
        team: _teamNote,
        stored: _stored,
      )..addListener(_docUpdatesChanged);

  void _docUpdatesChanged() {
    _docsAt += 1;
    _tick.tell();
  }

  /// The organization's space, home page and the ways to make and set it, for its dashboard.
  Space? _spaceOf(String orgId) => spaceOfOrg(_workspaces.value.list, orgId);

  /// Makes the organization's home page (`orgs/<Org>/Home.md`), filed in its workspace, so the team has it.
  Future<void> _createHome(String orgId, {DocsMode docs = DocsMode.edit, Iterable<String> plugins = const []}) async {
    final space = _spaceOf(orgId);
    if (space == null) return;
    try {
      final made = await PageMover(library: _library, workspaces: _workspaces).createHome(space, docs: docs, plugins: plugins);
      await _library.refresh().catchError((Object _) {});
      if (made == null && mounted) _say(context, 'The home page could not be put in ${space.name}’s folder.');
    } catch (failure) {
      if (mounted) _say(context, 'The home page was not made: $failure');
    }
  }

  /// The home page's `docs:` set to [mode]; the home page made with it where there is none yet.
  Future<void> _setDocs(String orgId, DocsMode mode) async {
    final space = _spaceOf(orgId);
    if (space == null) return;
    final home = teamspaceHomeIn(_library.value, space);
    if (home == null) return _createHome(orgId, docs: mode);
    await _changeNote(home.id, (body) => withDocsMode(body, mode), userEvent: 'teamspace.docs').catchError((Object _) {});
  }

  // ---- the project tools (docs/PM_PLUGINS.md) -----------------------------------------------------------------------

  /// Makes the root's suite the app's, and hears what may move its answers: the library and the workspaces (an
  /// organization's home page, which notes are a team's); the registry's switches it hears by itself.
  void _startProjectSuite() {
    useProjectSuite(_suite);
    _libraryChanges.addListener(_projectsHeard);
    _workspaces.addListener(_projectsHeard);
    _suite.addListener(_toolsMoved);
  }

  /// The organization a note is in: its workspace's, else the one whose folder its path is under; null for a
  /// personal note.
  String? _orgOfNoteForTools(String noteId) {
    final list = _workspaces.value.list;
    final filed = _workspaces.workspaceOf(noteId);
    if (filed != null) return orgOfWorkspace(list, filed.id);
    final path = _library.noteOf(noteId)?.path;
    if (path == null || !path.startsWith('$orgsFolder/')) return null;
    for (final space in spacesFor(list)) {
      final folder = space.folder;
      if (space.orgId != null && folder != null && path.startsWith('$folder/')) return space.orgId;
    }
    return null;
  }

  /// The tools an organization's home page lists; null where this device has no workspace for it.
  Set<String>? _orgToolsListed(String orgId) {
    final space = _spaceOf(orgId);
    if (space == null) return null;
    return TeamspaceSettings.of(teamspaceHomeIn(_library.value, space)?.body).plugins;
  }

  /// The organizations this device has a workspace for.
  List<String> _orgIdsHere() => [for (final w in _workspaces.value.list) ?orgIdOf(w.id)];

  String? _orgNameHere(String orgId) {
    for (final w in _workspaces.value.list) {
      if (w.id == orgWorkspaceId(orgId)) return w.name;
    }
    return null;
  }

  /// The tools an organization's notes use (`NoteFacts.tools`), its home page's own left out.
  Set<String> _toolsUsedIn(String orgId) {
    final out = <String>{};
    final space = _spaceOf(orgId);
    final home = space == null ? null : teamspaceHomeIn(_library.value, space);
    for (final note in _shown) {
      if (note.id == home?.id) continue;
      final tools = NoteFacts.of(note).tools;
      if (tools.isEmpty || out.containsAll(tools)) continue;
      if (_orgOfNoteForTools(note.id) == orgId) out.addAll(tools);
    }
    return out;
  }

  /// Writes an organization's tools into its home page's `plugins:`, the home page made with them where there is
  /// none yet. Answers whether they were written.
  Future<bool> _writeOrgTools(String orgId, Set<String> tools) async {
    final space = _spaceOf(orgId);
    if (space == null) return false;
    final home = teamspaceHomeIn(_library.value, space);
    try {
      if (home == null) {
        final made = await PageMover(library: _library, workspaces: _workspaces).createHome(space, plugins: tools);
        await _library.refresh().catchError((Object _) {});
        return made != null;
      }
      await _changeNote(home.id, (body) => withProjectPlugins(body, tools), userEvent: 'teamspace.plugins');
      return true;
    } catch (failure) {
      if (mounted) _say(context, 'The tools were not turned on: $failure');
      return false;
    }
  }

  /// A mention of this account in a team page follows the page, once per mention (lib/team/follow.dart
  /// [autoFollowMention]): read as the feed changes, each row once its seal has opened and the page is here.
  void _followMentions() {
    final services = _services;
    final me = _me;
    if (services == null || me == null) return;
    final feed = services.feed;
    for (final n in services.notifications) {
      if (!isMention(n) || _followLedger.done(me, mentionReason(n.id))) continue;
      final details = feed?.openDetails(n);
      if (details == null) continue;
      final note = _library.noteOf(details.noteId);
      if (note == null || !_teamNote(note.id)) continue;
      if (!autoFollowMention(notificationId: n.id, me: me, ledger: _followLedger)) continue;
      if (follows(note.body, me)) continue;
      unawaited(_changeNote(note.id, (body) => withFollowing(body, me, true), userEvent: 'follow').catchError((Object _) {}));
    }
  }

  /// A member's page, under the organization's dashboard.
  Widget _memberPage(AppShellState shell, String orgId, String handle) => MemberPage(
        services: _services,
        orgId: orgId,
        handle: handle,
        notes: shell.notes,
        record: _versions,
        seen: _seenIn(orgId),
        onBack: () => shell.openOrganization(orgId),
        onOpenNote: (note) => _openWhereLeft(shell, note),
        wisp: preferences.value.wispEdge,
      );
}
