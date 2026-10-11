/// What live sync says inside a sealed message (docs/LIVE.md). A port of `src/app/core/live/wire.ts`.
///
/// The relay carries these as base64url ciphertext and never sees which is which: every kind is sealed alike,
/// under the account key, bound to the note it belongs to; or, in an organization's rooms, under the organization
/// key, bound to the organization and the room.
///
/// One byte of kind, then the payload: binary rather than JSON, because the payload is a Yjs update, and turning
/// bytes into text to put them in JSON and back would cost a third more on every keystroke.
///
/// What differs: the sealing is the Rust core's ([AccountCrypto.sealBytes]), and a kind this Ghost.md does not
/// know, a message cut short and one that will not open are all a [FormatException] or the core's own error: the
/// caller drops the message either way.
library;

import 'dart:math';
import 'dart:typed_data';

import '../account/crypto_api.dart';
import '../core/bytes.dart';

/// The kinds (`Kind`).
abstract final class Kind {
  /// "I have joined and have no document: send me yours." A device that was not first into the room sends it. In
  /// a team's room the payload is the asker's state vector, and the answer what it lacks.
  static const int query = 1;

  /// The whole document, sent to one device in answer to a query. For an account's own note the payload starts
  /// with the seed id.
  static const int state = 2;

  /// A change to the document: one keystroke, one paste.
  static const int update = 3;

  /// Who a device is and where its caret or pointer is: an awareness update (y-protocols), in a team's rooms.
  static const int presence = 4;

  static const Set<int> all = {query, state, update, presence};
}

/// One message (`Envelope`).
class Envelope {
  const Envelope(this.kind, [this.payload]);

  final int kind;
  final Uint8List? payload;

  Uint8List get bytes => payload ?? Uint8List(0);
}

/// The associated data a note's live messages are sealed under: one sealed for another note will not open.
String liveContext(String noteId) => 'live:$noteId';

/// The associated data of an organization's room (docs/SHARED.md, S6): the organization and the room.
String teamContext(String orgId, String room) => 'live:org:$orgId:$room';

Uint8List encodeEnvelope(Envelope envelope) {
  final payload = envelope.bytes;
  return Uint8List(1 + payload.length)
    ..[0] = envelope.kind
    ..setRange(1, 1 + payload.length, payload);
}

Envelope decodeEnvelope(Uint8List bytes) {
  if (bytes.isEmpty || !Kind.all.contains(bytes[0])) throw const FormatException('A live message of a kind this Ghost.md does not know.');
  return Envelope(bytes[0], Uint8List.sublistView(bytes, 1));
}

/// An envelope sealed for the relay: what goes in a `msg` frame's `data`.
Future<String> sealEnvelope(AccountCrypto crypto, SealKey key, String noteId, Envelope envelope) async {
  return toBase64Url(await crypto.sealBytes(key, encodeEnvelope(envelope), liveContext(noteId)));
}

/// A `msg` frame's `data` opened. Throws on the wrong key, a tampered message, or one sealed for another note: the
/// caller drops it and carries on, since a message it cannot read is one it should not act on.
Future<Envelope> openEnvelope(AccountCrypto crypto, SealKey key, String noteId, String data) async {
  return decodeEnvelope(await crypto.openBytes(key, fromBase64Url(data), liveContext(noteId)));
}

Future<String> sealTeamEnvelope(AccountCrypto crypto, SealKey key, String orgId, String room, Envelope envelope) async {
  return toBase64Url(await crypto.sealBytes(key, encodeEnvelope(envelope), teamContext(orgId, room)));
}

Future<Envelope> openTeamEnvelope(AccountCrypto crypto, SealKey key, String orgId, String room, String data) async {
  return decodeEnvelope(await crypto.openBytes(key, fromBase64Url(data), teamContext(orgId, room)));
}

/// A seed id, and the document's state after it: how a `State` payload is laid out (docs/LIVE.md, Seeding).
const int seedBytes = 16;

final Random _random = Random.secure();

String newSeed() => toBase64Url(Uint8List.fromList([for (var i = 0; i < seedBytes; i += 1) _random.nextInt(256)]));

Uint8List packState(String seed, Uint8List state) {
  final id = fromBase64Url(seed);
  if (id.length != seedBytes) throw const FormatException('A seed id is sixteen bytes.');
  return Uint8List(seedBytes + state.length)
    ..setRange(0, seedBytes, id)
    ..setRange(seedBytes, seedBytes + state.length, state);
}

({String seed, Uint8List state}) unpackState(Uint8List payload) {
  if (payload.length < seedBytes) throw const FormatException('A document state too short to carry its seed id.');
  return (seed: toBase64Url(Uint8List.sublistView(payload, 0, seedBytes)), state: Uint8List.sublistView(payload, seedBytes));
}
