part of 'ghost_root.dart';

/// What the root does for the tickets queue (Matt, 2026-10-31): My tickets and Triage as a page
/// (lib/tickets/ui/tickets_screen.dart), the sidebar's count, `me` in a query as the account's handle, a label's
/// colour kept in its notebook, and the bulk edit of tickets picked in a query (lib/tickets/ui/bulk_bar.dart), each
/// batch all or nothing with one Undo (lib/tickets/bulk.dart).
///
/// Every change is a write of another note's words, as a query's tick is: through the library, and through the
/// note's own screen where it is open (the root's `_changeNote`), so a team's note goes through its sync as any edit
/// does and an open editor never has its words written under it.
///
/// One of the files `_GhostRootState` is written in (lib/root/ghost_root.dart says which); a ticket for a team, its
/// watchers, merge and digest, is root_tickets.dart's.
extension _RootTicketQueue on _GhostRootState {
  /// Who `me` is in a query: the account's handle, told again as the account changes.
  void _tellMe() {
    final handle = _services?.session?.handle;
    final next = [if (handle != null && handle.isNotEmpty) handle];
    if (listEquals(next, queryMe)) return;
    queryMe = next;
    _ticketReads.forget();
  }

  String get _ticketsToday => isoDay(DateTime.now());

  /// The organization a team's note is among, by name; null for one's own.
  String? _teamName(String noteId) {
    final space = _workspaces.workspaceOf(noteId);
    if (space == null) return null;
    final org = _workspaces.orgOf(space.id);
    if (org == null) return null;
    final id = orgWorkspaceId(org);
    return _workspaces.value.list.where((each) => each.id == id).firstOrNull?.name;
  }

  Note? _notebookOfNote(String noteId) {
    final note = _library.noteOf(noteId);
    return note == null ? null : _reads.notebookOf(note);
  }

  /// The colours a ticket's notebook gives its labels.
  Map<String, String> _labelColoursOf(String noteId) => labelColoursOf(_notebookOfNote(noteId)?.body);

  /// A label's colour kept in the ticket's notebook (`label-colours:`), or taken off for null.
  void _setLabelColour(String noteId, String label, String? hue) {
    final book = _notebookOfNote(noteId);
    if (book == null) return;
    unawaited(_changeNote(book.id, (body) => withLabelColour(body, label, hue), userEvent: 'tickets.label-colour').catchError((Object _) {}));
  }

  /// Every ticket as the duplicate picker offers it.
  List<TicketChoice> _ticketChoices() => [for (final entry in _reads.entries) ticketChoice(entry)];

  /// A ticket by its key, else its title, as a report names it.
  String _ticketName(String noteId) {
    for (final entry in _reads.entries) {
      if (entry.note.id == noteId) return entry.ticket.id ?? entry.title;
    }
    final note = _library.noteOf(noteId);
    return note == null ? 'A note' : NoteFacts.of(note).title;
  }

  /// My tickets and Triage, as the shell draws them.
  Widget _ticketsPart(BuildContext context, AppShellState shell, ScreenTickets screen) => _part(
        'tickets',
        () => (screen, shell.notes, _workspaces.value, _accountAt, preferences.value.simple, _claudeShown, _canTalk),
        (context) {
          _tellMe();
          return TicketsScreen(
            page: screen.triage ? TicketsPage.triage : TicketsPage.mine,
            library: _ticketReads.library,
            today: _ticketsToday,
            onPage: (page) => shell.showTickets(triage: page == TicketsPage.triage),
            onBack: shell.backToList,
            onOpen: (id) => _openWhereLeft(shell, id),
            write: (id, change) => _changeNote(id, (body) => change(body) ?? body, userEvent: 'tickets.change').catchError((Object _) {}),
            teamOf: _teamName,
            coloursOf: _labelColoursOf,
            onColour: _setLabelColour,
            people: _reads.people,
            labels: () => labelsIn([for (final note in _shown) note.body]),
            choices: _ticketChoices,
            simple: preferences.value.simple,
            dock: _notesDock(),
          );
        },
      );

  /// How many tickets are yours, for the sidebar's row: null where there are none to count.
  ({int all, int overdue})? _myTicketCount() {
    _tellMe();
    final count = _ticketReads.count(_ticketsToday);
    return count.all == 0 ? null : count;
  }

  // ---- bulk edit ----------------------------------------------------------------------------------------------

  /// What a query's picked tickets are changed through.
  BulkActions get _bulkActions => BulkActions(
        edit: _bulkEdit,
        move: _bulkMove,
        trash: _bulkTrash,
        notebooks: () => [
          for (final note in _shown)
            if (NoteFacts.of(note).isBook && !NoteFacts.of(note).isJournal && !NoteFacts.of(note).isTemplatesBook && (note.archivedAt ?? 0) == 0) (id: note.id, title: NoteFacts.of(note).title.isEmpty ? 'Untitled notebook' : NoteFacts.of(note).title),
        ],
        labels: () => labelsIn([for (final note in _shown) note.body]),
        people: _reads.people,
        coloursOf: _labelColoursOf,
      );

  /// [plan] written as one batch, said in a toast: its Undo takes every note back, or what failed is said and
  /// nothing is left changed.
  Future<void> _runBulk(Map<String, BodyChange> plan, String said, {int? count}) async {
    final store = _RootBulkStore(this);
    final outcome = await runBulk(plan, store);
    await _library.refresh().catchError((Object _) {});
    if (!mounted) return;
    final words = bulkReport(outcome, said, nameOf: _ticketName, count: count);
    GlacierToast.of(context).toast(
      message: Text(words),
      action: !outcome.whole || outcome.wrote.isEmpty
          ? null
          : GlacierToastAction(
              label: 'Undo',
              onPress: () => unawaited(() async {
                final undone = await undoBulk(outcome, store);
                await _library.refresh().catchError((Object _) {});
                if (!mounted || undone.whole) return;
                _say(context, 'Undone but for ${[for (final MapEntry(:key, :value) in undone.failed.entries) '${_ticketName(key)}: $value'].join(' ')}');
              }()),
            ),
    );
  }

  Future<void> _bulkEdit(List<String> ids, BulkEdit edit) => _runBulk({for (final id in ids) id: (body) => bulkBody(body, edit)}, edit.said);

  /// Every ticket's page out of its notebook's index and into [notebookId]'s. Its filing stays where it is: a note
  /// is never carried into or out of an organization by a move between notebooks.
  Future<void> _bulkMove(List<String> ids, String notebookId) async {
    final to = _library.noteOf(notebookId);
    if (to == null) return;
    final from = <String, String?>{}, titles = <String, String>{};
    for (final id in ids) {
      final note = _library.noteOf(id);
      if (note == null) continue;
      from[id] = _reads.notebookOf(note)?.id;
      titles[id] = NoteFacts.of(note).title;
    }
    final title = NoteFacts.of(to).title;
    await _runBulk(movePlan(to: notebookId, from: from, titles: titles), 'Moved to ${title.isEmpty ? 'the notebook' : title}', count: ids.length);
  }

  /// Every ticket into the Trash at once, with one Undo that brings them all back.
  void _bulkTrash(List<String> ids) {
    if (ids.isEmpty) return;
    _trashNotes(ids);
    if (!mounted) return;
    GlacierToast.of(context).toast(
      message: Text(ids.length == 1 ? 'Moved 1 ticket to the Trash.' : 'Moved ${ids.length} tickets to the Trash.'),
      action: GlacierToastAction(
        label: 'Undo',
        onPress: () {
          for (final id in ids) {
            _trash.restoreNote(id);
          }
        },
      ),
    );
  }
}

/// What a batch reads and writes through in the app: the note's own screen where it is open (its editor's words,
/// written as an edit there), else the library, from the revision read.
class _RootBulkStore implements BulkStore {
  _RootBulkStore(this.root);

  final _GhostRootState root;

  /// The revision a note open on screen is read at: its screen writes it, and nothing refuses it.
  static const int _onScreen = -1;

  @override
  Future<BulkNote?> read(String id) async {
    final screen = openNoteScreen(root._shell.currentContext, id);
    if (screen != null) {
      final view = screen.view;
      if (view != null) return BulkNote(view.state.doc.toString(), _onScreen);
      final note = await root._library.get(id);
      return note == null ? null : BulkNote(note.body, _onScreen);
    }
    final note = await root._library.get(id);
    return note == null ? null : BulkNote(note.body, note.revision);
  }

  @override
  Future<int> write(String id, String body, int revision) async {
    if (revision == _onScreen) {
      await root._changeNote(id, (_) => body, userEvent: 'tickets.bulk');
      return _onScreen;
    }
    final note = await root._library.update(id, body, revision);
    return note.revision;
  }
}
