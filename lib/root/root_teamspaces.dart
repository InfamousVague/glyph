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
  Future<void> _createHome(String orgId, {DocsMode docs = DocsMode.edit}) async {
    final space = _spaceOf(orgId);
    if (space == null) return;
    try {
      final made = await PageMover(library: _library, workspaces: _workspaces).createHome(space, docs: docs);
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
