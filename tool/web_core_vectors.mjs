// The browser's core (native/web, web/core/ghost_core_wasi.js) held to what the web app sealed and what the phone's
// library does: native/tests/fixtures/crypto_web.json, the fixture native/tests/crypto_vectors.rs holds the
// phone's library to, opened here through the very script and WebAssembly the page runs, in Node.
//
//   node tool/web_core_vectors.mjs          after tool/build-web-core.sh
//
// So a password derived in the page is the phone's login half and wrap key at the real 600,000 rounds, a blob the
// web sealed opens in its context and in no other, an organization's key arrives through the account's pair, and
// a note made in the page is named as the phone's library would name its file.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert/strict';
import vm from 'node:vm';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const scope = { console, crypto: globalThis.crypto, performance: globalThis.performance, TextEncoder, TextDecoder, WebAssembly, Proxy, BigInt, Date, Math, Error, Uint8Array, DataView };
scope.self = scope;
vm.runInNewContext(readFileSync(join(root, 'web/core/ghost_core_wasi.js'), 'utf8'), scope);
const wasm = readFileSync(join(root, 'web/core/ghost_core_web.wasm'));
const core = await scope.GhostCoreWasm.open(await WebAssembly.compile(wasm));

function said(command, args) {
  return JSON.parse(core.invoke(command, args === undefined ? '' : JSON.stringify(args)));
}
function ask(command, args) {
  const answer = said(command, args);
  if ('err' in answer) throw new Error(`${command}: ${answer.err}`);
  return answer.ok;
}
function refused(command, args) {
  const answer = said(command, args);
  assert.ok('err' in answer, `${command} should have refused`);
  return answer.err;
}

const NOT_OPENED = 'That could not be opened: it was sealed with another key, or for something else, or it has been changed.';
const web = JSON.parse(readFileSync(join(root, 'native/tests/fixtures/crypto_web.json'), 'utf8'));
let checks = 0;
const check = (name, run) => {
  const began = Date.now();
  run();
  checks += 1;
  console.log(`ok  ${name} (${Date.now() - began} ms)`);
};

check('ids are the library\'s', () => {
  const id = ask('new_id');
  assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

check('handles are salted and codes normalised as the web does it', () => {
  for (const one of web.salts) assert.equal(ask('salt', { handle: one.handle, kind: one.kind }), one.salt);
  for (const one of web.codes) assert.equal(ask('normalise_code', { code: one.typed }), one.normalised);
});

const note = web.sealed[0];
check('a secret derives to the web\'s login half and wrap key at the real rounds', () => {
  for (const one of web.derive) {
    const derived = ask('derive', { secret: one.secret, salt: one.salt });
    assert.equal(derived.login, one.login, one.salt);
    const key = ask('account_key_unwrap', { wrapped: one.wrapped, wrapKey: derived.wrapKey });
    assert.deepEqual(ask('open', { key: key.key, context: note.context, blob: note.blob }), note.value);
  }
});

const account = ask('key_restore', { kind: 'account', raw: web.accountKey }).key;
const pair = ask('pair_open', { sealed: web.pair.sealed, accountKey: account });
const org = ask('org_key_unwrap', { pair: pair.key, wrapped: web.org.wrapped, context: web.org.context }).key;

check('every blob the web sealed opens in its own context and in no other', () => {
  assert.equal(pair.public, web.pair.public);
  for (const one of web.sealed) {
    const [key, other] = one.key === 'org' ? [org, account] : [account, org];
    const opened = ask('open', { key, context: one.context, blob: one.blob, as: one.as });
    assert.deepEqual(opened, one[one.as], one.context);
    assert.equal(refused('open', { key: other, context: one.context, blob: one.blob, as: one.as }), NOT_OPENED);
    assert.equal(refused('open', { key, context: `${one.context}x`, blob: one.blob, as: one.as }), NOT_OPENED);
  }
});

check('what the page seals the web\'s keys open again', () => {
  const sealed = ask('seal', { key: account, context: 'note:web', value: { v: 1, words: 'día ✓ 😀' } });
  assert.deepEqual(ask('open', { key: account, context: 'note:web', blob: sealed }), { v: 1, words: 'día ✓ 😀' });
});

check('a file\'s digest is the web\'s', () => {
  for (const one of web.sha) assert.equal(ask('sha256_16', { data: one.data }), one.sha);
});

check('a device key signs as the web\'s', () => {
  const device = ask('key_restore', { kind: 'device', raw: web.device.seed });
  assert.equal(device.public, web.device.public);
  for (const one of web.device.signed) assert.equal(ask('device_key_sign', { key: device.key, nonce: one.nonce }), one.signature);
});

check('a team document opens, takes an edit and gives its words back', () => {
  const doc = ask('crdt_open', { words: '# Plan\n', clientId: 7 });
  const edit = ask('crdt_edit', { doc: doc.doc, edits: [{ index: 7, insert: 'Day one 😀' }] });
  assert.equal(edit.text, '# Plan\nDay one 😀');
  const again = ask('crdt_open', { state: ask('crdt_state', { doc: doc.doc }), clientId: 8 });
  assert.equal(ask('crdt_text', { doc: again.doc }), '# Plan\nDay one 😀');
  ask('crdt_undo_open', { doc: doc.doc });
  const room = ask('awareness_open', { clientId: 7 });
  ask('awareness_set', { awareness: room.awareness, state: { user: { name: 'Matt' } } });
  assert.equal(ask('awareness_states', { awareness: room.awareness }).length, 1);
});

check('a note made in the page is named as the phone\'s library names its file', () => {
  assert.equal(ask('note_path', { body: '# Weekend trip\n\nBook the cabin.', taken: [] }), 'Inbox/Weekend trip.md');
  assert.equal(ask('note_path', { body: '# Weekend trip\n', taken: ['Inbox/Weekend trip.md'] }), 'Inbox/Weekend trip 2.md');
  assert.equal(ask('note_path', { body: '', taken: [] }), 'Inbox/Untitled.md');
  assert.equal(ask('note_path', { body: '# A/B: plan?\n', taken: [] }), 'Inbox/AB plan.md');
  // A title that changed is followed, in the folder the note is in; one that did not keeps its name.
  assert.equal(ask('note_path', { body: '# Renamed\n', path: 'Work/Old.md', taken: [] }), 'Work/Renamed.md');
  assert.equal(ask('note_path', { body: '# Old\n', path: 'Work/Old 2.md', taken: ['Work/Old.md'] }), 'Work/Old 2.md');
  // Another device's folder is taken while it is free.
  assert.equal(ask('note_path', { body: '# Trip\n', wanted: 'Travel/Trip.md', taken: [] }), 'Travel/Trip.md');
  assert.equal(ask('note_path', { body: '# Trip\n', path: 'Inbox/Trip.md', wanted: 'Travel/Trip.md', taken: [] }), 'Travel/Trip.md');
  assert.equal(ask('note_path', { body: '# Trip\n', wanted: '../Trip.md', taken: [] }), 'Inbox/Trip.md');
  // A team note arrives at its organization folder's own path, named as the other device named it.
  assert.equal(ask('note_path', { body: '# Plan\n', wanted: 'orgs/Ghost/Clients/n1.md', taken: [] }), 'orgs/Ghost/Clients/n1.md');
  // Where that path is another note's here, it is the title's name in that folder.
  assert.equal(ask('note_path', { body: '# Plan\n', wanted: 'orgs/Ghost/Clients/n1.md', taken: ['orgs/Ghost/Clients/n1.md'] }), 'orgs/Ghost/Clients/Plan.md');
});

check('a command it has not is refused, not a trap', () => {
  assert.match(refused('list_notes', {}), /in the browser has no command named list_notes/);
  assert.match(refused('seal_file', { key: account, context: 'x', path: '/a', out: '/b' }), /./);
});

console.log(`${checks} checks, the browser's core agrees with the web app and the phone's library`);
