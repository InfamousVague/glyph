/// One note, live on this device (docs/LIVE.md): its CRDT document, how it came to be, and what goes out and comes
/// in. A port of `src/app/core/live/session.ts`.
///
/// The document is made once, by the first device into the room, and adopted by every other: never built twice,
/// since two documents built from the same words merge into the words twice. The session only moves bytes and
/// decides whose document stands; the editor binds to it once `ready` says the document holds the note.
///
/// What differs:
/// - The document is the Rust core's (lib/team/crdt.dart), a call away. What the session decides is still decided
///   at once, as the page decides it ([LiveSession.state], `ready`, the peers); what touches the document goes one
///   at a time behind it, in the order it was asked, and [LiveSession.sent] settles when all of it has.
/// - The page's editor is bound to `session.text` by y-codemirror. Here the session is the [LiveText] an editor
///   is bound to (lib/live/editor_binding.dart): [LiveSession.edit] is a key pressed here, sent as it is made,
///   and [LiveSession.onSplice] a change that arrived. Its undo is the document's while it is bound
///   ([LiveSession.openUndo], [LiveSession.undoStep]), as liveBinding.ts gives the page's `Y.UndoManager`: a step
///   taken back goes to the room as the update it is, like a key.
/// - `markShared` is the [SharedLive] the session was given.
library;

import 'dart:async';
import 'dart:typed_data';

import '../account/crypto_api.dart';
import '../team/crdt.dart';
import '../team/text_log.dart';
import 'hub.dart' show RoomListener;
import 'live_text.dart';
import 'shared.dart';
import 'transport.dart';
import 'wire.dart';

/// What a session stands on (`SessionDeps`).
class SessionDeps {
  const SessionDeps({required this.transport, required this.key, required this.crypto, required this.crdt, required this.hasUnsynced, required this.keepCopy, this.shared, this.schedule});

  final LiveTransport transport;
  final SealKey key;
  final AccountCrypto crypto;
  final Crdt crdt;

  /// Whether this device's copy of the note has changes the pass sync has not sent yet (its fingerprint moved).
  final Future<bool> Function(String noteId) hasUnsynced;

  /// Keeps this device's words as a note of their own: the conflict rule, a copy and never a loss.
  final Future<void> Function(String noteId, String words) keepCopy;
  final SharedLive? shared;

  /// For tests: when to ask again for a document that has not come.
  final Object? Function(void Function() run, int ms)? schedule;
}

/// `SessionState`.
enum SessionState { joining, waiting, ready, closed }

/// What a session tells the screen (`SessionListener`).
class SessionListener {
  const SessionListener({required this.ready, required this.peers});

  /// The document holds the note: bind the editor, whose words may differ from the ones given.
  final void Function(String words) ready;

  /// How many other devices have the note open right now.
  final void Function(int count) peers;
}

/// How long a device that was not first waits for a document before asking again.
const int askAgainMs = 2500;
const int asks = 3;

/// One live note (`LiveSession`).
class LiveSession implements RoomListener, LiveText {
  LiveSession(this.noteId, this._seedWords, this._deps, this._listener) {
    _doc = _deps.crdt.open();
    // Its own trouble is each call's that waits on it.
    unawaited(_doc.then<void>((_) {}, onError: (Object _) {}));
    _deps.transport.join(noteId);
  }

  final String noteId;

  /// The note as this device has it, when the session began.
  final String _seedWords;
  final SessionDeps _deps;
  final SessionListener _listener;
  late final Future<CrdtDoc> _doc;

  SessionState state = SessionState.joining;
  String? seed;
  int _others = 0;
  int _asks = 0;
  Object? _retry;
  String _words = '';
  final TextLog _log = TextLog();
  final Set<void Function(TextSplice splice)> _splices = {};

  /// Outgoing messages, one after another: sealing is asynchronous, and the order they were made in is kept.
  Future<void> _sending = Future<void>.value();

  /// Incoming ones the same, and everything that touches the document.
  Future<void> _receiving = Future<void>.value();
  Future<void> _ops = Future<void>.value();

  Future<T> _next<T>(Future<T> Function(CrdtDoc doc) op) {
    final done = _ops.then((_) async => op(await _doc));
    _ops = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  @override
  String get words => _words;

  @override
  int get rev => _log.rev;

  @override
  Future<void> settled() => _ops;

  @override
  void Function() onSplice(void Function(TextSplice splice) listener) {
    _splices.add(listener);
    return () => _splices.remove(listener);
  }

  /// Settles once every message taken so far has been read, the document has caught up with it, and every message
  /// posted has been sealed and handed to the transport: what a test of a room waits on rather than a guess at how
  /// long a loaded machine takes.
  Future<void> sent() async {
    for (;;) {
      final receiving = _receiving, ops = _ops, sending = _sending;
      await receiving;
      await ops;
      await sending;
      if (identical(receiving, _receiving) && identical(ops, _ops) && identical(sending, _sending)) return;
    }
  }

  /// A key pressed here: into the document, and out to the room as it is made.
  @override
  Future<Object?> edit(List<CrdtEdit> edits, {int? base, int? now}) {
    return _next((doc) async {
      if (state == SessionState.closed) return null;
      final change = await doc.edit(base == null ? edits : _log.carry(edits, base), now: now);
      _undo = change.undo ?? _undo;
      _words = change.text;
      final update = change.update;
      if (update != null && state == SessionState.ready) _post(Envelope(Kind.update, update));
      return change;
    });
  }

  @override
  Future<void> keepCaret(CrdtCaret caret, {int? base}) => _next((doc) async {
        final carried = base == null ? caret : _log.carryCaret(caret, base);
        if (carried != null && _undo.open && state != SessionState.closed) await doc.keepCaret(carried);
      });

  UndoState _undo = UndoState.none;

  @override
  UndoState get undoState => _undo;

  @override
  Future<UndoState> openUndo() => _next((doc) async => _undo = state == SessionState.closed ? UndoState.none : await doc.openUndo());

  @override
  Future<void> closeUndo() => _next((doc) async {
        _undo = UndoState.none;
        if (state != SessionState.closed) await doc.closeUndo();
      });

  /// The bound editor's last step taken back, or put in again: the document's own undo, its change sent to the
  /// room as the update it is and told to the editor as the stretches it was.
  @override
  Future<CrdtUndone?> undoStep({required bool redo, int? now}) {
    return _next((doc) async {
      if (state == SessionState.closed) return null;
      final done = redo ? await doc.redo(now: now) : await doc.undo(now: now);
      _undo = done.undo ?? _undo;
      final update = done.update;
      if (update == null) return done;
      _tell(done.text, done.splices);
      if (state == SessionState.ready) _post(Envelope(Kind.update, update));
      return done;
    });
  }

  /// The relay put this device in the room: the first seeds, the rest ask. Also on every rejoin after a drop.
  @override
  void joined(bool first, int peers) {
    _setPeers(peers);
    if (state == SessionState.closed) return;
    if (state == SessionState.ready) {
      // Back after a drop. Alone, the document here is the room's; with others, trade whole documents, which Yjs
      // merges exactly when they share a seed (and `message` below handles the case where they do not).
      if (!first) {
        _post(const Envelope(Kind.query));
        _postState();
      }
      return;
    }
    if (first) {
      _seedHere();
      return;
    }
    state = SessionState.waiting;
    _ask();
  }

  /// Another device came or went. The last one leaving while this one waits makes it the first after all.
  @override
  void peersChanged(int peers, [int? left]) {
    _setPeers(peers);
    if (state == SessionState.waiting && peers == 0) _seedHere();
  }

  /// A sealed message from another device. One that will not open is dropped: it is not ours to act on.
  @override
  Future<void> message(int from, String data) {
    return _receiving = _receiving.then((_) => _take(from, data)).catchError((Object _) {});
  }

  Future<void> _take(int from, String data) async {
    final Envelope envelope;
    try {
      envelope = await openEnvelope(_deps.crypto, _deps.key, noteId, data);
    } catch (_) {
      return;
    }
    if (state == SessionState.closed) return;
    switch (envelope.kind) {
      case Kind.query:
        if (state == SessionState.ready) _postState(from);
      case Kind.state:
        await _stateFrom(envelope.bytes);
      case Kind.update:
        // Safe before the document has come: a change whose history has not been seen waits for that history, and
        // then both are applied.
        await _apply(envelope.bytes);
      default:
        break;
    }
  }

  void close() {
    if (state == SessionState.closed) return;
    state = SessionState.closed;
    _deps.shared?.mark(noteId, false);
    _clearRetry();
    _deps.transport.leave(noteId);
    _splices.clear();
    unawaited(_next((doc) => doc.close()).catchError((Object _) {}));
  }

  /// Updates from the room, applied; the editor told when the words changed and it is bound.
  Future<void> _apply(Uint8List update) {
    return _next((doc) async {
      final ({String? text, List<CrdtSplice>? splices, UndoState? undo}) took;
      try {
        took = await doc.take([update]);
      } catch (_) {
        // One the core cannot hold: this copy is left as it was.
        return;
      }
      _undo = took.undo ?? _undo;
      final after = took.text;
      if (after == null) return;
      if (state != SessionState.ready) {
        _words = after;
        return;
      }
      _tell(after, took.splices);
    });
  }

  /// The words are [after] now, by a change that was not the editor's typing: told to a bound editor as the
  /// stretches the document says it was ([splices]), or, without that account or with one that does not lead to
  /// [after], as the one stretch between the words before and after.
  void _tell(String after, List<CrdtSplice>? splices) {
    final through = splices == null ? null : wordsThrough(_words, splices, after);
    if (through != null) {
      for (var i = 0; i < through.length; i += 1) {
        final splice = _log.add(splices![i].at, splices[i].removed, splices[i].inserted, more: i + 1 < through.length);
        _words = through[i];
        for (final listener in _splices.toList()) {
          listener(splice);
        }
      }
      return;
    }
    final splice = _log.record(_words, after);
    _words = after;
    if (splice == null) return;
    for (final listener in _splices.toList()) {
      listener(splice);
    }
  }

  Future<void> _stateFrom(Uint8List payload) async {
    final (seed: theirs, state: document) = unpackState(payload);
    if (state == SessionState.ready && theirs == seed) {
      // The same history: whatever the other device has that this one does not simply merges in.
      await _apply(document);
      return;
    }
    if (state != SessionState.waiting && state != SessionState.ready) return;
    if (state == SessionState.ready) {
      // A different history met after a drop: the room was made again while this device was away. Merging two
      // histories doubles the words, so it is not done; this device's session ends and the editor opens a new one,
      // which joins fresh and follows the rules of a first meeting.
      close();
      return;
    }
    _clearRetry();
    // Adopt the room's document, whole.
    final roomWords = await _next((doc) async {
      await doc.applyRemote([document]);
      return doc.words();
    });
    if (state != SessionState.waiting) return;
    seed = theirs;
    // This device's words were only behind, or carry changes of their own: the second keeps them, as a note beside.
    if (roomWords != _seedWords && await _deps.hasUnsynced(noteId)) {
      await _deps.keepCopy(noteId, _seedWords);
    }
    if (state != SessionState.waiting) return;
    _words = roomWords;
    state = SessionState.ready;
    _share();
    _listener.ready(roomWords);
  }

  void _seedHere() {
    _clearRetry();
    seed = newSeed();
    _words = _seedWords;
    // Not sent: every other device adopts the document whole.
    if (_seedWords.isNotEmpty) unawaited(_next((doc) => doc.edit([CrdtEdit(0, insert: _seedWords)])).catchError((Object _) => const CrdtChange(update: null, text: '')));
    state = SessionState.ready;
    _share();
    _listener.ready(_seedWords);
  }

  void _ask() {
    if (state != SessionState.waiting) return;
    if (_asks >= asks) {
      // Nobody has answered. With nobody there, this device makes the document; with somebody there who will not
      // answer, it stays out of the room rather than risk a second history.
      if (_others == 0) _seedHere();
      return;
    }
    _asks += 1;
    _post(const Envelope(Kind.query));
    void again() {
      _retry = null;
      _ask();
    }

    final schedule = _deps.schedule;
    _retry = schedule != null ? (schedule(again, askAgainMs) ?? again) : Timer(const Duration(milliseconds: askAgainMs), again);
  }

  /// The whole document with its seed, as it stands when its turn comes: to everyone, or to the one who asked.
  void _postState([int? to]) {
    unawaited(_next((doc) async {
      final held = seed;
      if (held == null || state != SessionState.ready) return;
      _post(Envelope(Kind.state, packState(held, await doc.snapshot())), to);
    }).catchError((Object _) {}));
  }

  void _post(Envelope envelope, [int? to]) {
    _sending = _sending.then((_) async {
      if (state == SessionState.closed) return;
      _deps.transport.send(noteId, await sealEnvelope(_deps.crypto, _deps.key, noteId, envelope), to: to);
    }).catchError((Object _) {
      // A message that could not be sealed is one fewer keystroke on the other device, not a reason to stop; the
      // next whole-document exchange carries it.
    });
  }

  void _setPeers(int peers) {
    _others = peers;
    _listener.peers(peers);
    _share();
  }

  /// Tells the pass sync whether to leave this note alone: ready, and another device in it (shared.dart).
  void _share() => _deps.shared?.mark(noteId, state == SessionState.ready && _others > 0);

  void _clearRetry() {
    final retry = _retry;
    if (retry is Timer) retry.cancel();
    _retry = null;
  }
}
