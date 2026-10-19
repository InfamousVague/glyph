// A spike for GHST-106: one Chrome joining a Google Meet as a guest. Roles: `bot` (records the call's audio from the
// remote WebRTC tracks and reads Meet's captions) or `speaker` (its microphone is a WAV file, played on a loop).
//   node join.mjs <meet-url> <role> <name> <seconds> [wav]
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { appendFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [url, role, name, secondsText, wav] = process.argv.slice(2);
const seconds = Number(secondsText || 120);
const here = new URL('.', import.meta.url).pathname;
const tag = name.replace(/\W+/g, '-').toLowerCase();
const log = (...a) => { const line = `${new Date().toISOString()} [${name}] ${a.join(' ')}`; console.log(line); appendFileSync(join(here, `${tag}.log`), line + '\n'); };
const audioFile = wav ? join(here, wav) : join(here, 'silence.wav');

// PROFILE: a Chrome profile signed in to Ghost's Google account; without it, a throwaway one (an anonymous guest).
const profile = process.env.PROFILE || mkdtempSync(join(tmpdir(), 'meet-'));
const context = await chromium.launchPersistentContext(profile, {
  channel: 'chrome',
  headless: false,
  viewport: { width: 1000, height: 700 },
  // The speaker's microphone is a file; the bot has no microphone or camera at all (never this Mac's), and hears the
  // meeting by capturing its own tab.
  args: [
    ...(role === 'bot' ? [] : ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-audio-capture=${audioFile}`]),
    '--autoplay-policy=no-user-gesture-required', '--window-size=1000,780', '--disable-blink-features=AutomationControlled',
    '--disable-features=AudioServiceOutOfProcess,AudioServiceSandbox', '--auto-accept-this-tab-capture',
  ],
  permissions: role === 'bot' ? [] : ['microphone', 'camera'],
  // Meet turns an automated browser away ("You can't join this video call"): no automation banner, no
  // navigator.webdriver.
  // And the real keychain, not Playwright's mock one: a profile signed in by hand keeps its cookies sealed with it.
  ignoreDefaultArgs: ['--enable-automation', '--no-sandbox', '--use-mock-keychain', '--password-store=basic'],
  chromiumSandbox: true,
});
const page = context.pages()[0] ?? (await context.newPage());
await context.addInitScript(() => Object.defineProperty(navigator, 'webdriver', { get: () => undefined }));

const out = join(here, `${tag}.webm`), captionsOut = join(here, `${tag}.captions.jsonl`);
if (role === 'bot') {
  writeFileSync(out, Buffer.alloc(0));
  writeFileSync(captionsOut, '');
  await page.exposeFunction('__ghostChunk', (b64) => appendFileSync(out, Buffer.from(b64, 'base64')));
  await page.exposeFunction('__ghostLog', (text) => log(text));
  await page.addInitScript(() => {
    const Original = window.RTCPeerConnection;
    const box = { ctx: null, dest: null, rec: null, seen: new Set() };
    const ensure = () => {
      if (box.ctx) return;
      box.ctx = new AudioContext({ sampleRate: 48000 });
      box.dest = box.ctx.createMediaStreamDestination();
      box.rec = new MediaRecorder(box.dest.stream, { mimeType: 'audio/webm;codecs=opus' });
      box.rec.ondataavailable = async (e) => {
        if (!e.data.size) return;
        const bytes = new Uint8Array(await e.data.arrayBuffer());
        let s = '';
        for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
        window.__ghostChunk(btoa(s));
      };
      box.rec.start(5000);
      const meter = box.ctx.createAnalyser(); meter.fftSize = 2048;
      box.meter = meter;
      window.__ghostLog('recorder started, context ' + box.ctx.state);
      box.ctx.resume().then(() => window.__ghostLog('context ' + box.ctx.state));
      const buf = new Float32Array(2048);
      setInterval(() => { meter.getFloatTimeDomainData(buf); let sum = 0; for (const v of buf) sum += v * v; window.__ghostLog('level ' + (20 * Math.log10(Math.sqrt(sum / buf.length) + 1e-9)).toFixed(1) + ' dB, context ' + box.ctx.state); }, 5000);
    };
    // Meet plays each of its audio streams through an <audio> element: those streams, fed in as they appear.
    box.fromElements = new Set();
    window.__ghostScan = () => {
      const found = [];
      for (const el of document.querySelectorAll('audio, video')) {
        const stream = el.srcObject;
        if (!stream || !stream.getAudioTracks().length || box.fromElements.has(stream.id)) continue;
        box.fromElements.add(stream.id);
        ensure();
        const source = box.ctx.createMediaStreamSource(stream);
        source.connect(box.dest);
        source.connect(box.meter);
        found.push(el.tagName + ' ' + stream.getAudioTracks().map((t) => t.id.slice(0, 8) + (t.muted ? ' muted' : '') + ' ' + t.readyState).join(','));
      }
      return { found, elements: document.querySelectorAll('audio').length };
    };
    // The whole tab's sound, as the person at this seat would hear it: the meeting's mix.
    window.__ghostTab = async () => {
      const stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: { suppressLocalAudioPlayback: false }, preferCurrentTab: true, selfBrowserSurface: 'include', systemAudio: 'exclude' });
      ensure();
      const source = box.ctx.createMediaStreamSource(new MediaStream(stream.getAudioTracks()));
      source.connect(box.dest);
      source.connect(box.meter);
      stream.getVideoTracks().forEach((t) => t.stop());
      return stream.getAudioTracks().map((t) => t.label + ' ' + t.readyState);
    };
    window.__ghostStop = () => new Promise((done) => { if (!box.rec) return done(); box.rec.onstop = () => setTimeout(done, 300); box.rec.stop(); });
    function Patched(...args) {
      const pc = new Original(...args);
      pc.addEventListener('track', (ev) => {
        if (ev.track.kind !== 'audio' || box.seen.has(ev.track.id)) return;
        box.seen.add(ev.track.id);
        ensure();
        const source = box.ctx.createMediaStreamSource(new MediaStream([ev.track]));
        // (Not fed: the tracks as the connection hands them over were silent in the spike.)
        // Chrome feeds a remote WebRTC track to Web Audio only while the track also plays in a media element.
        const el = new Audio(); el.muted = true; el.srcObject = new MediaStream([ev.track]); el.play().catch(() => {});
        window.__ghostLog(`audio track ${box.seen.size} (${ev.track.id.slice(0, 8)})`);
      });
      return pc;
    }
    Patched.prototype = Original.prototype;
    Object.setPrototypeOf(Patched, Original);
    window.RTCPeerConnection = Patched;
  });
}

log('opening', url);
await page.goto(url, { waitUntil: 'domcontentloaded' });
const clickIf = async (label) => { const b = page.getByRole('button', { name: label }).first(); if (await b.isVisible().catch(() => false)) { await b.click().catch(() => {}); return true; } return false; };
// The preview: the name, the camera off (and the microphone too, for the bot), then ask to join.
const nameBox = page.getByRole('textbox', { name: /your name/i });
await nameBox.waitFor({ timeout: 45000 }).catch(() => log('no name box'));
if (await nameBox.isVisible().catch(() => false)) { await nameBox.click(); await page.keyboard.type(name, { delay: 90 }); }
await page.waitForTimeout(1500);
await clickIf(/continue without microphone and camera/i);
await clickIf(/turn off camera/i);
if (role === 'bot') await clickIf(/turn off microphone/i);
await page.waitForTimeout(2500);
let asked = false;
// The bot takes over a seat its own account left behind ("Switch here"); a second window of the same account joins
// beside it ("Other ways to join" › "Join here too").
const labels = role === 'bot' ? [/ask to join/i, /join now/i, /switch here/i] : [/ask to join/i, /join now/i];
for (const label of labels) { if (await clickIf(label)) { asked = true; log('pressed', String(label)); break; } }
await clickIf(/^got it$/i);
if (!asked && (await clickIf(/other ways to join/i))) {
  await page.waitForTimeout(1200);
  const items = await page.locator('[role="menuitem"], [role="option"], li, [role="menu"] *').allInnerTexts().catch(() => []);
  log('other ways:', items.map((t) => t.replace(/\s+/g, ' ').trim()).filter((t) => t && t.length < 60).slice(0, 12).join(' | '));
  const here = page.getByText(/join here too/i).first();
  if (await here.isVisible().catch(() => false)) { await here.click(); asked = true; log('pressed join here too'); }
}
if (!asked) log('buttons:', (await page.getByRole('button').allInnerTexts().catch(() => [])).map((t) => t.replace(/\s+/g, ' ').trim()).filter(Boolean).join(' | ').slice(0, 400));
log(asked ? 'asked to join' : 'found no join button');
await page.waitForTimeout(6000);
await page.screenshot({ path: join(here, `${tag}-preview.png`) });
log('after asking:', (await page.locator('body').innerText().catch(() => '')).replace(/\s+/g, ' ').slice(0, 200));

// Admitted when the Leave call button is there.
const leave = page.getByRole('button', { name: /leave call/i });
try {
  // In the call when the Leave button exists: Meet hides its tray of controls until the pointer moves, so attached,
  // not visible.
  await leave.waitFor({ state: 'attached', timeout: 5 * 60 * 1000 });
} catch {
  log('not admitted within five minutes');
  await page.screenshot({ path: join(here, `${tag}-waiting.png`) });
  await context.close();
  process.exit(2);
}
log('admitted');
await page.waitForTimeout(2000);

if (role === 'bot') {
  if (!(await clickIf(/turn on captions/i))) await page.keyboard.press('c');
  log('captions asked for');
  await page.mouse.click(500, 300);
  log('tab capture:', JSON.stringify(await page.evaluate(() => window.__ghostTab()).catch((e) => 'failed: ' + e)));
  const scan = setInterval(async () => { const r = await page.evaluate(() => window.__ghostScan()).catch((e) => ({ error: String(e) })); if (r.error || r.found?.length) log('scan', JSON.stringify(r)); }, 3000);
  // Meet's captions, read twice a second: the region's lines as they stand, with when.
  const started = Date.now();
  const timer = setInterval(async () => {
    const lines = await page.evaluate(() => {
      const region = document.querySelector('[role="region"][aria-label*="aption" i]');
      return region ? region.innerText : null;
    }).catch(() => null);
    if (lines) appendFileSync(captionsOut, JSON.stringify({ at: Date.now() - started, text: lines }) + '\n');
  }, 500);
  await page.waitForTimeout(seconds * 1000);
  clearInterval(timer);
  clearInterval(scan);
  await page.screenshot({ path: join(here, `${tag}-in-call.png`) });
  await page.evaluate(() => window.__ghostStop()).catch(() => {});
} else {
  const level = await page.evaluate(async () => {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const ctx = new AudioContext(); await ctx.resume();
    const a = ctx.createAnalyser(); a.fftSize = 2048; ctx.createMediaStreamSource(stream).connect(a);
    const buf = new Float32Array(2048); let peak = -200;
    for (let i = 0; i < 40; i++) { await new Promise((r) => setTimeout(r, 250)); a.getFloatTimeDomainData(buf); let s = 0; for (const v of buf) s += v * v; peak = Math.max(peak, 20 * Math.log10(Math.sqrt(s / buf.length) + 1e-9)); }
    stream.getTracks().forEach((t) => t.stop());
    return { peak, label: stream.getAudioTracks()[0]?.label };
  }).catch((e) => ({ error: String(e) }));
  log('own microphone over 10 s:', JSON.stringify(level));
  const muted = await page.getByRole('button', { name: /turn on microphone/i }).first().isVisible().catch(() => false);
  log('microphone muted in the call:', muted);
  if (muted) { await clickIf(/turn on microphone/i); log('turned the microphone on'); }
  await page.waitForTimeout(seconds * 1000);
}
await page.mouse.move(500, 600);
await page.waitForTimeout(400);
await leave.click({ timeout: 5000 }).catch(() => page.keyboard.press('Control+Meta+KeyQ').catch(() => {}));
log('left');
await page.waitForTimeout(1500);
await context.close();
