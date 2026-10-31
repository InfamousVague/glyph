part of 'ghost_root.dart';

/// A ticket for a team, as the root wires it (Matt, 2026-10-31, of the ticket features): what a ticket's panel is
/// handed for its watchers, its history, its possible duplicates and Merge into… (lib/editor/tickets/ticket_follow.dart),
/// the merge itself with its one Undo (lib/book/ticket_merge.dart), Unwatch from the bell, Watch on a card's menu, and
/// the morning's digest (lib/book/ticket_digest.dart) with its page.
///
/// One of the files `_GhostRootState` is written in (lib/root/ghost_root.dart says which), as root_commands.dart is.
extension _RootTickets on _GhostRootState {
  /// Who is reading: the account's handle, or null signed out.
  String? get _me {
    final handle = _services?.session?.handle;
    return handle == null || handle.isEmpty ? null : handle;
  }

  /// Whether a note is a team's: filed in an organization's workspace.
  bool _teamNote(String id) {
    final space = _workspaces.workspaceOf(id);
    return space != null && orgOfWorkspace(_workspaces.value.list, space.id) != null;
  }

  /// A ticket's likely duplicates in the library, by its title and words (lib/book/ticket_duplicates.dart).
  List<LikelyDuplicate> _likely(String title, {String words = '', String? selfId}) => [
        for (final hit in likelyDuplicates(title: title, words: words, entries: _reads.entries, index: _linkIndex.index, selfId: selfId))
          (ticket: ticketChoice(hit.entry), shared: hit.shared),
      ];

  /// What a ticket's panel is handed for its team's parts.
  TicketFollow _ticketFollow(String noteId) => TicketFollow(
        me: () => _me,
        history: () => _ticketHistory.of(noteId),
        duplicates: () {
          final note = _library.noteOf(noteId);
          if (note == null) return const <LikelyDuplicate>[];
          final kept = _duplicatesRead[noteId];
          if (kept != null && kept.body == note.body && kept.version == _linkIndex.index.version) return kept.likely;
          final likely = _likely(NoteFacts.of(note).title, words: note.body, selfId: noteId);
          _duplicatesRead[noteId] = (body: note.body, version: _linkIndex.index.version, likely: likely);
          return likely;
        },
        similar: (title) => _likely(title),
        merge: (target) => unawaited(_mergeTicket(noteId, target)),
        undoMerge: () {
          final record = mergeOf(_stored, noteId);
          return record == null ? null : () => unawaited(_undoMerge(record));
        },
        simple: () => preferences.value.simple,
      );

  /// Where a merge reads and writes: an open editor's words where the note is open, so nothing typed is lost, else
  /// the library's; a version kept of each note's words before, where the note keeps versions.
  MergeWorld get _mergeWorld => MergeWorld(
        body: (id) async {
          final view = openNoteScreen(_shell.currentContext, id)?.view;
          if (view != null) return view.state.doc.toString();
          return (await _library.get(id))?.body;
        },
        write: (id, body) => _changeNote(id, (_) => body, userEvent: 'ticket.merge'),
        keepVersion: (id, text, label) async {
          if (_versions.keepsVersions(id)) await _versions.keepVersion(id, text, label: label);
        },
        kept: _stored,
      );

  /// [duplicateId] merged into [target] (lib/book/ticket_merge.dart): the plan made, said and asked first with its
  /// warnings, written, and a toast with its Undo.
  Future<void> _mergeTicket(String duplicateId, TicketChoice target) async {
    final entries = _reads.entries;
    final duplicate = entries.where((each) => each.note.id == duplicateId).firstOrNull;
    final into = entries.where((each) => (target.key != null && each.ticket.id == target.key) || (target.key == null && each.title == target.title)).firstOrNull;
    if (duplicate == null || into == null || into.note.id == duplicateId) return;
    final world = _mergeWorld;
    // The words as they are now, an open editor's among them.
    final notes = <String, ({String title, String body})>{
      for (final note in _library.value) note.id: (title: NoteFacts.of(note).title, body: note.body),
    };
    for (final id in [duplicateId, into.note.id]) {
      final now = await world.body(id);
      if (now != null) notes[id] = (title: notes[id]?.title ?? '', body: now);
    }
    TicketEntry fresh(TicketEntry entry) {
      final body = notes[entry.note.id]?.body ?? entry.note.body;
      return body == entry.note.body ? entry : TicketEntry(note: entry.note.copyWith(body: body), title: entry.title, ticket: ticketOf(body, entry.statuses) ?? entry.ticket, statuses: entry.statuses, notebook: entry.notebook);
    }

    final plan = planMerge(duplicate: fresh(duplicate), target: fresh(into), notes: notes, index: _linkIndex.index, editable: _readableHere);
    if (!mounted) return;
    final yes = await askFirst(
      context,
      FirstAsk(title: 'Merge ${plan.duplicateName} into ${plan.targetName}?', note: [plan.summary, ...plan.warnings, 'One Undo takes it all back.'].join(' '), yes: 'Merge'),
    );
    if (!yes || !mounted) return;
    try {
      final record = await applyMerge(plan, world);
      await _library.refresh().catchError((Object _) {});
      if (!mounted) return;
      GlacierToast.of(context).toast(
        message: Text('Merged ${plan.duplicateName} into ${plan.targetName}.'),
        duration: const Duration(seconds: 10),
        action: GlacierToastAction(label: 'Undo', onPress: () => unawaited(_undoMerge(record))),
      );
    } catch (failure) {
      if (mounted) _say(context, failure is StateError ? failure.message : 'The merge could not be made: $failure');
    }
  }

  /// A merge taken back as one step; any note changed since it is left and said.
  Future<void> _undoMerge(MergeRecord record) async {
    final left = await undoMerge(record, _mergeWorld);
    await _library.refresh().catchError((Object _) {});
    if (!mounted) return;
    _say(context, left.isEmpty ? 'The merge of ${record.duplicateName} was taken back.' : 'The merge was taken back, but ${left.join(', ')} changed since and ${left.length == 1 ? 'was' : 'were'} left as ${left.length == 1 ? 'it is' : 'they are'}.');
  }

  /// This account off a ticket's watchers: from its bell row's Unwatch, or a card's menu.
  Future<void> _setWatching(String noteId, bool on) async {
    final me = _me;
    if (me == null) return;
    await _changeNote(noteId, (body) => withWatcher(body, me, on), userEvent: 'ticket.watch').catchError((Object _) {});
    if (mounted) _say(context, on ? 'You’re watching it now.' : 'You won’t be told of changes to it.');
  }

  /// A ticket's rows on a card's menu: Watch or Unwatch, and Merge into… (not in simple mode).
  List<Widget> _ticketMenuRows(BuildContext context, Note note) {
    if (!NoteFacts.of(note).isTicket) return const [];
    final me = _me;
    final rows = <Widget>[];
    if (me != null) {
      final watching = watches(note.body, me);
      rows.add(GlacierMenuItem(icon: AppIcon(watching ? Lucide.eyeOff : Lucide.eye, size: context.tokens.fontSize('sm')), onSelect: () => unawaited(_setWatching(note.id, !watching)), child: Text(watching ? 'Unwatch' : 'Watch')));
    }
    return rows;
  }

  /// The morning's digest as the notes are now (lib/book/ticket_digest.dart).
  TicketDigest _digestOf(String day) => digestFor(_reads.entries, me: _me, today: day, team: _teamNote, skip: (entry) => _trash.isTrashed(entry.note.id) || (entry.note.archivedAt ?? 0) != 0);

  /// The digest's runner, started once the notes are read: claimed, sent, and on a phone rung as a reminder.
  void _startDigest() {
    late final TicketDigestRunner runner;
    runner = TicketDigestRunner(
      claims: DigestClaims(
        device: thisDevice,
        preferences: () => preferences.value,
        setPreferences: preferences.update,
        syncNow: () async => await _services?.engine?.syncNow(),
        accountHeld: () => _services?.engine?.accountPrefs,
      ),
      choices: () => digestSettingsOf(preferences.value),
      digest: _digestOf,
      phone: () => phoneReminders.value != null,
      send: (digest) async {
        final session = _services?.session;
        if (session == null) return;
        await _services?.engine?.record?.recordAs(digestRowId(session.accountId, digest.day), 'ticket-digest', {'noteId': digestNoteId, 'title': digest.title, 'first': digest.text});
      },
      writeNote: (digest) async => (await _library.createNote(digest.markdown)).id,
      // A phone's morning rung as one of its reminders: the plan handed over again whenever its alarm changes.
      planChanged: () => extraReminders.value = () => [?digestReminderOf(runner)],
    );
    _digest = runner;
    unawaited(runner.look());
  }

  /// The notes changed: the digest looked at again, a moment later, for a phone's alarm to carry today's words.
  void _digestHeard() {
    _digestPoke?.cancel();
    _digestPoke = Timer(const Duration(seconds: 5), () => unawaited(_digest?.look()));
  }

  /// The digest's page, where a tap on its notification lands (or the My tickets inbox, once there is one).
  void _openDigest() {
    final shell = _shell.currentState;
    if (shell == null || !mounted) return;
    unawaited(showTicketDigest(context, _digestOf(isoDay(DateTime.now())), onOpen: (id) => _openWhereLeft(shell, id)));
  }
}
