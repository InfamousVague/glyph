#!/usr/bin/env node
/**
 * Measure live transcription ON THE FOLD, with a recording instead of a voice.
 *
 * The question this answers is the one no desktop number can: does Whisper keep
 * up with speech on this phone's CPU? On the M5 the streaming path ran at about
 * 1.8x real time; the Fold is slower, and if it falls below 1.0x the words lag
 * further behind the speaker every second. So the fixture WAV is replayed
 * through exactly the path a voice takes - `capture_start`, 200 ms of samples
 * per `capture_push`, paced at REAL speed, each push awaited because wry on
 * Android can run two in-flight IPC requests out of order - while every
 * `capture://` event is timestamped.
 *
 * Reported: when each committed phrase arrived relative to when its audio
 * ended (the lag Matt would feel), how many partials there were, how long
 * `capture_stop` took to flush, and the committed text, so accuracy on the
 * phone can be read alongside speed.
 *
 * Requires Glyph ON SCREEN on the phone (see fold-eval.mjs for why) and the
 * model downloaded. Usage:
 *   node scripts/fold-bench.mjs [models/fixture.wav]
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT } from './lib/paths.mjs';

const wavPath = process.argv[2] ?? join(ROOT, 'models', 'fixture.wav');
const wav = readFileSync(wavPath);

// Find the PCM `data` chunk rather than assuming a 44-byte header; macOS writes
// extra chunks, and a wrong offset replays the header as a burst of noise.
let offset = 12;
let pcm = null;
while (offset + 8 <= wav.length) {
  const id = wav.toString('ascii', offset, offset + 4);
  const size = wav.readUInt32LE(offset + 4);
  if (id === 'data') {
    pcm = wav.subarray(offset + 8, offset + 8 + size);
    break;
  }
  offset += 8 + size + (size % 2);
}
if (!pcm) throw new Error(`${wavPath} has no data chunk`);

const expression = `
// Never on top of a real capture. The engine runs one capture at a time and a
// new capture_start cancels the running one, so benchmarking while Matt is
// dictating would silently throw his note away.
if (document.querySelector('[data-phase]')) return { skipped: 'a capture is on screen' };

const b64 = ${JSON.stringify(pcm.toString('base64'))};
const raw = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
const view = new DataView(raw.buffer);
const samples = new Float32Array(raw.length / 2);
for (let i = 0; i < samples.length; i += 1) samples[i] = view.getInt16(i * 2, true) / 32768;

const T = window.__TAURI_INTERNALS__;
const events = [];
const t0 = performance.now();
const handlers = [];
for (const name of ['capture://partial', 'capture://segment', 'capture://error']) {
  const handler = T.transformCallback((event) => events.push({ name, at: performance.now() - t0, payload: event.payload }));
  handlers.push({ name, id: await T.invoke('plugin:event|listen', { event: name, target: { kind: 'Any' }, handler }) });
}

const loadStart = performance.now();
await T.invoke('capture_start');
const startMs = performance.now() - loadStart;

const CHUNK = 3200;
const streamStart = performance.now();
for (let i = 0; i < samples.length; i += CHUNK) {
  const chunk = samples.slice(i, i + CHUNK);
  // The same envelope the app sends: base64 in JSON, because Android's bridge
  // cannot carry raw bytes (see toBase64 in src/app/capture/engine.ts).
  const bytes = new Uint8Array(chunk.buffer);
  let binary = '';
  for (let j = 0; j < bytes.length; j += 0x8000) binary += String.fromCharCode(...bytes.subarray(j, j + 0x8000));
  await T.invoke('capture_push', { pcm: btoa(binary) });
  // Real-time pacing: the next chunk is sent when its audio would have been spoken.
  const due = streamStart + ((i + CHUNK) / 16000) * 1000;
  const wait = due - performance.now();
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
}
const audioEnd = performance.now() - t0;
const stopStart = performance.now();
const transcript = await T.invoke('capture_stop');
const stopMs = performance.now() - stopStart;

for (const h of handlers) {
  try { await T.invoke('plugin:event|unlisten', { event: h.name, eventId: h.id }); } catch {}
}

const streamOffset = streamStart - t0;
const segments = events.filter((e) => e.name === 'capture://segment').map((e) => ({
  text: e.payload.text,
  audioEndMs: e.payload.endMs,
  lagMs: Math.round(e.at - streamOffset - e.payload.endMs),
}));
return {
  audioSeconds: +(samples.length / 16000).toFixed(2),
  captureStartMs: Math.round(startMs),
  partials: events.filter((e) => e.name === 'capture://partial' && e.payload.text).length,
  errors: events.filter((e) => e.name === 'capture://error').map((e) => e.payload.message),
  segments,
  maxLagMs: Math.max(0, ...segments.map((s) => s.lagMs)),
  stopFlushMs: Math.round(stopMs),
  totalSecondsAfterAudioEnded: +((performance.now() - t0 - audioEnd) / 1000).toFixed(2),
  transcript,
};
`;

// The expression carries half a megabyte of base64 audio, and a failed
// execFileSync puts the whole command line in its error - so on failure the
// child's own stderr is reported and the command is not.
try {
  const out = execFileSync(process.execPath, [join(ROOT, 'scripts', 'fold-eval.mjs'), expression], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 16 * 1024 * 1024,
  });
  process.stdout.write(out);
} catch (error) {
  process.stderr.write(String(error.stderr ?? 'fold-eval failed with no output\n'));
  process.exit(1);
}
