/// A fresh id that nothing else has: a note's, a conflict copy's, a picture's, a notification's. A port of
/// `src/app/core/ids.ts`.
///
/// What differs: the page asks `crypto.randomUUID`, which needs a secure context, and falls back to the time and
/// eight random characters behind a prefix where it has none. Dart's [Random.secure] needs no context, so [randomId]
/// is always a version 4 UUID and its `prefix` is kept only so a call ports as it is written. A platform with no
/// secure source at all throws [UnsupportedError] from `Random.secure()`; none this app runs on is one.
library;

import 'dart:math';
import 'dart:typed_data';

import 'bytes.dart';

final Random _secure = Random.secure();

Uint8List _random(int count) {
  final out = Uint8List(count);
  for (var i = 0; i < count; i += 1) {
    out[i] = _secure.nextInt(256);
  }
  return out;
}

/// A UUID, version 4 (`randomId`). [prefix] says what the id is for on the web's fallback; it is not used here.
String randomId([String prefix = 'n']) {
  final bytes = _random(16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = toHex(bytes);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// How long a short id is: 128 random bits as base64url, with no padding (`SHORT_ID_LENGTH`).
const int shortIdLength = 22;

/// A short id: 22 base64url characters, 128 random bits (`shortId`). The shape the service gives an organization and
/// asks of a notification (docs/TEAMS.md): the app makes one for each self notification it records
/// (lib/sync/record.dart).
String shortId() => toBase64Url(_random(16));

final RegExp _shortId = RegExp(r'^[A-Za-z0-9_-]{22}$');

/// Whether [text] is a short id as [shortId] makes one: the service's check, made here before a round trip
/// (`isShortId`).
bool isShortId(String text) => _shortId.hasMatch(text);
