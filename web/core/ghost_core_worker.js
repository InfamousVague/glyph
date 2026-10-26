// The worker that owns Ghost.md's core in a browser: the page's ghost_worker.dart (lib/core/native), with a Web
// Worker where the phone has an isolate. lib/core/native/web_core.dart is its other end.
//
// **One at a time, in the order asked**, as the phone's worker answers: a message is a command, run to its end
// and answered before the next is read. So a 600,000-round sign-in is made here, off the page that draws, and the
// page is never still while it runs.
//
// What crosses (structured clone, strings only, so nothing is copied twice):
//
// - to the worker: `{id, command, args}`, `args` the command's arguments already written as JSON;
// - from the worker, once: `{ready: true}`, or `{failed: "why"}` when the core would not open;
// - from the worker, per command: `{id, answer}`, `answer` the core's own JSON text, `{"ok": …}` or `{"err": "…"}`.
//
// A trap (a panic in Rust: wasm32 aborts) is answered as an `err` and a fresh core is opened from the module
// already compiled, so the next command is answered too. The keys and documents the old one held are gone with
// it, which the app reads as it reads a key that is not held any more.
'use strict';

importScripts('ghost_core_wasi.js');

let module = null;
let core = null;

async function start() {
  try {
    const response = await fetch('ghost_core_web.wasm');
    if (!response.ok) throw new Error('ghost_core_web.wasm answered ' + response.status);
    module = await GhostCoreWasm.compile(await response.arrayBuffer());
    core = await GhostCoreWasm.open(module);
    self.postMessage({ ready: true });
  } catch (failure) {
    self.postMessage({ failed: String(failure && failure.message ? failure.message : failure) });
  }
}

const started = start();
let queue = Promise.resolve();

self.onmessage = (event) => {
  const { id, command, args } = event.data || {};
  queue = queue.then(async () => {
    await started;
    if (core === null) {
      self.postMessage({ id, answer: JSON.stringify({ err: 'Ghost.md\'s core could not be loaded in this browser.' }) });
      return;
    }
    let answer;
    try {
      answer = core.invoke(command, args);
    } catch (trap) {
      answer = JSON.stringify({ err: 'Ghost.md\'s core stopped in the middle of that: ' + (trap && trap.message ? trap.message : trap) });
      try {
        core = await GhostCoreWasm.open(module);
      } catch (_) {
        core = null;
      }
    }
    self.postMessage({ id, answer });
  });
};
