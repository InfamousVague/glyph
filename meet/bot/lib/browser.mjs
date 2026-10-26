/**
 * The bot's Chrome and its recorder, the same whichever service the meeting is on (Google Meet, lib/meet.mjs; Zoom,
 * lib/zoom.mjs): the profile opened with no automation markers (chrome.mjs), the tab's own sound captured into a
 * MediaRecorder and appended to a file as it comes, and the few page helpers both services' drivers press buttons with.
 * Moved here from meet.mjs when Zoom came (Matt, 2026-10-26: "While you're at it also consider zoom meetings"), so
 * that a meeting is recorded one way, wherever it is.
 */
import { appendFileSync } from 'node:fs';
import { chromium } from 'playwright-core';
import { botLaunchOptions } from './chrome.mjs';

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Runs in the page before the service's does: no navigator.webdriver, and the recorder (tab capture into a MediaRecorder). */
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

export async function openBrowser(profile) {
  const context = await chromium.launchPersistentContext(profile, botLaunchOptions());
  await context.addInitScript(pageScript);
  const page = context.pages()[0] ?? (await context.newPage());
  return { context, page };
}

/** A visible element of `role` whose accessible name matches, clicked; whether there was one. */
export async function clickIf(page, name, role = 'button') {
  const button = page.getByRole(role, { name }).first();
  if (!(await button.isVisible().catch(() => false))) return false;
  await button.click({ timeout: 5000 }).catch(() => {});
  return true;
}

/** How many buttons the page shows, for the log where a lobby was not as expected (no names: a button can carry a person's). */
export async function lobbyButtons(page) {
  return page
    .evaluate(() =>
      [...document.querySelectorAll('button,[role=button]')]
        .filter((b) => b.offsetParent !== null)
        .length,
    )
    .catch(() => null);
}

export async function bodyText(page) {
  return page.locator('body').innerText({ timeout: 5000 }).catch(() => '');
}

/** The page's host, for the log; never its path or query, which hold a meeting's id and passcode. */
export function hostOf(page) {
  try {
    return new URL(page.url()).hostname;
  } catch {
    return '';
  }
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
