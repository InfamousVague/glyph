/// The note a meeting Ghost was in becomes (docs/MEET.md, "On the device"): the pure half, with nothing here that
/// calls anything.
///
/// Filed on a device that will write it up (it kept the sound, and has the write-up):
///
/// ```markdown
/// # Launch sync
///
/// Ghost was in this meeting on 18 Oct, 14:00 to 14:45.
///
/// ## Captions
///
/// **Sam Lee (0:04):** Good morning everyone. Let's start with the launch checklist.
///
/// **Daniel (0:15):** Thanks. The pricing page is drafted.
/// ```
///
/// The captions are kept under `## Captions` and not `## Transcript` because the write-up (tauri/src-tauri/src/
/// write_up.rs `kept_transcript`) takes words already under `## Transcript` as the transcript a person corrected, and
/// would summarise them instead of listening to the recording. The write-up appends `## Transcript` with Whisper's
/// words, and [withSpeakers] then names who said each part from the captions and drops `## Captions`:
///
/// ```markdown
/// ## Transcript
///
/// **Sam Lee (0:04):** Good morning everyone. Let's start with the launch checklist.
/// ```
///
/// Each part says when its first phrase began, as the captions did (Matt, 2026-10-26: "Also after some time all the
/// speaker labels disappeared"): the transcript's view shows Whisper's phrases, which carry no names, and names them
/// again from these (speakers.dart `phraseSpeakers`) on every device, long after the captions have gone.
///
/// Filed where nothing will write it up (no sound came, the sound could not be kept here, or the device has no
/// write-up: an iPhone), the captions are the transcript at once, in turns, `**Name (0:04):** words` (a long one cut
/// about a minute apart, speakers.dart `captionTurnLines`), and the first line says so.
///
/// The title is the invite's; with none, the date's, as a meeting recorded on the device is named
/// (lib/capture/meeting.dart `meetingTitle`). A note's id is made from the take's ([meetNoteId]), as a mail's is
/// from the mail's, so a pass cut short, or two devices at once, file one note and not two.
library;

import 'dart:typed_data';

import '../capture/meeting.dart' show meetingTitle;
import '../core/bytes.dart';
import '../core/library.dart' show transcriptOf, withTranscript;
import '../core/locale_dates.dart';
import '../core/note.dart' show Segment;
import '../mail/mail_note.dart' show mailNoteId;
import 'gmt.dart';
import 'speakers.dart';
import '../tapes/tape.dart' show counter;

/// The id of the note take [takeId] becomes: a UUID made from the take's id, never the one a mail with the same id
/// would make.
String meetNoteId(String takeId) {
  try {
    final bytes = fromBase64Url(takeId);
    if (bytes.length == 16) {
      final turned = Uint8List.fromList(bytes);
      turned[0] ^= 0x6d;
      turned[1] ^= 0x74;
      return mailNoteId(toBase64Url(turned));
    }
  } catch (_) {
    // Not the service's shape: made from its words below.
  }
  return mailNoteId('meet:$takeId');
}

/// The note's title: the invite's, or the date's.
String meetTitle(OpenedTake take, {required int now}) {
  final title = take.title.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (title.isNotEmpty) return title;
  return meetingTitle(take.startedAt > 0 ? take.startedAt : now);
}

String _two(int n) => n.toString().padLeft(2, '0');
String _clock(DateTime at) => '${_two(at.hour)}:${_two(at.minute)}';

/// How [ghostLine] starts: the words that tell a note Ghost filed from one a person recorded (meet_in.dart
/// `meetingNoteFor`).
const String ghostLineStart = 'Ghost was in this meeting on ';

/// "Ghost was in this meeting on 18 Oct, 14:00 to 14:45." in the device's own order of day and month.
String ghostLine(OpenedTake take, {required int now}) {
  final start = DateTime.fromMillisecondsSinceEpoch(take.startedAt > 0 ? take.startedAt : now);
  final day = localeDayMonth(start, DateForm.MMMd);
  if (take.endedAt <= take.startedAt || take.startedAt <= 0) return '$ghostLineStart$day, from ${_clock(start)}.';
  final end = DateTime.fromMillisecondsSinceEpoch(take.endedAt);
  return '$ghostLineStart$day, ${_clock(start)} to ${_clock(end)}.';
}

/// Why a note was filed from the captions alone, as its first line says it after [ghostLine].
enum CaptionsOnly {
  /// The take had no sound in it.
  noSound,

  /// This device could not keep the sound (an iPhone, or a sound it could not read).
  notKept,
}

/// The note [take] becomes (see the header). With [writeUp] the captions wait under `## Captions` for the write-up;
/// without it they are the transcript, and [why] says why in the note's words.
String meetNoteBody(OpenedTake take, {required int now, required bool writeUp, CaptionsOnly why = CaptionsOnly.notKept}) {
  final turns = captionTurns(take.captions);
  final out = StringBuffer('# ${meetTitle(take, now: now)}\n\n${ghostLine(take, now: now)}');
  if (writeUp) {
    out.write(' It is being written up on your device.\n');
    if (turns.isNotEmpty) out.write('\n${captionsSection(turns)}\n');
    return out.toString();
  }
  // A Discord call has no captions to be a transcript: who spoke when is all its lines say (docs/DISCORD_CALLS.md).
  if (take.service == MeetService.discord) {
    out.write(switch (why) {
      CaptionsOnly.noSound => ' No sound came with it, and Discord shows no captions.\n',
      CaptionsOnly.notKept => ' The recording could not be kept on this device, and Discord shows no captions: who spoke when is below.\n',
    });
    final spoke = [for (final turn in turns) if (turn.speaker.isNotEmpty) '- ${turn.speaker}, ${counter(turn.startMs)}'];
    out.write(spoke.isEmpty ? '\n## Who spoke\n\nNobody was heard.\n' : '\n## Who spoke\n\n${spoke.join('\n')}\n');
    return out.toString();
  }
  // Whose captions: a Zoom's are Zoom's (Matt, 2026-10-26: "also consider zoom meetings").
  final whose = take.service.captions, who = take.service.short;
  out.write(switch (why) {
    CaptionsOnly.noSound => ' No sound came with it, so this is from $whose captions.\n',
    CaptionsOnly.notKept => ' This is from $whose captions: the recording could not be kept on this device.\n',
  });
  // Timed, a turn a paragraph and a long one cut about a minute apart, as every meeting's transcript is (2026-10-30).
  final paragraphs = captionTurnLines(turns);
  out.write(paragraphs.isEmpty ? '\n## Transcript\n\n$who showed no captions.\n' : '\n## Transcript\n\n${paragraphs.join('\n\n')}\n');
  return out.toString();
}

/// The words the first line says while the write-up is to come, taken off once it has.
const String _writingUp = ' It is being written up on your device.';

/// Whether [body]'s first line still says its write-up is to come (taken off by [withSpeakers] once it has).
bool awaitsWriteUp(String body) => body.contains(_writingUp);

/// [body] with Whisper's transcript in turns, each given its speaker from the note's captions, and the captions
/// dropped (see the header); null while there is nothing to do yet (no transcript from the write-up, or no words
/// heard in it). The first line's "being written up" is taken off (2026-10-19: it stayed under a finished write-up).
///
/// Every way out writes turns, each timed (Matt, 2026-10-30: "some of the meeting transcripts still go into one
/// giant block instead of maintaining the name (timestamp): prefix on each line"; speakers.dart `turnsTranscript`).
/// This used to give up in two places and leave the write-up's words as it wrote them, which for a meeting was one
/// paragraph (its paragraphs broke only at a silence of a second and a half, and Whisper's phrases over a call's
/// sound abut): with no phrases to name it dropped the captions and kept that block, and with no captions it took the
/// line off and kept it too. Now, with no phrases, the captions' own turns are the transcript, names and times; with
/// no captions, a transcript not already in turns is written in turns from its phrases, named by nobody (or by the
/// transcript's own names, where it has them); and with captions that meet none of the phrases, the captions' turns.
/// A transcript already in turns, with no captions to name it better, is left as it is.
String? withSpeakers(String body, List<Segment> segments) {
  if (transcriptOf(body) == null || (sectionOf(body, '## Transcript') ?? '').isEmpty) return null;
  final captions = sectionOf(body, captionsHeading) != null;
  final out = (captions ? withoutSection(body, captionsHeading) : body).replaceFirst(_writingUp, '');
  if (!captions && transcriptTimed(body)) return out;
  final transcript = turnsTranscript(segments, body);
  if (transcript == null) return out;
  final written = withTranscript(out, transcript);
  return written.endsWith('\n') ? written : '$written\n';
}

/// A meeting's transcript made again in turns from what the note keeps (Rebuild transcript, on its tape; Matt,
/// 2026-10-30): its phrases, named from its captions where it still keeps them, else from [captions] (the newest
/// captions its versions kept, for a meeting whose captions went before this was mended), else as its transcript
/// names them. Nothing is heard again, and nothing above `## Transcript` moves (the summary, the meeting's line, the
/// person's words), so it is one edit of the transcript's lines. Null where there is nothing to make it from: no
/// phrases kept and no captions.
String? rebuiltTranscript(String body, List<Segment> segments, {List<CaptionTurn>? captions}) {
  final kept = turnsOf(body);
  final named = kept.any((turn) => turn.speaker.isNotEmpty) ? kept : (captions != null && captions.any((turn) => turn.speaker.isNotEmpty) ? captions : null);
  return turnsTranscript(segments, body, captions: named);
}

/// The newest captions a note's versions kept ([versions], newest last, each a whole text the note once had), for
/// [rebuiltTranscript]; null where none of them kept any with a name.
List<CaptionTurn>? captionsOfVersions(List<String> versions) {
  for (final text in versions.reversed) {
    final turns = turnsOf(text);
    if (turns.any((turn) => turn.speaker.isNotEmpty && turn.text.trim().isNotEmpty)) return turns;
  }
  return null;
}
