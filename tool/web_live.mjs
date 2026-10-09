#!/usr/bin/env node
// A WEB device in a live room, under Node, against the local server: the web app's own live code
// (../glyph/src/app/core/live: transport.ts, hub.ts, wire.ts, session.ts, team.ts, with its own Yjs, its own
// y-protocols awareness and its own WebCrypto) in the same note as a Dart device, typing at once. What
// test/live/web_test.dart drives; the proof that the Flutter app and the web app are one wire through one real
// relay, in both directions.
//
//   GHOST_E2E_API=http://127.0.0.1:<port>/api node --experimental-transform-types tool/web_live.mjs '<job as JSON>'
//
// The job: {handle, password, rounds, team: {note}} for a team's note (the device signs in, syncs the
// organizations' keys and their notes as tool/web_client.mjs does, and opens the note's room as the web's editor
// does: core/live/team.ts `openTeamRoom` over the document core/team/doc.ts holds), or {…, own: {note, words}}
// for a note of the account's own (core/live/session.ts over the relay's transport, as the web's own
// live.e2e.test.ts opens one). Then it reads commands from its stdin, one JSON object a line, and answers each
// with one JSON line:
//
//   {do: 'type', at, insert?, remove?}     what y-codemirror does with a key: the text changed in one transaction
//   {do: 'reconcile', words}               words that reach the note without the editor (core/team/doc.ts)
//   {do: 'cursor', anchor, head}           the caret said in the room's awareness, as y-codemirror says it
//   {do: 'canvas', set: {...}}             a team canvas changed through core/team/canvas.ts (see `canvas` below)
//   {do: 'words'}                          the document's words, and for a canvas its structure
//   {do: 'others'}                         everyone else in the room: name, hue, colours, caret as indexes here
//   {do: 'until', words? | name? | caret?, ms?}   waits for the words, a member, or a member's caret at an index
//   {do: 'sync'}                           one pass of the organization channel
//   {do: 'close'}                          leaves the room and ends
//
// THE FIRST RULE (docs/STAGE7.md): nothing here may reach ghostmarkdown.com. As in tool/web_client.mjs, this
// refuses to start unless GHOST_E2E_API is http://127.0.0.1:<port>/api, writes that base into the web's
// `import.meta.env` and checks `API_BASE` before a call, and replaces `fetch` and `WebSocket`, before any web code
// loads, by ones that throw for any host but 127.0.0.1.
//
// ../glyph is only READ: its TypeScript is loaded as it is, its node_modules give it `yjs` and `y-protocols`.
import { registerHooks } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath, pathToFileURL } from 'node:url';

const base = (process.env.GHOST_E2E_API ?? '').replace(/\/+$/, '');
if (!/^http:\/\/127\.0\.0\.1:\d+\/api$/.test(base)) {
  console.error(`web_live: GHOST_E2E_API must be http://127.0.0.1:<port>/api (tool/local-server.sh start); it is "${base}".`);
  process.exit(2);
}

const realFetch = globalThis.fetch;
globalThis.fetch = (input, init) => {
  const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url);
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1') throw new Error(`web_live: refused a request to ${url.host}: only 127.0.0.1 is ever asked.`);
  // The service lets an address in twenty times a minute, and every device of the suite is this Mac.
  const ask = async (tries) => {
    const answer = await realFetch(input, init);
    if (answer.status !== 429 || tries >= 8) return answer;
    await new Promise((done) => setTimeout(done, 3200));
    return ask(tries + 1);
  };
  return ask(0);
};
const RealSocket = globalThis.WebSocket;
const sockets = [];
globalThis.WebSocket = class extends RealSocket {
  constructor(address, ...rest) {
    const url = new URL(address);
    if (url.protocol !== 'ws:' || url.hostname !== '127.0.0.1') throw new Error(`web_live: refused a socket to ${url.host}: only 127.0.0.1 is ever asked.`);
    super(address, ...rest);
    sockets.push(url.href);
  }
};
globalThis.__GHOST_WEB_ENV = Object.freeze({ VITE_GLYPH_API: base, MODE: 'test', DEV: false, PROD: false });

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const glyph = resolve(root, '../glyph');
const web = join(glyph, 'src/app');
const webUrl = pathToFileURL(web).href;

registerHooks({
  load(url, context, nextLoad) {
    const loaded = nextLoad(url, context);
    if (!url.startsWith(webUrl) || loaded.source == null) return loaded;
    const source = typeof loaded.source === 'string' ? loaded.source : Buffer.from(loaded.source).toString('utf8');
    return { ...loaded, source: source.replaceAll('import.meta.env', 'globalThis.__GHOST_WEB_ENV') };
  },
});

const from = (path) => import(pathToFileURL(join(web, path)).href);
const api = await from('core/account/api.ts');
if (api.API_BASE !== base) {
  console.error(`web_live: the web's API_BASE is ${api.API_BASE}, not the local server. Nothing was asked.`);
  process.exit(2);
}
// The web's own Yjs, by the file its modules load, so there is one of it.
const Y = await import(pathToFileURL(join(glyph, 'node_modules/yjs/dist/yjs.mjs')).href);
const account = await from('core/account/account.ts');
const { memoryKeys } = await from('core/account/keystore.ts');
const { ensureEncryptionKey } = await from('core/account/encKey.ts');
const N = await from('core/sync/notes.ts');
const K = await from('core/orgs/orgKeys.ts');
const T = await from('core/team/sync.ts');
const D = await from('core/team/doc.ts');
const C = await from('core/team/canvas.ts');
const { memoryDocs } = await from('core/team/docs.ts');
const { liveUrl, WebSocketTransport } = await from('core/live/transport.ts');
const { LiveSession } = await from('core/live/session.ts');
const team = await from('core/live/team.ts');
const J = await from('canvas/jsonCanvas.ts');

const job = JSON.parse(process.argv[2] ?? '{}');
const say = (value) => process.stdout.write(`${JSON.stringify(value)}\n`);

const keys = memoryKeys();
await account.signIn(job.handle, job.password, { keys, rounds: job.rounds });
const session = account.accountState().session;
const token = session.token;
const accountKey = await keys.accountKey();

// ---- the device: its notes in maps, as tool/web_client.mjs keeps them ---------------------------------------

const notes = new Map();
const files = new Map();
const filed = new Map();
const local = {
  list: async () => [...notes.values()].map((n) => ({ ...n, segments: null, formatted: null })),
  get: async (id) => (notes.has(id) ? { ...notes.get(id) } : null),
  apply: async (note) => {
    notes.set(note.id, { ...note });
    return { ...note, segments: null, formatted: null };
  },
  remove: async (id) => void notes.delete(id),
};
const localFiles = {
  read: async (kind, name) => files.get(`${kind}/${name}`) ?? null,
  write: async (kind, name, bytes) => void files.set(`${kind}/${name}`, bytes),
  owed: () => [],
  settled: () => undefined,
};
let state = N.emptyState();
const teamStates = new Map();
const docs = memoryDocs();
let orgOf = null;

async function pass() {
  await N.syncNotes({ token, key: accountKey, notes: local, files: localFiles, state, save: (next) => (state = JSON.parse(JSON.stringify(next))), teamNote: (id) => filed.has(id) });
  const { orgs } = await api.call('GET', 'orgs', { token });
  const enc = await ensureEncryptionKey({ token, accountKey, keys });
  await K.syncOrgKeys({ token, pair: enc.pair, list: orgs });
  const outcomes = {};
  for (const row of orgs) {
    if (row.state !== 'member') continue;
    const key = K.orgKeyOf(row.id);
    if (!key) continue;
    outcomes[row.id] = await T.syncTeamNotes({
      token,
      orgId: row.id,
      key,
      generation: K.orgKeyGeneration(row.id),
      notes: local,
      files: localFiles,
      docs,
      state: teamStates.get(row.id) ?? T.emptyTeamState(),
      save: (next) => void teamStates.set(row.id, next),
      isTeamNote: (id) => filed.get(id) === row.id,
      file: (id) => void filed.set(id, row.id),
    });
  }
  return outcomes;
}

// ---- the room ------------------------------------------------------------------------------------------------

let doc = null; // a team note's TeamDoc
let room = null; // its TeamRoom
let own = null; // an account's own note: {session, transport}
let canvas = null;

if (job.team) {
  await pass();
  orgOf = filed.get(job.team.note);
  if (!orgOf) throw new Error(`the web device never received the team note ${job.team.note}`);
  doc = await D.teamDoc(job.team.note, docs, notes.get(job.team.note).body);
  // What editor/useTeamNote.ts does: the note's words reconciled into the document, then its room.
  doc.reconcile(notes.get(job.team.note).body);
  room = team.openTeamRoom(orgOf, job.team.note, doc);
  if (!room) throw new Error('the web device could not open the room: no organization key, or signed out');
  // The library's copy follows the document, as the channel's own listener keeps it on a page.
  doc.onWords((words) => notes.set(job.team.note, { ...notes.get(job.team.note), body: words, updatedAt: Date.now() }));
  if (job.team.canvas) {
    // canvas/useTeamCanvas.ts: the structure seeded from the words once the room has had its say.
    await room.caughtUp();
    canvas = C.teamCanvas(doc);
  }
} else if (job.own) {
  let shown;
  const ready = new Promise((done) => (shown = done));
  const copies = [];
  const transport = new WebSocketTransport({
    url: liveUrl(api.API_BASE),
    token: () => token,
    events: {
      ready: () => undefined,
      joined: (_room, first, peers) => live.joined(first, peers),
      peers: (_room, peers) => live.peersChanged(peers),
      message: (_room, sender, data) => void live.message(sender, data),
      down: () => undefined,
    },
  });
  const live = new LiveSession(job.own.note, job.own.words ?? '', { transport, key: accountKey, hasUnsynced: () => Boolean(job.own.unsynced), keepCopy: async (_id, kept) => void copies.push(kept) }, { ready: shown, peers: () => undefined });
  own = { session: live, transport, copies, shown: await ready };
}

const text = () => (doc ? doc.text : own.session.text);
const words = () => (doc ? doc.words() : own.session.text.toString());

function others() {
  if (!room) return [];
  const list = [];
  for (const [client, said] of room.awareness.getStates()) {
    if (client === room.awareness.clientID) continue;
    const caret = said.cursor ? team.caretIndexes(doc, said.cursor) : null;
    list.push({ client, user: said.user ?? null, caret, pointer: said.pointer ?? null });
  }
  return list;
}

async function until(check, ms = 8000) {
  const start = performance.now();
  while (!check()) {
    if (performance.now() - start > ms) return false;
    await new Promise((done) => setTimeout(done, 5));
  }
  return true;
}

/** The note's screen saves what its editor holds: the library's copy follows the document, whoever typed. */
function saved() {
  if (doc) notes.set(job.team.note, { ...notes.get(job.team.note), body: doc.words(), updatedAt: Date.now() });
}

const relative = (index) => Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(text(), index));

async function run(command) {
  switch (command.do) {
    case 'type':
      text().doc.transact(() => {
        if (command.remove) text().delete(command.at, command.remove);
        if (command.insert) text().insert(command.at, command.insert);
      });
      saved();
      return { words: words() };
    case 'reconcile':
      return { changed: doc.reconcile(command.words), words: words(), text: doc.text.toString() };
    case 'cursor':
      room.awareness.setLocalStateField('cursor', { anchor: relative(command.anchor), head: relative(command.head ?? command.anchor) });
      await room.sent();
      return {};
    case 'canvas': {
      // The whole canvas handed back, as the view hands it (canvas/CanvasView.tsx `onChange`).
      const now = canvas.canvas();
      const nodes = now.nodes.map((node) => (command.set?.[node.id] ? { ...node, ...command.set[node.id] } : node)).filter((node) => !(command.remove ?? []).includes(node.id));
      canvas.apply({ ...now, nodes: [...nodes, ...(command.add ?? [])] });
      saved();
      return { canvas: canvas.canvas() };
    }
    case 'pointer':
      room.awareness.setLocalStateField('pointer', command.at);
      await room.sent();
      return {};
    case 'words':
      return { words: words(), text: text().toString(), canvas: canvas ? canvas.canvas() : null, hasCanvas: doc ? C.hasTeamCanvas(doc.doc) : false, parsed: doc && J.isCanvasBody?.(words()) ? J.parseCanvas(J.canvasOf?.(words()) ?? words()) : null };
    case 'others':
      return { others: others() };
    case 'until': {
      let ok = true;
      if (command.words !== undefined) ok = await until(() => words() === command.words, command.ms);
      if (ok && command.name !== undefined) ok = await until(() => others().some((each) => each.user?.name === command.name && (command.caret === undefined || each.caret?.head === command.caret)), command.ms);
      if (ok && command.gone !== undefined) ok = await until(() => !others().some((each) => each.user?.name === command.gone), command.ms);
      if (ok && command.card !== undefined) ok = await until(() => canvas && canvas.canvas().nodes.some((node) => node.id === command.card.id && Object.entries(command.card).every(([field, value]) => node[field] === value)), command.ms);
      return { ok, words: words(), others: others(), canvas: canvas ? canvas.canvas() : null };
    }
    case 'sync':
      return { outcomes: await pass(), words: doc ? doc.words() : null };
    case 'close':
      room?.close();
      own?.session.close();
      own?.transport.close();
      return { closed: true, sockets };
    default:
      throw new Error(`web_live: no such command: ${command.do}`);
  }
}

say({ ready: true, handle: session.handle, apiBase: api.API_BASE, org: orgOf, words: words(), shown: own?.shown ?? null, client: doc ? doc.doc.clientID : own.session.doc.clientID });

for await (const line of createInterface({ input: process.stdin })) {
  if (!line.trim()) continue;
  let command;
  try {
    command = JSON.parse(line);
    say({ id: command.id ?? null, ...(await run(command)) });
  } catch (failure) {
    say({ id: command?.id ?? null, error: String(failure?.stack ?? failure) });
  }
  if (command?.do === 'close') break;
}
process.exit(0);
