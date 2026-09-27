import { hasNativeGeneration } from '../core/nativeGeneration.ts';
import { isAndroid, isIOS, isMobile } from '../core/platform.ts';
import { isTauri } from '../core/tauri.ts';
import { renderTranscript, type Segment } from './markdown.ts';

/**
 * A meeting: a recording made with the dictation features off and written up afterwards (docs/DESIGN.md §127
 * section 3; Matt: "I'm going to start recording meetings and stuff and letting the audio be transcribed then
 * summarized by AI so I get summarized recording notes automatically via a background task").
 *
 * Where one can be recorded, and how its note is named, are decided here once. On the Mac the page recorder records
 * it (capture/CaptureScreen.tsx `meeting`): its window keeps running behind other apps and its memory is not a
 * phone's. On Android a foreground service records it, with the screen off and the app left (capture/MeetingScreen.tsx,
 * capture/meetingLive.ts), and that service arrived with native generation 20, so the gate is the binary's generation
 * (core/nativeGeneration.ts). Never in a browser, whose engine keeps no audio, and never on iOS, which has no whisper
 * and no model.
 *
 * The title is the date and the time, "Meeting, 26 Sep 14:05", in the device's own order of day and month
 * (ai/summaryText.ts `dateTitled` knows the shape, and swaps it for the model's heading once the summary comes). The
 * body a meeting is written with is its title and its transcript under a `## Transcript` heading, no cues and no
 * title from the first sentence (capture/markdown.ts `renderTranscript`); Rust's write-up writes the same shape from
 * the phone's own transcription (src-tauri/src/transcript.rs), so a note reads the same whichever side wrote it.
 */

/** The binary generation with the meeting service, its host bridge and the write-up commands. */
export const MEETING_GENERATION = 20;

/** Whether a meeting can be recorded here: the Mac, and Android from generation 20. */
export async function canRecordMeeting(): Promise<boolean> {
  if (!isTauri() || isIOS) return false;
  if (isAndroid) return hasNativeGeneration(MEETING_GENERATION);
  return !isMobile;
}

/**
 * "Meeting, 26 Sep 14:05": the day and the month in the locale's own order, then the time on a 24-hour clock. The
 * locale's literals between the day and the month (de-DE's "." after the day) are dropped, so the title is always
 * the day, a space, the month, whichever comes first; a locale's own month abbreviation is kept as it is ("Sept.").
 */
export function meetingTitle(ms: number, locale?: string): string {
  const date = new Date(ms);
  const parts = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short' }).formatToParts(date);
  const day = parts
    .filter((part) => part.type === 'day' || part.type === 'month')
    .map((part) => part.value)
    .join(' ');
  const time = new Intl.DateTimeFormat(locale, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(date);
  return `Meeting, ${day} ${time}`;
}

/** The body a meeting note is made with: its date title over its transcript. */
export function meetingBody(title: string, segments: readonly Segment[], partial = ''): string {
  return `# ${title}\n\n${renderTranscript(segments, partial)}`;
}
