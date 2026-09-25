#!/usr/bin/env node
/**
 * Run a JavaScript expression inside Glyph's WebView on the Fold, and print what
 * comes back.
 *
 * The capture pipeline cannot be verified by eye: a person would have to hold
 * the phone and speak while someone else read the logs. But a debug build of a
 * Tauri Android app exposes its WebView over Chrome's remote debugging socket,
 * and adb can forward that socket to this Mac. From there the DevTools protocol
 * can evaluate `window.__TAURI_INTERNALS__.invoke(...)` in the real page, which
 * reaches the real Rust commands on the real phone - so Whisper's speed on this
 * exact chip can be measured with a WAV pushed to the device and no voice at all.
 *
 * Debug builds only. A release build turns WebView debugging off, which is right.
 *
 * Usage:
 *   node scripts/fold-eval.mjs "await window.__TAURI_INTERNALS__.invoke('capture_model_status')"
 *
 * The expression runs as the body of an async function, so `await` works and the
 * value of the final `return` (or the expression itself) is printed as JSON.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { ROOT } from './lib/paths.mjs';

const ADB = join(process.env.ANDROID_HOME ?? join(homedir(), 'Library/Android/sdk'), 'platform-tools/adb');
const APP_ID = 'com.mattssoftware.glyph';
const LOCAL_PORT = 9234;

const expression = process.argv.slice(2).join(' ');
if (!expression) {
  console.error('usage: node scripts/fold-eval.mjs "<expression>"');
  process.exit(2);
}

// The push script remembers the last address that worked; reuse it.
let device;
try {
  device = readFileSync(join(ROOT, 'node_modules', '.glyph-fold'), 'utf8').trim();
} catch {
  console.error('no remembered phone; run `npm run push:fold` once first');
  process.exit(1);
}
const adb = (...args) => execFileSync(ADB, ['-s', device, ...args], { encoding: 'utf8' }).trim();

const pid = adb('shell', 'pidof', APP_ID);
if (!pid) {
  console.error(`${APP_ID} is not running on the phone`);
  process.exit(1);
}

/*
 * THAW FIRST. Android freezes a backgrounded app's process outright (the cached
 * apps freezer), and a frozen process accepts the debugger's TCP connection and
 * then never answers - the first version of this script simply hung, and
 * `dumpsys activity processes` showed `isFrozen=true`. `unfreeze --sticky`
 * holds it awake without bringing it to the front, so nothing appears on the
 * phone's screen. `--sticky` because a Whisper run can outlast the freezer's
 * re-freeze delay. When it was frozen to begin with, a plain `freeze` at the end
 * hands it back to the system in the state it started; one that was already
 * awake is left alone.
 */
const wasFrozen = adb('shell', 'am', 'isfrozen', APP_ID) === 'true';
adb('shell', 'am', 'unfreeze', '--sticky', APP_ID);
const restore = () => {
  if (!wasFrozen) return;
  try {
    adb('shell', 'am', 'freeze', APP_ID);
  } catch {
    // The process may have exited; there is nothing left to hand back.
  }
};
process.on('exit', restore);

// Each WebView process publishes an abstract socket named after its pid.
adb('forward', `tcp:${LOCAL_PORT}`, `localabstract:webview_devtools_remote_${pid}`);

/*
 * A backgrounded Glyph does not answer even once thawed: the activity pauses its
 * WebView when it leaves the screen, and a paused WebView's debugger accepts the
 * connection and serves nothing (measured on the Fold, 2026-09-12). Only the
 * foreground case is supported, and the failure says so instead of hanging.
 */
let pages;
try {
  pages = await (await fetch(`http://127.0.0.1:${LOCAL_PORT}/json`, { signal: AbortSignal.timeout(10_000) })).json();
} catch {
  console.error('the WebView did not answer. Is Glyph on screen? A backgrounded WebView is paused and serves nothing.');
  process.exit(1);
}
const page = pages.find((p) => p.type === 'page');
if (!page) {
  console.error('the WebView exposes no page to debug (is this a release build?)');
  process.exit(1);
}

const socket = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});

const wrapped = `(async () => { ${/\breturn\b/.test(expression) ? expression : `return (${expression});`} })()`;
socket.send(
  JSON.stringify({
    id: 1,
    method: 'Runtime.evaluate',
    params: { expression: wrapped, awaitPromise: true, returnByValue: true },
  }),
);

const reply = await new Promise((resolve) => {
  socket.onmessage = (event) => {
    const message = JSON.parse(String(event.data));
    if (message.id === 1) resolve(message);
  };
});
socket.close();

const { result, exceptionDetails } = reply.result ?? {};
if (exceptionDetails) {
  // Tauri's invoke rejects with a plain STRING, not an Error, and a string has
  // no `description` - so the first version printed only "Uncaught (in
  // promise)" for every failed command, hiding the one line that mattered.
  const thrown = exceptionDetails.exception;
  console.error('threw:', thrown?.description ?? (thrown && 'value' in thrown ? JSON.stringify(thrown.value) : exceptionDetails.text));
  process.exit(1);
}
console.log(JSON.stringify(result?.value, null, 2));
