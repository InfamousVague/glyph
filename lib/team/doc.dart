/// A team note's document on this device (docs/SHARED.md, S5): one Yjs document per note, held while the app runs,
/// its text in `body`, what the organization channel syncs (lib/team/sync.dart) and what the editor will bind to
/// when live typing is here. A port of `src/app/core/team/doc.ts`.
///
/// Every change made here becomes an update the next pass posts to the note's log; every update the log holds is
/// applied here; the note's words in the library are the document's text, written as it changes. Words that reach
/// the note without the editor - a capture appending to it, a journal entry, another device's sync - are reconciled
/// into the document as a change ([TeamDoc.reconcile]): the lines that differ go and the new ones come, in one
/// transaction, so a change made anywhere merges with the team's rather than overwriting it.
///
/// What differs:
/// - The document is the Rust core's (lib/team/crdt.dart, `yrs`), behind a handle, so everything that touches it
///   waits: [TeamDoc.reconcile], [TeamDoc.applyRemote], [TeamDoc.pending], [TeamDoc.snapshot]. The words are kept
///   here beside it ([TeamDoc.words], at once), and stay true as long as every change goes through the [TeamDoc]:
///   [TeamDoc.crdt] is for what reads (a caret's position), never for a change.
/// - The page's module map of documents is [TeamDocs], made once with the [Crdt] and the [TeamDocStore]; `teamDoc`,
///   `adoptTeamDoc`, `dropTeamDoc`, `heldTeamDocs` and `forgetTeamDocs` are its methods. Two of them in one test are
///   two devices.
/// - [TeamDocs.forget] also lets the documents go from the core, which a page reload did for the web.
/// - **A canvas is not here.** The web keeps a team canvas as types beside the text (core/team/canvas.ts); the core
///   holds text alone, and the channel passes a canvas over (sync.dart says how) rather than merge its JSON as
///   words.
/// - A change from the web that splits a character in two is refused by the core (crdt.dart): [TeamDoc.applyRemote]
///   throws its [CoreError], the document as it was.
library;

import 'dart:async';
import 'dart:typed_data';

import 'crdt.dart';
import 'docs.dart';

/// How long a change rests before the document is kept to the store (`KEEP_AFTER_MS`).
const Duration keepAfter = Duration(milliseconds: 400);

/// One note's document (`TeamDoc`).
class TeamDoc {
  TeamDoc._(this.noteId, this.crdt, this._store, this._words, {required this.seq, required this.snapshotSeq, required Duration rest}) : _rest = rest;

  final String noteId;

  /// The document in the core: for reading (a relative position, a state vector). Changes go through this class.
  final CrdtDoc crdt;
  final TeamDocStore _store;
  final Duration _rest;

  /// The last seq of the note's log applied here, and the seq the organization's row covered when last put or read.
  int seq;
  int snapshotSeq;

  String _words;
  bool _closed = false;
  final Set<void Function(String words)> _listeners = {};
  Timer? _keep;
  Future<void> _keeping = Future<void>.value();

  /// The document's words now.
  String get words => _words;

  void _tell() {
    for (final listener in _listeners.toList()) {
      listener(_words);
    }
  }

  /// [words] brought into the document as one change, where they differ from it. True when something changed.
  Future<bool> reconcile(String words) async {
    if (_words == words) return false;
    final change = await crdt.reconcile(words);
    _words = change.text;
    if (!change.changed) return false;
    _soon();
    _tell();
    return true;
  }

  /// An editor's own changes, in order, as one (crdt.dart `edit`): pending for the service like any change made
  /// here. Listeners are not told: the editor knows what it typed.
  Future<CrdtChange> edit(List<CrdtEdit> edits) async {
    final change = await crdt.edit(edits);
    _words = change.text;
    if (change.changed) _soon();
    return change;
  }

  /// Updates from the log or the organization's row, applied; the words after, when they changed. Throws the core's
  /// refusal for an update it cannot hold, the document left as it was.
  Future<String?> applyRemote(List<Uint8List> updates, [int? seq]) async {
    final after = updates.isEmpty ? null : await crdt.applyRemote(updates);
    if (seq != null && seq > this.seq) this.seq = seq;
    _soon();
    if (after == null) return null;
    _words = after;
    _tell();
    return after;
  }

  /// The updates made here that the service has not been given yet, in order.
  Future<List<Uint8List>> pending() => crdt.pending();

  /// The first [count] pending updates are with the service now.
  Future<void> posted(int count) async {
    if (count > 0) await crdt.posted(count);
    _soon();
  }

  /// The whole document, for the organization's row.
  Future<Uint8List> snapshot() => crdt.snapshot();

  /// Kept to the store now, rather than a moment from now.
  Future<void> flush() {
    _keep?.cancel();
    _keep = null;
    return _keeping = _keeping.then((_) async {
      if (_closed) return;
      await _store.write(noteId, TeamDocRecord(state: await crdt.snapshot(), seq: seq, snapshotSeq: snapshotSeq, pending: await crdt.pending()));
    });
  }

  /// Told when the words change by an update from elsewhere, or by a reconcile. Answers the way to stop hearing.
  void Function() onWords(void Function(String words) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _soon() {
    if (_closed) return;
    _keep?.cancel();
    _keep = Timer(_rest, () {
      _keep = null;
      // Its own trouble: the next change, or the pass's own flush, keeps it.
      unawaited(flush().catchError((Object _) {}));
    });
  }

  /// Let go from the core, whatever was being kept finished first.
  Future<void> _close() async {
    _keep?.cancel();
    _keep = null;
    try {
      await _keeping;
    } catch (_) {
      // Not kept: nothing to wait for.
    }
    _closed = true;
    _listeners.clear();
    try {
      await crdt.close();
    } catch (_) {
      // Already gone.
    }
  }
}

/// This device's team documents, by note (`teamDoc` and the functions beside it).
class TeamDocs {
  /// [rest] is how long a change rests before it is kept; a test may shorten it.
  TeamDocs({required Crdt crdt, required this.store, Duration rest = keepAfter})
      : _crdt = crdt,
        _rest = rest;

  final Crdt _crdt;
  final Duration _rest;

  /// Where the documents are kept between launches.
  final TeamDocStore store;

  final Map<String, Future<TeamDoc?>> _held = {};

  Future<TeamDoc> _make(String noteId, TeamDocRecord? record, String? seedWords) async {
    // A document seeded here from the note's words is itself a change the service has not seen: the whole of it.
    final crdt = record != null ? await _crdt.open(state: record.state, pending: record.pending) : await _crdt.open(words: seedWords);
    final doc = TeamDoc._(noteId, crdt, store, await crdt.words(), seq: record?.seq ?? 0, snapshotSeq: record?.snapshotSeq ?? 0, rest: _rest);
    // Seeded here: kept soon, so an app closed before the first pass still has the words pending for the team.
    if (record == null && (seedWords ?? '').isNotEmpty) doc._soon();
    return doc;
  }

  /// Note [noteId]'s document (`teamDoc`): the one held, else the one kept in the store, else - with [seedWords] - a
  /// new one with those words, the whole of them pending for the service. Null when there is none and nothing to
  /// seed with.
  Future<TeamDoc?> doc(String noteId, {String? seedWords}) {
    final held = _held[noteId];
    if (held != null) return held;
    final made = () async {
      final record = await store.read(noteId);
      if (record == null && seedWords == null) return null;
      return _make(noteId, record, seedWords);
    }();
    _held[noteId] = made;
    // None, or it could not be made: asked again next time, not remembered as nothing.
    made.then((doc) {
      if (doc == null && identical(_held[noteId], made)) _held.remove(noteId);
    }, onError: (Object _) {
      if (identical(_held[noteId], made)) _held.remove(noteId);
    });
    return made;
  }

  /// The document adopted from the organization's row (`adoptTeamDoc`): its state applied over whatever this device
  /// holds, merged and never doubled.
  Future<TeamDoc> adopt(String noteId, Uint8List state, int seq) async {
    final held = await doc(noteId);
    if (held != null) {
      await held.applyRemote([state], seq);
      if (seq > held.snapshotSeq) held.snapshotSeq = seq;
      return held;
    }
    final made = await _make(noteId, TeamDocRecord(state: state, seq: seq, snapshotSeq: seq), null);
    _held[noteId] = Future.value(made);
    await made.flush();
    return made;
  }

  /// The document let go (`dropTeamDoc`): the note is gone, or no longer the team's.
  Future<void> drop(String noteId) async {
    final held = _held.remove(noteId);
    TeamDoc? doc;
    try {
      doc = await held;
    } catch (_) {
      doc = null;
    }
    await doc?._close();
    await store.remove(noteId);
  }

  /// Every document held, for the pass and the tests (`heldTeamDocs`).
  List<String> held() => _held.keys.toList();

  /// Forgotten without touching the store (`forgetTeamDocs`): signing out, and a test's "the app was closed". What
  /// was kept stays kept; what was only resting is not.
  Future<void> forget() async {
    final all = _held.values.toList();
    _held.clear();
    for (final each in all) {
      try {
        await (await each)?._close();
      } catch (_) {
        // Never made.
      }
    }
  }
}
