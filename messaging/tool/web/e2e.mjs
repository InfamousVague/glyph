#!/usr/bin/env node
/**
 * Ghost Messaging in a browser, tried end to end as two people would use it (Matt: "the full web client"): a relay
 * on this machine serving the built app, and real browser engines driving the page itself.
 *
 *   node tool/build-web.mjs                 first: build/web
 *   node tool/web/e2e.mjs                   Chromium, then WebKit
 *   node tool/web/e2e.mjs --engine webkit   one of them
 *   node tool/web/e2e.mjs --web <folder> --shots <folder> --headed
 *
 * WHAT IT DOES, in each engine
 *   1. Starts the relay (relay/bin/relay.dart, with Flutter's own Dart) on a free port of this machine, with a new
 *      empty folder for what it keeps and `--web` at the built app. Never the live relay, never a real account: the
 *      two people are made here, with names nobody has.
 *   2. Two browsers (two contexts: nothing shared) open the page and sign up, each with a username and a password.
 *   3. One adds the other by username; the other accepts; each writes to the other and sees what the other wrote.
 *   4. One page is loaded again: still signed in, the conversation still there.
 *   5. What that browser keeps, read as any script in the page could read it: every record sealed, the store's key
 *      not extractable, no recovery words, no password key, nothing of the conversation or the account in the clear.
 *   6. A second tab in the same browser is told the app is open in another tab; "Use it here" moves it over.
 *   7. One makes a circle and copies its invite link; the other joins by the link; each writes in its General space
 *      and reads what the other wrote there; its chat-and-voice space is its chat alone, with no way into a call.
 *   8. Settings call it a browser, with an About of its own and none of what a browser has nothing to set for; and
 *      the Marketplace is on no key (Ctrl+5), in no quick switcher and in no list of shortcuts.
 *   9. One signs in on a third, new browser with the username and password: the same person, the friend still there,
 *      both browsers in the account's devices as browsers, after the password. How long signing in took is said.
 *  10. The page's own Argon2id (web/argon2id.js, in a worker) is held to test/vectors/argon2id.json.
 *  11. In a narrow window the page is laid out as a phone; wide again, as a computer.
 *  12. From the third browser the first is removed: started again, it deletes everything of the account and opens at
 *      the welcome saying why, and what is written to the account after reaches the third and not it.
 *  13. The third signs out: everything deleted, the welcome saying so; the next person signs up there and finds nothing
 *      of the one before. Signed in once more (from an address naming a page after its #), the account lists that
 *      browser alone: the removed one and the one that signed out (by its own number) are gone.
 *  14. Every answer from the app's address carries the headers in tool/web/headers.json, the page's own policy among
 *      them with frame-ancestors 'none'.
 *  15. Nothing was asked of any address but the relay's own, the pages logged no error, and the relay wrote nothing to
 *      stderr.
 *
 * The page is a canvas: what is on it is found through Flutter's accessibility tree (the fields' and buttons' names),
 * which the script switches on as a screen reader would, and everything is done with it on, messages written too.
 *
 * GHOST_E2E_LOOK, for finding the way when adding a step: names joined by > ("Settings>About"), pressed in turn once
 * the run is through, a picture and the page's words after each. "=Label=text" types into a field, "~Name" turns the
 * wheel over it, "@sam" goes to Sam's page and "@new" opens one in a browser of its own.
 *
 * NEEDS Playwright with its browsers. It is not one of the app's packages: the script looks for it in npm's npx cache
 * (`npx playwright install chromium webkit` puts it there), or where GHOST_PLAYWRIGHT names its index.mjs.
 * A tool, not part of `flutter test`. Exit code 0 when everything held.
 */
import { spawn, execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const args = process.argv.slice(2);
const option = (name, fallback) => {
  const at = args.indexOf(`--${name}`);
  return at >= 0 && at + 1 < args.length ? args[at + 1] : fallback;
};
const webDir = resolve(option('web', join(root, 'build', 'web')));
const shots = option('shots', null);
const headed = args.includes('--headed');
const engines = option('engine', 'both') === 'both' ? ['chromium', 'webkit'] : [option('engine', 'chromium')];
// A build that names its hub (tool/build-web.mjs --hub ws://127.0.0.1:<port>/hub), as app.gogho.st's names gogho.st's:
// the hub is a relay of its own on that port, and the page comes from another, so the two are different addresses.
const hubPort = option('hub-port', null);
// The people's first steps only: signing up, a friend, a message each way.
const quick = args.includes('--quick');

if (!existsSync(join(webDir, 'index.html'))) {
  console.error(`e2e: no built app at ${webDir}: run node tool/build-web.mjs first.`);
  process.exit(2);
}

// --- what it needs -------------------------------------------------------------------------------------------------

function findPlaywright() {
  if (process.env.GHOST_PLAYWRIGHT) return process.env.GHOST_PLAYWRIGHT;
  const cache = join(homedir(), '.npm', '_npx');
  if (existsSync(cache)) {
    for (const dir of readdirSync(cache)) {
      const at = join(cache, dir, 'node_modules', 'playwright', 'index.mjs');
      if (existsSync(at)) return at;
    }
  }
  console.error('e2e: Playwright was not found. `npx playwright install chromium webkit`, or set GHOST_PLAYWRIGHT to its index.mjs.');
  process.exit(2);
}

function findDart() {
  if (process.env.GHOST_DART) return process.env.GHOST_DART;
  try {
    // Flutter's own Dart: the one the relay is tested with.
    const flutter = execFileSync('which', ['flutter'], { encoding: 'utf8' }).trim();
    const real = execFileSync('python3', ['-c', 'import os,sys;print(os.path.realpath(sys.argv[1]))', flutter], { encoding: 'utf8' }).trim();
    const dart = join(dirname(real), 'cache', 'dart-sdk', 'bin', 'dart');
    if (existsSync(dart)) return dart;
  } catch {}
  return 'dart';
}

const playwright = await import(pathToFileURL(findPlaywright()).href);
const dart = findDart();

// --- a relay of its own ----------------------------------------------------------------------------------------------

async function startRelay({ port: asked = '0', web = true } = {}) {
  const data = mkdtempSync(join(tmpdir(), 'ghost-web-e2e-'));
  const child = spawn(dart, ['run', 'bin/relay.dart', '--host', '127.0.0.1', '--port', String(asked), '--data', data, ...(web ? ['--web', webDir] : [])], {
    cwd: join(root, 'relay'),
    // Nothing of this computer's settings: the relay as anyone would first run it.
    env: { PATH: process.env.PATH, HOME: process.env.HOME },
  });
  const errors = [];
  child.stderr.on('data', (d) => errors.push(String(d)));
  const port = await new Promise((done, fail) => {
    child.stdout.on('data', (d) => {
      const m = /listening on ws:\/\/127\.0\.0\.1:(\d+)/.exec(String(d));
      if (m) done(Number(m[1]));
    });
    child.on('exit', (code) => fail(new Error(`the relay ended (${code}): ${errors.join('')}`)));
    setTimeout(() => fail(new Error(`the relay never said it was listening: ${errors.join('')}`)), 90000);
  });
  return {
    port,
    errors,
    async stop() {
      child.kill('SIGTERM');
      await new Promise((r) => child.once('exit', r));
      rmSync(data, { recursive: true, force: true });
    },
  };
}

// --- the page, as a person finds things on it ----------------------------------------------------------------------------

class Problem extends Error {}

/// One person's page: what it logged, what it asked the network for, and how to find and press what is on it.
class Seat {
  constructor(name, page, origin) {
    this.name = name;
    this.page = page;
    this.origin = origin;
    this.errors = [];
    this.outside = new Set();
    // The fonts the engine asks for a letter none of the app's own fonts has (tool/web/fallback-fonts.mjs): a build
    // without them answers 404 for each, which the browser logs as an error. Those are counted and said, not taken for
    // the page's own errors; every other 404 still is one.
    this.missingFonts = new Set();
    this.fontMisses = 0;
    this.notFound = [];
    page.on('response', (r) => {
      if (r.status() !== 404 || !new URL(r.url()).pathname.includes('/fallback-fonts/')) return;
      this.missingFonts.add(new URL(r.url()).pathname.split('/fallback-fonts/')[1]);
      this.fontMisses++;
    });
    page.on('console', (m) => {
      if (m.type() !== 'error' || /GL Driver Message|WebGL|GPU stall/.test(m.text())) return;
      // Weighed at the end against the fonts missed: the two arrive in either order.
      if (/the server responded with a status of 404/.test(m.text())) return this.notFound.push(m.text().slice(0, 600));
      this.errors.push(m.text().slice(0, 600));
    });
    page.on('pageerror', (e) => this.errors.push(`uncaught: ${String(e.message || e)} ${String(e.stack || '').slice(0, 1200)}`));
    page.on('request', (r) => {
      const u = new URL(r.url());
      if (u.origin !== origin && !['data:', 'blob:', 'about:'].includes(u.protocol)) this.outside.add(`${u.origin}${u.pathname}`);
    });
    page.on('websocket', (w) => {
      const u = new URL(w.url());
      // The page's own address, or the hub its build names (--hub-port): nothing else.
      if (u.host !== new URL(origin).host && u.host !== `127.0.0.1:${hubPort}`) this.outside.add(`${u.protocol}//${u.host}`);
    });
    // What the relay told the browser with the page and with the worker, as it said it.
    this.headers = {};
    page.on('response', (r) => {
      const u = new URL(r.url());
      if (u.origin === origin && (u.pathname === '/app/' || u.pathname === '/app/argon2id.js')) this.headers[u.pathname] = r.headers();
    });
  }

  static async open(context, name, origin, { at = '' } = {}) {
    const seat = new Seat(name, await context.newPage(), origin);
    await seat.load({ at });
    return seat;
  }

  /// The page, loaded; [at] is what follows /app/ in the address (a # and anything a link might say).
  async load({ at = '' } = {}) {
    await this.page.goto(`${this.origin}/app/${at}`);
    await this.ready();
  }

  /// Everything the page keeps, read as any script running in the page could read it: each record's kind, and for one
  /// that is text, the text. (What a script could open with the store's key is lib/web/store.dart's to say; this is
  /// what anyone reading the browser's store gets without it.)
  async kept() {
    return this.page.evaluate(async () => {
      const db = await new Promise((done, fail) => {
        const r = indexedDB.open('ghost-messaging');
        r.onsuccess = () => done(r.result);
        r.onerror = () => fail(r.error);
      });
      try {
        if (!db.objectStoreNames.contains('kept')) return {};
        const store = db.transaction('kept').objectStore('kept');
        const all = (q) => new Promise((done) => { q.onsuccess = () => done(q.result); });
        const keys = await all(store.getAllKeys());
        const values = await all(store.getAll());
        const out = {};
        keys.forEach((k, i) => {
          const v = values[i];
          out[k] = typeof v === 'string' ? { kind: 'text', text: v }
            : v instanceof Uint8Array ? { kind: 'sealed', latin1: new TextDecoder('latin1').decode(v) }
            : v instanceof CryptoKey ? { kind: 'key', extractable: v.extractable }
            : { kind: typeof v };
        });
        return out;
      } finally {
        db.close();
      }
    });
  }

  /// Flutter's view on the page and its accessibility tree switched on, as a screen reader switches it on.
  async ready() {
    await this.page.waitForSelector('flutter-view, flt-glass-pane', { state: 'attached', timeout: 60000 });
    await this.page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 60000 });
    await this.page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
    await this.page.waitForSelector('flt-semantics', { state: 'attached', timeout: 30000 });
  }

  /// Everything the page says, as text: what is on the screen, to look for words in. A piece of text is a node of the
  /// tree with its words in a span; a button's words are its own; a field or a picture has a label.
  async words() {
    return this.page.evaluate(() => {
      const own = (e) => [...e.childNodes].filter((n) => n.nodeType === 3 || (n.nodeType === 1 && n.tagName === 'SPAN')).map((n) => n.textContent).join('').trim();
      return [...document.querySelectorAll('flt-semantics, flt-semantics input, flt-semantics textarea')].map((e) => e.getAttribute('aria-label') || own(e)).filter(Boolean).join('\n');
    });
  }

  /// [like]: [text] is a pattern one of the page's lines must match, not words it holds.
  async sees(text, { within = 30000, like = false } = {}) {
    const until = Date.now() + within;
    const holds = (words) => (like ? words.split('\n').some((line) => new RegExp(text).test(line)) : words.includes(text));
    for (;;) {
      if (holds(await this.words())) return;
      if (Date.now() > until) throw new Problem(`${this.name} never saw "${text}". On the page: ${(await this.words()).replace(/\n/g, ' | ').slice(0, 900)}`);
      await this.page.waitForTimeout(150);
    }
  }

  async gone(text, { within = 30000 } = {}) {
    const until = Date.now() + within;
    while ((await this.words()).includes(text)) {
      if (Date.now() > until) throw new Problem(`${this.name} still sees "${text}".`);
      await this.page.waitForTimeout(150);
    }
  }

  /// The middle of the thing called [name] (a button's words, or its label), to press there.
  /// [like]: [name] is a pattern the whole of its words must match ("^Lighthouse, .* options$"), not the words.
  async where(name, { role = null, last = false, like = false } = {}) {
    return this.page.evaluate(({ name, role, last, like }) => {
      const own = (e) => [...e.childNodes].filter((n) => n.nodeType === 3 || (n.nodeType === 1 && n.tagName === 'SPAN')).map((n) => n.textContent).join('').trim();
      const is = like ? (words) => new RegExp(name).test(words) : (words) => words === name;
      const all = [...document.querySelectorAll('flt-semantics')].filter((e) => {
        if (role && e.getAttribute('role') !== role) return false;
        if (is(e.getAttribute('aria-label') || '')) return true;
        const words = own(e);
        return is(words) || words.split('\n').some(is);
      });
      const e = last ? all[all.length - 1] : all[0];
      if (!e) return null;
      const r = e.getBoundingClientRect();
      return r.width > 0 && r.height > 0 ? { x: r.left + r.width / 2, y: r.top + r.height / 2, left: r.left, top: r.top } : null;
    }, { name, role, last, like });
  }

  async press(name, { within = 30000, role = null, last = false, like = false } = {}) {
    const until = Date.now() + within;
    for (;;) {
      const at = await this.where(name, { role, last, like });
      // Pressed only where it has come to rest: a menu or a page still sliding into place moves it from under the
      // pointer, and the press lands on whatever was there.
      await this.page.waitForTimeout(120);
      const still = at && (await this.where(name, { role, last, like }));
      if (at && still && Math.abs(at.x - still.x) < 1 && Math.abs(at.y - still.y) < 1) {
        await this.page.mouse.click(still.x, still.y);
        return;
      }
      if (Date.now() > until) throw new Problem(`${this.name} found nothing called "${name}" to press. On the page: ${(await this.words()).replace(/\n/g, ' | ').slice(0, 900)}`);
      await this.page.waitForTimeout(150);
    }
  }

  /// Types into the field called [label], and makes sure it arrived (a field still sliding into place can miss the
  /// press that gives it the keyboard).
  async type(label, text, { within = 30000 } = {}) {
    // By its name (the words of the section it is in come before it there, a line each), or by the words it shows
    // while empty.
    const field = this.page.locator(['input', 'textarea'].flatMap((tag) => [`${tag}[aria-label="${label}"]`, `${tag}[aria-label$="\\a ${label}"]`, `${tag}[aria-description="${label}"]`]).join(', ')).first();
    await field.waitFor({ state: 'attached', timeout: within });
    for (let attempt = 0; ; attempt++) {
      await this.page.waitForTimeout(250);
      // Where it has come to rest: a page still sliding in moves it from under the pointer.
      let box = await field.boundingBox();
      for (let i = 0; i < 20; i++) {
        await this.page.waitForTimeout(100);
        const again = await field.boundingBox();
        const still = box && again && Math.abs(box.x - again.x) < 1 && Math.abs(box.y - again.y) < 1;
        box = again;
        if (still) break;
      }
      if (!box) throw new Problem(`${this.name}: the field "${label}" is not on the screen.`);
      // Toward its end: a toast stands in the middle of the window's foot, over a composer's start.
      await this.page.mouse.click(box.x + box.width * 0.85, box.y + box.height / 2);
      await this.page.waitForTimeout(200);
      await this.page.keyboard.type(text, { delay: 8 });
      // The field's element holds what was typed once the app has taken it and drawn the field again: looked at for a
      // while, not once.
      for (let i = 0; i < 12; i++) {
        await this.page.waitForTimeout(150);
        if ((await field.inputValue().catch(() => '')) === text) return;
      }
      if (attempt >= 3) {
        // Every field on the page, to say where the keys went instead.
        const fields = await this.page.evaluate(() => [...document.querySelectorAll('input, textarea')].map((e) => `${e.tagName.toLowerCase()} ${JSON.stringify(e.getAttribute('aria-label') ?? e.getAttribute('aria-description'))} = ${JSON.stringify(e.value)}${document.activeElement === e ? ' (has the keyboard)' : ''}`));
        throw new Problem(`${this.name}: what was typed into "${label}" did not arrive (it holds ${JSON.stringify(await field.inputValue().catch(() => null))}). The page's fields: ${fields.join('; ')}`);
      }
      // Whatever part of it did arrive is taken out before trying again.
      await this.page.keyboard.press('ControlOrMeta+a');
      await this.page.keyboard.press('Backspace');
    }
  }

  /// Turns the wheel over the thing called [over], a little at a time, until the thing called [target] is in view: what
  /// is under the fold of a list. At [over]'s top left corner, over its words rather than a button, so the wheel
  /// reaches the app as it does with no screen reader. (No field should hold the keyboard meanwhile: [clickAside].)
  async wheelTo(over, target) {
    const height = this.page.viewportSize().height;
    for (let turn = 0; turn < 16; turn++) {
      const there = await this.where(target);
      if (there && there.y > 10 && there.y < height - 10) return;
      // A list whose rows are still coming in (Settings' fade in one by one) is waited for.
      let at = await this.where(over);
      for (let wait = 0; !at && wait < 60; wait++) {
        await this.page.waitForTimeout(150);
        at = await this.where(over);
      }
      if (!at) throw new Problem(`${this.name} found nothing called "${over}" to scroll at.`);
      await this.page.mouse.move(at.left + 6, at.top + 6);
      await this.page.mouse.wheel(0, 300);
      await this.page.waitForTimeout(250);
    }
    throw new Problem(`${this.name} turned the wheel and never brought "${target}" into view.`);
  }

  /// Clicks beside the field that has the keyboard, on the words at the top left of [name], as one does to be done
  /// with a field: it lets go (Flutter's own, for a click outside a field). Before a scroll: a field holding the
  /// keyboard while the page scrolls can be made afresh, empty, by Flutter's engine with its tree for screen readers on
  /// (seen in Chromium: a circle's name typed, the page scrolled to its button, the name gone).
  async clickAside(name) {
    const at = await this.where(name);
    if (!at) throw new Problem(`${this.name} found nothing called "${name}" to click beside.`);
    await this.page.mouse.click(at.left + 6, at.top + 6);
    await this.page.waitForTimeout(300);
  }

  /// None of [texts] is on the page: what a browser has none of is not offered there.
  async lacks(...texts) {
    const words = await this.words();
    for (const text of texts) {
      if (words.split('\n').includes(text)) throw new Problem(`${this.name}'s page offers "${text}", which a browser has none of.`);
    }
  }

  /// The page's own Argon2id (argon2id.js beside it, started as the app starts it: a worker) asked for each of
  /// [vectors]: what it made of each, and how long each took.
  async argon2(vectors) {
    return this.page.evaluate(async (vectors) => {
      const unhex = (t) => Uint8Array.from((t.match(/../g) || []).map((h) => parseInt(h, 16)));
      const hex = (b) => [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
      const out = [];
      for (const v of vectors) {
        const began = performance.now();
        const key = await new Promise((done, fail) => {
          const worker = new Worker('argon2id.js');
          worker.onmessage = (e) => {
            worker.terminate();
            e.data.key ? done(e.data.key) : fail(new Error(String(e.data.error)));
          };
          worker.onerror = (e) => {
            worker.terminate();
            fail(new Error(e.message || 'the worker could not be started'));
          };
          worker.postMessage({ password: new TextEncoder().encode(v.password), salt: unhex(v.salt), memoryKiB: v.m, passes: v.t, lanes: v.p, length: v.key.length / 2 });
        });
        out.push({ got: hex(key), ms: Math.round(performance.now() - began) });
      }
      return out;
    }, vectors);
  }

  /// Writes [text] in the open conversation's field (called [label], the words it shows while empty) and sends it
  /// with Enter, as someone with a screen reader would: the field pressed, the words typed, Enter. Its words gone from
  /// the field is the app taking them.
  async write(label, text) {
    await this.type(label, text);
    await this.page.keyboard.press('Enter');
    const field = this.page.locator(`textarea[aria-label="${label}"]`).first();
    const until = Date.now() + 15000;
    while ((await field.inputValue().catch(() => '')) !== '') {
      if (Date.now() > until) throw new Problem(`${this.name}: Enter did not send what was written in "${label}".`);
      await this.page.waitForTimeout(150);
    }
  }

  async shot(name) {
    if (!shots) return;
    mkdirSync(shots, { recursive: true });
    await this.page.screenshot({ path: join(shots, `${name}.png`) });
  }
}

// --- the run ---------------------------------------------------------------------------------------------------------

const said = [];
const say = (words) => {
  said.push(words);
  console.log(words);
};

async function run(engine) {
  const relay = await startRelay();
  // The hub elsewhere, where the build names one: the page's relay then serves the page alone.
  const hub = hubPort ? await startRelay({ port: hubPort, web: false }) : null;
  const origin = `http://127.0.0.1:${relay.port}`;
  const browser = await playwright[engine].launch({ headless: !headed });
  const seats = [];
  let skipping = false;
  const step = async (words, what) => {
    if (skipping) return;
    const began = Date.now();
    await what();
    say(`  ok  ${words} (${((Date.now() - began) / 1000).toFixed(1)} s)`);
  };
  // Names nobody has: this run's own.
  const tag = Math.random().toString(36).slice(2, 8);
  const maya = { username: `maya_${tag}`, password: `maya's password ${tag}` };
  const sam = { username: `sam_${tag}`, password: `sam's password ${tag}` };
  try {
    say(`${engine}: the relay at ${origin}, the app from ${webDir}`);
    const size = { viewport: { width: 1180, height: 780 } };
    // What the page copies is kept for the script to read: a browser with no window gives a page no clipboard.
    const copies = () => {
      if (navigator.clipboard) navigator.clipboard.writeText = async (text) => { window.__ghostCopied = text; };
    };
    const person = async () => {
      const context = await browser.newContext(size);
      await context.addInitScript(copies);
      return context;
    };
    const mayaBrowser = await person(), samBrowser = await person();
    let m, s;
    let signIn = 0, stretch = 0;
    await step('two browsers open the page', async () => {
      m = await Seat.open(mayaBrowser, 'Maya', origin);
      s = await Seat.open(samBrowser, 'Sam', origin);
      seats.push(m, s);
      await m.sees('Pick a username and a password.');
      await s.sees('Pick a username and a password.');
    });
    for (const [seat, who] of [[m, maya], [s, sam]]) {
      await step(`${seat.name} signs up as ${who.username}`, async () => {
        await seat.press('Continue', { role: 'button' }).catch(() => {});
        await seat.type('Username', who.username);
        await seat.type('Password', who.password);
        await seat.shot(`${engine}-${seat.name}-1-welcome`);
        await seat.press('Continue', { role: 'button' });
        await seat.gone('Pick a username and a password.', { within: 90000 });
        await seat.shot(`${engine}-${seat.name}-2-signed-up`);
      });
    }
    for (const seat of [m, s]) {
      await step(`${seat.name} puts the recovery words by for later, and is in the app`, async () => {
        await seat.sees('Your recovery words');
        await seat.press('Later', { role: 'button' });
        await seat.gone('Your recovery words');
        await seat.page.waitForTimeout(1500);
        await seat.shot(`${engine}-${seat.name}-3-app`);
      });
    }
    await step(`Maya adds @${sam.username} by username`, async () => {
      await m.press('Contacts', { role: 'button' });
      await m.press('Add a friend');
      await m.type('Search by @username', sam.username);
      await m.sees('On Ghost Messaging');
      await m.press('Add', { role: 'button' });
      await m.sees('Friend request sent');
      await m.shot(`${engine}-Maya-4-asked`);
      await m.page.keyboard.press('Escape');
    });
    await step('Sam finds the request in Contacts and accepts', async () => {
      await s.press('Contacts', { role: 'button' });
      await s.sees('Friend request');
      await s.shot(`${engine}-Sam-4-request`);
      await s.press('Accept', { role: 'button' });
      await s.gone('Friend request');
      await s.page.waitForTimeout(1500);
      await s.shot(`${engine}-Sam-5-friends`);
    });
    const hello = `Hello Sam, from ${engine}`, answer = `And hello Maya, from ${engine}`;
    await step('Maya opens Sam from Contacts and writes to him', async () => {
      await m.press(`${sam.username}, Ghost`);
      await m.sees('Friend · encrypted');
      await m.write('Encrypted message', hello);
      await m.sees(hello);
      await m.shot(`${engine}-Maya-5-wrote`);
    });
    await step('Sam finds it in his list, opens it, and answers; Maya reads the answer', async () => {
      await s.press('Messages', { role: 'button' });
      await s.sees(hello, { within: 20000 });
      await s.shot(`${engine}-Sam-6-list`);
      // The conversation's row in the list: Maya's name, the first place it is written.
      await s.press(maya.username);
      await s.sees('Friend · encrypted');
      // No calls in a browser yet, and no microphone: neither is offered. Nor the Marketplace on the rail.
      await s.lacks('Voice call', 'Video call', 'Record a voice message', 'Marketplace');
      await s.write('Encrypted message', answer);
      await s.sees(answer);
      await s.sees(hello);
      await m.sees(answer, { within: 20000 });
      await m.shot(`${engine}-Maya-7-answered`);
    });
    if (quick) {
      say('  (--quick: the rest is left out)');
      skipping = true;
    }
    await step('Maya loads the page again: still signed in, the conversation and both messages still there', async () => {
      await m.load();
      await m.sees(sam.username);
      await m.sees(answer);
      await m.press(sam.username);
      await m.sees(hello);
      await m.sees(answer);
      await m.shot(`${engine}-Maya-8-reloaded`);
    });
    await step('what Maya\'s browser keeps is all sealed, and holds neither her recovery words nor her password\'s key', async () => {
      const kept = await m.kept();
      const names = Object.keys(kept);
      for (const name of ['seal-key', 'identity', 'state', 'secret:account_mine']) {
        if (!names.includes(name)) throw new Problem(`the browser keeps no ${name}: ${names.join(', ')}`);
      }
      for (const gone of ['secret:account_words', 'secret:account_pwkey', 'secret:was_key']) {
        if (names.includes(gone)) throw new Problem(`the browser keeps ${gone}, which a browser must not keep.`);
      }
      if (kept['seal-key'].kind !== 'key' || kept['seal-key'].extractable !== false) throw new Problem(`the store's key is ${JSON.stringify(kept['seal-key'])}, not one that can't be read out.`);
      for (const [name, v] of Object.entries(kept)) {
        if (name !== 'seal-key' && v.kind !== 'sealed') throw new Problem(`${name} is kept as ${v.kind}, not sealed.`);
        // Nothing of the conversation, the friend or the account is there to be read without the key.
        for (const plain of [hello, answer, sam.username, 'acct_sealed', 'acct_address', 'circles']) {
          if ((v.latin1 ?? v.text ?? '').includes(plain)) throw new Problem(`${name} holds "${plain}" as it was written.`);
        }
      }
    });
    await step('a second tab of Maya\'s browser is told the app is open in another tab; "Use it here" moves it over', async () => {
      const second = await Seat.open(mayaBrowser, 'Maya (second tab)', origin);
      seats.push(second);
      await second.sees('Ghost Messaging is open in another tab.');
      await second.shot(`${engine}-Maya-9-second-tab`);
      // The first tab is still the app meanwhile.
      await m.sees(sam.username);
      await second.press('Use it here', { role: 'button' });
      await second.sees(sam.username, { within: 30000 });
      await second.sees(answer);
      // And the first tab, which gave way, now says what the second did.
      await m.ready();
      await m.sees('Ghost Messaging is open in another tab.', { within: 30000 });
      await m.shot(`${engine}-Maya-9-first-tab`);
      // From here Maya is in the tab that took over.
      m = second;
    });
    let link;
    await step('Sam makes a circle, Lighthouse, and copies its invite link', async () => {
      await s.press('New', { role: 'button' });
      await s.press('New circle');
      await s.type('Circle name', 'Lighthouse');
      await s.sees('Lighthouse');
      await s.clickAside('Colour');
      // A browser can choose no picture yet, and keeps no files: neither is offered.
      await s.lacks('Choose a picture');
      await s.wheelTo('Icon', 'Make the circle');
      await s.press('Make the circle');
      await s.sees('Lighthouse made');
      await s.sees('Message General');
      await s.shot(`${engine}-Sam-10-circle`);
      await s.press('^Lighthouse, .* options$', { like: true });
      await s.press('Invite people');
      await s.sees('Whoever has the link is in the circle.');
      await s.lacks('Text an invite', 'Share link…');
      await s.press('Copy invite link');
      await s.sees('Invite link copied. Anyone with it can join Lighthouse.');
      link = await s.page.evaluate(() => window.__ghostCopied);
      if (!/^https:\/\/gogho\.st\/join\/#c\.[0-9a-f]{64}/.test(link || '')) throw new Problem(`what Sam copied is no circle's link: ${link}`);
    });
    const inSpace = `Maya, in the circle's General, from ${engine}`, back = `Sam, back in General, from ${engine}`;
    await step('Maya joins it by the link and writes in its General space; Sam, who has it open, reads it', async () => {
      await m.press('New', { role: 'button' });
      await m.press('Join a circle by link');
      await m.type('Join a circle', link);
      await m.press('Save');
      await m.sees('General, Text', { within: 30000 });
      await m.sees('Lounge, Chat & voice');
      await m.sees('^Lighthouse(, open)?$', { like: true });
      await m.press('General, Text');
      await m.sees('Message General');
      await m.write('Message General', inSpace);
      await m.sees(inSpace);
      await m.shot(`${engine}-Maya-11-space`);
      await s.sees(inSpace, { within: 20000 });
    });
    await step('Sam answers there, and Maya reads it; a voice space is its chat, with no way into a call', async () => {
      await s.write('Message General', back);
      await s.sees(back);
      await s.sees(inSpace);
      await m.sees(back, { within: 20000 });
      // The other space is chat and voice: in a browser, its chat alone.
      await s.press('Lounge, Chat & voice');
      await s.sees('Message Lounge');
      await s.lacks('Join', 'Join voice', 'Start the call');
      await s.shot(`${engine}-Sam-12-voice-space`);
    });
    await step('Sam\'s Settings call this a browser, with an About of its own and none of what it has nothing to set for', async () => {
      await s.press('Settings', { role: 'button' });
      await s.sees('Appearance');
      await s.wheelTo('Emoji', 'About');
      await s.sees('Ghost Messaging in a browser');
      await s.lacks('Voice and video', 'Sounds', 'Notifications', 'Updates', 'Your phone');
      await s.press('About');
      await s.sees('Not in the browser yet');
      await s.sees('What this browser keeps');
      await s.shot(`${engine}-Sam-13-about`);
    });
    await step('the Marketplace is nowhere in a browser: not on its keys, in the quick switcher or in the shortcuts', async () => {
      await s.press('Messages', { role: 'button' });
      await s.page.mouse.click(800, 600);
      // Cmd or Ctrl and 5 opens the Marketplace on a phone or a computer (lib/keys.dart); in a page Ctrl is the key.
      await s.page.keyboard.press('Control+5');
      await s.page.waitForTimeout(1500);
      await s.lacks('Marketplace', 'Discover', 'Installed');
      // The quick switcher: the app's places, and no Marketplace among them.
      await s.page.keyboard.press('Control+k');
      await s.sees('Keyboard shortcuts', { within: 10000 });
      await s.sees('Archive');
      await s.lacks('Marketplace');
      await s.shot(`${engine}-Sam-14-switcher`);
      await s.page.keyboard.press('Escape');
      await s.page.waitForTimeout(500);
      await s.press('Settings', { role: 'button' });
      await s.wheelTo('Emoji', 'Keyboard shortcuts');
      await s.press('Keyboard shortcuts');
      await s.sees('Start something new');
      await s.lacks('Marketplace', 'Push to talk', 'Mute or unmute');
      await s.shot(`${engine}-Sam-15-shortcuts`);
    });
    await step('Maya brings her backup up to date from her browser, with her password: what a browser keeps can\'t do it by itself', async () => {
      await m.press('Settings', { role: 'button' });
      await m.wheelTo('Change password', 'Update your backup');
      await m.press('Update your backup');
      await m.sees('Your password first');
      await m.type('Password', maya.password);
      await m.press('Update my backup', { role: 'button' });
      await m.sees('Backup up to date', { within: 60000 });
      await m.shot(`${engine}-Maya-13-backup`);
      await m.press('Messages', { role: 'button' });
    });
    let elsewhere;
    await step('Maya signs in on another browser with her username and password: the same person, her friend there', async () => {
      elsewhere = await Seat.open(await person(), 'Maya (another browser)', origin);
      seats.push(elsewhere);
      await elsewhere.sees('Already have an account?');
      await elsewhere.press('Sign in', { role: 'button', last: true });
      await elsewhere.sees('How to sign in');
      await elsewhere.type('Username', maya.username);
      await elsewhere.type('Password', maya.password);
      await elsewhere.shot(`${engine}-Maya-14-sign-in`);
      const began = Date.now();
      // The app starts again as her: the page loads itself again.
      const loaded = elsewhere.page.waitForEvent('load', { timeout: 120000 });
      await elsewhere.press('Sign in', { role: 'button', last: true });
      await loaded;
      await elsewhere.ready();
      await elsewhere.sees('Messages', { within: 60000 });
      signIn = Date.now() - began;
      await elsewhere.press('Contacts', { role: 'button' });
      await elsewhere.sees(`${sam.username}, Ghost`, { within: 30000 });
      await elsewhere.shot(`${engine}-Maya-15-signed-in`);
      // Her two browsers, in her list of devices, each called what it is: after her password, which a browser keeps
      // nothing in place of.
      await elsewhere.press('Settings', { role: 'button' });
      await elsewhere.press('Signed in on these devices');
      await elsewhere.sees('Your password first');
      await elsewhere.type('Password', maya.password);
      await elsewhere.press('Show my devices', { role: 'button' });
      await elsewhere.sees('Browser · ', { within: 30000 });
      await elsewhere.sees('^A browser\\. Last seen today, signed in today$', { like: true });
      await elsewhere.lacks('Computer', 'Computer · browser', 'Mac', 'Linux');
      await elsewhere.shot(`${engine}-Maya-16-devices`);
    });
    await step('the page\'s own Argon2id gives every vector the app\'s other half is held to', async () => {
      const { vectors } = JSON.parse(readFileSync(join(root, 'test', 'vectors', 'argon2id.json'), 'utf8'));
      const got = await elsewhere.argon2(vectors);
      vectors.forEach((v, i) => {
        if (got[i].got !== v.key) throw new Problem(`a vector fails in the page (${v.m} KiB, ${v.t} passes, ${v.p} lanes, ${JSON.stringify(v.password)}): ${got[i].got}, not ${v.key}.`);
      });
      // The account's own settings (lib/account/account_crypto.dart): 64 MiB, 3 passes, 1 lane.
      const accounts = vectors.findIndex((v) => v.m === 65536 && v.t === 3 && v.p === 1);
      if (accounts < 0) throw new Problem('no vector has the account\'s own settings.');
      stretch = got[accounts].ms;
    });
    await step('in a narrow window it is laid out as a phone: a page over everything, Back to the list; wide again, side by side', async () => {
      // Wide, the devices page stands beside Settings' list, with the handle between them.
      await elsewhere.sees('Resize the list');
      await elsewhere.page.setViewportSize({ width: 390, height: 800 });
      // Narrow, the page that was open covers the list and the rail, as a phone's does, and nothing can be resized.
      await elsewhere.gone('Resize the list');
      await elsewhere.gone('Navigation');
      await elsewhere.sees('Signed in on these devices');
      await elsewhere.shot(`${engine}-Maya-17-narrow-page`);
      // Back (from the devices, then from Me) to Settings' list, the rail beside it again.
      for (let i = 0; i < 4 && !(await elsewhere.words()).includes('Navigation'); i++) {
        await elsewhere.press('Back');
        await elsewhere.page.waitForTimeout(900);
      }
      await elsewhere.sees('Navigation');
      await elsewhere.sees('Appearance');
      await elsewhere.shot(`${engine}-Maya-18-narrow-list`);
      await elsewhere.page.setViewportSize({ width: 1180, height: 780 });
      await elsewhere.sees('Resize the list');
    });
    const afterRemoval = `Sam, after one of Maya's browsers was removed, from ${engine}`;
    await step('Maya removes her first browser from another: it deletes everything of her as it next starts, and hears nothing more for her', async () => {
      await elsewhere.press('Settings', { role: 'button' });
      await elsewhere.press('Signed in on these devices');
      // The page asks for the password again: it held the opened account only while it was open.
      await elsewhere.sees('Your password first');
      await elsewhere.type('Password', maya.password);
      await elsewhere.press('Show my devices', { role: 'button' });
      await elsewhere.press('A browser. Last seen today, signed in today', { within: 30000 });
      await elsewhere.press('Remove', { role: 'button', last: true });
      await elsewhere.gone('A browser. Last seen today, signed in today', { within: 30000 });
      await elsewhere.sees('This device');
      await elsewhere.shot(`${engine}-Maya-19-removed-one`);
      // The removed browser starts again (the next time it is opened): it asks the relay, is told, deletes everything,
      // and loads itself again, at the welcome saying why. Two loads: the one asked for, and the one after the wipe.
      let loads = 0;
      const counted = () => loads++;
      m.page.on('load', counted);
      await m.page.goto(`${origin}/app/`);
      for (const until = Date.now() + 90000; loads < 2;) {
        if (Date.now() > until) throw new Problem('the removed browser never loaded itself again.');
        await m.page.waitForTimeout(200);
      }
      m.page.off('load', counted);
      await m.ready();
      await m.sees('This browser was removed from your account from another device', { within: 60000 });
      await m.sees('Pick a username and a password.');
      await m.shot(`${engine}-Maya-20-removed`);
      const kept = Object.keys(await m.kept());
      if (kept.includes('secret:account_mine')) throw new Problem(`the removed browser still keeps the account's key: ${kept.join(', ')}`);
      // Sam writes to Maya: her other browser hears it, the removed one nothing.
      await s.press('Messages', { role: 'button' });
      await s.press(maya.username);
      await s.write('Encrypted message', afterRemoval);
      await elsewhere.press('Messages', { role: 'button' });
      await elsewhere.sees(afterRemoval, { within: 20000 });
      await m.page.waitForTimeout(2000);
      if ((await m.words()).includes(afterRemoval) || (await m.words()).includes(hello)) throw new Problem('the removed browser still reads what is written to Maya.');
    });
    await step('Maya signs out of her other browser: everything of her is deleted from it, and it opens at the welcome saying so', async () => {
      await elsewhere.press('Settings', { role: 'button' });
      await elsewhere.wheelTo('Change password', 'Sign out of this browser');
      await elsewhere.press('Sign out of this browser');
      await elsewhere.sees('Everything of your account is deleted from it');
      await elsewhere.shot(`${engine}-Maya-21-sign-out`);
      const loaded = elsewhere.page.waitForEvent('load', { timeout: 90000 });
      await elsewhere.press('Sign out and delete', { role: 'button', last: true });
      await loaded;
      await elsewhere.ready();
      await elsewhere.sees('You\'re signed out, and everything of your account was deleted from this browser.', { within: 60000 });
      await elsewhere.shot(`${engine}-Maya-22-signed-out`);
      const kept = Object.keys(await elsewhere.kept());
      if (kept.includes('secret:account_mine')) throw new Problem(`the browser signed out of still keeps the account's key: ${kept.join(', ')}`);
    });
    await step('the next person at that browser signs up, and finds nothing of Maya\'s', async () => {
      const eve = { username: `eve_${tag}`, password: `eve's password ${tag}` };
      await elsewhere.press('Continue', { role: 'button' }).catch(() => {});
      await elsewhere.type('Username', eve.username);
      await elsewhere.type('Password', eve.password);
      await elsewhere.press('Continue', { role: 'button' });
      await elsewhere.gone('Pick a username and a password.', { within: 90000 });
      await elsewhere.sees('Your recovery words');
      await elsewhere.press('Later', { role: 'button' });
      await elsewhere.gone('Your recovery words');
      await elsewhere.press('Messages', { role: 'button' });
      await elsewhere.page.waitForTimeout(2000);
      const words = await elsewhere.words();
      for (const theirs of [sam.username, hello, answer, afterRemoval, inSpace, 'Lighthouse']) {
        if (words.includes(theirs)) throw new Problem(`the next person at Maya's browser sees "${theirs}".`);
      }
      await elsewhere.shot(`${engine}-Eve-1-nothing-of-maya`);
    });
    await step('Maya signs in once more, from a link with a page after its #: her list has that browser alone', async () => {
      // An address that names a page of the app (once, the Marketplace) opens at the welcome, as any does.
      const again = await Seat.open(await person(), 'Maya (once more)', origin, { at: '#/settings/../marketplace' });
      seats.push(again);
      await again.sees('Already have an account?');
      await again.press('Sign in', { role: 'button', last: true });
      await again.sees('A private window is a new device each time');
      await again.type('Username', maya.username);
      await again.type('Password', maya.password);
      const loaded = again.page.waitForEvent('load', { timeout: 120000 });
      await again.press('Sign in', { role: 'button', last: true });
      await loaded;
      await again.ready();
      await again.sees('Messages', { within: 60000 });
      await again.press('Settings', { role: 'button' });
      await again.press('Signed in on these devices');
      await again.type('Password', maya.password);
      await again.press('Show my devices', { role: 'button' });
      await again.sees('This device', { within: 30000 });
      await again.page.waitForTimeout(1000);
      // The browser she removed, and the one she signed out of (which took itself off by its own number), are gone.
      if (/Last seen/.test(await again.words())) throw new Problem(`Maya's list still has other devices: ${(await again.words()).replace(/\n/g, ' | ').slice(0, 600)}`);
      await again.shot(`${engine}-Maya-23-alone`);
    });
    await step('every answer from the app\'s address says what the app may do: the page\'s policy as a header, and the rest of the list', async () => {
      const list = JSON.parse(readFileSync(join(root, 'tool', 'web', 'headers.json'), 'utf8'));
      const page = readFileSync(join(webDir, 'index.html'), 'utf8');
      const meta = /<meta http-equiv="Content-Security-Policy" content="([^"]+)">/.exec(page)?.[1];
      for (const path of ['/app/', '/app/argon2id.js', '/app/nothing-here.js']) {
        const got = await fetch(`${origin}${path}`);
        for (const [name, value] of Object.entries(list.every)) {
          if (got.headers.get(name) !== value) throw new Problem(`${path} says ${name}: ${got.headers.get(name)}, not ${value}.`);
        }
        if (got.headers.get('content-security-policy') !== `${meta}; ${list.frameAncestors}`) throw new Problem(`${path}'s policy is ${got.headers.get('content-security-policy')}`);
      }
    });
    say(`  ${engine}: signing in took ${(signIn / 1000).toFixed(1)} s from the press to the app, signed in (the page loads again on the way); the password itself took ${stretch} ms of it, on a thread of its own.`);
    if (process.env.GHOST_E2E_LOOK) {
      let x = seats[seats.length - 1];
      for (const name of process.env.GHOST_E2E_LOOK.split('>')) {
        if (name === '@sam') {
          x = s;
          continue;
        } else if (name === '@new') {
          x = await Seat.open(await person(), 'Someone new', origin);
          seats.push(x);
        } else if (name.startsWith('~')) {
          const at = await x.where(name.slice(1));
          if (at) {
            await x.page.mouse.move(at.left + 6, at.top + 6);
            await x.page.mouse.wheel(0, 900);
          }
        } else if (name.startsWith('=')) {
          const [label, text] = name.slice(1).split('=');
          await x.type(label, text).catch((e) => say(`  look: ${e.message.slice(0, 200)}`));
        } else {
          await x.press(name).catch((e) => say(`  look: ${e.message.slice(0, 200)}`));
        }
        await x.page.waitForTimeout(1500);
        await x.shot(`look-${engine}-${name.replace(/[^a-z0-9]+/gi, '-')}`);
        say(`  look after "${name}": ${(await x.words()).replace(/\n/g, ' | ').slice(0, 3000)}`);
        if (x.errors.length) say(`  look: errors so far: ${x.errors.join(' || ')}`);
      }
    }
    const missing = new Set(seats.flatMap((x) => [...x.missingFonts]));
    if (missing.size) say(`  ${engine}: the engine asked for ${missing.size} fallback font${missing.size === 1 ? '' : 's'} this build hasn't got (${[...missing].map((p) => p.split('/')[0]).join(', ')}): letters outside the app's own fonts were drawn as boxes. node tool/web/fallback-fonts.mjs --fetch, then build again.`);
    const outside = new Set(seats.flatMap((x) => [...x.outside]));
    // A 404 logged that no missing fallback font accounts for is the page's own error.
    for (const x of seats) x.errors.push(...x.notFound.slice(x.fontMisses).map((e) => `${e} (no missing fallback font to account for it)`));
    const errors = seats.flatMap((x) => x.errors.map((e) => `${x.name}: ${e}`));
    if (outside.size) throw new Problem(`something was asked of ${[...outside].join(', ')}`);
    if (errors.length) throw new Problem(`the page logged errors:\n    ${errors.join('\n    ')}`);
    if (relay.errors.length) throw new Problem(`the relay wrote to stderr: ${relay.errors.join('')}`);
    if (hub?.errors.length) throw new Problem(`the hub's relay wrote to stderr: ${hub.errors.join('')}`);
    return true;
  } catch (e) {
    say(`  FAILED in ${engine}: ${e instanceof Problem ? e.message : e.stack}`);
    for (const x of seats) {
      await x.shot(`${engine}-${x.name}-failed`).catch(() => {});
      if (x.errors.length) say(`    ${x.name}'s page logged: ${x.errors.slice(0, 6).join(' || ')}`);
    }
    return false;
  } finally {
    await browser.close();
    await relay.stop();
    await hub?.stop();
  }
}

let held = true;
for (const engine of engines) {
  held = (await run(engine)) && held;
}
process.exit(held ? 0 : 1);
