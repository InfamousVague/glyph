/// Who said what in a meeting Ghost was in (docs/MEET.md, "On the device"): Meet's captions name the speakers, the
/// device's Whisper hears the words, and this puts the two together. Pure, so every rule here is tested.
///
/// - **Turns.** The captions are grouped into turns, a speaker's run of lines; a turn lasts from its first line to
///   the next turn's first line ([captionTurns]).
/// - **Alignment.** Each of Whisper's segments is given the speaker whose turns overlap it longest ([alignSpeakers]).
///   A caption shows a moment after the words are said, so a turn is moved earlier by [captionLagMs] before it is
///   compared. A segment no turn overlaps takes the nearest turn's speaker within [nearestMs], and otherwise none.
/// - **The transcript.** Consecutive segments of one speaker are one paragraph, `**Name:** words`; a segment with no
///   speaker is a paragraph of its words alone ([speakerParagraphs]). With no Whisper at all, the captions' own turns
///   are the transcript, in the same shape ([captionParagraphs]).
/// - **The captions kept in the note** until the write-up comes are the turns with when each began,
///   `**Name (0:12):** words` under `## Captions` ([captionsSection]), which [turnsOf] reads back: so the alignment
///   needs nothing but the note, on whichever of the account's devices writes it up.
library;

import 'dart:math' as math;

import '../core/note.dart' show Segment;
import '../tapes/tape.dart' show counter;
import 'gmt.dart';

/// How long after the words a caption shows, in ms.
const int captionLagMs = 1000;

/// How far a segment no turn overlaps may be from the nearest turn and still take its speaker, in ms.
const int nearestMs = 4000;

/// The heading the captions are kept under until the write-up gives the note its `## Transcript`.
const String captionsHeading = '## Captions';

/// One speaker's run of caption lines.
class CaptionTurn {
  const CaptionTurn({required this.speaker, required this.startMs, required this.endMs, required this.text});

  /// The name; empty where Meet showed none.
  final String speaker;
  final int startMs;
  final int endMs;
  final String text;

  @override
  bool operator ==(Object other) => other is CaptionTurn && other.speaker == speaker && other.startMs == startMs && other.endMs == endMs && other.text == text;

  @override
  int get hashCode => Object.hash(speaker, startMs, endMs, text);

  @override
  String toString() => 'CaptionTurn($speaker, $startMs-$endMs, $text)';
}

/// How long the last turn is taken to last: a fifth of a second a character, at least two seconds.
int _guessMs(String text) => math.max(2000, text.length * 200 ~/ 3);

/// A name as a note writes it: no asterisks, no brackets, no colon at its end, one space between words.
String _name(String speaker) => speaker.replaceAll(RegExp(r'[*\[\]()]'), '').replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r':+$'), '');

/// The captions as turns (see the header).
List<CaptionTurn> captionTurns(List<CaptionLine> lines) {
  final groups = <({String speaker, int start, List<String> words})>[];
  for (final line in lines) {
    final speaker = _name(line.speaker);
    if (groups.isNotEmpty && groups.last.speaker == speaker) {
      groups.last.words.add(line.text);
    } else {
      groups.add((speaker: speaker, start: line.at, words: [line.text]));
    }
  }
  return [
    for (final (i, group) in groups.indexed)
      CaptionTurn(
        speaker: group.speaker,
        startMs: group.start,
        endMs: i + 1 < groups.length ? math.max(group.start, groups[i + 1].start) : group.start + _guessMs(group.words.join(' ')),
        text: group.words.join(' '),
      ),
  ];
}

/// The speaker of each of [segments], or null for one no turn can be given to (see the header).
List<String?> alignSpeakers(List<Segment> segments, List<CaptionTurn> turns, {int lagMs = captionLagMs}) {
  final named = [for (final turn in turns) if (turn.speaker.isNotEmpty) turn];
  return [
    for (final segment in segments) _speakerOf(segment, named, lagMs),
  ];
}

String? _speakerOf(Segment segment, List<CaptionTurn> turns, int lagMs) {
  if (turns.isEmpty) return null;
  final overlap = <String, int>{};
  for (final turn in turns) {
    final from = math.max(segment.startMs, turn.startMs - lagMs);
    final to = math.min(segment.endMs, turn.endMs - lagMs);
    if (to > from) overlap[turn.speaker] = (overlap[turn.speaker] ?? 0) + (to - from);
  }
  if (overlap.isNotEmpty) {
    // The longest; between equals, the one that spoke first in this segment (the map keeps that order).
    var best = overlap.entries.first;
    for (final entry in overlap.entries) {
      if (entry.value > best.value) best = entry;
    }
    return best.key;
  }
  final middle = (segment.startMs + segment.endMs) ~/ 2;
  CaptionTurn? nearest;
  var distance = nearestMs + 1;
  for (final turn in turns) {
    final from = turn.startMs - lagMs, to = turn.endMs - lagMs;
    final away = middle < from ? from - middle : (middle > to ? middle - to : 0);
    if (away < distance) {
      distance = away;
      nearest = turn;
    }
  }
  return nearest?.speaker;
}

/// The transcript's paragraphs from Whisper's [segments] and each one's speaker (see the header).
List<String> speakerParagraphs(List<Segment> segments, List<String?> speakers) {
  final out = <String>[];
  String? current;
  var words = <String>[];
  var open = false;
  void flush() {
    if (!open) return;
    final text = words.join(' ').trim();
    if (text.isNotEmpty) out.add(current == null ? text : '**$current:** $text');
    words = <String>[];
    open = false;
  }

  for (final (i, segment) in segments.indexed) {
    final text = segment.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    final speaker = i < speakers.length ? speakers[i] : null;
    if (!open || speaker != current) {
      flush();
      current = speaker;
      open = true;
    }
    words.add(text);
  }
  flush();
  return out;
}

/// The transcript's paragraphs from the captions alone: each turn, `**Name:** words`.
List<String> captionParagraphs(List<CaptionTurn> turns) => [
      for (final turn in turns)
        if (turn.text.trim().isNotEmpty) turn.speaker.isEmpty ? turn.text.trim() : '**${turn.speaker}:** ${turn.text.trim()}',
    ];

/// The section the captions are kept in until the write-up (see the header): heading and all.
String captionsSection(List<CaptionTurn> turns) {
  final paragraphs = [
    for (final turn in turns)
      if (turn.text.trim().isNotEmpty) turn.speaker.isEmpty ? '(${counter(turn.startMs)}) ${turn.text.trim()}' : '**${turn.speaker} (${counter(turn.startMs)}):** ${turn.text.trim()}',
  ];
  return paragraphs.isEmpty ? captionsHeading : '$captionsHeading\n\n${paragraphs.join('\n\n')}';
}

final RegExp _named = RegExp(r'^\*\*(.+?) \((\d+(?::\d{2}){1,2})\):\*\*\s*(.*)$');
final RegExp _unnamed = RegExp(r'^\((\d+(?::\d{2}){1,2})\)\s*(.*)$');

int _ms(String clock) {
  var total = 0;
  for (final part in clock.split(':')) {
    total = total * 60 + int.parse(part);
  }
  return total * 1000;
}

/// The turns a note's `## Captions` section keeps ([captionsSection]), read back; empty where it has none. A
/// paragraph that is not a turn is taken as more words of the turn before it.
List<CaptionTurn> turnsOf(String body) {
  final section = sectionOf(body, captionsHeading);
  if (section == null) return const [];
  final read = <({String speaker, int start, String text})>[];
  for (final paragraph in section.split(RegExp(r'\n\s*\n'))) {
    final line = paragraph.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.isEmpty) continue;
    final named = _named.firstMatch(line);
    final unnamed = named == null ? _unnamed.firstMatch(line) : null;
    if (named != null) {
      read.add((speaker: _name(named.group(1)!), start: _ms(named.group(2)!), text: named.group(3)!.trim()));
    } else if (unnamed != null) {
      read.add((speaker: '', start: _ms(unnamed.group(1)!), text: unnamed.group(2)!.trim()));
    } else if (read.isNotEmpty) {
      final last = read.removeLast();
      read.add((speaker: last.speaker, start: last.start, text: '${last.text} $line'.trim()));
    }
  }
  return [
    for (final (i, turn) in read.indexed)
      CaptionTurn(speaker: turn.speaker, startMs: turn.start, endMs: i + 1 < read.length ? math.max(turn.start, read[i + 1].start) : turn.start + _guessMs(turn.text), text: turn.text),
  ];
}

/// The words under a level-2 [heading] in [body], up to the next level-2 heading or the end; null where there is no
/// such heading.
String? sectionOf(String body, String heading) {
  final lines = body.split('\n');
  final at = lines.indexWhere((line) => line.trimRight() == heading);
  if (at < 0) return null;
  final out = <String>[];
  for (final line in lines.skip(at + 1)) {
    if (line.startsWith('## ')) break;
    out.add(line);
  }
  return out.join('\n').trim();
}

/// [body] without the level-2 section under [heading], blank lines around where it was made one.
String withoutSection(String body, String heading) {
  final lines = body.split('\n');
  final at = lines.indexWhere((line) => line.trimRight() == heading);
  if (at < 0) return body;
  var end = at + 1;
  while (end < lines.length && !lines[end].startsWith('## ')) {
    end += 1;
  }
  final before = lines.sublist(0, at).join('\n').trimRight();
  final after = lines.sublist(end).join('\n').trimLeft();
  if (before.isEmpty) return after;
  if (after.isEmpty) return '$before\n';
  return '$before\n\n$after';
}
