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
/// - `meetingTitle` asks `Intl.DateTimeFormat` on the web, which knows every locale. This app has the page's own
///   answers for en-US and en-GB (lib/core/locale_dates.dart) and takes no package for more, so a title with no
///   locale named is in the phone's own order once the phone has said which of the two it reads ("Sep 26", "26
///   Sept"), and as en-GB writes it until then. A locale named is one of the three the web's own tests pin, en-GB,
///   en-US and de-DE, each month as that locale shortens it, and any other is en-GB's. The time is the device's own
///   clock, 24-hour, as on the web.
library;

import '../core/locale_dates.dart';
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

/// de-DE's short months, the day before them: the one locale the web's tests pin that the app's own tables
/// (lib/core/locale_dates.dart) have not got.
const List<String> _germanMonths = ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', 'Juli', 'Aug.', 'Sept.', 'Okt.', 'Nov.', 'Dez.'];

String _two(int n) => n.toString().padLeft(2, '0');

/// "Meeting, 26 Sep 14:05": the day and the month in the locale's own order, then the time on a 24-hour clock. The
/// locale's literals between the day and the month (de-DE's "." after the day) are dropped, so the title is always
/// the day, a space, the month, whichever comes first; a locale's own month abbreviation is kept as it is ("Sept.").
String meetingTitle(int ms, [String? locale]) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  final day = switch (locale) {
    // The phone's own order, and en-GB's until the phone has said.
    null => localeDayMonth(date, DateForm.MMMd),
    'en-US' => localeDayMonth(date, DateForm.MMMd, DateLocale.enUS),
    'de-DE' => '${date.day} ${_germanMonths[date.month - 1]}',
    _ => localeDayMonth(date, DateForm.MMMd, DateLocale.enGB),
  };
  final time = '${_two(date.hour)}:${_two(date.minute)}';
  return 'Meeting, $day $time';
}

/// The body a meeting note is made with: its date title over its transcript.
String meetingBody(String title, List<Segment> segments, [String partial = '']) => '# $title\n\n${renderTranscript(segments, partial)}';
