/// A meeting's transcript as turns, one paragraph each, every one of them saying who spoke (where anyone is named)
/// and when: `**Sam Lee (0:04):** words`, or `(0:04) words` where nobody is (Matt, 2026-10-30: "some of the meeting
/// transcripts still go into one giant block instead of maintaining the name (timestamp): prefix on each line please
/// address"). Pure, so every rule is tested (test/meet/transcript_turns_test.dart).
///
/// The rules, the same for every writer of a meeting's transcript (the write-up's Rust twin is
/// tauri/src-tauri/src/transcript.rs `meeting_paragraphs`, for the turns with nobody named):
/// - **A turn is a speaker's run of phrases**, joined by a space, its first letter a capital, and a phrase after a
///   finished sentence starting with one.
/// - **A new turn starts** where the speaker changes; after a pause longer than [turnPauseMs] between two phrases;
///   and once a turn has run [turnMostMs] (a minute), at the next phrase, so one speaker's long stretch is a paragraph
///   a minute and never a wall.
/// - **Every turn is timed**, from its first phrase's start ([counter], `0:04`, `12:40`, `1:02:03`). A phrase with no
///   words is skipped.
///
/// Why a minute and not just the pauses: Whisper's phrases over a meeting's mixed sound abut (one ends where the next
/// begins), so a pause rule alone, which the write-up's paragraphs had (1.5 s, `paragraphs`), wrote the 38 minutes of
/// the 2026-10-29 Engineering Standup as one paragraph with nothing to say who or when.
library;

import '../core/note.dart' show Segment;
import '../core/text.dart' show capitalise;
import '../tapes/tape.dart' show counter;

/// A pause between two phrases longer than this starts another turn, in ms (`MEETING_PAUSE_MS`).
const int turnPauseMs = 3000;

/// How long a turn runs before the next phrase starts another, in ms (`TURN_MOST_MS`).
const int turnMostMs = 60000;

final RegExp _stop = RegExp(r'[.!?]$');

/// One turn: who (null for nobody named), when its first phrase began and its last ended, and its words.
typedef MeetingTurn = ({String? speaker, int startMs, int endMs, String text});

/// [segments] as turns (see the header), each segment's speaker in [speakers] by index (null, or past its end, for
/// nobody named).
List<MeetingTurn> transcriptTurns(List<Segment> segments, [List<String?> speakers = const []]) {
  final out = <MeetingTurn>[];
  String? speaker;
  var words = <String>[];
  var startMs = 0, endMs = 0;
  var open = false;
  void flush() {
    if (!open) return;
    final text = words.join(' ').trim();
    if (text.isNotEmpty) out.add((speaker: speaker, startMs: startMs, endMs: endMs, text: capitalise(text)));
    words = <String>[];
    open = false;
  }

  for (final (i, segment) in segments.indexed) {
    final text = segment.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    final who = i < speakers.length ? speakers[i] : null;
    if (!open || who != speaker || segment.startMs - endMs > turnPauseMs || segment.startMs - startMs >= turnMostMs) {
      flush();
      speaker = who;
      startMs = segment.startMs;
      endMs = segment.endMs;
      open = true;
    } else if (segment.endMs > endMs) {
      endMs = segment.endMs;
    }
    // A phrase after a finished sentence starts one, whatever case it came in (the live recognizer's are lower case).
    words.add(words.isNotEmpty && _stop.hasMatch(words.last) ? capitalise(text) : text);
  }
  flush();
  return out;
}

/// A turn as its paragraph: `**Sam Lee (0:04):** words`, or `(0:04) words` with nobody named.
String turnLine(String? speaker, int startMs, String text) {
  final at = counter(startMs);
  return speaker == null || speaker.isEmpty ? '($at) $text' : '**$speaker ($at):** $text';
}

/// [segments] as the paragraphs of a meeting's transcript (see the header).
List<String> turnLines(List<Segment> segments, [List<String?> speakers = const []]) => [for (final turn in transcriptTurns(segments, speakers)) turnLine(turn.speaker, turn.startMs, turn.text)];

/// A meeting recorded here as its `## Transcript` section, in turns with nobody named (see the header): what the
/// recorder writes as it records and the better words write after, and what the write-up writes from the same
/// phrases (tauri/src-tauri/src/transcript.rs `meeting_paragraphs`, which agrees with this line for line). The phrase
/// still being guessed, when there is one, ends the last turn, or is a turn of its own at the start. The dictation's
/// `renderTranscript` (markdown.dart) stays as the web's fixture pins it; a meeting is written with this.
String meetingTranscript(List<Segment> segments, [String partial = '']) {
  final lines = turnLines(segments);
  final guess = partial.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (guess.isNotEmpty) {
    if (lines.isEmpty) {
      lines.add(turnLine(null, 0, capitalise(guess)));
    } else {
      lines[lines.length - 1] = '${lines.last} $guess';
    }
  }
  return '## Transcript\n\n${lines.join('\n\n')}';
}
