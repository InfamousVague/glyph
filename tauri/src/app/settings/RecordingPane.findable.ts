import type { SettingsFindable } from './settingsSearch.ts';

/**
 * What Settings' search finds on Recording (settings/RecordingPane.tsx), by the names the page draws, in its order.
 * The model moved to its own AI section (AiPane.findable.ts; Matt: "move the Model sections into an AI setting
 * section"), so its words are no longer here.
 *
 * Android's rows are listed on Android only: the meetings, which the page draws only on a binary with the meeting
 * service (native generation 20) but the search lists on an older one too, where it opens the page. The tapes and the
 * meetings are the app's (`app`): a browser on an Android phone has no file and no meeting service. "The side key", the
 * card where the recorder's rings were placed, went on 2026-10-02 (docs/DESIGN.md §173). A meeting's own sound is on
 * both: "Include sound from other apps" in Android's Meetings card, "Record the computer's sound too" in the Mac's.
 */
export function findable({ android, app }: { android: boolean; app: boolean }): SettingsFindable[] {
  return [
    { name: 'Stop when I go quiet', words: 'silence auto stop' },
    { name: 'Review after recording', words: 'check transcript' },
    { name: 'Better words', words: 'refine clean up transcript' },
    { name: 'Summaries', words: 'summary meeting write-up minutes long voice notes' },
    ...(android && app
      ? [
          { name: 'Include sound from other apps', words: 'system audio media games screen share meeting record' },
          { name: 'Tell me when a meeting is written up', words: 'notification notify alert written up' },
          { name: 'Write up straight away', words: 'meeting battery charging background' },
        ]
      : []),
    // The Mac's own Meetings card: one switch, for the computer's sound (native generation 25).
    ...(app && !android ? [{ name: "Record the computer's sound too", words: 'system audio meeting call both sides zoom' }] : []),
    ...(app
      ? [
          { name: 'Tapes', words: 'your tapes storage audio remove space' },
          { name: 'Remove audio older than a month', words: 'storage space delete recordings audio' },
        ]
      : []),
  ];
}
