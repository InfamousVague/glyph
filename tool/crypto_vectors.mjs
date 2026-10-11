#!/usr/bin/env node
// The crypto fixtures of stage 7 (docs/STAGE7.md, "Crypto"): made by the WEB app's own code, at its real 600,000
// rounds, and the web app's own code opening what the Rust core made. The web repository has no pinned vectors,
// so these are the proof that native/src/crypto.rs and ../glyph/src/app/core/sync/crypto.ts are one format.
//
//   node tool/crypto_vectors.mjs make     writes native/tests/fixtures/crypto_web.json
//   node tool/crypto_vectors.mjs check    opens native/target/vectors/crypto_from_rust.json, which
//                                         `cargo test --test crypto_vectors` writes (tool/build-native.sh test)
//
// ../glyph is only read. Its TypeScript is imported as it is (Node strips the types): crypto.ts, wrap.ts, wire.ts,
// ids.ts. share.ts and sync/notes.ts import half the app, so the few functions wanted from them (`sealShare`,
// `openShare`, `sha`, `fileId`) are lifted out of their source text, word for word, into a module of their own in
// the temp directory. Nothing here touches a network.
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const web = resolve(root, '../glyph/src/app');
const FIXTURE = join(root, 'native/tests/fixtures/crypto_web.json');
const FROM_RUST = join(root, 'native/target/vectors/crypto_from_rust.json');

const from = (path) => import(pathToFileURL(join(web, path)).href);
const C = await from('core/sync/crypto.ts');
const W = await from('core/orgs/wrap.ts');
const wire = await from('core/live/wire.ts');
const ids = await from('core/ids.ts');

// ---- the functions lifted out of files that cannot be imported whole ---------------------------------------

/** A top-level declaration of `name` in `source`, from its line's start to its end. */
function lift(source, name) {
  const found = new RegExp(`^(export )?(async )?(function ${name}\\(|const ${name}\\b)`, 'm').exec(source);
  if (!found) throw new Error(`the web source no longer declares ${name}`);
  const isFunction = found[0].includes('function');
  const end = source.indexOf(isFunction ? '\n}\n' : ';\n', found.index);
  return source.slice(found.index, end + (isFunction ? 3 : 2));
}

const scratch = mkdtempSync(join(tmpdir(), 'ghost-crypto-vectors-'));
process.on('exit', () => rmSync(scratch, { recursive: true, force: true }));

async function lifted(file, names, head) {
  const source = readFileSync(join(web, file), 'utf8');
  const text = `${head}\n${names.map((name) => lift(source, name).replace(/^(?!export )/, 'export ')).join('\n')}\n`;
  const path = join(scratch, `${file.replace(/[^a-z]/gi, '_')}.ts`);
  writeFileSync(path, text);
  return import(pathToFileURL(path).href);
}

const cryptoUrl = pathToFileURL(join(web, 'core/sync/crypto.ts')).href;
const bytesUrl = pathToFileURL(join(web, 'core/bytes.ts')).href;
const share = await lifted('share/share.ts', ['CONTEXT', 'PICTURED', 'PICTURE_NAME', 'keyOf', 'sealShare', 'openShare'], `import { fromBase64Url, openBytes, sealBytes, toBase64Url } from '${cryptoUrl}';`);
const notes = await lifted('core/sync/notes.ts', ['fileId', 'sha'], `import { toHex } from '${bytesUrl}';`);

// ---- helpers ---------------------------------------------------------------------------------------------

const b64 = C.toBase64Url;
const unb64 = C.fromBase64Url;
const utf8 = (text) => new TextEncoder().encode(text);
/** Random bytes, in the 65,536 at a time `getRandomValues` gives. */
function random(count) {
  const out = new Uint8Array(count);
  for (let at = 0; at < count; at += 65_536) crypto.getRandomValues(out.subarray(at, Math.min(count, at + 65_536)));
  return out;
}
const aes = (raw) => crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
/** A value with every object's keys in order, so two that hold the same things read the same. */
const sorted = (value) =>
  Array.isArray(value) ? value.map(sorted) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, sorted(value[key])])) : value;
const same = (a, b) => JSON.stringify(sorted(a)) === JSON.stringify(sorted(b));

/** A PNG's first bytes and then noise: what `sync_put_file` would take for a picture. */
function picture(length) {
  const bytes = random(length);
  bytes.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0);
  return bytes;
}

// ---- make: what the web code seals, for Rust to open -----------------------------------------------------

async function make() {
  const out = { made: new Date().toISOString(), by: 'tool/crypto_vectors.mjs make, from ../glyph/src/app', rounds: C.ROUNDS };

  // The account key, extractable for as long as it takes to write it down.
  const accountKey = await C.newAccountKey();
  const accountRaw = new Uint8Array(await crypto.subtle.exportKey('raw', accountKey));
  out.accountKey = b64(accountRaw);

  // Secrets: each derived at the real rounds, the login half as the web sends it, and the wrap key proved by the
  // account key wrapped under it (the wrap key itself cannot be read out of WebCrypto, and never is).
  out.salts = [
    { handle: 'Matt', kind: 'password', salt: C.passwordSalt('Matt') },
    { handle: '  MattsSoftware\n', kind: 'password', salt: C.passwordSalt('  MattsSoftware\n') },
    { handle: 'ÉLODIE Σ', kind: 'password', salt: C.passwordSalt('ÉLODIE Σ') },
    { handle: ' Matt ', kind: 'recovery', salt: C.recoverySalt(' Matt ') },
  ];
  out.codes = ['abcd-efgh ijkl', 'ABCD-EFGH-JKLM', ' 2345_6789\tzzzz '].map((typed) => ({ typed, normalised: C.normaliseCode(typed) }));
  out.derive = [];
  for (const [secret, salt] of [
    ['correct horse battery staple', C.passwordSalt('Matt')],
    ['pässwörd ✓ 😀 with spaces', C.passwordSalt('ÉLODIE Σ')],
    [C.normaliseCode('abcd-efgh ijkl'), C.recoverySalt('matt')],
    ['', C.passwordSalt('nobody')],
  ]) {
    const { login, wrapKey } = await C.derive(secret, salt);
    out.derive.push({ secret, salt, rounds: C.ROUNDS, login, wrapped: await C.wrap(accountKey, wrapKey) });
  }

  // A recovery sheet: eight codes, each with what the service keeps.
  out.sheet = { handle: 'Matt', ...(await C.newSheet('Matt', accountKey)) };

  // An organization's key and the account's pair.
  const orgRaw = random(32);
  const orgKey = await aes(orgRaw);
  const pair = await W.newEncryptionKey();
  const jwk = await W.exportPrivateKey(pair);
  const pub = await W.publicKeyOf(pair);
  const context = W.wrapContext('org-1', 3);
  out.pair = {
    // In the clear only so `check` can be this pair again; the app never holds it so.
    jwk,
    public: pub,
    sealed: await C.seal(accountKey, jwk, 'encryption-key'),
    // The same private half without its public coordinates, as a careful exporter might leave it.
    sealedBare: await C.seal(accountKey, { kty: jwk.kty, crv: jwk.crv, d: jwk.d }, 'encryption-key'),
  };
  out.org = { id: 'org-1', generation: 3, context, wrapped: await W.wrapFor(pub, orgRaw, context), wrappedAgain: await W.wrapFor(pub, orgRaw, context) };

  // A sealed blob in every context the app seals in (docs/STAGE7.md lists them), each with what was sealed.
  const note = { v: 1, note: { id: 'n1', body: '# Weekend trip\n\nBook the cabin. día ✓ 😀\n', createdAt: 1759000000000, updatedAt: 1759000001234, source: 'editor', starred: true, archivedAt: null, path: 'Inbox/Weekend trip.md' } };
  const png = picture(4096);
  const update = random(41);
  const sealed = [];
  const json = async (key, who, context, value) => sealed.push({ key: who, context, as: 'value', value, blob: await C.seal(key, value, context) });
  const data = async (key, who, context, bytes) => sealed.push({ key: who, context, as: 'data', data: b64(bytes), blob: b64(await C.sealBytes(key, bytes, context)) });
  await json(accountKey, 'account', 'note:n1', note);
  await json(accountKey, 'account', 'prefs', { v: 1, theme: 'dark', workspaces: { list: ['Work', 'Home'], notes: { n1: 'Work' } }, trash: { n9: 1759000000000 }, scale: 1.25 });
  await data(accountKey, 'account', `file:${notes.fileId('image', 'a1b2-c3.PNG')}`, png);
  await data(accountKey, 'account', `file:${notes.fileId('recording', 'n1')}`, utf8('RIFF and then the sound'));
  await data(accountKey, 'account', `file:${notes.fileId('versions', 'n1')}`, utf8('{"v":1,"versions":[]}'));
  await json(accountKey, 'account', 'notification:AAAAAAAAAAAAAAAAAAAAAA', { kind: 'mention', note: 'n1', by: 'sam', at: 1759000002000 });
  await json(accountKey, 'account', 'encryption-key', jwk);
  await data(accountKey, 'account', 'recording:a', random(60_000));
  await data(accountKey, 'account', 'prefs', new Uint8Array(0));
  // Live typing: the web's own envelopes (a kind byte, then a Yjs update), sealed for the relay.
  const envelope = { kind: wire.Kind.Update, payload: update };
  sealed.push({ key: 'account', context: 'live:n1', as: 'data', data: b64(wire.encode(envelope)), blob: await wire.sealEnvelope(accountKey, 'n1', envelope) });
  sealed.push({ key: 'org', context: 'live:org:org-1:n1', as: 'data', data: b64(wire.encode(envelope)), blob: await wire.sealTeamEnvelope(orgKey, 'org-1', 'n1', envelope) });
  const presence = { kind: wire.Kind.Presence, payload: random(30) };
  sealed.push({ key: 'org', context: 'live:org:org-1:presence', as: 'data', data: b64(wire.encode(presence)), blob: await wire.sealTeamEnvelope(orgKey, 'org-1', 'presence', presence) });
  await json(orgKey, 'org', 'org:org-1:note:n1', { v: 1, note: note.note, by: 'matt' });
  await data(orgKey, 'org', 'org:org-1:note:n1:update', update);
  await data(orgKey, 'org', `file:${notes.fileId('image', 'team.jpg')}`, Uint8Array.of(0xff, 0xd8, 0xff, 0xe0, 1, 2));
  out.sealed = sealed;
  // A blob from a newer app: the same bytes with another first byte.
  const newer = unb64(sealed[0].blob);
  newer[0] = 2;
  out.newer = { context: 'note:n1', blob: b64(newer) };

  // The device key. The web's is never extractable; this one is made the same way but for that, so its seed can
  // be written down, and signed with the web's own `signNonce`.
  const device = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
  const seed = unb64((await crypto.subtle.exportKey('jwk', device.privateKey)).d);
  out.device = { seed: b64(seed), public: await C.publicKeyOf(device), signed: [] };
  for (const nonce of ['nonce-1', '', 'dQw4w9WgXcQ-día-😀', b64(random(32))]) out.device.signed.push({ nonce, signature: await C.signNonce(device, nonce) });

  // Shares: one that is its JSON alone, one with pictures (GSP1), sealed by share.ts's own lines.
  const shareKey = b64(random(32));
  const words = { v: 1, kind: 'book', title: 'Trip', pages: [{ title: 'Trip', body: '# Trip\n\n![](image/a1.png)\n[[Day one]]\n' }, { title: 'Day one', body: 'We left. ![view](image/b-2.jpg)\n' }], at: 1759000003000 };
  const pictures = { 'a1.png': picture(5000), 'b-2.jpg': Uint8Array.of(0xff, 0xd8, 0xff, 0xe0, 9, 9, 9) };
  out.share = {
    key: shareKey,
    words,
    plain: await share.sealShare(words, shareKey),
    pictured: await share.sealShare({ ...words, pictures }, shareKey),
    pictures: Object.entries(pictures).map(([name, bytes]) => [name, b64(bytes)]),
  };

  // Fingerprints and ids.
  out.sha = [];
  for (const bytes of [new Uint8Array(0), utf8('abc'), png, random(70_000)]) out.sha.push({ data: b64(bytes), sha: await notes.sha(bytes) });
  out.shortId = ids.shortId();
  out.base64url = [0, 1, 2, 3, 255, 256, 1000].map((length) => {
    const bytes = Uint8Array.from({ length }, (_, i) => (i * 37 + (i >> 8)) & 0xff);
    return { url: b64(bytes), standard: Buffer.from(bytes).toString('base64') };
  });

  mkdirSync(dirname(FIXTURE), { recursive: true });
  writeFileSync(FIXTURE, `${JSON.stringify(out, null, 1)}\n`);
  const count = out.salts.length + out.codes.length + out.derive.length + out.sheet.codes.length + out.sealed.length + 1 + 3 + 2 + 1 + out.device.signed.length + 2 + out.sha.length + out.base64url.length;
  console.log(`crypto_vectors: ${FIXTURE}\n  ${count} vectors from the web code at ${C.ROUNDS} rounds`);
}

// ---- check: what Rust sealed, opened by the web code ------------------------------------------------------

async function check() {
  const web = JSON.parse(readFileSync(FIXTURE, 'utf8'));
  let rust;
  try {
    rust = JSON.parse(readFileSync(FROM_RUST, 'utf8'));
  } catch {
    console.error(`crypto_vectors: ${FROM_RUST} is not there. Run tool/build-native.sh test first: the Rust tests write it.`);
    process.exit(1);
  }
  if (rust.fixture !== web.made) {
    console.error('crypto_vectors: what Rust wrote was made from another fixture. Run tool/build-native.sh test again.');
    process.exit(1);
  }
  let passed = 0;
  const failures = [];
  const hold = async (name, body) => {
    try {
      const said = await body();
      if (said === false) throw new Error('not what was sealed');
      passed += 1;
    } catch (failure) {
      failures.push(`${name}: ${failure?.message ?? failure}`);
    }
  };
  const refuses = async (promise) => promise.then(() => false, () => true);

  const accountRaw = unb64(web.accountKey);
  const accountKey = await aes(accountRaw);

  // Secrets derived in Rust: the same login half, and a wrap key that the web's own derivation unwraps.
  for (const one of rust.derive) {
    await hold(`derive ${one.salt}`, async () => {
      const { login, wrapKey } = await C.derive(one.secret, one.salt, one.rounds);
      if (login !== one.login) throw new Error(`login ${one.login}, the web derives ${login}`);
      const back = await C.unwrap(one.wrapped, wrapKey, true);
      return same([...new Uint8Array(await crypto.subtle.exportKey('raw', back))], [...accountRaw]);
    });
  }
  for (const one of rust.salts) await hold(`salt ${JSON.stringify(one.handle)}`, () => (one.kind === 'recovery' ? C.recoverySalt(one.handle) : C.passwordSalt(one.handle)) === one.salt);
  for (const one of rust.codes) await hold(`code ${one.typed}`, () => C.normaliseCode(one.typed) === one.normalised);

  // A recovery sheet made in Rust: every code, typed as a person types, unwraps the account key in the web code.
  for (const [i, code] of rust.sheet.codes.entries()) {
    await hold(`sheet code ${i}`, async () => {
      if (!/^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/.test(code)) throw new Error(`${code} is not a code`);
      const { login, wrapKey } = await C.derive(C.normaliseCode(code.toLowerCase().replace(/-/g, ' ')), C.recoverySalt(rust.sheet.handle));
      if (login !== rust.sheet.entries[i].login) throw new Error('another login');
      const back = await C.unwrap(rust.sheet.entries[i].wrapped, wrapKey);
      return (await C.open(back, await C.seal(accountKey, 'ok', 'prefs'), 'prefs')) === 'ok';
    });
  }

  // The pair made in Rust arrives as the web's other device would read it, and unwraps what Rust wrapped for it.
  let rustPair = null;
  await hold('pair: the sealed private half imports', async () => {
    const jwk = await C.open(accountKey, rust.pair.sealed, 'encryption-key');
    rustPair = await W.importEncryptionKey(jwk);
    return (await W.publicKeyOf(rustPair)) === rust.pair.public && jwk.kty === 'EC' && jwk.crv === 'P-256';
  });
  await hold('pair: the JWK Rust exported for its caller to seal', async () => (await W.publicKeyOf(await W.importEncryptionKey(await C.open(accountKey, rust.pair.sealedByCaller, 'encryption-key')))) === rust.pair.public);
  // The organization key Rust made, out of the wrap it made for the WEB's pair, and for its own.
  const webPair = await W.importEncryptionKey(web.pair.jwk);
  let orgRaw = null;
  await hold('org key: wrapped in Rust for the web pair', async () => {
    orgRaw = await W.unwrapWith(webPair, rust.org.wrappedForWeb, rust.org.context);
    return orgRaw.length === 32;
  });
  await hold('org key: wrapped in Rust for the Rust pair', async () => same([...(await W.unwrapWith(rustPair, rust.org.wrappedForRust, rust.org.context))], [...orgRaw]));
  await hold('org key: wrapped in Rust from its bytes', async () => b64(await W.unwrapWith(webPair, rust.org.rawWrappedForWeb, rust.org.context)) === rust.org.raw);
  await hold('org key: bound to its context', async () => refuses(W.unwrapWith(webPair, rust.org.wrappedForWeb, W.wrapContext('org-1', 4))));
  const orgKey = orgRaw ? await aes(orgRaw) : null;

  // Every sealed blob, in every context.
  for (const one of rust.sealed) {
    const key = one.key === 'org' ? orgKey : accountKey;
    await hold(`sealed ${one.key} ${one.context}`, async () => {
      if (one.as === 'data') return b64(await C.openBytes(key, unb64(one.blob), one.context)) === one.data;
      return same(await C.open(key, one.blob, one.context), one.value);
    });
    await hold(`sealed ${one.key} ${one.context}: another context does not open it`, async () => refuses(C.openBytes(key, unb64(one.blob), `${one.context}x`)));
  }
  // The live envelopes open through the web's own wire.
  for (const one of rust.live) {
    await hold(`live ${one.room}`, async () => {
      const envelope = one.org ? await wire.openTeamEnvelope(orgKey, one.org, one.room, one.blob) : await wire.openEnvelope(accountKey, one.room, one.blob);
      return envelope.kind === one.kind && b64(envelope.payload) === one.payload;
    });
  }
  // A file sealed where it lay.
  await hold('seal_file', async () => b64(await C.openBytes(accountKey, unb64(rust.file.sealed), rust.file.context)) === rust.file.data);

  // The device key: the service checks a signature with the public half.
  for (const one of rust.device.signed) {
    await hold(`device signature ${JSON.stringify(one.nonce)}`, async () => {
      const publicKey = await crypto.subtle.importKey('raw', unb64(rust.device.public), { name: 'Ed25519' }, true, ['verify']);
      return crypto.subtle.verify({ name: 'Ed25519' }, publicKey, unb64(one.signature), utf8(one.nonce));
    });
  }

  // Shares.
  await hold('share: words alone', async () => same(await share.openShare(rust.share.plain, rust.share.key), rust.share.words));
  await hold('share: GSP1 with pictures', async () => {
    const opened = await share.openShare(rust.share.pictured, rust.share.key);
    const { pictures, ...words } = opened;
    return same(words, rust.share.words) && same(Object.entries(pictures).map(([name, bytes]) => [name, b64(bytes)]), rust.share.pictures);
  });
  await hold('share: another key does not open it', async () => refuses(share.openShare(rust.share.pictured, b64(random(32)))));

  for (const one of rust.sha) await hold('sha256-16', async () => (await notes.sha(unb64(one.data))) === one.sha);
  for (const id of rust.shortIds) await hold('short id', () => ids.isShortId(id));

  for (const failure of failures) console.error(`  FAILED ${failure}`);
  console.log(`crypto_vectors: the web code opened ${passed} of ${passed + failures.length} things Rust made`);
  process.exit(failures.length ? 1 : 0);
}

const mode = process.argv[2];
if (mode === 'make') await make();
else if (mode === 'check') await check();
else {
  console.error('usage: node tool/crypto_vectors.mjs make|check');
  process.exit(2);
}
