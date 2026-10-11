/// What the AI keeps on the device per note: the home page's one-line gist. A port of `src/app/format/results.ts`.
///
/// Each mode's text used to be kept here too; the model's words land in the note itself now (ai/landing.dart), so
/// only the gist is left, under the same key with the hash of the body it came from. A reset clears the key with
/// every other `glyph-` one.
///
/// What differs: [Gist] is a class, and its `for` (a word Dart keeps) is [Gist.forBody]; what is kept is the web's
/// JSON, key for key. A kept gist without a text, a hash and a model that are a string, a number and a string reads
/// as none, where the page cast whatever was there.
library;

import 'package:flutter/foundation.dart';

import '../ai/support/note_sheet.dart';
import '../core/stored.dart';

const String _key = 'glyph-ai-results';

/// Per note, the gist, beside whatever an older sheet still holds for a mode's text, which is read past and kept.
typedef _Kept = Map<String, Object?>;

/// Read shared (core/stored.dart `readShared`): the home page reads a gist for every card it draws, and each read
/// was the whole sheet parsed again. A read asks for the text, which cannot be stale, and parses only when it has
/// changed.
final NoteSheet<_Kept> _sheet = NoteSheet<_Kept>(
  () => stored.readShared<Sheet<_Kept>>(_key, <String, _Kept>{}, (raw) => sheetOf<_Kept>(raw, (one) => one is Map ? one.cast<String, Object?>() : null)),
  (value) => stored.write(_key, value),
);

/// The home page's gist: its line, the body it came from as a hash, its length and its first line, and the model
/// (`Gist`).
@immutable
class Gist {
  const Gist({required this.text, required this.forBody, required this.model, this.len, this.head});

  final String text;

  /// The hash of the body the gist was written from (format/body_hash.dart); `for` on the web and in what is kept.
  final int forBody;

  final String model;

  /// The body's length and first line when the gist was written: what "a meaningful change" is measured against.
  final int? len;
  final String? head;

  /// A gist as kept, or null for anything that is not one.
  static Gist? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    final forBody = raw['for'];
    final model = raw['model'];
    final len = raw['len'];
    final head = raw['head'];
    if (text is! String || forBody is! num || model is! String) return null;
    return Gist(text: text, forBody: forBody.toInt(), model: model, len: len is num ? len.toInt() : null, head: head is String ? head : null);
  }

  Map<String, Object?> toJson() => {'text': text, 'for': forBody, 'model': model, if (len != null) 'len': len, if (head != null) 'head': head};

  @override
  bool operator ==(Object other) => other is Gist && other.text == text && other.forBody == forBody && other.model == model && other.len == len && other.head == head;

  @override
  int get hashCode => Object.hash(text, forBody, model, len, head);

  @override
  String toString() => 'Gist($text, $forBody, $model, $len, $head)';
}

/// The gist kept for the note [id], or null.
Gist? readGist(String id) => Gist.fromJson(_sheet.read()[id]?['gist']);

/// Keeps [gist] for the note [id], beside whatever else its record holds.
void keepGist(String id, Gist gist) {
  _sheet.update(id, (was) => {...?was, 'gist': gist.toJson()});
}

/// A note is gone: so is its gist.
void forgetResults(String id) => _sheet.forget(id);
