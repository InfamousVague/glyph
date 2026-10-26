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
/// - **The written-up transcript keeps its times too** (Matt, 2026-10-26: "Also after some time all the speaker
///   labels disappeared"): the paragraphs `withSpeakers` leaves (meet_note.dart) are `**Name (0:12):** words`, each
///   with when its first phrase began ([speakerParagraphs] `timed`), so the names, and the moments they spoke at,
///   travel with the note to every device and outlive the captions, which the write-up drops. The transcript's view
///   shows Whisper's timed phrases once they have come, and a phrase carries no speaker: [phraseSpeakers] gives each
///   one its name back from the note's words - the captions while they are kept, else the transcript's timed
///   paragraphs, else, for a meeting written up before the times were kept (`**Name:** words`), the paragraphs matched
///   to the phrases by where their words fall. A recording made on the device has no captions and no names, and its
///   phrases stay unnamed.
/// - **A Discord call's turns have no words** (docs/DISCORD_CALLS.md): a line a turn, the speaker and when, and no
///   text (gmt.dart). They are turns all the same: kept under `## Captions` as `**Name (0:12):**` with nothing after
///   ([captionsSection]), read back by [turnsOf], and every phrase named from them; with no words they make no
///   paragraphs of a transcript of their own ([captionParagraphs]).
/// - **Meet's icons are no names** ([captionIcons]; Matt's engineering standup, 2026-10-26, had a speaker called
///   `groups`): Meet draws its icons from Material Symbols, whose glyph is drawn from a word, so a caption block read
///   as text can start with one where the speaker's name should be. The bot drops them as it reads the page
///   (meet/bot/lib/captions.mjs `parseBlock`); a name kept before it did is read here as no name, rather than as a
///   person called "groups".
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

/// The Material Symbols words Meet draws icons with inside its captions, which a block read as text can begin with
/// (see the header): never a speaker's name. Lower case, as a ligature is written; a person's name is not, so only
/// the word exactly is taken.
const Set<String> captionIcons = {
  'groups',
  'group',
  'group_add',
  'person',
  'people',
  'account_circle',
  'meeting_room',
  'devices',
  'co_present',
  'present_to_all',
  'frame_person',
  'mic',
  'mic_off',
  'keep',
  'keep_off',
  'push_pin',
  'more_vert',
  'more_horiz',
  'closed_caption',
  'arrow_downward',
};

/// A name as a note writes it: no asterisks, no brackets, no colon at its end, one space between words; and none at
/// all for one of Meet's icons ([captionIcons]).
String _name(String speaker) {
  final name = speaker.replaceAll(RegExp(r'[*\[\]()]'), '').replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r':+$'), '');
  return captionIcons.contains(name) ? '' : name;
}

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

/// The transcript's paragraphs from Whisper's [segments] and each one's speaker (see the header). With [timed], each
/// paragraph says when its first phrase began, `**Sam Lee (0:12):** words`, and one with no speaker `(0:40) words`:
/// the shape the captions are kept in ([captionsSection]), which the transcript's view lights by.
List<String> speakerParagraphs(List<Segment> segments, List<String?> speakers, {bool timed = false}) {
  final out = <String>[];
  String? current;
  var words = <String>[];
  var startMs = 0;
  var open = false;
  void flush() {
    if (!open) return;
    final text = words.join(' ').trim();
    if (text.isNotEmpty) {
      final at = counter(startMs);
      final name = current;
      out.add(name == null ? (timed ? '($at) $text' : text) : (timed ? '**$name ($at):** $text' : '**$name:** $text'));
    }
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
      startMs = segment.startMs;
      open = true;
    }
    words.add(text);
  }
  flush();
  return out;
}

/// One paragraph of a meeting's written transcript, as [transcriptParagraphs] reads it: who spoke (null for nobody
/// named, or one of Meet's icons), when it began where it says so (`**Sam Lee (0:12):**`, `(0:12)`), and how many
/// words it has past the name.
typedef WrittenTurn = ({String? speaker, int? startMs, int words});

final RegExp _writtenTimed = RegExp(r'^\*\*(.+?) \((\d+(?::\d{2}){1,2})\):\*\*\s*(.*)$', dotAll: true);
final RegExp _writtenBare = RegExp(r'^\((\d+(?::\d{2}){1,2})\)\s*(.*)$', dotAll: true);
final RegExp _writtenNamed = RegExp(r'^\*\*([^*\n]+?):\*\*\s*(.*)$', dotAll: true);

int _wordsIn(String text) => text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;

String? _nameOrNone(String raw) {
  final name = _name(raw);
  return name.isEmpty ? null : name;
}

/// The paragraphs of [body]'s `## Transcript`, each with its speaker and time where it says them (see the header);
/// empty where it has none.
List<WrittenTurn> transcriptParagraphs(String body) {
  final section = sectionOf(body, '## Transcript');
  if (section == null) return const [];
  final out = <WrittenTurn>[];
  for (final paragraph in section.split(RegExp(r'\n\s*\n'))) {
    final line = paragraph.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.isEmpty) continue;
    if (_writtenTimed.firstMatch(line) case final m?) {
      out.add((speaker: _nameOrNone(m.group(1)!), startMs: _ms(m.group(2)!), words: _wordsIn(m.group(3)!)));
    } else if (_writtenBare.firstMatch(line) case final m?) {
      out.add((speaker: null, startMs: _ms(m.group(1)!), words: _wordsIn(m.group(2)!)));
    } else if (_writtenNamed.firstMatch(line) case final m?) {
      out.add((speaker: _nameOrNone(m.group(1)!), startMs: null, words: _wordsIn(m.group(2)!)));
    } else {
      out.add((speaker: null, startMs: null, words: _wordsIn(line)));
    }
  }
  return out;
}

/// How far a phrase may begin before the time the paragraph it opens was written with and still be that
/// paragraph's, in ms: the times are written to the second, cut down.
const int _writtenSlackMs = 999;

/// The speaker of each of [segments] as [body] names them (see the header): by the captions while the note keeps
/// them ([alignSpeakers]); else by the transcript's timed paragraphs, each phrase the speaker of the last paragraph
/// begun by its start (a paragraph with no time after a timed one is more words of it); else by the named paragraphs
/// of a transcript written with no times, each phrase the speaker of the paragraph its middle word falls in, the
/// words counted through both as a share of each whole, so a transcript written from these very phrases matches them
/// exactly and one corrected by hand nearly. All null where the note names nobody: a recording made on the device.
List<String?> phraseSpeakers(List<Segment> segments, String body) {
  final none = List<String?>.filled(segments.length, null);
  if (segments.isEmpty) return none;
  final turns = turnsOf(body);
  if (turns.any((turn) => turn.speaker.isNotEmpty)) return alignSpeakers(segments, turns);
  final written = transcriptParagraphs(body);
  if (!written.any((p) => p.speaker != null)) return none;
  if (written.first.startMs != null) {
    final starts = [
      for (final p in written)
        if (p.startMs case final at?) (at: at, speaker: p.speaker),
    ];
    return [
      for (final segment in segments)
        () {
          String? speaker;
          for (final s in starts) {
            if (s.at > segment.startMs + _writtenSlackMs) break;
            speaker = s.speaker;
          }
          return speaker;
        }(),
    ];
  }
  final paragraphWords = written.fold<int>(0, (sum, p) => sum + p.words);
  final segmentWords = segments.fold<int>(0, (sum, s) => sum + _wordsIn(s.text));
  if (paragraphWords == 0 || segmentWords == 0) return none;
  final ends = <double>[];
  var counted = 0;
  for (final p in written) {
    counted += p.words;
    ends.add(counted / paragraphWords);
  }
  var before = 0;
  return [
    for (final segment in segments)
      () {
        final words = _wordsIn(segment.text);
        final middle = (before + words / 2) / segmentWords;
        before += words;
        var at = 0;
        while (at < ends.length - 1 && middle >= ends[at]) {
          at += 1;
        }
        return written[at].speaker;
      }(),
  ];
}

/// [segments] as a meeting's transcript, `## Transcript` and its paragraphs, each named and timed where [body] names
/// its speakers ([phraseSpeakers]): what a write-up that writes the transcript again from its phrases leaves, so
/// the names the captions gave are not lost to it. Null where [body] names nobody, for the caller's own shape.
String? namedTranscript(List<Segment> segments, String body) {
  final speakers = phraseSpeakers(segments, body);
  if (!speakers.any((s) => s != null)) return null;
  final paragraphs = speakerParagraphs(segments, speakers, timed: true);
  return paragraphs.isEmpty ? null : '## Transcript\n\n${paragraphs.join('\n\n')}';
}

/// The transcript's paragraphs from the captions alone: each turn, `**Name:** words`.
List<String> captionParagraphs(List<CaptionTurn> turns) => [
      for (final turn in turns)
        if (turn.text.trim().isNotEmpty) turn.speaker.isEmpty ? turn.text.trim() : '**${turn.speaker}:** ${turn.text.trim()}',
    ];

/// The section the captions are kept in until the write-up (see the header): heading and all. A named turn with no
/// words (a Discord call's) is kept as its name and time alone, `**Sam Lee (0:12):**`; an unnamed one with none is
/// nothing.
String captionsSection(List<CaptionTurn> turns) {
  final paragraphs = [
    for (final turn in turns)
      if (turn.text.trim().isNotEmpty)
        turn.speaker.isEmpty ? '(${counter(turn.startMs)}) ${turn.text.trim()}' : '**${turn.speaker} (${counter(turn.startMs)}):** ${turn.text.trim()}'
      else if (turn.speaker.isNotEmpty)
        '**${turn.speaker} (${counter(turn.startMs)}):**',
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
