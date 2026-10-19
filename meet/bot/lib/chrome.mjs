/**
 * How the bot's Chrome is started: the installed Google Chrome (not Playwright's Chromium), on the signed-in profile,
 * with everything that tells Meet "this browser is automated" taken away (meet/spike/README.md):
 *
 *   - no `--enable-automation` (the banner, and Meet's refusal), and `AutomationControlled` off, and
 *     navigator.webdriver hidden by an init script (meet.mjs);
 *   - Chrome's own sandbox kept (`--no-sandbox` is one of Playwright's defaults taken away; chromiumSandbox: true);
 *   - the profile's cookies opened the way they were sealed at sign-in. On a Mac that is the real keychain, so
 *     Playwright's `--use-mock-keychain` and `--password-store=basic` go. On Linux there is no keyring for a service
 *     account, so BOTH Chromes - the plain one Matt signs in with (`signinCommand`) and the automated one - are given
 *     `--password-store=basic`: the same store on both sides, or the bot opens a profile whose cookies it cannot read
 *     and Chrome throws them away (the first sign-in in the spike was lost exactly so).
 *
 * No microphone or camera: no permission granted, no fake devices. The meeting is heard by capturing the bot's own tab
 * (`--auto-accept-this-tab-capture`), which is all the spike found to work.
 */

/** Playwright's default switches the bot takes away. */
export const IGNORE_DEFAULT_ARGS = ['--enable-automation', '--no-sandbox', '--use-mock-keychain', '--password-store=basic'];

/** The window: the Xvfb screen's size (meet/box/glyph-meet-xvfb.service), at its corner (there is no window manager). */
const WINDOW = ['--window-size=1280,800', '--window-position=0,0'];

/**
 * English, whatever the box's locale: the buttons are found by their English names. (The Google account's own
 * language decides Meet's, so the bot's account must be set to English too; docs/MEET.md.)
 */
const LANGUAGE = ['--lang=en-US'];

const passwordStore = (platform) => (platform === 'linux' ? ['--password-store=basic'] : []);

/** The switches for the automated Chrome. */
export function botArgs(platform = process.platform) {
  return [
    ...WINDOW,
    ...LANGUAGE,
    ...passwordStore(platform),
    '--autoplay-policy=no-user-gesture-required',
    '--disable-blink-features=AutomationControlled',
    '--auto-accept-this-tab-capture',
  ];
}

/** Playwright's launchPersistentContext options for the bot. */
export function botLaunchOptions({ platform = process.platform, executablePath = process.env.GLYPH_MEET_CHROME } = {}) {
  return {
    ...(executablePath ? { executablePath } : { channel: 'chrome' }),
    headless: false,
    // The page is the window's own size, not an emulated viewport.
    viewport: null,
    args: botArgs(platform),
    ignoreDefaultArgs: IGNORE_DEFAULT_ARGS,
    chromiumSandbox: true,
    permissions: [],
    // Chrome is closed by the bot itself (meet.mjs), after leaving the call; not by Playwright on a signal.
    handleSIGINT: false,
    handleSIGTERM: false,
    handleSIGHUP: false,
  };
}

/** The installed Chrome, for the plain sign-in browser. */
export function chromePath(platform = process.platform) {
  if (process.env.GLYPH_MEET_CHROME) return process.env.GLYPH_MEET_CHROME;
  return platform === 'darwin' ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' : '/usr/bin/google-chrome-stable';
}

/**
 * The sign-in browser: a plain Chrome command line, no Playwright and no automation switches at all, because Google
 * refuses a sign-in in an automated browser. Same profile, same password store as the bot's.
 */
export function signinCommand(profile, platform = process.platform) {
  return {
    command: chromePath(platform),
    args: [
      `--user-data-dir=${profile}`,
      ...WINDOW,
      ...LANGUAGE,
      ...passwordStore(platform),
      '--no-first-run',
      '--no-default-browser-check',
      'https://accounts.google.com/',
    ],
  };
}
