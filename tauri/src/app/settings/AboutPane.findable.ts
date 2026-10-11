import type { SettingsFindable } from './settingsSearch.ts';

/**
 * What Settings' search finds on About (settings/AboutPane.tsx), by the names the page draws, in its order. Help is
 * five rows since docs/DESIGN.md §138: the cheat sheet and the four examples are pages of their own behind two of
 * them (CheatSheet, ExamplesPane.tsx), each with its own list, and found by its own name, so the two rows that open
 * them are not listed here too: a search for "examples" showed two rows called Examples. "The welcome walkthrough"
 * carries the words of the two rows it replaced: "How to talk to Ghost.md", which the words for the "hey Ghost" switch
 * led to when it went (§136), and Developer's "Welcome guide". What's new is listed where the page draws it: not on an
 * iPhone, where the App Store says what is new (`whatsNew` false).
 */
export function findable({ whatsNew }: { whatsNew: boolean }): SettingsFindable[] {
  return [
    { name: 'Updates', words: 'update check upgrade install' },
    // Android's own switch, drawn only where the activity has alerts to switch.
    { name: 'Update alerts', words: 'notifications notify' },
    { name: 'Ghost.md Academy', words: 'learn tutorial lessons' },
    { name: 'The welcome walkthrough', words: 'guide onboarding set-up first launch side key how to talk to ghost.md voice commands cues hey ghost keyword' },
    { name: 'Ghost.md: The Guide', words: 'guide manual help book notebook chapters add' },
    ...(whatsNew ? [{ name: "What's new", words: 'changelog releases' }] : []),
  ];
}
