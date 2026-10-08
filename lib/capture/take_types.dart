/// The shapes a take (capture/take.dart) is written in terms of, which its host, its offers and the tape's timeline
/// all share: the note it can be written to, a note a command can name, and a stretch of its recording. A port of
/// `src/app/capture/takeTypes.ts`.
///
/// The take is generic in its note: the recorder runs one over the real notes, and its tests over notes of their
/// own, so all a take asks of a note is its id and its body.
///
/// What differs: the web's types are structural, so any object with an id and a body is a `TakeNote`, the store's
/// `Note` among them. Dart's are not, and `lib/core/note.dart`'s `Note` cannot be made to implement an interface
/// declared here. So [TakeNote] is a plain class (what the tests run a take over), the take's `N` is bounded by
/// `Object` rather than by it, and [TakeCandidate] - a class that extends `Candidate` with the note, where the web
/// intersects two types - reads the body of either kind of note through `noteBody`.
library;

import '../core/note.dart' show Note;
import 'route.dart';

/// A note as a take sees it: all it reads is the id and the body.
class TakeNote {
  const TakeNote({required this.id, required this.body});

  final String id;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is TakeNote && other.runtimeType == runtimeType && other.id == id && other.body == body;

  @override
  int get hashCode => Object.hash(id, body);

  @override
  String toString() => '{id: $id, body: $body}';
}

/// A note a command can name, by the title the command list knows it by, with the note itself.
class TakeCandidate<N extends Object> extends Candidate {
  const TakeCandidate({required super.id, required super.title, required this.note});

  final N note;

  /// The note's body, for a [TakeNote] or the library's own `Note`; null for anything else.
  @override
  String? get noteBody => switch (note) {
    final TakeNote note => note.body,
    final Note note => note.body,
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is TakeCandidate && other.id == id && other.title == title && other.note == note;

  @override
  int get hashCode => Object.hash(id, title, note);

  @override
  String toString() => '{id: $id, title: $title, note: $note}';
}

/// A stretch of the take's recording, in ms on its own timeline.
class Span {
  const Span({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  @override
  bool operator ==(Object other) => other is Span && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => '{startMs: $startMs, endMs: $endMs}';
}
