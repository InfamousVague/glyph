import type { SettingsFindable } from './settingsSearch.ts';

/**
 * What Settings' search finds on Recording (settings/RecordingPane.tsx), by the names the page draws, in its order.
 * The model is here since docs/DESIGN.md §138 (ModelCard.tsx, which was the Formatting page), so it carries that
 * page's words, and the Developer page's "Choose your model", which went.
 *
 * Android's rows are listed on Android only: the side key, and the meetings, which the page draws only on a binary with
 * the meeting service (native generation 20) but the search lists on an older one too, where it opens the page. The
 * model, the tapes and the meetings are the app's (`app`): a browser on an Android phone has no model to fetch, no file
 * and no meeting service, only the side key's place. "The side key" keeps the words of the row it was, "Where the side
 * key is", so the whole of that name still finds it.
 */
export function findable({ android, app }: { android: boolean; app: boolean }): SettingsFindable[] {
  return [
    { name: 'Stop when I go quiet', words: 'silence auto stop' },
    { name: 'Review after recording', words: 'check transcript' },
    { name: 'Better words', words: 'refine clean up transcript' },
    { name: 'Summaries', words: 'summary meeting write-up minutes long voice notes' },
    ...(app ? [{ name: 'Model', words: 'ai llm download formatting format enhance summarize choose your qwen gemma storage remove' }] : []),
    ...(android && app
      ? [
          { name: 'Tell me when a meeting is written up', words: 'notification notify alert written up' },
          { name: 'Write up straight away', words: 'meeting battery charging background' },
        ]
      : []),
    ...(app
      ? [
          { name: 'Tapes', words: 'your tapes storage audio remove space' },
          { name: 'Remove audio older than a month', words: 'storage space delete recordings audio' },
        ]
      : []),
    ...(android ? [{ name: 'The side key', words: 'where is button height position hardware' }] : []),
  ];
}
