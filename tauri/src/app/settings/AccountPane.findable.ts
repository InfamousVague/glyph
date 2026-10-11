import type { SettingsFindable } from './settingsSearch.ts';

/**
 * What Settings' search finds on Account (settings/AccountPane.tsx), by the names the page draws: a row's label or a
 * card's title, so a hit opens the page and lights it. Beside the page rather than in SettingsSheet.tsx, which kept
 * every pane's list by hand until docs/DESIGN.md §138; SettingsSheet.test.tsx renders the page and fails on a name it
 * does not draw.
 *
 * Signed in the page is the account's, signed out it is the ways in. The Privacy card (PrivacyCard.tsx) and the
 * Location card (LocationCard.tsx) are on it either way, after the account's own cards: what leaves the phone is
 * Account's story. In the page's order, so "privacy" and Enter open the Privacy card itself.
 */

/**
 * The Privacy card's: the switch that keeps everything here, the one that reads a linked site, the one that looks a
 * live blank up (the app's only, where a model runs, docs/DESIGN.md §145), and the policy.
 */
function privacy(app: boolean): SettingsFindable[] {
  return [
    { name: 'Privacy', words: 'what leaves the phone' },
    { name: 'Local only', words: 'offline privacy network internet nothing leaves the phone' },
    { name: 'Link previews', words: 'links url cards' },
    ...(app ? [{ name: 'Look up blanks online', words: 'fill blank weather rates wikipedia web live internet' }] : []),
    { name: 'Privacy policy', words: 'data privacy personal information policy' },
  ];
}

/** The Location card's, which was a page of its own (Settings › Location) until §138, with that page's words. */
const LOCATION: SettingsFindable[] = [
  { name: 'Location', words: 'map place where geotag gps' },
  { name: 'Map on a tagged note', words: 'openstreetmap tiles' },
  { name: 'Place names', words: 'nominatim address geocode' },
  { name: 'Tag new notes with my location', words: 'automatic gps position geotag place where front matter' },
];

export function findable(signedIn: boolean, app = false): SettingsFindable[] {
  const PRIVACY = privacy(app);
  return signedIn
    ? [
        { name: 'Sync now', words: 'devices' },
        { name: 'Sync meeting recordings', words: 'audio meeting meetings tapes' },
        { name: 'Live typing (trial)', words: 'realtime collaborate' },
        { name: 'Password and recovery codes', words: 'change' },
        { name: 'Sign out', words: 'log out logout' },
        { name: 'Shared links', words: 'share publish read' },
        ...PRIVACY,
        ...LOCATION,
        { name: 'Delete account', words: 'remove close erase data' },
      ]
    : [
        { name: 'I have an account', words: 'sign in login' },
        { name: 'Create an account', words: 'sign up register' },
        { name: 'Lost the password', words: 'forgot recovery code reset' },
        ...PRIVACY,
        ...LOCATION,
      ];
}
