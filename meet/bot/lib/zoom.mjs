/**
 * Zoom, driven through its web client (Matt, 2026-10-26: "While you're at it also consider zoom meetings"): the same
 * exports as lib/meet.mjs, so session.mjs runs a Zoom call as it runs a Meet, and the same browser and recorder
 * (lib/browser.mjs). What the page's words mean is lib/zoomtext.mjs, tested there; this file is what touches the page.
 *
 * Ghost joins a Zoom as a GUEST, by name ("Ghost (notetaker)"), never signed in to Zoom: the profile is signed in to
 * Google for Meet, and Zoom is not offered it. So a meeting is joined only where its host lets a guest join from the
 * browser; a sign-in wall, a captcha, or the browser join turned off is given up on at once with its own detail
 * (docs/MEET.md, "Zoom"). Terms and recording notices are agreed to, as joining in person agrees to them; a cookie
 * banner is answered with the fewest cookies.
 *
 * Unlike Meet's, Zoom's web client is not the spike's: nothing here has been run against a live Zoom, and its markup
 * changes often. So every element is found by its accessible name or its words first, by a class name only as a
 * fallback, and each list of names below is the place to add Zoom's next wording. The selectors are listed in
 * docs/MEET.md.
 *
 * Nothing read from the page reaches the log except which of a few known situations it was.
 */
import { bodyText, clickIf, hostOf, lobbyButtons, sleep } from './browser.mjs';
import { ZOOM_NAME, captionBlocks as blocksOf, endedOutcome, isPersonalLink, lobbyOutcome, participantsCount, resolvedWebClientUrl, waitingRoom, webClientUrl } from './zoomtext.mjs';

export { openBrowser, soundLevel, startRecording, stopRecording } from './browser.mjs';

/** The join button on the web client's page ("Join"), and nothing longer ("Join Audio", "Join from your browser"). */
const JOIN_BUTTON = /^\s*join\s*$/i;
/** The call's Leave button; "Leave Meeting" is the confirmation that follows it, and ends no meeting for others. */
const LEAVE_BUTTON = /^\s*leave\s*$/i;
const LEAVE_CONFIRM = /^\s*leave meeting\s*$/i;
/** The Leave button by its markup, where its accessible name is drawn otherwise. */
const LEAVE_SELECTOR = 'button.footer__leave-btn, button[aria-label="Leave"], button[aria-label^="Leave" i]:not([aria-label*="breakout" i])';

/** A captcha on the page, by its frame (reCAPTCHA, hCaptcha, Arkose) or its box. */
const CAPTCHA_SELECTOR = 'iframe[src*="recaptcha"], iframe[src*="hcaptcha"], iframe[src*="arkoselabs"], iframe[title*="captcha" i], .g-recaptcha, #captcha, [id*="captcha" i]';

/**
 * Notices clicked away wherever they come: a recording or transcript notice ("Got it"; staying is consenting, as for
 * a person), terms ("I Agree"), Zoom's tips. A button of a dialog alone, so a word in the chat is never pressed; and
 * never a dialog's Close, which would close the one that joins the meeting's sound.
 */
const NOTICE_BUTTONS = /^\s*(got it|i agree|agree|agree and (continue|proceed)|continue|ok|okay|i understand|not now|maybe later)\s*$/i;
/** A cookie banner, answered with the fewest cookies (the choice a person who did not care to read would want). */
const COOKIE_BUTTONS = /^\s*(reject all( cookies)?|decline( all)?|necessary cookies only|only necessary( cookies)?|reject optional cookies)\s*$/i;

/** The preview's way past a microphone and camera it does not have, and its own switches turned off. */
const NO_DEVICES = /continue without (microphone and camera|audio or video|audio and video|microphone|camera)/i;
const MIC_OFF = /^\s*(mute|mute my microphone|mute audio)\s*$/i;
const CAMERA_OFF = /^\s*(stop video|turn off video|stop my video)\s*$/i;

/** Joining the meeting's sound: without it the web client plays nothing, and the tab capture hears silence. */
const JOIN_AUDIO = /join (audio )?by computer|join with computer audio|^\s*join audio\s*$|computer audio/i;

/** The ways to Zoom's captions a participant may have, tried in turn (`captionsOn`). */
const SHOW_CAPTIONS = /^\s*(show captions?|show subtitles?|enable captions?|turn on captions?)\s*$/i;
const CAPTIONS_MENU = /^\s*(captions?|cc|closed captions?|live transcript|show captions options|captions options)\b/i;
const MORE = /^\s*more\s*$/i;

async function dialogClick(page, name) {
  const button = page.getByRole('dialog').getByRole('button', { name }).first();
  if (!(await button.isVisible().catch(() => false))) return false;
  await button.click({ timeout: 5000 }).catch(() => {});
  return true;
}

/** Clicks away whatever stands between the bot and the meeting: cookies, terms, notices. Whether anything was. */
async function clearNotices(page) {
  let any = false;
  // A cookie banner is not always a dialog: its buttons are found anywhere, by names no meeting draws.
  if (await clickIf(page, COOKIE_BUTTONS)) any = true;
  if (await dialogClick(page, NOTICE_BUTTONS)) any = true;
  return any;
}

async function hasCaptcha(page) {
  return (await page.locator(CAPTCHA_SELECTOR).count().catch(() => 0)) > 0;
}

async function leaveAttached(page) {
  if ((await page.getByRole('button', { name: LEAVE_BUTTON }).count().catch(() => 0)) > 0) return true;
  return (await page.locator(LEAVE_SELECTOR).count().catch(() => 0)) > 0;
}

/** The name box: by its label ("Your Name"), else Zoom's id for it. */
function nameBox(page) {
  return page.getByRole('textbox', { name: /^\s*(your )?name\b/i }).or(page.locator('#input-for-name')).first();
}

/** The passcode box, which the web client shows only when the link brought no passcode. */
function passcodeBox(page) {
  return page.getByRole('textbox', { name: /passcode|password/i }).or(page.locator('#input-for-pwd')).first();
}

/**
 * A personal link (`/my/<name>`) asked of Zoom: opened, and where it leads read off the page Zoom moves to or its
 * "Join from your browser" link. Resolves to the web client's page, or null.
 */
async function resolvePersonal(page, url) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  const by = Date.now() + 30_000;
  while (Date.now() < by) {
    const hrefs = await page.evaluate(() => [...document.querySelectorAll('a[href]')].map((a) => a.getAttribute('href'))).catch(() => []);
    const found = resolvedWebClientUrl(page.url(), hrefs);
    if (found) return found;
    await sleep(1000);
  }
  return null;
}

/**
 * The lobby: the web client's page for the link, the name, the microphone and camera off, Join, and the wait to be let
 * in (the waiting room, or a host not yet there) for up to `admitMs`. Resolves to `{ ok: true }` in the call, or
 * `{ ok: false, detail }`: `captcha`, `sign_in_required`, `no_browser_join`, `passcode_needed`, `passcode_wrong`,
 * `invalid_link`, `refused`, `meeting_ended`, `unsupported_browser`, `no_join_button`, `not_admitted`, `shutdown`.
 */
export async function join(page, url, { admitMs, shouldStop = () => false, log = () => {} }) {
  let target = webClientUrl(url);
  if (!target && isPersonalLink(url)) {
    target = await resolvePersonal(page, url);
    if (!target) {
      const text = await bodyText(page);
      return { ok: false, detail: lobbyOutcome(text, page.url()) ?? 'invalid_link' };
    }
  }
  if (!target) return { ok: false, detail: 'invalid_link' };
  const hasPasscode = new URL(target).searchParams.has('pwd');
  await page.goto(target, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  const openedAt = Date.now();

  const previewBy = Date.now() + 90_000;
  let named = false;
  for (;;) {
    if (shouldStop()) return { ok: false, detail: 'shutdown' };
    if (Date.now() > previewBy) {
      log('lobby', { host: hostOf(page), count: await lobbyButtons(page) });
      return { ok: false, detail: 'no_join_button' };
    }
    if (await hasCaptcha(page)) return { ok: false, detail: 'captcha' };
    const outcome = lobbyOutcome(await bodyText(page), page.url());
    if (outcome) return { ok: false, detail: outcome };
    // Already in: a host who lets everyone straight in, with nothing asked.
    if (await leaveAttached(page)) return { ok: true };
    await clearNotices(page);
    await clickIf(page, NO_DEVICES);
    await clickIf(page, MIC_OFF);
    await clickIf(page, CAMERA_OFF);
    const name = nameBox(page);
    if (await name.isVisible().catch(() => false)) {
      if ((await name.inputValue().catch(() => '')) !== ZOOM_NAME) await name.fill(ZOOM_NAME, { timeout: 5000 }).catch(() => {});
      named = true;
    }
    const passcode = passcodeBox(page);
    if ((await passcode.isVisible().catch(() => false)) && !(await passcode.inputValue().catch(() => ''))) {
      // The link carried none, or Zoom has not taken the one it carried in ten seconds: the bot has none to type.
      if (!hasPasscode || Date.now() - openedAt > 10_000) return { ok: false, detail: 'passcode_needed' };
    }
    const button = page.getByRole('button', { name: JOIN_BUTTON }).first();
    if ((await button.isVisible().catch(() => false)) && (await button.isEnabled().catch(() => false))) {
      await button.click({ timeout: 5000 }).catch(() => {});
      log('join_pressed', { button: 'join', named });
      break;
    }
    await sleep(1000);
  }

  // Let in when the Leave button is attached: Zoom hides its footer while the pointer is still, so not "visible".
  const admitBy = Date.now() + admitMs;
  let waiting = false;
  while (Date.now() < admitBy) {
    if (shouldStop()) return { ok: false, detail: 'shutdown' };
    if (await leaveAttached(page)) return { ok: true };
    if (await hasCaptcha(page)) return { ok: false, detail: 'captcha' };
    const text = await bodyText(page);
    const outcome = lobbyOutcome(text, page.url());
    if (outcome) return { ok: false, detail: outcome };
    if (!waiting && waitingRoom(text)) {
      waiting = true;
      log('waiting_room');
    }
    await clearNotices(page);
    await sleep(2000);
  }
  return { ok: false, detail: 'not_admitted' };
}

/** Zoom shows its footer when the pointer moves. */
async function revealFooter(page) {
  await page.mouse.move(640, 400).catch(() => {});
  await page.mouse.move(640, 760).catch(() => {});
  await sleep(400);
}

/**
 * In the call: the meeting's sound joined ("Join Audio by Computer"; without it the web client plays nothing), the
 * microphone muted and the camera off again, and the notices a call opens with clicked away (recording, AI summary,
 * tips). session.mjs calls it once in, and the recorder hears the call from then on.
 */
export async function ready(page, log = () => {}) {
  for (let i = 0; i < 5; i++) {
    if (await dialogClick(page, JOIN_AUDIO)) {
      log('audio_joined');
      break;
    }
    await clearNotices(page);
    await revealFooter(page);
    if (await clickIf(page, JOIN_AUDIO)) {
      await sleep(1000);
      await dialogClick(page, JOIN_AUDIO);
      log('audio_joined');
      break;
    }
    await sleep(1000);
  }
  await clearNotices(page);
  await revealFooter(page);
  await clickIf(page, MIC_OFF);
  await clickIf(page, CAMERA_OFF);
}

/** The bot's line in the meeting's chat: the Chat panel opened, typed, Enter, closed. A meeting with chat off is let be. */
export async function announce(page, text, log = () => {}) {
  if (!text) return;
  try {
    await revealFooter(page);
    const chat = page.getByRole('button', { name: /^\s*chat\b|open the chat pane|open chat/i }).first();
    await chat.click({ timeout: 5000 });
    const box = page
      .getByRole('textbox', { name: /type message|message|chat/i })
      .or(page.locator('[class*="chat" i] [contenteditable="true"], textarea[class*="chat" i]'))
      .first();
    await box.waitFor({ state: 'visible', timeout: 8000 });
    await box.click({ timeout: 3000 });
    await page.keyboard.type(text, { delay: 15 });
    await page.keyboard.press('Enter');
    await sleep(800);
    await revealFooter(page);
    await chat.click({ timeout: 5000 }).catch(() => clickIf(page, /^\s*close\s*$/i));
    log('announced');
  } catch {
    log('announce_skipped');
    await page.keyboard.press('Escape').catch(() => {});
  }
}

/**
 * Zoom's captions on, where the host lets a participant see them: "Show Captions" on the footer; else the Captions
 * (CC, Live Transcript) button and its "Show captions" / "Show subtitle"; else the same under More. A host with
 * captions off offers none, and the bot records the sound alone; it never asks the host to turn them on.
 */
export async function captionsOn(page) {
  await revealFooter(page);
  if (await clickIf(page, SHOW_CAPTIONS)) return settleCaptions(page);
  for (const opener of [CAPTIONS_MENU, MORE]) {
    if (!(await clickIf(page, opener))) continue;
    await sleep(500);
    if (opener === MORE) {
      for (const role of ['menuitem', 'button']) if (await clickIf(page, CAPTIONS_MENU, role)) break;
      await sleep(500);
    }
    for (const role of ['menuitem', 'menuitemcheckbox', 'button']) {
      if (await clickIf(page, SHOW_CAPTIONS, role)) return settleCaptions(page);
    }
    await page.keyboard.press('Escape').catch(() => {});
  }
}

/** Zoom can ask which language is spoken once captions come on: its own choice (English) kept, and the dialog closed. */
async function settleCaptions(page) {
  await sleep(800);
  await dialogClick(page, /^\s*(save|confirm|done|ok)\s*$/i);
  await page.keyboard.press('Escape').catch(() => {});
}

/**
 * The captions on the page, and who is speaking: `{ items: [{ name, text }], active }`, or null with no captions shown.
 * The captions are the overlay Zoom draws over the video (by a class or label with "caption", "subtitle" or
 * "transcri" in it); each caption's name where Zoom draws one in an element of its own; `active`, the name on the tile
 * Zoom marks as speaking.
 */
function readZoomCaptions() {
  const overlay = document.querySelector(
    [
      '[aria-label*="caption" i][aria-live]',
      '[class*="live-transcription-subtitle" i]',
      '[class*="subtitle" i][aria-live]',
      '[class*="caption" i][aria-live]',
      '[id*="subtitle" i]',
      '[class*="caption-container" i]',
      '[class*="captions-container" i]',
    ].join(','),
  );
  const activeEl = document.querySelector(
    [
      '[class*="speaker-active" i] [class*="avatar-name" i]',
      '[class*="active-speaker" i] [class*="name" i]',
      '[class*="video-avatar__avatar--active" i] [class*="name" i]',
      '[class*="speaking" i] [class*="name" i]',
    ].join(','),
  );
  const active = activeEl ? (activeEl.innerText || '').trim().split('\n')[0] : null;
  if (!overlay || !(overlay.innerText || '').trim()) return overlay ? { items: [], active } : null;
  const rows = [...overlay.querySelectorAll('[class*="item" i], [class*="line" i], [class*="row" i], li, p')].filter(
    (el) => !el.querySelector('[class*="item" i], [class*="line" i], [class*="row" i], li, p') && (el.innerText || '').trim(),
  );
  const items = (rows.length ? rows : [overlay]).map((el) => {
    const nameEl = el.querySelector('[class*="name" i], [class*="speaker" i], [class*="user" i]');
    const name = nameEl ? (nameEl.innerText || '').trim() : '';
    let text = (el.innerText || '').trim();
    if (name && text.startsWith(name)) text = text.slice(name.length).trim();
    return { name, text };
  });
  return { items, active };
}

export async function captionBlocks(page) {
  const read = await page.evaluate(readZoomCaptions).catch(() => null);
  if (!read) return null;
  return blocksOf(read.items, read.active);
}

/**
 * How many people are in the call, the bot counted: the number on the Participants button (its name or its badge),
 * else the video tiles. `{ count, from: 'button' | 'tiles' }`, or null.
 */
function readZoomPeople() {
  const buttons = [...document.querySelectorAll('button, [role="button"]')].filter((b) =>
    /partic(i)?pants?/i.test(`${b.getAttribute('aria-label') || ''} ${b.innerText || ''}`),
  );
  for (const b of buttons) {
    const badge = b.querySelector('[class*="counter" i], [class*="number" i], [class*="badge" i]');
    return { label: `${b.getAttribute('aria-label') || ''} ${b.innerText || ''}`, badge: badge ? badge.innerText : '' };
  }
  const tiles = new Set(
    [...document.querySelectorAll('[class*="video-avatar__avatar" i] [class*="name" i], [class*="gallery-video-container__video-frame" i]')].map(
      (el, i) => (el.innerText || '').trim() || `tile-${i}`,
    ),
  );
  return tiles.size ? { tiles: tiles.size } : null;
}

export async function people(page) {
  const read = await page.evaluate(readZoomPeople).catch(() => null);
  if (!read) return null;
  if (read.tiles) return { count: read.tiles, from: 'tiles' };
  const count = participantsCount(read.label, read.badge);
  return count == null ? null : { count, from: 'button' };
}

/**
 * Why the call is over for the bot, or null while it is in it. Only once the Leave button is gone, as for Meet: the
 * captions and the chat are on the page too. Three reads with no button and no words is over.
 */
export async function endedReason(page, state) {
  if (page.isClosed()) return 'meeting_ended';
  const there = await leaveAttached(page);
  state.goneFor = there ? 0 : (state.goneFor ?? 0) + 1;
  if (there) return null;
  const said = endedOutcome(await bodyText(page), page.url());
  if (said) return said;
  return state.goneFor >= 3 ? 'meeting_ended' : null;
}

/** Leaves the call: Leave, then Zoom's "Leave Meeting" (never "End Meeting for All", which only a host is offered). */
export async function leaveCall(page) {
  if (page.isClosed()) return;
  await revealFooter(page);
  const leave = page.getByRole('button', { name: LEAVE_BUTTON }).or(page.locator(LEAVE_SELECTOR)).first();
  await leave.click({ timeout: 5000 }).catch(() => leave.click({ force: true, timeout: 3000 }).catch(() => {}));
  await sleep(800);
  await clickIf(page, LEAVE_CONFIRM);
  await sleep(1500);
}
