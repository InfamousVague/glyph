/// A meeting's words while it is still going on (Matt, 2026-10-30: "If possible add real time transcriptions for
/// meetings"; docs/MEET.md, "Live captions" and "Live words on this device"): the one store both ways in fill, read by
/// the meeting's note's Transcript view (lib/meet/ui/live_transcript_view.dart) and the phone's meeting screen.
///
/// - **Ghost in a Meet or a Zoom** (lib/meet/live_captions.dart): the captions the bot reads, sealed to the account and
///   passed on as they come, each line named and timed by the captions themselves; with the line being said.
/// - **A meeting recorded on this device** (lib/capture/meeting_live_words.dart): the phone's own recogniser beside the
///   meeting service's recording, phrase by phrase, named by nobody (the final write-up names nobody either where it
///   cannot), and only while the screen is on.
///
/// What it is not: the meeting's words. Those are the take's, filed in one edit when the meeting ends (meet_in.dart
/// `syncMeet`), or the write-up's, which replace the live words as they always replaced the captions. So the live
/// words are kept in memory alone and never written into the note as they come, and the note's text is not touched
/// on every caption. Not in batches either: a note's lines changed on two of the account's devices at once are a
/// conflict to sync (lib/core/merge_words.dart, two insertions at one place), and every device of the account hears
/// the same captions, so two devices batching the same captions into `## Captions` would make two notes of one
/// meeting; and in a team's note every batch would be an edit sent to every member. The take carries every caption,
/// and a device that comes to the front mid-meeting catches up from the service's sealed frames (GET meet/{id}/live).
///
/// A meeting Ghost is in has a note from its first caption on ([liveNoteBody], under [meetLiveNoteId]), so the
/// person can open it, keep their own notes in it while the meeting runs, and read its Transcript live; the take is
/// filed into that note when it comes ([handedOver]), the person's words kept where they wrote them.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../capture/meeting_turns.dart' show transcriptTurns;
import '../core/front_matter.dart' show frontMatterEnd;
import '../core/note.dart' show Segment;
import '../mail/mail_note.dart' show mailNoteId;
import '../tapes/transcript_words.dart' show ShownTurn;
import 'meet_note.dart' show ghostLineStart;

/// Where a meeting's live words come from.
enum LiveFrom {
  /// Ghost's bot, from the meeting's captions: named.
  bot,

  /// This device's recogniser, beside its own recording: named by nobody.
  device,
}

/// One line of a meeting's live words: when it was first heard, in ms since the recording began, who said it (empty
/// for nobody named), and its words.
@immutable
class LiveLine {
  const LiveLine({required this.at, this.speaker = '', required this.text});

  final int at;
  final String speaker;
  final String text;

  @override
  bool operator ==(Object other) => other is LiveLine && other.at == at && other.speaker == speaker && other.text == text;

  @override
  int get hashCode => Object.hash(at, speaker, text);

  @override
  String toString() => 'LiveLine($at, $speaker, $text)';
}

/// The most lines a meeting's live words keep: four hours of a busy meeting's captions. The oldest go past it; the
/// take has them all.
const int liveLinesMost = 6000;

/// One meeting's live words.
@immutable
class LiveTranscript {
  const LiveTranscript({required this.noteId, required this.from, this.lines = const [], this.saying, this.live = true, this.meeting});

  /// The note the meeting is, or will be filed as.
  final String noteId;
  final LiveFrom from;

  /// The finished lines, in the order they were heard.
  final List<LiveLine> lines;

  /// The line being said now, its words not yet finished; null for none.
  final LiveLine? saying;

  /// Still going on; false once the meeting has ended, while its note waits for the take or the write-up.
  final bool live;

  /// The booking the words are of, for Ghost's; null for this device's own.
  final String? meeting;

  /// The words as the meeting's turns (lib/capture/meeting_turns.dart): a turn a speaker's run, a new one after a
  /// pause of three seconds or once one has run a minute, each timed; the line being said ends the last.
  List<ShownTurn> get turns => liveTurns(lines, saying);

  LiveTranscript copyWith({List<LiveLine>? lines, LiveLine? Function()? saying, bool? live}) =>
      LiveTranscript(noteId: noteId, from: from, lines: lines ?? this.lines, saying: saying == null ? this.saying : saying(), live: live ?? this.live, meeting: meeting);
}

/// How long a line is taken to last where the next does not say: a fifteenth of a second a character, a second and a
/// half at least.
int _lasts(String text) => math.max(1500, text.length * 1000 ~/ 15);

/// [lines] and the line being said as the meeting's turns (see [LiveTranscript.turns]).
List<ShownTurn> liveTurns(List<LiveLine> lines, [LiveLine? saying]) {
  final all = [...lines, ?saying];
  final segments = <Segment>[];
  final speakers = <String?>[];
  for (final (i, line) in all.indexed) {
    final next = i + 1 < all.length ? all[i + 1].at : null;
    final end = line.at + _lasts(line.text);
    segments.add(Segment(text: line.text, startMs: line.at, endMs: next == null ? end : math.max(line.at, math.min(end, next))));
    speakers.add(line.speaker.trim().isEmpty ? null : line.speaker.trim());
  }
  return [for (final turn in transcriptTurns(segments, speakers)) (speaker: turn.speaker, startMs: turn.startMs, text: turn.text)];
}

/// Every meeting's live words on this device, by note.
class LiveTranscripts extends ChangeNotifier {
  final Map<String, LiveTranscript> _byNote = {};

  /// Note [noteId]'s live words; null where it has none.
  LiveTranscript? of(String noteId) => _byNote[noteId];

  /// Whether note [noteId]'s meeting is still going on, with words to show.
  bool isLive(String noteId) => _byNote[noteId]?.live ?? false;

  /// The notes with live words, for tests.
  Iterable<String> get notes => _byNote.keys;

  /// [lines] heard for note [noteId], and the line being said now ([saying]; null for none, which clears it). A
  /// meeting heard of for the first time starts here.
  void heard(String noteId, {required LiveFrom from, List<LiveLine> lines = const [], LiveLine? saying, String? meeting}) {
    final was = _byNote[noteId] ?? LiveTranscript(noteId: noteId, from: from, meeting: meeting);
    final kept = [for (final line in lines) if (line.text.trim().isNotEmpty) line];
    if (kept.isEmpty && was.saying == saying && was.live && _byNote.containsKey(noteId)) return;
    var next = kept.isEmpty ? was.lines : [...was.lines, ...kept];
    if (next.length > liveLinesMost) next = next.sublist(next.length - liveLinesMost);
    _byNote[noteId] = LiveTranscript(noteId: noteId, from: was.from, lines: next, saying: saying != null && saying.text.trim().isNotEmpty ? saying : null, meeting: was.meeting ?? meeting);
    notifyListeners();
  }

  /// Note [noteId]'s meeting has ended: its words stay, not live, until the note has its own ([forget]).
  void ended(String noteId) {
    final was = _byNote[noteId];
    if (was == null || !was.live) return;
    _byNote[noteId] = was.copyWith(live: false, saying: () => null);
    notifyListeners();
  }

  /// Note [noteId]'s live words gone: the take or the write-up has given it its own, or it was discarded.
  void forget(String noteId) {
    if (_byNote.remove(noteId) != null) notifyListeners();
  }

  /// Everything gone: signing out.
  void clear() {
    if (_byNote.isEmpty) return;
    _byNote.clear();
    notifyListeners();
  }
}

/// This device's, for the life of the app.
final LiveTranscripts liveTranscripts = LiveTranscripts();

// --- the note a meeting Ghost is in has from its first caption -----------------------------------------------------

/// The id of the note meeting [meeting] has while Ghost is in it, and keeps once its take is filed: a UUID made from
/// the booking's id, so every device of the account makes the same note, and never one a take or a mail would make.
String meetLiveNoteId(String meeting) => mailNoteId('meet-live:$meeting');

/// The line a meeting's note starts with while Ghost is in it, taken off when its take is filed ([handedOver]).
const String liveLine = 'Ghost is in this meeting now. Its transcript comes in as people speak.';

/// The line it has instead when the meeting ended with no take to file (the bot failed, or never said it was over).
const String liveLineNoTake = 'Ghost was in this meeting, but its recording didn’t reach Ghost.md.';

/// The note a meeting Ghost is in starts as: its title and [liveLine]. The same words on every device, so two of the
/// account's devices that make it at once make one note: no date, no time, nothing the device's own clock or language
/// would say differently.
String liveNoteBody(String? title) {
  final named = (title ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return '# ${named.isEmpty ? 'A meeting' : named}\n\n$liveLine\n';
}

/// Whether [body] is a meeting's note while Ghost is still in it, its take not yet filed.
bool isLiveNote(String body) => body.contains(liveLine);

/// The words the person wrote in a meeting's note while it ran: everything but its title, its live line and any
/// level-2 sections (the transcript's places).
String personsWords(String live) {
  final lines = live.split('\n');
  final out = <String>[];
  var skipping = false;
  // The note's front matter (its `meeting:` mark, lib/meet/meeting_mark.dart) is the note's, not the person's words,
  // and the title is the first line after it.
  final front = frontMatterEnd(lines);
  for (final (i, line) in lines.indexed) {
    if (i < front) continue;
    if (i == front && line.startsWith('# ')) continue;
    if (line.trim() == liveLine || line.trim() == liveLineNoTake) continue;
    if (line.startsWith('## ')) {
      skipping = line.trimRight() == '## Captions' || line.trimRight() == '## Transcript';
      if (skipping) continue;
    }
    if (!skipping) out.add(line);
  }
  return out.join('\n').trim();
}

/// The note a meeting's take is filed as, [filed] (meet_note.dart `meetNoteBody`), put into the note it had while
/// Ghost was in it, [live]: the take's title and line, the person's own words where they were (under the line), then
/// the take's sections. One edit of the note.
String handedOver(String live, String filed) {
  final words = personsWords(live);
  if (words.isEmpty) return filed;
  final at = RegExp(r'^## ', multiLine: true).firstMatch(filed)?.start;
  final head = (at == null ? filed : filed.substring(0, at)).trimRight();
  final rest = at == null ? '' : filed.substring(at);
  return rest.isEmpty ? '$head\n\n$words\n' : '$head\n\n$words\n\n$rest';
}

/// [live] with its line saying no take came ([liveLineNoTake]): the same words on every device, so it is one change
/// however many make it.
String withoutTake(String live) => live.replaceFirst(liveLine, liveLineNoTake);

/// Whether [body] is a meeting Ghost was in: its live line, the line after, or the line a take is filed with.
bool ghostsMeeting(String body) => body.contains(liveLine) || body.contains(liveLineNoTake) || body.contains(ghostLineStart);
