part of 'ghost_root.dart';

/// The app's own Claude in the root (docs/CLAUDE_APP.md): the library and the screen as Claude's tools reach them,
/// the chat with Claude, Claude on the dock, the bar over a note Claude writes in, the "Ask Claude" inbox, and Claude
/// talked to: the dock's orange mic and the phone's assistant (lib/claude/claude_voice.dart).
extension _RootClaude on _GhostRootState {
  /// Starts the inbox once the library is read; the runner itself is made on first use.
  void _startClaude() {
    unawaited(claudeSettings.load());
    _claudeInbox.start();
  }

  /// The chat with Claude, or with [agent] (an organization's AI row's Chat), its field starting with [initial].
  /// Nothing while the Claude plugin is off.
  void _openAskClaude({String? agent, String? initial}) {
    if (!_claudeOn) return;
    _shell.currentState?.closeSidebar();
    _told(() {
      _askClaude = true;
      _chatAgent = agent;
      _chatInitial = initial;
    });
  }

  void _closeAskClaude() => _told(() => _askClaude = false);

  /// Whether Claude can be talked to here: its plugin on, and a recorder to hear with (lib/root/root_voice.dart).
  bool get _canTalk => _claudeOn && _voice != null;

  /// Talk to Claude on the home page's dock; none where Claude cannot be talked to.
  Widget? _claudeTalkDock() => _canTalk ? ClaudeTalkButton(onPressed: () => _startTalk()) : null;

  /// Talk to Claude for a page's dock, about what the page is about where it says (see [_claudeDockAbout]).
  DockClaudeBuilder? get _claudeTalkForDock => _canTalk ? _claudeTalkAbout : null;

  Widget _claudeTalkAbout(String Function()? subject) => ClaudeTalkButton(onPressed: () => _startTalk(about: subject?.call()));

  /// Opens the ear for an ask said aloud (lib/claude/claude_voice.dart), its sheet over the app: from the dock, or,
  /// [fromAssistant], the phone's assistant. Pressed again while it listens, it is done. Answers whether it opened:
  /// not while Claude is off or nothing can hear, nor while the recorder or a meeting holds the microphone.
  bool _startTalk({String? about, bool fromAssistant = false}) {
    final voice = _voice;
    if (!_canTalk || voice == null) return false;
    final talking = _talk;
    if (talking != null && talking.stage == ClaudeVoiceStage.listening) {
      unawaited(talking.done());
      return true;
    }
    if ((_shell.currentState?.screen.isRecording ?? false) || (voice.live?.meetingStateNow()?.recording ?? false)) return false;
    if (talking != null) _endTalk();
    FocusManager.instance.primaryFocus?.unfocus();
    final recorder = voice.recorder;
    late final ClaudeVoice talk;
    talk = ClaudeVoice(
      runner: _claude,
      follow: _follow,
      inbox: _toClaudeInbox,
      about: about,
      ear: recorderEar(
        openMicrophone: recorder.openMicrophone,
        startCapture: recorder.startCapture,
        native: recorder.native,
        simulate: recorder.simulate,
        setLive: recorder.setRecorderLive,
        haptic: recorder.host.haptic,
        warn: recorder.warn,
      ),
      onEnd: () {
        if (identical(_talk, talk)) _endTalk();
      },
    );
    _told(() {
      _askClaude = false;
      _talk = talk;
      _talkFromAssistant = fromAssistant;
    });
    talk.start();
    return true;
  }

  /// The talk's sheet put away. Claude goes on with what it was asked, in the chat. A talk the phone's assistant
  /// started takes back the launch's leave to show over the lock screen, as a recording's end does.
  void _endTalk() {
    final talk = _talk;
    if (talk == null) return;
    final assistant = _talkFromAssistant;
    _told(() {
      _talk = null;
      _talkFromAssistant = false;
    });
    // After the frame: its sheet is being taken down in it.
    WidgetsBinding.instance.addPostFrameCallback((_) => talk.dispose());
    if (assistant) unawaited(_voice?.service?.endCapture(leave: false).then<void>((_) {}, onError: (Object _) {}));
  }

  /// The phone's assistant asked (lib/root/capture_route.dart `CaptureRouteWorld.askAi`): Claude is talked to where
  /// it can answer here, with its plugin on and a key on this device, and the phone not locked (a note Claude opens
  /// is not for the lock screen). Else the assistant records, as it did.
  Future<bool> _assistantTalk() async {
    if (!_canTalk) return false;
    await claudeSettings.load();
    final voice = _voice;
    if (!mounted || voice == null || !_claude.ready) return false;
    await voice.readLocked();
    if (!mounted || voice.locked) return false;
    return _startTalk(fromAssistant: true);
  }

  Widget _talkPart(BuildContext context) {
    final talk = _talk;
    if (talk == null || !_claudeOn) return _RootParts._nothing;
    return ClaudeVoiceSheet(
      voice: talk,
      onChat: () {
        _endTalk();
        _openAskClaude();
      },
      onSettings: () {
        _endTalk();
        _openSettingsAt('plugin:claude');
      },
      onOpenNote: (id) {
        _endTalk();
        _openForClaude(id);
      },
    );
  }

  /// Claude on the home page's dock; none while the Claude plugin is off.
  Widget? _claudeDock() => _claudeOn ? ClaudeDockButton(runner: _claude, follow: _follow, onPressed: _openAskClaude) : null;

  /// Claude for a page's dock (see [_claudeDockAbout]); none while the Claude plugin is off, so the dock has a ring
  /// fewer.
  DockClaudeBuilder? get _claudeForDock => _claudeOn ? _claudeDockAbout : null;

  /// Claude at the head of a page's dock (docs/DOCK.md): the chat, about what the page is about where it says. The
  /// chat holds no subject, so a note's `[[Title]]` is put in its field, ready to ask about.
  Widget _claudeDockAbout(String Function()? subject) => ClaudeDockButton(
        runner: _claude,
        follow: _follow,
        onPressed: () {
          final about = subject?.call().trim() ?? '';
          _openAskClaude(initial: about.isEmpty ? null : '[[$about]] ');
        },
      );

  /// The bars under the top bar: Follow's, for an AI through the connector, and the app's own Claude's.
  Widget _claudeBanner() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_follow != null) FollowBar(follow: _follow!),
          if (_claudeOn) ClaudeBar(runner: _claude, onReply: _openAskClaude, onOpenNote: _openForClaude),
        ],
      );

  void _openForClaude(String noteId) {
    final shell = _shell.currentState;
    if (shell == null || _library.noteOf(noteId) == null) return;
    _told(() => _askClaude = false);
    if (shell.shown != noteId) shell.openNote(noteId);
  }

  Widget _askClaudePart(BuildContext context) {
    if (!_askClaude || !_claudeOn) return _RootParts._nothing;
    return ClaudeChat(
      runner: _claude,
      follow: _follow,
      agent: _chatAgent,
      initial: _chatInitial,
      onClose: _closeAskClaude,
      onOpenNote: _openForClaude,
      onSettings: () {
        _told(() => _askClaude = false);
        // The key is added on the Claude plugin's page (lib/plugins/claude).
        _openSettingsAt('plugin:claude');
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
    // Written here rather than by `_writeNote`, which swallows what goes wrong: a passage not found, or a write
    // refused, reaches the tool and Claude is told.
    final note = await _root._library.get(noteId);
    if (note == null) throw StateError('No such note.');
    final next = change(note.body);
    if (next == note.body) return;
    await _root._library.update(noteId, next, note.revision);
    await _root._library.refresh();
  }

  @override
  bool get smoke => preferences.value.wisp;
}
