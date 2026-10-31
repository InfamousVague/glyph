part of 'ghost_root.dart';

/// The ticket features as the app wires them (Matt, 2026-10-31: rules, GitHub pull request links, time tracking):
/// the notebooks' rules heard on this device's saves and run with the buttons' world (root_buttons.dart) and the bell,
/// the timers in the synced settings, and the pull requests read on GitHub with the plugin's token, each merge moved
/// once. What each does is its own file's (lib/book/rule_runs.dart, lib/book/timers.dart,
/// lib/plugins/github/pull_links.dart); this is only the doing.
///
/// One of the files `_GhostRootState` is written in (lib/root/ghost_root.dart says which).
class _RootTicketRules {
  _RootTicketRules(this._root);

  final _GhostRootState _root;

  TicketRules? rules;
  TicketTimers? timers;
  VoidCallback? _stopRules;
  Timer? _githubSoon;
  Timer? _githubEvery;

  NoteLibrary get _library => _root._library;

  /// Started once the library is the core's: what the rules hear is its own saves.
  void start() {
    final library = _library;
    rules = TicketRules(
      device: thisDevice,
      preferences: () => preferences.value,
      setPreferences: preferences.update,
      notes: () => _library.value,
      world: () => _world,
      syncNow: () async => await _root._services?.engine?.syncNow(),
      accountHeld: () => _root._services?.engine?.accountPrefs,
      isTrashed: _root._trash.isTrashed,
    );
    if (library is CoreLibrary) _stopRules = rules!.start(library.savedHere, changes: _library);
    final made = timers = TicketTimers(
      device: thisDevice,
      preferences: () => preferences.value,
      setPreferences: preferences.update,
      prefsChanged: preferences,
      write: (noteId, change) => _root._changeNote(noteId, change, userEvent: 'input.timer'),
      who: () => _root._services?.session?.handle ?? '',
    );
    ticketTimers.value = made;
    ticketCardTimer = (look, noteId, {required title, ticketKey}) => TicketCardTimer(look: look, timers: made, noteId: noteId, title: title, ticketKey: ticketKey);
    // The pull requests, a while after the notes change (a sync brought them) and every ten minutes.
    _library.addListener(_notesChanged);
    _githubEvery = Timer.periodic(const Duration(minutes: 10), (_) => unawaited(_github()));
    _notesChanged();
  }

  void dispose() {
    _stopRules?.call();
    _library.removeListener(_notesChanged);
    _githubSoon?.cancel();
    _githubEvery?.cancel();
    if (identical(ticketTimers.value, timers)) ticketTimers.value = null;
    ticketCardTimer = null;
    timers?.dispose();
  }

  // ---- what a rule reaches with ---------------------------------------------------------------------------------

  RuleWorld get _world {
    final buttons = _root._buttonWorld;
    return RuleWorld(
      setFields: (noteId, fields) => _root._changeNote(noteId, (body) => fields.entries.fold<String>(body, (was, field) => withTicketProperty(was, field.key, field.value.trim().isEmpty ? null : field.value.trim())), userEvent: 'input.rule'),
      post: buttons.post,
      claude: buttons.claude,
      make: buttons.make,
      notify: _notify,
    );
  }

  /// A person told by a rule: the person themself through the bell, a row of their own feed (lib/sync/record.dart);
  /// a member of the ticket's organization through the mentions route, as an @mention is told
  /// (lib/mentions/mention_notices.dart). The row's id comes from the run's, so a retry tells nobody twice.
  Future<void> _notify(RuleNotice notice) async {
    final services = _root._services;
    final session = services?.session;
    if (services == null || session == null) throw 'Sign in to Ghost.md to be told by your rules.';
    final id = toBase64Url(hashes.sha256.convert(utf8.encode('rule\u0000${notice.id}')).bytes.sublist(0, 24));
    final person = notice.person.replaceFirst(RegExp('^@'), '');
    if (person == 'me' || handleKey(person) == handleKey(session.handle)) {
      final record = services.engine?.record;
      if (record == null) throw 'The bell is not ready on this device yet.';
      await record.recordAs(id, ticketRuleKind, {'noteId': notice.noteId, 'title': notice.title, 'by': 'A rule', 'first': notice.words});
      return;
    }
    final space = _root._workspaces.workspaceOf(notice.noteId);
    final org = space == null ? null : orgOfWorkspace(_root._workspaces.value.list, space.id);
    if (org == null) throw 'Only you can be told about a ticket in your own notebook. File it in an organization to tell $person.';
    final key = services.orgKeys?.orgKeyOf(org);
    if (key == null) throw 'This device does not hold the organization’s key yet. Try again after it syncs.';
    final payload = mentionPayload(noteId: notice.noteId, title: notice.title, by: session.handle, line: notice.words, lineNo: 1);
    final blob = await services.account.crypto.seal(key, payload, mentionContext(org, id));
    await services.account.api.call('POST', 'orgs/${Uri.encodeComponent(org)}/mentions', token: session.token, body: {'id': id, 'to': [person], 'blob': blob, 'generation': services.orgKeys!.orgKeyGeneration(org)});
  }

  // ---- the panel, and the palette -------------------------------------------------------------------------------

  /// The open ticket's work for its panel: its timer, and its pull requests where its notebook names repos.
  TicketWorkOptions? work(String noteId) {
    final entry = _root._reads.entries.where((each) => each.note.id == noteId).firstOrNull;
    if (entry == null) return null;
    final key = entry.ticket.id;
    final repos = entry.notebook == null ? const <String>[] : githubReposOf(entry.notebook!.body);
    final linked = key != null && repos.isNotEmpty;
    return TicketWorkOptions(
      noteId: noteId,
      title: entry.title,
      ticketKey: key,
      timers: timers,
      pulls: linked ? () => pullLinks.pullsFor(key, repos) : null,
      pullsChanged: linked ? pullLinks : null,
      openUrl: _root.widget.openLink,
      lookForPulls: linked ? () => unawaited(pullLinks.lookFor(key, repos).then<void>((_) {}, onError: (Object failure) => debugPrint('[github] $key’s pull requests were not read: $failure'))) : null,
      today: todayIs,
    );
  }

  /// The tickets a timer can be started on, newest first, for the palette.
  List<PaletteTicket> get paletteTickets => [
        for (final entry in _root._reads.entries)
          if (entry.ticket.id case final key? when key.isNotEmpty) (noteId: entry.note.id, key: key, title: entry.title),
      ];

  PaletteTicket? get timing {
    final mine = timers?.mine;
    return mine == null ? null : (noteId: mine.noteId, key: mine.named, title: mine.title);
  }

  void startTimer(String noteId) {
    final entry = _root._reads.entries.where((each) => each.note.id == noteId).firstOrNull;
    unawaited(timers?.start(noteId, title: entry?.title ?? '', key: entry?.ticket.id));
  }

  void stopTimer() {
    final made = timers, context = _root._shell.currentContext;
    final mine = made?.mine;
    if (made == null || mine == null) return;
    unawaited(context != null ? stopTimerAsking(context, made, mine) : made.stop());
  }

  // ---- the pull requests ----------------------------------------------------------------------------------------

  void _notesChanged() {
    _githubSoon?.cancel();
    _githubSoon = Timer(const Duration(seconds: 20), () => unawaited(_github()));
  }

  bool _reading = false;

  /// Every notebook's repos read, then each ticket a merge moves, moved once (pull_links.dart's header): on the device
  /// that holds the rules' sweep.
  Future<void> _github() async {
    if (_reading || !pullLinks.ready || !plugins.isEnabled('github')) return;
    _reading = true;
    try {
      final entries = _root._reads.entries;
      final repos = <String>{
        for (final entry in entries)
          if (entry.notebook case final book?) ...githubReposOf(book.body),
      };
      if (repos.isEmpty) return;
      await pullLinks.poll(repos);
      final rules = this.rules;
      if (rules == null) return;
      var held = false;
      for (final entry in entries) {
        final book = entry.notebook;
        final key = entry.ticket.id;
        if (book == null || key == null || _root._trash.isTrashed(entry.note.id)) continue;
        final mine = githubReposOf(book.body);
        if (mine.isEmpty) continue;
        final pulls = pullLinks.pullsFor(key, mine);
        final target = mergeMove(status: entry.ticket.status, statuses: entry.statuses, onMerge: onMergeOf(book.body), pulls: pulls);
        if (target == null) continue;
        if (!held && !(held = await rules.holdsSweep())) return;
        final merged = pulls.firstWhere((linked) => linked.pull.state == PullState.merged).pull;
        final id = mergeRunId(merged, entry.note.id);
        if (!rules.claimRun(id)) continue;
        await _move(entry.note.id, key, merged, target, id);
      }
    } catch (failure) {
      debugPrint('[github] the pull requests were not read: $failure');
    } finally {
      _reading = false;
    }
  }

  Future<void> _move(String noteId, String key, PullRecord merged, String target, String id) async {
    final job = activity.begin(TicketRules.jobId(id), kind: JobKind.sync, title: '$key: ${merged.name} merged', line: 'Moving it to $target', plugin: 'github', onOpen: activityRoutes.noteOpener(noteId));
    try {
      await _root._changeNote(noteId, (body) => withStatus(body, target), userEvent: 'input.rule');
      job.done(quiet: true, tally: const JobTally('ticket moved by a merge', 'tickets moved by merges'));
    } catch (failure) {
      job.failed('$key was not moved to $target: $failure', fix: JobFix(JobFixKind.retry, () => unawaited(_move(noteId, key, merged, target, id))));
    }
  }
}
