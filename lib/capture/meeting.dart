/// A meeting: a recording made with the dictation features off and written up afterwards. A port of
/// `src/app/capture/meeting.ts`.
///
/// Where one can be recorded, and how its note is named, are decided here once. On the Mac the recorder itself
/// records it: its window keeps running behind other apps and its memory is not a phone's. On Android a foreground
/// service records it, with the screen off and the app left (meeting_live.dart), and that service arrived with
/// native generation 20, so the gate is the binary's generation. Never where there is no native core, whose engine
/// keeps no audio, and never on iOS, which has no whisper and no model.
///
/// The title is the date and the time, "Meeting, 26 Sep 14:05", in the locale's own order of day and month
/// (core/summary_text.dart `dateTitled` knows the shape, and swaps it for the model's heading once the summary
/// comes). The body a meeting is written with is its title and its transcript under a `## Transcript` heading, no
/// cues and no title from the first sentence (markdown.dart `renderTranscript`); Rust's write-up writes the same
/// shape from the phone's own transcription, so a note reads the same whichever side wrote it.
///
/// What differs:
/// - `canRecordMeeting` reads its platform from modules on the web (`core/tauri.ts`, `core/platform.ts`,
///   `core/nativeGeneration.ts`); here they are its named parameters.
/// - `meetingTitle` asks `Intl.DateTimeFormat` on the web, which knows every locale. This app has no such table
///   (and takes no package for one), so the title is written for the three locales the web's own tests pin - en-GB,
///   en-US and de-DE, each month as that locale shortens it - and for any other, or none, as en-GB writes it: the
///   day, then the month in English, which is how the rest of this app writes a date (lib/core/note_names.dart).
///   The time is the device's own clock, 24-hour, as on the web.
library;

import 'markdown.dart' show Segment, renderTranscript;

/// The binary generation with the meeting service, its host bridge and the write-up commands (`MEETING_GENERATION`).
const int meetingGeneration = 20;

/// Said when something that would end the recording is asked for while a meeting records: a reset, an update's
/// install (`STOP_THE_MEETING`).
const String stopTheMeeting = 'Stop the meeting first.';

/// Whether a meeting can be recorded here: the Mac, and Android from generation 20.
///
/// [native] is the web's `isTauri()`; [isIOS], [isAndroid] and [isMobile] are `core/platform.ts`'s; and
/// [hasNativeGeneration] is `core/nativeGeneration.ts`'s.
Future<bool> canRecordMeeting({
  required bool native,
  required bool isIOS,
  required bool isAndroid,
  required bool isMobile,
  required Future<bool> Function(int wanted) hasNativeGeneration,
}) async {
  if (!native || isIOS) return false;
  if (isAndroid) return hasNativeGeneration(meetingGeneration);
  return !isMobile;
}

/// A locale's short months, and whether it says the month before the day.
const Map<String, ({bool monthFirst, List<String> months})> _locales = {
  'en-GB': (monthFirst: false, months: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec']),
  'en-US': (monthFirst: true, months: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']),
  'de-DE': (monthFirst: false, months: ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', 'Juli', 'Aug.', 'Sept.', 'Okt.', 'Nov.', 'Dez.']),
};

String _two(int n) => n.toString().padLeft(2, '0');

/// "Meeting, 26 Sep 14:05": the day and the month in the locale's own order, then the time on a 24-hour clock. The
/// locale's literals between the day and the month (de-DE's "." after the day) are dropped, so the title is always
/// the day, a space, the month, whichever comes first; a locale's own month abbreviation is kept as it is ("Sept.").
String meetingTitle(int ms, [String? locale]) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  final words = _locales[locale] ?? _locales['en-GB']!;
  final month = words.months[date.month - 1];
  final day = words.monthFirst ? '$month ${date.day}' : '${date.day} $month';
  final time = '${_two(date.hour)}:${_two(date.minute)}';
  return 'Meeting, $day $time';
}

/// The body a meeting note is made with: its date title over its transcript.
String meetingBody(String title, List<Segment> segments, [String partial = '']) => '# $title\n\n${renderTranscript(segments, partial)}';
