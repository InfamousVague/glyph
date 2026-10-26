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
/// write-up: an iPhone), the captions are the transcript at once, in the `**Name:** words` shape, and the first
/// line says so.
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
  // Whose captions: a Zoom's are Zoom's (Matt, 2026-10-26: "also consider zoom meetings").
  final whose = take.service.captions, who = take.service.short;
  out.write(switch (why) {
    CaptionsOnly.noSound => ' No sound came with it, so this is from $whose captions.\n',
    CaptionsOnly.notKept => ' This is from $whose captions: the recording could not be kept on this device.\n',
  });
  final paragraphs = captionParagraphs(turns);
  out.write(paragraphs.isEmpty ? '\n## Transcript\n\n$who showed no captions.\n' : '\n## Transcript\n\n${paragraphs.join('\n\n')}\n');
  return out.toString();
}

/// The words the first line says while the write-up is to come, taken off once it has.
const String _writingUp = ' It is being written up on your device.';

/// Whether [body]'s first line still says its write-up is to come (taken off by [withSpeakers] once it has).
bool awaitsWriteUp(String body) => body.contains(_writingUp);

/// [body] with each part of Whisper's transcript given its speaker from the note's captions, and the captions
/// dropped (see the header); null while there is nothing to do yet (no transcript from the write-up, or no words
/// heard in it). With no captions kept there is no one to name: once the transcript has come, only the first line's
/// "being written up" is taken off (2026-10-19: it stayed under a finished write-up), and a note without it comes back
/// as it is.
String? withSpeakers(String body, List<Segment> segments) {
  if (transcriptOf(body) == null || (sectionOf(body, '## Transcript') ?? '').isEmpty) return null;
  if (sectionOf(body, captionsHeading) == null) return body.replaceFirst(_writingUp, '');
  final turns = turnsOf(body);
  var out = withoutSection(body, captionsHeading).replaceFirst(_writingUp, '');
  if (segments.isEmpty || turns.isEmpty) return out;
  final paragraphs = speakerParagraphs(segments, alignSpeakers(segments, turns), timed: true);
  if (paragraphs.isEmpty) return out;
  out = withTranscript(out, '## Transcript\n\n${paragraphs.join('\n\n')}');
  return out.endsWith('\n') ? out : '$out\n';
}
