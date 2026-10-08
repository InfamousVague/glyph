/// Team notes' and live typing's documents (docs/STAGE7.md, "Live typing and team notes"), as the Dart side holds
/// them: Yjs documents kept by the Rust core (native/src/crdt.rs, `yrs`), each behind a handle, speaking the wire
/// the web app's `yjs` speaks. What `Y.Doc`, `Y.Text` and y-protocols' `Awareness` were to
/// `src/app/core/team/doc.ts` and `src/app/core/live/team.ts`.
///
/// - **[Crdt]** opens documents and rooms over a [CoreInvoke] (`core.invoke`, or a test's fake).
/// - **[CrdtDoc]** is one note's document, with doc.ts's `TeamDoc` in mind: [CrdtDoc.words], [CrdtDoc.reconcile],
///   [CrdtDoc.applyRemote], [CrdtDoc.pending], [CrdtDoc.posted], [CrdtDoc.snapshot]. What doc.ts adds round its
///   `Y.Doc` (the store it is kept in, `seq` and `snapshotSeq`, the listeners) is the caller's.
/// - **[CrdtRoom]** is who is in a room and where: y-protocols' awareness, its states as JSON.
///
/// **Offsets are UTF-16 code units**, which are a Dart [String]'s own: `text.length`, a selection's offsets and
/// `substring` all count as the document does.
///
/// **Updates are bytes** ([Uint8List]): Yjs's v1 encoding, to be sealed and sent as they are.
///
/// **Two things are not as the web has them**, both said at length in crdt.rs: a change made here never splits a
/// character in two (the web's `applyTextDiff` can, and Yjs then writes U+FFFD over the halves), and an update FROM
/// the web that does split one is refused by [CrdtDoc.applyRemote] with a [CoreError], the document left as it was.
///
/// Every call is quick (a note's worth of text), so all of it goes through the app's one worker isolate.
library;

import 'dart:typed_data';

import '../core/bytes.dart';
import '../core/native/core.dart';

/// The field a note's words live in (doc.ts `FIELD`), and the `tname` of every relative position in them.
const String crdtField = 'body';

/// What a change made here did ([CrdtDoc.reconcile], [CrdtDoc.edit]).
class CrdtChange {
  const CrdtChange({required this.update, required this.text});

  /// The change as an update, already queued in [CrdtDoc.pending]; null when nothing changed.
  final Uint8List? update;

  /// The words after it.
  final String text;

  bool get changed => update != null;
}

/// One change an editor made: [remove] code units gone at [index], then [insert] put there.
class CrdtEdit {
  const CrdtEdit(this.index, {this.remove = 0, this.insert = ''});
  final int index;
  final int remove;
  final String insert;

  Map<String, Object?> toJson() => {'index': index, 'remove': remove, 'insert': insert};
}

/// Opens documents and rooms in the core.
class Crdt {
  const Crdt(this._invoke);

  final CoreInvoke _invoke;

  /// Note's document (doc.ts `make`): the one kept ([state], with what was [pending] when it was kept), else a new
  /// one seeded with [words], the whole of it pending for the service, else an empty one. [clientId] is a test's;
  /// left out, the core draws one as Yjs does.
  Future<CrdtDoc> open({Uint8List? state, List<Uint8List> pending = const [], String? words, int? clientId}) async {
    final said =
        await _invoke('crdt_open', {
              'state': ?_b64(state),
              'pending': [for (final update in pending) toBase64Url(update)],
              'words': ?words,
              'clientId': ?clientId,
            })
            as Map;
    return CrdtDoc._(_invoke, said['doc'] as int, said['clientId'] as int);
  }

  /// A room's awareness with this device in it as [clientId] (a document's [CrdtDoc.clientId] in its own room).
  Future<CrdtRoom> room(int clientId) async {
    final said = await _invoke('awareness_open', {'clientId': clientId}) as Map;
    return CrdtRoom._(_invoke, said['awareness'] as int, clientId);
  }

  /// Whether [theirs], a state vector, holds anything [mine] lacks (live/team.ts `lacks`). An empty list is a
  /// device with nothing.
  Future<bool> lacks(Uint8List mine, Uint8List theirs) async {
    return await _invoke('crdt_lacks', {'mine': toBase64Url(mine), 'theirs': toBase64Url(theirs)}) as bool;
  }
}

String? _b64(Uint8List? bytes) => bytes == null ? null : toBase64Url(bytes);

/// One note's document. Let it go with [close].
class CrdtDoc {
  CrdtDoc._(this._invoke, this._handle, this.clientId);

  final CoreInvoke _invoke;
  final int _handle;

  /// This device in the document: who its own changes are by.
  final int clientId;

  /// The document's words now (`text.toString()`).
  Future<String> words() async => await _invoke('crdt_text', {'doc': _handle}) as String;

  /// [words] brought into the document as one change, where they differ from it (doc.ts `reconcile`, by
  /// textDiff.ts `applyTextDiff`): the common head and foot are kept, and what lies between goes and comes.
  Future<CrdtChange> reconcile(String words) async => _change(await _invoke('crdt_apply_diff', {'doc': _handle, 'to': words}));

  /// An editor's own changes, in order, as one: each index is against the words as the edits before it left them.
  /// Refused whole, with nothing changed, when one runs past the end or would split a character.
  Future<CrdtChange> edit(List<CrdtEdit> edits) async {
    return _change(await _invoke('crdt_edit', {'doc': _handle, 'edits': [for (final edit in edits) edit.toJson()]}));
  }

  CrdtChange _change(Object? answer) {
    final said = answer as Map;
    final update = said['update'] as String?;
    return CrdtChange(update: update == null ? null : fromBase64Url(update), text: said['text'] as String);
  }

  /// Updates from the log, a peer or the organization's row, applied (doc.ts `applyRemote`): the words after, when
  /// they changed, else null. Not queued in [pending]. One that arrives before what it builds on waits for it.
  Future<String?> applyRemote(List<Uint8List> updates) async {
    final said = await _invoke('crdt_apply', {'doc': _handle, 'updates': [for (final update in updates) toBase64Url(update)]}) as Map;
    return said['changed'] == true ? said['text'] as String : null;
  }

  /// The updates made here that the service has not been given yet, in order (doc.ts `pending`).
  Future<List<Uint8List>> pending() async {
    return [for (final update in await _invoke('crdt_pending', {'doc': _handle}) as List) fromBase64Url(update as String)];
  }

  /// The first [count] pending updates are with the service now (doc.ts `posted`). Answers how many still wait.
  Future<int> posted(int count) async => await _invoke('crdt_posted', {'doc': _handle, 'count': count}) as int;

  /// The whole document as one update, for the organization's row and for keeping (`Y.encodeStateAsUpdate`).
  Future<Uint8List> snapshot() => stateFor(null);

  /// What a device at state [vector] lacks (`Y.encodeStateAsUpdate(doc, vector)`): the answer to a room's query.
  Future<Uint8List> stateFor(Uint8List? vector) async {
    return fromBase64Url(await _invoke('crdt_state', {'doc': _handle, 'vector': ?_b64(vector)}) as String);
  }

  /// What this copy holds, for a peer to answer with what it lacks (`Y.encodeStateVector`).
  Future<Uint8List> stateVector() async => fromBase64Url(await _invoke('crdt_vector', {'doc': _handle}) as String);

  /// [index] as a position that stays with its character while others type (`Y.createRelativePositionFromTypeIndex`
  /// written by `Y.relativePositionToJSON`): what a caret is in presence. [assoc] below zero keeps to the character
  /// before, as CodeMirror's `assoc` does.
  Future<Map<String, Object?>> relative(int index, {int assoc = 0}) async {
    return (await _invoke('crdt_relative', {'doc': _handle, 'index': index, 'assoc': assoc}) as Map).cast<String, Object?>();
  }

  /// A relative position's index in the words as they are now, or null when it cannot be placed: the words it sat in
  /// have not arrived, or it was never in this document.
  Future<int?> absolute(Object? position) async => await _invoke('crdt_absolute', {'doc': _handle, 'position': position}) as int?;

  /// A caret from a member's presence (`{anchor, head}`) as indexes here, or null when its anchor cannot be placed
  /// (live/team.ts `caretIndexes`). A head that cannot be is the anchor.
  Future<({int anchor, int head})?> caretIndexes(Object? caret) async {
    if (caret is! Map) return null;
    final int? anchor;
    try {
      anchor = await absolute(caret['anchor']);
    } on CoreError {
      return null;
    }
    if (anchor == null) return null;
    int? head;
    try {
      head = await absolute(caret['head']);
    } on CoreError {
      head = null;
    }
    return (anchor: anchor, head: head ?? anchor);
  }

  /// Lets the document go from the core (`doc.destroy()`). Keep [snapshot] and [pending] first.
  Future<void> close() async {
    await _invoke('crdt_close', {'doc': _handle});
  }
}

/// What an awareness change touched, as y-protocols' `change` event says it, with every state said again
/// (changed or not) in [touched], which is its `update` event's list and what is passed on to the room.
class RoomChange {
  const RoomChange({required this.added, required this.updated, required this.touched, required this.removed});
  final List<int> added;
  final List<int> updated;
  final List<int> touched;
  final List<int> removed;

  /// Whether who is here, or what any of them says, is different: when the `change` event would fire.
  bool get changed => added.isNotEmpty || updated.isNotEmpty || removed.isNotEmpty;

  static RoomChange _of(Map<Object?, Object?> said) {
    List<int> list(String field) => [for (final client in said[field] as List? ?? const []) client as int];
    return RoomChange(added: list('added'), updated: list('updated'), touched: list('touched'), removed: list('removed'));
  }
}

/// One device in a room, as last heard.
class RoomState {
  const RoomState({required this.client, required this.clock, required this.state});
  final int client;
  final int clock;

  /// What it says of itself: `user` (live/team.ts `Me`), `cursor` (`{anchor, head}`), `at` (presence.ts).
  final Map<String, Object?> state;
}

/// Who is in a room and where (y-protocols `Awareness`). Let it go with [close].
class CrdtRoom {
  CrdtRoom._(this._invoke, this._handle, this.clientId);

  final CoreInvoke _invoke;
  final int _handle;
  final int clientId;

  /// This device's whole state replaced; null leaves the room (`setLocalState`). Answers the update to send.
  Future<Uint8List> setLocal(Map<String, Object?>? state) async {
    final said = await _invoke('awareness_set', {'awareness': _handle, 'state': state}) as Map;
    return fromBase64Url(said['update'] as String);
  }

  /// One field of this device's state (`setLocalStateField`): `user`, `cursor`, `at`. Answers the update to send,
  /// or null once this device has left, when there is nothing to set a field of.
  Future<Uint8List?> setField(String field, Object? value) async {
    final said = await _invoke('awareness_set', {'awareness': _handle, 'field': field, 'value': value}) as Map;
    final update = said['update'] as String?;
    return update == null ? null : fromBase64Url(update);
  }

  /// The states of [clients] as an update (`encodeAwarenessUpdate`); of everyone here when left out, which is what
  /// a device that has just joined is sent.
  Future<Uint8List> encode([List<int>? clients]) async {
    return fromBase64Url(await _invoke('awareness_encode', {'awareness': _handle, 'clients': ?clients}) as String);
  }

  /// An update from the room, heard (`applyAwarenessUpdate`).
  Future<RoomChange> apply(Uint8List update) async {
    return RoomChange._of(await _invoke('awareness_apply', {'awareness': _handle, 'update': toBase64Url(update)}) as Map);
  }

  /// The clients a connection that left spoke for, gone (`removeAwarenessStates`). Answers those that were here.
  Future<List<int>> remove(List<int> clients) async {
    final said = await _invoke('awareness_remove', {'awareness': _handle, 'clients': clients}) as Map;
    return [for (final client in said['removed'] as List) client as int];
  }

  /// Everyone here, this device included, by client id.
  Future<List<RoomState>> states() async {
    return [
      for (final one in await _invoke('awareness_states', {'awareness': _handle}) as List)
        RoomState(client: (one as Map)['client'] as int, clock: one['clock'] as int, state: (one['state'] as Map).cast<String, Object?>()),
    ];
  }

  /// What y-protocols does every three seconds, to be called on a timer of that length: says this device is still
  /// here once its last word is fifteen seconds old (the update to send, else null), and forgets whoever has not
  /// been heard for thirty.
  Future<({Uint8List? update, List<int> removed})> tick() async {
    final said = await _invoke('awareness_tick', {'awareness': _handle}) as Map;
    final update = said['update'] as String?;
    return (update: update == null ? null : fromBase64Url(update), removed: [for (final client in said['removed'] as List) client as int]);
  }

  /// Lets the room go from the core. Say [setLocal] null first, so the others see this device leave.
  Future<void> close() async {
    await _invoke('awareness_close', {'awareness': _handle});
  }
}
