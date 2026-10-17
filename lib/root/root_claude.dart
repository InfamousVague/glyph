part of 'ghost_root.dart';

/// The app's own Claude in the root (docs/CLAUDE_APP.md): the library and the screen as Claude's tools reach them,
/// the chat with Claude, Claude on the dock, the bar over a note Claude writes in, and the "Ask Claude" inbox.
extension _RootClaude on _GhostRootState {
  /// Starts the inbox once the library is read; the runner itself is made on first use.
  void _startClaude() {
    unawaited(claudeSettings.load());
    _claudeInbox.start();
  }

  /// The chat with Claude, or with [agent] (an organization's AI row's Chat).
  void _openAskClaude({String? agent}) {
    _shell.currentState?.closeSidebar();
    _told(() {
      _askClaude = true;
      _chatAgent = agent;
    });
  }

  void _closeAskClaude() => _told(() => _askClaude = false);

  /// Claude on the home page's dock.
  Widget _claudeDock() => ClaudeDockButton(runner: _claude, follow: _follow, onPressed: _openAskClaude);

  /// The bars under the top bar: Follow's, for an AI through the connector, and the app's own Claude's.
  Widget _claudeBanner() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_follow != null) FollowBar(follow: _follow!),
          ClaudeBar(runner: _claude, onReply: _openAskClaude, onOpenNote: _openForClaude),
        ],
      );

  void _openForClaude(String noteId) {
    final shell = _shell.currentState;
    if (shell == null || _library.noteOf(noteId) == null) return;
    _told(() => _askClaude = false);
    if (shell.shown != noteId) shell.openNote(noteId);
  }

  Widget _askClaudePart(BuildContext context) {
    if (!_askClaude) return _RootParts._nothing;
    return ClaudeChat(
      runner: _claude,
      follow: _follow,
      agent: _chatAgent,
      onClose: _closeAskClaude,
      onOpenNote: _openForClaude,
      onSettings: () {
        _told(() => _askClaude = false);
        _openSettingsAt('ask-claude');
      },
      onOpenAi: _openForAi,
      onInbox: _toClaudeInbox,
    );
  }

  /// A request written into the "Ask Claude" note, made first with the connector's own words where there is none
  /// (mcp/prompts.ts `INBOX_BODY`): for the connector's agents and the Mac's routine to work through.
  Future<void> _toClaudeInbox(String request) async {
    final line = '- [ ] ${request.replaceAll('\n', ' ').trim()}';
    final inbox = _claudeInboxBody();
    if (inbox == null) {
      await _library.createNote(newInboxBody(line));
      await _library.refresh();
      return;
    }
    await _RootClaudeDesk(this).change(inbox.id, (body) => addInboxRequest(body, line));
  }
}

/// The library as Claude's tools read and write it.
class _RootClaudeNotes implements ClaudeNotes {
  _RootClaudeNotes(this._root);

  final _GhostRootState _root;

  NoteLibrary get _library => _root._library;

  static DateTime _at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  static String _preview(String body) {
    final lines = body.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty && !line.startsWith('#') && line != '---').toList();
    final line = lines.isEmpty ? '' : lines.first;
    return line.length > 120 ? '${line.substring(0, 117)}…' : line;
  }

  NoteBrief _brief(Note note) => NoteBrief(
        id: note.id,
        title: noteTitle(note.body),
        updated: _at(note.updatedAt),
        preview: _preview(note.body),
        folder: _folderOf(note.path),
        pinned: note.starred,
      );

  static String? _folderOf(String? path) {
    if (path == null) return null;
    final at = path.lastIndexOf('/');
    return at <= 0 ? null : path.substring(0, at);
  }

  List<Note> get _notes => [
        for (final note in _root._shown)
          if (note.archivedAt == null) note,
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<List<NoteBrief>> list({String? query, int limit = 50}) async {
    final q = (query ?? '').trim().toLowerCase();
    return [
      for (final note in _notes)
        if (q.isEmpty || noteTitle(note.body).toLowerCase().contains(q)) _brief(note),
    ].take(limit).toList();
  }

  @override
  Future<List<NoteHit>> search(String query, {int limit = 20}) async {
    final found = searchNotes(_notes, query).take(limit);
    final words = searchWords(query);
    return [
      for (final note in found) NoteHit(id: note.id, title: noteTitle(note.body), snippet: _snippet(note.body, words)),
    ];
  }

  static String _snippet(String body, List<String> words) {
    final low = body.toLowerCase();
    var at = -1;
    for (final word in words) {
      at = low.indexOf(word);
      if (at >= 0) break;
    }
    if (at < 0) return _preview(body);
    final from = (at - 60).clamp(0, body.length), to = (at + 100).clamp(0, body.length);
    return '${from > 0 ? '…' : ''}${body.substring(from, to).replaceAll('\n', ' ')}${to < body.length ? '…' : ''}';
  }

  /// The note's words as they are now: its editor's where it is open (unsaved letters included), else the store's.
  String? _wordsOf(String id) {
    final screen = openNoteScreen(_root._shell.currentContext, id);
    return screen?.view?.state.doc.toString() ?? screen?.body;
  }

  @override
  Future<NoteRead?> read({String? id, String? title}) async {
    Note? note;
    if (id != null && id.isNotEmpty) note = _library.noteOf(id);
    if (note == null && title != null && title.trim().isNotEmpty) {
      final key = title.trim().toLowerCase();
      note = _notes.where((n) => noteTitle(n.body).trim().toLowerCase() == key).firstOrNull ?? _root._reads.titled(title.trim());
    }
    if (note == null) return null;
    final fresh = await _library.get(note.id) ?? note;
    final body = _wordsOf(note.id) ?? fresh.body;
    return NoteRead(id: note.id, title: noteTitle(body), body: body);
  }

  @override
  Future<String> create(String body) async {
    // The account's own, in no workspace: filed nowhere, it is in the Inbox.
    final made = await _library.createNote(body);
    await _library.refresh();
    return made.id;
  }

  @override
  Future<void> write(String id, String body) => _root._writeNote(id, (_) => body);
}

/// The screen as a run reaches it.
class _RootClaudeDesk implements ClaudeDesk {
  _RootClaudeDesk(this._root);

  final _GhostRootState _root;

  ed.EditorViewLike? _viewOf(String noteId) => openNoteScreen(_root._shell.currentContext, noteId)?.view;

  @override
  Future<ed.EditorViewLike?> open(String noteId) async {
    final shell = _root._shell.currentState;
    if (shell == null || !_root.mounted) return null;
    // A note just made is in the list after the library's next read.
    for (var i = 0; i < 20 && _root._library.noteOf(noteId) == null; i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_root._library.noteOf(noteId) == null) return null;
    // The sheet makes way for the note.
    if (_root._askClaude) _root._told(() => _root._askClaude = false);
    if (shell.shown != noteId) shell.openNote(noteId);
    // Its editor, once the screen has made it: a few frames.
    for (var i = 0; i < 60; i += 1) {
      final view = _viewOf(noteId);
      if (view != null) return view;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  @override
  bool showing(String noteId, ed.EditorViewLike view) => _root.mounted && identical(_viewOf(noteId), view);

  @override
  Future<void> change(String noteId, String Function(String body) change) async {
    final view = _viewOf(noteId);
    if (view != null) {
      final now = view.state.doc.toString();
      final next = change(now);
      if (next == now) return;
      // Only the stretch that differs, so the person's caret and the note's marks outside it stay where they are.
      var start = 0;
      while (start < now.length && start < next.length && now.codeUnitAt(start) == next.codeUnitAt(start)) {
        start += 1;
      }
      var endNow = now.length, endNext = next.length;
      while (endNow > start && endNext > start && now.codeUnitAt(endNow - 1) == next.codeUnitAt(endNext - 1)) {
        endNow -= 1;
        endNext -= 1;
      }
      view.dispatch(ed.TransactionSpec(changes: ed.Change(from: start, to: endNow, insert: next.substring(start, endNext)), userEvent: 'claude.type'));
      return;
    }
    // Open without an editor (a notebook's own words drawn): the screen writes it, as it writes its index.
    final screen = openNoteScreen(_root._shell.currentContext, noteId);
    if (screen != null) return screen.writeNotebook(change);
    await _root._writeNote(noteId, change);
  }

  @override
  bool get smoke => preferences.value.wisp;
}
