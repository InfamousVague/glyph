#!/usr/bin/env node
// A WEB device, under Node, against the local server: the web app's own client code (../glyph/src/app/core:
// account.ts, sync/notes.ts, sync/prefs.ts, account/encKey.ts, orgs/orgKeys.ts, team/sync.ts with its own Yjs)
// signing in to an account a Dart device made, reading what it wrote and writing back. What test/e2e/web_test.dart
// runs; the proof that the two clients are one wire through one real service.
//
//   GHOST_E2E_API=http://127.0.0.1:<port>/api node --experimental-transform-types tool/web_client.mjs '<job as JSON>'
//
// The job: {handle, password, rounds, write?: {note: {id, body}, theme, team: {id, append}}}. A fresh web device
// signs in, syncs its notes, its settings, the organizations' keys and each organization's team notes; with
// `write` it then makes a note of its own, changes the theme, adds a line at the foot of a team note, and syncs
// again. The last line it prints is JSON: what it holds at the end.
//
// THE FIRST RULE (docs/STAGE7.md): nothing here may reach ghostmarkdown.com. The web's api.ts falls back to it
// when `VITE_GLYPH_API` is unset, so three things stand in the way, each enough alone:
//   1. this refuses to start unless GHOST_E2E_API is http://127.0.0.1:<port>/api;
//   2. the web's `import.meta.env` is that base, written into its source as it loads (Vite does the same at build
//      time), and `API_BASE` is checked before a single call;
//   3. `fetch` is replaced, before any web code loads, by one that throws for any host but 127.0.0.1, and
//      `WebSocket` is taken away.
//
// ../glyph is only READ: its TypeScript is loaded as it is (Node strips the types), its node_modules give it `yjs`
// and `react`. Nothing is written there.
import { registerHooks } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const base = (process.env.GHOST_E2E_API ?? '').replace(/\/+$/, '');
if (!/^http:\/\/127\.0\.0\.1:\d+\/api$/.test(base)) {
  console.error(`web_client: GHOST_E2E_API must be http://127.0.0.1:<port>/api (tool/local-server.sh start); it is "${base}".`);
  process.exit(2);
}

const realFetch = globalThis.fetch;
const asked = [];
globalThis.fetch = (input, init) => {
  const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url);
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1') throw new Error(`web_client: refused a request to ${url.host}: only 127.0.0.1 is ever asked.`);
  asked.push(`${init?.method ?? 'GET'} ${url.pathname}`);
  // The service lets an address in twenty times a minute, and every device of the suite is this Mac: a way in
  // refused as too many is waited for and asked again.
  const ask = async (tries) => {
    const answer = await realFetch(input, init);
    if (answer.status !== 429 || tries >= 8) return answer;
    await new Promise((done) => setTimeout(done, 3200));
    return ask(tries + 1);
  };
  return ask(0);
};
globalThis.WebSocket = undefined;
globalThis.__GHOST_WEB_ENV = Object.freeze({ VITE_GLYPH_API: base, MODE: 'test', DEV: false, PROD: false });

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const web = resolve(root, '../glyph/src/app');
const webUrl = pathToFileURL(web).href;

// Vite's `import.meta.env`, as the web's source is loaded: the local base, and nothing else.
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
  console.error(`web_client: the web's API_BASE is ${api.API_BASE}, not the local server. Nothing was asked.`);
  process.exit(2);
}
const account = await from('core/account/account.ts');
const { memoryKeys } = await from('core/account/keystore.ts');
const { ensureEncryptionKey } = await from('core/account/encKey.ts');
const N = await from('core/sync/notes.ts');
const P = await from('core/sync/prefs.ts');
const { DEFAULT_PREFERENCES } = await from('core/preferences.ts');
const K = await from('core/orgs/orgKeys.ts');
const T = await from('core/team/sync.ts');
const { memoryDocs } = await from('core/team/docs.ts');

const job = JSON.parse(process.argv[2] ?? '{}');
const text = (bytes) => new TextDecoder().decode(bytes);

// ---- the device: its notes, files and settings in maps, as the web's own e2e test keeps them -----------------

const keys = memoryKeys();
await account.signIn(job.handle, job.password, { keys, rounds: job.rounds });
const session = account.accountState().session;
const token = session.token;
const accountKey = await keys.accountKey();

const notes = new Map();
const files = new Map();
const filed = new Map(); // note id -> organization id
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
let prefs = { ...DEFAULT_PREFERENCES };
let prefsState = { rev: 0, seen: null };
const teamStates = new Map();
const docs = memoryDocs();
const outcomes = [];

async function pass() {
  const synced = await N.syncNotes({
    token,
    key: accountKey,
    notes: local,
    files: localFiles,
    state,
    save: (next) => (state = JSON.parse(JSON.stringify(next))),
    teamNote: (id) => filed.has(id),
  });
  await P.syncPrefs({
    token,
    key: accountKey,
    read: () => prefs,
    write: (next) => (prefs = { ...prefs, ...next }),
    state: prefsState,
    save: (next) => (prefsState = next),
  });
  // Step 5: the account's pair, each organization's key, each organization's channel.
  const { orgs } = await api.call('GET', 'orgs', { token });
  const enc = await ensureEncryptionKey({ token, accountKey, keys });
  await K.syncOrgKeys({ token, pair: enc.pair, list: orgs });
  const teams = {};
  for (const row of orgs) {
    if (row.state !== 'member') continue;
    const key = K.orgKeyOf(row.id);
    if (!key) continue;
    const outcome = await T.syncTeamNotes({
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
    teams[row.id] = { generation: K.orgKeyGeneration(row.id), ...outcome };
  }
  outcomes.push({ notes: synced, teams });
}

await pass();
const read = { notes: Object.fromEntries([...notes].map(([id, n]) => [id, n.body])), theme: prefs.theme };

if (job.write) {
  const now = Date.now();
  const { note, theme, team } = job.write;
  if (note) notes.set(note.id, { id: note.id, body: note.body, createdAt: now, updatedAt: now, source: 'editor', starred: false, archivedAt: null });
  if (theme) prefs = { ...prefs, theme };
  if (team) {
    const had = notes.get(team.id);
    if (!had) throw new Error(`the web device never received the team note ${team.id}`);
    notes.set(team.id, { ...had, body: `${had.body}${team.append}`, updatedAt: now });
  }
  await pass();
}

console.log(
  JSON.stringify({
    handle: session.handle,
    apiBase: api.API_BASE,
    read,
    notes: Object.fromEntries([...notes].map(([id, n]) => [id, { body: n.body, starred: Boolean(n.starred), team: filed.get(id) ?? null }])),
    files: Object.fromEntries([...files].map(([name, bytes]) => [name, [...bytes]])),
    versions: Object.fromEntries([...files].filter(([name]) => name.startsWith('versions/')).map(([name, bytes]) => [name, text(bytes)])),
    theme: prefs.theme,
    outcomes,
    asked: asked.length,
    hosts: ['127.0.0.1'],
  }),
);
