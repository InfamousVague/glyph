/// A take's place on the tape of the note it is kept with. A port of `src/app/capture/timeline.ts`.
///
/// A take's phrases and commands are timed from the start of the take. Its sound is kept under the note's id
/// (capture_stop `recordAs`), on the end of the note's own tape when the note still has one ([appendsTo]), so
/// everything stored against the tape - its phrases, the better words' job - is on that longer timeline, later by the
/// length the tape already had ([onTape]). One that forgot the shift would play the wrong sound, and the better words
/// would listen to the wrong stretch. Pure, so each rule is a test.
///
/// What differs: the shapes, since the web's are structural. [shifted] moves a [Span] or a [Segment] (a phrase is a
/// span with words on the web; here the two are classes of their own) and refuses anything else. [TapedNote] is a
/// class, with [TapedNote.ofNote] for the library's own `Note`, which the web passes as it is. The take [onTape]
/// reads is [TakeSpans], its two lists of spans, where the web takes any object that has them.
library;

import '../core/note.dart' show Note;
import 'markdown.dart';
import 'take_types.dart';

/// [spans] moved [by] ms later, keeping whatever else each one carries (a phrase's words). Each is a [Span] or a
/// [Segment].
List<T> shifted<T extends Object>(List<T> spans, int by) => [
  for (final span in spans)
    switch (span) {
          final Segment phrase => Segment(text: phrase.text, startMs: phrase.startMs + by, endMs: phrase.endMs + by),
          final Span stretch => Span(startMs: stretch.startMs + by, endMs: stretch.endMs + by),
          _ => throw ArgumentError.value(span, 'spans', 'neither a Span nor a Segment'),
        }
        as T,
];

/// The part of a note its tape is read from: how long the tape is, and the phrases timed against it.
class TapedNote {
  const TapedNote({this.recordingMs, this.segments});

  /// The library's own note, read as its tape.
  TapedNote.ofNote(Note note) : recordingMs = note.recordingMs, segments = note.segments;

  final int? recordingMs;
  final List<Segment>? segments;
}

/// Whether a take's sound goes on the end of [continued]'s tape: only onto a tape the note still has. A recording
/// removed from the note leaves its file behind, and a take added after it starts the file afresh rather than
/// playing after the removed sound. A new note (null) starts a tape of its own.
bool appendsTo(TapedNote? continued) => continued != null && (continued.recordingMs ?? 0) > 0;

/// What [onTape] reads of a take: the stretches that were commands, and the phrases that ended in the keyword.
class TakeSpans {
  const TakeSpans({required this.commandSpans, required this.keywordSpans});
  final List<Span> commandSpans;
  final List<Span> keywordSpans;
}

/// Where a take's pieces sit on the tape it was kept on.
class OnTape {
  const OnTape({required this.fromMs, required this.prior, required this.segments, required this.skip, required this.keywordAt});

  /// Where the take starts on the tape: the length the continued note's tape already had, or 0.
  final int fromMs;

  /// The continued note's phrases from before this take, as they were.
  final List<Segment> prior;

  /// Every phrase on the tape: the prior ones, then this take's, moved after them.
  final List<Segment> segments;

  /// The stretches that were commands, for the better words to leave out.
  final List<Span> skip;

  /// Phrases that were words and then "Glyph", for the better words to keep only what came before it.
  final List<Span> keywordAt;

  @override
  bool operator ==(Object other) =>
      other is OnTape &&
      other.fromMs == fromMs &&
      _same(other.prior, prior) &&
      _same(other.segments, segments) &&
      _same(other.skip, skip) &&
      _same(other.keywordAt, keywordAt);

  @override
  int get hashCode => Object.hash(fromMs, Object.hashAll(prior), Object.hashAll(segments), Object.hashAll(skip), Object.hashAll(keywordAt));

  @override
  String toString() => 'OnTape(fromMs: $fromMs, prior: $prior, segments: $segments, skip: $skip, keywordAt: $keywordAt)';
}

bool _same(List<Object> a, List<Object> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The take's phrases ([spoken], with any the stopped decode added) and commands, moved onto the tape of
/// [continued].
OnTape onTape(TapedNote? continued, TakeSpans take, List<Segment> spoken) {
  final fromMs = continued?.recordingMs ?? 0;
  final prior = [...?continued?.segments];
  return OnTape(
    fromMs: fromMs,
    prior: prior,
    segments: [...prior, ...shifted(spoken, fromMs)],
    skip: shifted(take.commandSpans, fromMs),
    keywordAt: shifted(take.keywordSpans, fromMs),
  );
}
