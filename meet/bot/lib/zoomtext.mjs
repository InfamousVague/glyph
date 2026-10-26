/**
 * What Zoom's web client says, read: the pure half of lib/zoom.mjs, kept apart from the browser so it can be tested
 * with plain strings (Matt, 2026-10-26: "While you're at it also consider zoom meetings").
 *
 *   - which page to open for a booked Zoom link (`webClientUrl`; a personal link is asked of Zoom first,
 *     `resolvedWebClientUrl`);
 *   - what the page's words mean before the bot is let in (`lobbyOutcome`, `waitingRoom`) and once it is in
 *     (`endedOutcome`);
 *   - the people count on the Participants button (`participantsCount`);
 *   - a caption, with the name Zoom shows on it or the active speaker's, as the `name\ntext` block captions.mjs reads
 *     (`captionBlocks`).
 *
 * Zoom's English UI, as the bot's Chrome runs in en-US (chrome.mjs). Every phrase is matched loosely, by a few words
 * Zoom has used for years, since its web client is redrawn more often than Meet and gives no stable ids.
 */

/** The name Ghost joins a Zoom by: Zoom asks a guest for one, where Meet takes the Google account's. */
export const ZOOM_NAME = 'Ghost (notetaker)';

/** Who said a caption when Zoom names nobody and no tile is marked as speaking: a name a transcript can carry. */
export const NOBODY = 'Someone';

/** zoom.us, or one name under it (`us06web.zoom.us`, a company's `acme.zoom.us`), as the server books them. */
export function isZoomHost(host) {
  return host === 'zoom.us' || /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.zoom\.us$/.test(host);
}

/** A passcode as Zoom writes one into a link, and as the server keeps it. */
const PASSCODE = /^[A-Za-z0-9._-]{1,128}$/;

/** The web client's join page: where a guest joins in the browser, with no app and no sign-in. */
export const WEB_CLIENT = 'https://app.zoom.us/wc/join/';

/**
 * The web client's page for a booked Zoom link: `https://<host>/j/<id>?pwd=<passcode>` (or `/wc/join/<id>`) becomes
 * `https://app.zoom.us/wc/join/<id>?pwd=<passcode>`, the passcode the one part of the query kept. Null for anything
 * else, a personal link (`/my/<name>`) among them: only Zoom knows which meeting that is (`resolvedWebClientUrl`).
 */
export function webClientUrl(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (parsed.protocol !== 'https:' || !isZoomHost(parsed.hostname)) return null;
  const id = /^\/(?:j|wc\/join)\/(\d{9,11})\/?$/.exec(parsed.pathname)?.[1];
  if (!id) return null;
  const pwd = parsed.searchParams.get('pwd');
  return `${WEB_CLIENT}${id}${pwd && PASSCODE.test(pwd) ? `?pwd=${pwd}` : ''}`;
}

/** A personal link, `https://<host>/my/<name>`: opened as it is, for Zoom to say which meeting it is now. */
export function isPersonalLink(url) {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'https:' && isZoomHost(parsed.hostname) && /^\/my\/[a-z0-9._-]{1,64}\/?$/i.test(parsed.pathname);
  } catch {
    return false;
  }
}

/**
 * Where a personal link led: the page Zoom moved to (`/j/<id>?pwd=…`, its launch page) or one of the links on it
 * ("Join from your browser", `/wc/join/<id>…`, possibly relative), as the web client's page; null when none is a
 * meeting.
 */
export function resolvedWebClientUrl(current, hrefs = []) {
  for (const candidate of [current, ...hrefs]) {
    if (!candidate) continue;
    let absolute;
    try {
      absolute = new URL(candidate, current || 'https://zoom.us/').toString();
    } catch {
      continue;
    }
    const url = webClientUrl(absolute);
    if (url) return url;
  }
  return null;
}

/**
 * The lobby's words that end the attempt to join, and the detail each is reported with. A captcha or a sign-in wall
 * is given up on at once and never answered (docs/MEET.md, "Zoom"): Ghost is a guest, and a meeting that wants more
 * than a guest's name is not one it joins.
 */
const LOBBY_OUTCOMES = [
  [/captcha|i'?m not a robot|verify (?:that )?you(?:'| a)re (?:a )?human|security check|prove you'?re human/i, 'captcha'],
  [
    /sign in to join|only (?:authenticated|signed[- ]in) (?:users|participants)|authorized attendees only|you need to sign in|please sign in to|requires? (?:you to )?sign in|sign in with your work account/i,
    'sign_in_required',
  ],
  [/(?:disabled|not allowed|not permitted|turned off) (?:joining )?from (?:a |the |your )?(?:web )?browser|can'?t join from (?:a |the |your )?browser/i, 'no_browser_join'],
  [/(?:wrong|incorrect|invalid) (?:meeting )?passcode|passcode (?:is )?(?:wrong|incorrect|invalid)/i, 'passcode_wrong'],
  [/invalid meeting id|meeting id is (?:not valid|invalid)|this meeting (?:id )?(?:does not|doesn'?t) exist|meeting (?:link )?(?:is invalid|has expired)|not a valid meeting/i, 'invalid_link'],
  [/(?:this|the) meeting has (?:been )?ended|meeting has been ended by (?:the )?host|this meeting is over/i, 'meeting_ended'],
  [/(?:host|someone) (?:has )?removed you|you (?:have been|were) removed|not allowed to (?:re)?join|denied your request|meeting is locked|reached (?:its|the) (?:participant )?(?:capacity|limit)|meeting is full/i, 'refused'],
  [/browser (?:is )?not supported|unsupported browser/i, 'unsupported_browser'],
];

/** Why joining is over before the bot is in, from the page's words and where it is; null to keep going. */
export function lobbyOutcome(text, url = '') {
  try {
    const where = new URL(url);
    // Zoom's own sign-in, or a company's single sign-on, is a wall.
    if (isZoomHost(where.hostname) && /^\/(?:signin|sso|saml|login)\b/i.test(where.pathname)) return 'sign_in_required';
    if (/(?:^|\.)(?:okta|onelogin|auth0)\.com$|^login\.microsoftonline\.com$|^accounts\.google\.com$/.test(where.hostname)) return 'sign_in_required';
  } catch {
    // Not a URL: the words alone.
  }
  for (const [pattern, detail] of LOBBY_OUTCOMES) if (pattern.test(text ?? '')) return detail;
  return null;
}

/** The waiting room, or a meeting whose host has not yet started it: the bot waits, as long as `admitMs`. */
export function waitingRoom(text) {
  return /will let you in soon|waiting room|we'?ve let (?:them|the host) know you'?re here|waiting for the host to start|host has not (?:yet )?(?:started|joined)|please wait/i.test(text ?? '');
}

/**
 * Why the call is over for the bot once it was in, from the page's words and where it is: Zoom leaves the web client
 * for a page of its own (`/postattendee`, `/wc/leave`) when a meeting ends. Read only once the Leave button is gone
 * (zoom.mjs), since the chat and the captions are on the page too.
 */
export function endedOutcome(text, url = '') {
  if (/(?:host|someone) (?:has )?removed you|you (?:have been|were) removed/i.test(text ?? '')) return 'removed';
  if (/(?:this|the) meeting has (?:been )?ended|ended by (?:the )?host|you left the meeting|you have left the meeting/i.test(text ?? '')) return 'meeting_ended';
  try {
    if (/^\/(?:postattendee|wc\/leave|wc\/[^/]+\/leave)\b/i.test(new URL(url).pathname)) return 'meeting_ended';
  } catch {
    // Not a URL.
  }
  return null;
}

/**
 * The people count on the Participants button, the bot counted: from its accessible name ("open the participants
 * list pane,[4] particpants" - Zoom's own spelling, for years - or "Participants 4") or the badge beside it ("4").
 * Null where neither has a number.
 */
export function participantsCount(label, badge) {
  const named = String(label ?? '');
  const bracketed = /\[(\d{1,4})\]/.exec(named) ?? /\bpartic(?:i)?pants?\D{0,3}(\d{1,4})\b/i.exec(named) ?? /\b(\d{1,4})\s*partic(?:i)?pants?\b/i.exec(named);
  if (bracketed) return Number(bracketed[1]);
  const shown = /^\s*(\d{1,4})\s*$/.exec(String(badge ?? ''));
  return shown ? Number(shown[1]) : null;
}

/**
 * "Sam Lee: we shipped it" as a name and words, where Zoom writes a caption so. A name is short (four words at most)
 * and has no sentence's punctuation in it; a short word a person says before a colon ("Note: …") still reads as one.
 */
function namedLine(line) {
  const m = /^([^:\n]{1,60}):\s+(.+)$/.exec(line);
  if (!m || /[.,;!?]/.test(m[1]) || m[1].trim().split(/\s+/).length > 4) return null;
  return { speaker: m[1].trim(), text: m[2].trim() };
}

/**
 * Zoom's captions as the blocks captions.mjs reads, each `speaker\ntext`. `items` are what the page read: each
 * `{ name, text }` where Zoom draws the speaker's name on the caption (its own element), or `{ text }` alone; the
 * speaker is that name, else a `Name: words` the line begins with, else the tile Zoom marks as speaking (`active`),
 * else `NOBODY`. Empty captions are left out.
 */
export function captionBlocks(items, active = null) {
  const fallback = String(active ?? '').trim() || NOBODY;
  const out = [];
  for (const item of items ?? []) {
    const text = String(item?.text ?? '').replace(/\s+/g, ' ').trim();
    if (!text) continue;
    const name = String(item?.name ?? '').trim();
    if (name && name !== text) {
      out.push(`${name}\n${text.startsWith(`${name}:`) ? text.slice(name.length + 1).trim() : text}`);
      continue;
    }
    const named = namedLine(text);
    out.push(named ? `${named.speaker}\n${named.text}` : `${fallback}\n${text}`);
  }
  return out;
}
