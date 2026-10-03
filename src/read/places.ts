/**
 * The page is served in two places: beside the app on attack.fm/glyph (and a dev server), and on ghostmarkdown.com,
 * where the root is the download page rather than the app. So the app's own copy, which saves the share into the
 * reader's library (`#fork=`, shell/useForkLinks.ts), joining by an invite link on the web (`#join=`), and the place
 * to get the app, depend on which. Shared by the reader (Reader.tsx) and the invitation (JoinPage.tsx).
 */
const LANDING = typeof location !== 'undefined' && /(^|\.)ghostmarkdown\.com$/.test(location.hostname);
export const APP_URL = LANDING ? 'https://attack.fm/glyph/' : new URL('./', typeof location !== 'undefined' ? location.href : 'https://attack.fm/glyph/').href;
/** Where the app is got: the download page on ghostmarkdown.com, or the install page beside the app. */
export const INSTALL_URL = LANDING ? 'https://ghostmarkdown.com/' : new URL('./install.html', APP_URL).href;
