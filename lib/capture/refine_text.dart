/// The better words, as the note will read with them: the pure half of the pass after a recording
/// (capture/refine.dart runs it). A port of `src/app/capture/refineText.ts`.
///
/// The larger model hears the take's whole recording again, commands and all, so what it answers is not yet the
/// note's words: the stretches that were commands are taken out, a phrase the live words cut at "hey Ghost" is cut
/// there again, and the voice memos of a job queued before a recording stopped making them (refine.dart `clips`) -
/// which it never heard as words - are put back where they were said. Then the take is rendered again from the
/// result, into the note's text from before it where the recorder put the live words (place.dart: its end, or its
/// lists). By overlap rather than by match throughout, because the larger model hears the phrases at slightly
/// different times. Pure, so every rule is a test.
///
/// What differs: the call of two of them. The web's `withClips(job, refined)` and `withoutCommands(job, refined)`
/// take a `Pick` of a job - any object with `clips`, or with `skip`, `keywordAt` and `live` - which Dart has no type
/// for. Here the phrases come first and what was picked follows by name: `withClips(refined, clips: …)`,
/// `withoutCommands(refined, skip: …, keywordAt: …, live: …)`. A stretch is a [Span] (take_types.dart).
/// `refinedBody` and `refinedSegments` take the whole job, as on the web.
library;

import 'dart:math' as math;

import 'command.dart' show findKeyword;
import 'markdown.dart' show RenderOptions, Segment, renderNote;
import 'place.dart' show end, placeTake;
import 'refine.dart' show RefineJob;
import 'take_types.dart' show Span;

/// The note as it should read with the take's better phrases in place of the live ones: the text before the take,
/// then the take rendered again from the new phrases - the first take titled, a later one not, as the recorder did.
String refinedBody(RefineJob job, List<Segment> refined) {
  final take = renderNote(_better(job, refined), '', RenderOptions(titled: job.titled)).markdown;
  return placeTake(job.baseBody, take, job.placing ?? end).body;
}

/// The job's better phrases as the note and the tape take them: its commands out, its memos back.
List<Segment> _better(RefineJob job, List<Segment> refined) =>
    withClips(withoutCommands(refined, skip: job.skip, keywordAt: job.keywordAt, live: job.live), clips: job.clips);

/// The better phrases with this take's voice memos back among them, in the order they were spoken.
List<Segment> withClips(List<Segment> refined, {List<Segment>? clips}) {
  if (clips == null || clips.isEmpty) return [...refined];
  // By where each starts, then where it ends, and as they came among equals (JavaScript's sort is stable).
  final out = <Segment>[];
  for (final segment in [...refined, ...clips]) {
    var at = out.length;
    while (at > 0 && _order(out[at - 1], segment) > 0) {
      at -= 1;
    }
    out.insert(at, segment);
  }
  return out;
}

int _order(Segment a, Segment b) => a.startMs != b.startMs ? a.startMs - b.startMs : a.endMs - b.endMs;

/// The recording's phrases with the take's replaced by the better ones.
List<Segment> refinedSegments(RefineJob job, List<Segment> refined) =>
    [...job.priorSegments.where((s) => s.endMs <= job.fromMs), ..._better(job, refined)];

/// How much of [segment] the spans cover, 0 to 1.
double _covered(Segment segment, List<Span> spans) {
  final length = math.max(1, segment.endMs - segment.startMs);
  var overlap = 0;
  for (final span in spans) {
    overlap += math.max(0, math.min(span.endMs, segment.endMs) - math.max(span.startMs, segment.startMs));
  }
  return overlap / length;
}

/// The better phrases with the take's commands taken out: a phrase mostly inside a command's stretch goes, and one
/// that overlaps a phrase the live words cut at "Glyph" is cut there too. The larger model hears the phrases at
/// slightly different times, so it is by overlap, not by match.
List<Segment> withoutCommands(List<Segment> refined, {List<Span>? skip, List<Span>? keywordAt, List<Segment>? live}) {
  final skipped = skip ?? const <Span>[];
  final keyed = keywordAt ?? const <Span>[];
  if (live != null) {
    // The live reader kept the take's phrases itself, a command's payload among them: a better phrase that touches a
    // command is replaced by the live phrases inside it, so it neither erases what the command sent nor brings the
    // command back.
    final spans = [...skipped, ...keyed];
    return [
      for (final segment in refined)
        if (!spans.any((span) => math.min(span.endMs, segment.endMs) > math.max(span.startMs, segment.startMs)))
          segment
        else
          ...live.where((phrase) {
            final middle = (phrase.startMs + phrase.endMs) / 2;
            return middle >= segment.startMs && middle <= segment.endMs;
          }),
    ];
  }
  final out = <Segment>[];
  for (final segment in refined) {
    if (skipped.isNotEmpty && _covered(segment, skipped) >= 0.5) continue;
    if (keyed.isNotEmpty && _covered(segment, keyed) > 0) {
      final found = findKeyword(segment.text);
      if (found != null) {
        if (found.before.isNotEmpty) out.add(Segment(text: found.before, startMs: segment.startMs, endMs: segment.endMs));
        continue;
      }
    }
    out.add(segment);
  }
  return out;
}
