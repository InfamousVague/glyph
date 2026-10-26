/**
 * Google Meet, driven: everything that touches the page. What is matched here (button names, texts, the captions
 * region) was found by the spike (meet/spike/README.md) and is Meet's English UI; when Meet changes, this is the file.
 *
 * Nothing read from the page reaches the log except which of a few known situations it was.
 */
import { appendFileSync } from 'node:fs';
import { chromium } from 'playwright-core';
import { botLaunchOptions } from './chrome.mjs';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Texts that end the attempt to join, and the detail each is reported with. */
const PREVIEW_OUTCOMES = [
  [/you can'?t join this video call/i, 'refused'],
  [/someone in the call denied your request|denied your request to join|no one responded to your request/i, 'not_admitted'],
  [/(this|the) meeting has ended|this call has ended/i, 'meeting_ended'],
  [/check your meeting code|meeting code is invalid|couldn'?t find the meeting|invalid video call name/i, 'invalid_link'],
];

/** Texts that say the call is over for the bot, once it was in. */
const ENDED = [
  [/you'?ve been removed from the meeting|removed you from the meeting/i, 'removed'],
  [/you left the meeting|the meeting has ended|this call has ended|everyone has left|returning to home screen/i, 'meeting_ended'],
];

/**
 * The lobby's way in. Not anchored: on the box (no microphone, no camera) Meet badges "Join now" with a warning, and the
 * badge is part of the button's accessible name, so an exact "Join now" found nothing (2026-10-19, no_join_button).
 * "Other ways to join" holds none of these phrases.
 */
export const JOIN_BUTTON = /\b(join now|ask to join|switch here)\b/i;
const LEAVE_BUTTON = /leave call/i;

/** Runs in the page before Meet does: no navigator.webdriver, and the recorder (tab capture into a MediaRecorder). */
function pageScript() {
  Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  const box = { ctx: null, rec: null, chain: Promise.resolve(), meter: null, stream: null };
  window.__ghostStart = async () => {
    // The tab's own sound, as a person at this seat would hear it: the meeting's mix. Chrome accepts the prompt
    // itself (--auto-accept-this-tab-capture).
    const stream = await navigator.mediaDevices.getDisplayMedia({
      video: true,
      audio: { suppressLocalAudioPlayback: false },
      preferCurrentTab: true,
      selfBrowserSurface: 'include',
      systemAudio: 'exclude',
    });
    stream.getVideoTracks().forEach((t) => t.stop());
    const tracks = stream.getAudioTracks();
    if (!tracks.length) throw new Error('the tab capture has no audio track');
    box.stream = stream;
    box.ctx = new AudioContext({ sampleRate: 48000 });
    await box.ctx.resume().catch(() => {});
    const source = box.ctx.createMediaStreamSource(new MediaStream(tracks));
    const dest = box.ctx.createMediaStreamDestination();
    source.connect(dest);
    box.meter = box.ctx.createAnalyser();
    box.meter.fftSize = 2048;
    source.connect(box.meter);
    box.rec = new MediaRecorder(dest.stream, { mimeType: 'audio/webm;codecs=opus', audioBitsPerSecond: 48000 });
    // Slices handed over in order: each waits for the one before it to reach Node.
    box.rec.ondataavailable = (e) => {
      if (!e.data || !e.data.size) return;
      box.chain = box.chain.then(async () => {
        const bytes = new Uint8Array(await e.data.arrayBuffer());
        let s = '';
        for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
        await window.__ghostChunk(btoa(s));
      });
    };
    box.rec.start(5000);
    return tracks.length;
  };
  /** The sound's level over the last instant, in dB: a recording of silence shows up in the log as -100s. */
  window.__ghostLevel = () => {
    if (!box.meter) return null;
    const buf = new Float32Array(2048);
    box.meter.getFloatTimeDomainData(buf);
    let sum = 0;
    for (const v of buf) sum += v * v;
    return Math.round(20 * Math.log10(Math.sqrt(sum / buf.length) + 1e-9));
  };
  /** Stops the recorder: the last slice is handed over before this resolves. */
  window.__ghostStop = () =>
    new Promise((done) => {
      if (!box.rec || box.rec.state === 'inactive') return box.chain.then(done, done);
      box.rec.onstop = () => box.chain.then(done, done);
      box.rec.stop();
      if (box.stream) box.stream.getTracks().forEach((t) => t.stop());
    });
}

/** The captions region's blocks, each `name\ntext`; null when the region is not there (captions off). */
function readCaptions() {
  const region = document.querySelector('[role="region"][aria-label*="aption" i]');
  if (!region) return null;
  // Down through the wrappers to the element whose children are the blocks.
  let list = region;
  while (list.children.length === 1 && list.firstElementChild.innerText === list.innerText) list = list.firstElementChild;
  const blocks = [...list.children].map((el) => el.innerText).filter((t) => t && t.trim());
  return blocks.length ? blocks : list.innerText.trim() ? [list.innerText] : [];
}

/**
 * How many people are in the call, or null when the page does not say: the number on the People button, else the
 * participant tiles.
 */
function readPeople() {
  const button = [...document.querySelectorAll('button[aria-label]')].find((b) =>
    /^(show everyone|people|participants)\b/i.test(b.getAttribute('aria-label')),
  );
  if (button) {
    const label = /(\d+)/.exec(button.getAttribute('aria-label'));
    if (label) return { count: Number(label[1]), from: 'button' };
    const around = (button.parentElement ?? button).innerText ?? '';
    const badge = /(?:^|\n)\s*(\d{1,4})\s*(?:\n|$)/.exec(around);
    if (badge) return { count: Number(badge[1]), from: 'button' };
  }
  // The tiles, where the button says no number: a presentation can be a tile of its own, so a count from them is
  // never taken for a big group (decide.mjs nextPeak).
  const tiles = new Set([...document.querySelectorAll('[data-participant-id]')].map((el) => el.getAttribute('data-participant-id')));
  return tiles.size ? { count: tiles.size, from: 'tiles' } : null;
}

export async function openBrowser(profile) {
  const context = await chromium.launchPersistentContext(profile, botLaunchOptions());
  await context.addInitScript(pageScript);
  const page = context.pages()[0] ?? (await context.newPage());
  return { context, page };
}

/** A visible button whose accessible name matches, clicked; whether there was one. */
async function clickIf(page, name) {
  const button = page.getByRole('button', { name }).first();
  if (!(await button.isVisible().catch(() => false))) return false;
  await button.click({ timeout: 5000 }).catch(() => {});
  return true;
}

async function lobbyButtons(page) {
  return page
    .evaluate(() =>
      [...document.querySelectorAll('button,[role=button]')]
        .filter((b) => b.offsetParent !== null)
        .length,
    )
    .catch(() => null);
}

async function bodyText(page) {
  return page.locator('body').innerText({ timeout: 5000 }).catch(() => '');
}

/** Google's sign-in pages: Meet sends a profile there when its sign-in has lapsed (no name box, no Sign in button). */
export function isSignInPage(url) {
  try {
    return new URL(url).hostname === 'accounts.google.com';
  } catch {
    return false;
  }
}

async function signedOut(page) {
  if (isSignInPage(page.url())) return true;
  if (await page.getByRole('textbox', { name: /your name/i }).first().isVisible().catch(() => false)) return true;
  for (const role of ['button', 'link']) {
    if (await page.getByRole(role, { name: /^sign in$/i }).first().isVisible().catch(() => false)) return true;
  }
  return false;
}

/**
 * The lobby: open the link, check the bot is signed in, turn its (absent) microphone and camera off, press the join
 * button, and wait to be let in. Resolves to `{ ok: true }` in the call, or `{ ok: false, detail }`.
 * Never joins anonymously: a name box or a Sign in button is `signed_out`, and that is the end of it.
 */
export async function join(page, url, { admitMs, shouldStop = () => false, log = () => {} }) {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60_000 });
  const previewBy = Date.now() + 60_000;
  let pressed = null;
  while (!pressed) {
    if (shouldStop()) return { ok: false, detail: 'shutdown' };
    if (Date.now() > previewBy) {
      // Where the lobby was instead, for the log: the page's host and how many buttons it showed (no names: a button
      // can carry a person's).
      log('lobby', { host: (() => { try { return new URL(page.url()).hostname; } catch { return ''; } })(), count: await lobbyButtons(page) });
      return { ok: false, detail: 'no_join_button' };
    }
    if (await signedOut(page)) return { ok: false, detail: 'signed_out' };
    const text = await bodyText(page);
    for (const [pattern, detail] of PREVIEW_OUTCOMES) if (pattern.test(text)) return { ok: false, detail };
    // Without a microphone or camera permission Meet asks how to carry on; and the tray's own switches, if offered.
    await clickIf(page, /continue without microphone and camera/i);
    await clickIf(page, /^got it$/i);
    await clickIf(page, /turn off microphone/i);
    await clickIf(page, /turn off camera/i);
    const button = page.getByRole('button', { name: JOIN_BUTTON }).first();
    if (await button.isVisible().catch(() => false)) {
      pressed = ((await button.innerText().catch(() => '')) || 'join').trim().toLowerCase();
      await button.click({ timeout: 5000 }).catch(() => {});
      log('join_pressed', { button: pressed.replace(/\s+/g, '_') });
      break;
    }
    await sleep(1000);
  }
  // Admitted when the Leave button is attached: Meet hides its tray until the pointer moves, so not "visible".
  const admitBy = Date.now() + admitMs;
  const leave = page.getByRole('button', { name: LEAVE_BUTTON });
  while (Date.now() < admitBy) {
    if (shouldStop()) return { ok: false, detail: 'shutdown' };
    if ((await leave.count().catch(() => 0)) > 0) return { ok: true };
    const text = await bodyText(page);
    for (const [pattern, detail] of PREVIEW_OUTCOMES) if (pattern.test(text)) return { ok: false, detail };
    // A seat its own account left behind: "Switch here" can come up again after the first press.
    await clickIf(page, /^switch here$/i);
    await sleep(2000);
  }
  return { ok: false, detail: 'not_admitted' };
}

/** The bot's line in the meeting's chat: open the panel, type, Enter, close. A meeting with chat turned off is let be. */
export async function announce(page, text, log = () => {}) {
  if (!text) return;
  try {
    await revealTray(page);
    const chat = page.getByRole('button', { name: /chat with everyone|open chat|^chat$/i }).first();
    await chat.click({ timeout: 5000 });
    const box = page.getByRole('textbox', { name: /send a message/i }).first();
    await box.waitFor({ state: 'visible', timeout: 8000 });
    await box.click({ timeout: 3000 });
    await page.keyboard.type(text, { delay: 15 });
    await page.keyboard.press('Enter');
    await sleep(800);
    await chat.click({ timeout: 5000 }).catch(() => clickIf(page, /^close$/i));
    log('announced');
  } catch {
    log('announce_skipped');
    await page.keyboard.press('Escape').catch(() => {});
  }
}

/** Meet's captions on: the button when it shows, else the "c" shortcut (with nothing focused, so the c is not typed). */
export async function captionsOn(page) {
  if (await clickIf(page, /turn on captions/i)) return;
  await page.evaluate(() => document.activeElement && document.activeElement.blur && document.activeElement.blur()).catch(() => {});
  await page.keyboard.press('c').catch(() => {});
}

export async function captionBlocks(page) {
  return page.evaluate(readCaptions).catch(() => null);
}

/** The people in the call, the bot counted, and where the number was read: `{ count, from: 'button' | 'tiles' }`,
 * or null where the page would not say. */
export async function people(page) {
  return page.evaluate(readPeople).catch(() => null);
}

/**
 * The recorder: every 5-second slice of Opus/WebM appended to `file` as it arrives, so a crash loses at most one.
 * Returns whether capture started.
 */
export async function startRecording(page, file) {
  await page.exposeFunction('__ghostChunk', (b64) => appendFileSync(file, Buffer.from(b64, 'base64')));
  await page.evaluate(() => window.__ghostStart());
}

export async function soundLevel(page) {
  return page.evaluate(() => window.__ghostLevel && window.__ghostLevel()).catch(() => null);
}

/** Stops the recorder and waits (up to 20 s) for the last slice to be on disk. */
export async function stopRecording(page) {
  await Promise.race([page.evaluate(() => window.__ghostStop && window.__ghostStop()).catch(() => {}), sleep(20_000)]);
}

/**
 * Why the call is over for the bot, or null while it is still in it. Only once the Leave button is gone: the page's
 * text alone is not trusted while the bot is in the call, because the captions and the chat are on the page too, and
 * anyone can say "the meeting has ended". `state.goneFor` counts consecutive reads with no Leave button; three is over
 * even without a text that says so.
 */
export async function endedReason(page, state) {
  if (page.isClosed()) return 'meeting_ended';
  const there = (await page.getByRole('button', { name: LEAVE_BUTTON }).count().catch(() => 0)) > 0;
  state.goneFor = there ? 0 : (state.goneFor ?? 0) + 1;
  if (there) return null;
  const text = await bodyText(page);
  for (const [pattern, detail] of ENDED) if (pattern.test(text)) return detail;
  return state.goneFor >= 3 ? 'meeting_ended' : null;
}

/** Meet shows its tray when the pointer moves. */
async function revealTray(page) {
  await page.mouse.move(640, 500).catch(() => {});
  await page.mouse.move(640, 700).catch(() => {});
  await sleep(400);
}

/** Leaves the call: the Leave button, revealed first, and forced if Meet still has it hidden. */
export async function leaveCall(page) {
  if (page.isClosed()) return;
  await revealTray(page);
  const leave = page.getByRole('button', { name: LEAVE_BUTTON }).first();
  await leave.click({ timeout: 5000 }).catch(() => leave.click({ force: true, timeout: 3000 }).catch(() => {}));
  await sleep(1500);
}

/** Whether the profile is signed in to Google: myaccount.google.com, and where it ends up. */
export async function signedIn(page) {
  await page.goto('https://myaccount.google.com/', { waitUntil: 'domcontentloaded', timeout: 60_000 });
  await page.waitForLoadState('load', { timeout: 20_000 }).catch(() => {});
  await sleep(2000);
  const where = new URL(page.url());
  if (where.hostname !== 'myaccount.google.com' || where.pathname.startsWith('/intro')) return false;
  return !(await page.getByRole('link', { name: /^sign in$/i }).first().isVisible().catch(() => false));
}
