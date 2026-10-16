// @vitest-environment node
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { GlyphAccount, importAccountKey, type NoteRecord } from '../../mcp/glyph.ts';
import { bookNoteBody } from '../../tauri/src/app/book/book.ts';
import { signUp } from '../../tauri/src/app/core/account/account.ts';
import { API_BASE } from '../../tauri/src/app/core/account/api.ts';
import { memoryKeys } from '../../tauri/src/app/core/account/keystore.ts';
import { frontMatterValue } from '../../tauri/src/app/core/frontMatter.ts';
import { imageNames } from '../../tauri/src/app/core/imageRefs.ts';
import { noteTitle } from '../../tauri/src/app/core/noteTitle.ts';
import { ROUNDS, type Bytes } from '../../tauri/src/app/core/sync/crypto.ts';
import { fetchFile } from '../../tauri/src/app/core/sync/notes.ts';

/**
 * The clipper in a real Chromium against a real glyph-api: run by e2e/run.mjs, which starts the service, the fixture
 * sites and the build, and skipped otherwise. A made-up account is made with the app's own sign-up code; the person
 * signs in through the popup, clips each mode, and every note is read back through the connector's GlyphAccount
 * (mcp/glyph.ts), its pictures fetched and opened with the app's own sync code. Pictures of the popup and the notes as
 * saved go to e2e/out.
 *
 * The popup is the real one: the toolbar button is pressed through Chrome's DevTools command for it
 * (`Extensions.triggerAction`), which gives the clipper the `activeTab` grant a click gives, and the popup it opens is
 * driven and photographed over its own DevTools connection. The pages are at localhost and the clipper's one host is
 * the service's (127.0.0.1), so every page is read by that grant alone, as it would be on any site.
 */

const ON = process.env.CLIPPER_E2E === '1';
const SITE = process.env.E2E_SITE ?? '';
const EXT = process.env.E2E_EXT ?? '';
const OUT = process.env.E2E_OUT ?? '';
const CDN = process.env.E2E_CDN ?? '';
const PLAYWRIGHT = process.env.PLAYWRIGHT ?? '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
const PNGJS = process.env.PNGJS ?? '/Users/matt/.npm/_npx/249ca9fcd30c476a/node_modules/pngjs/lib/png.js';

/** Only this computer is ever asked, whatever the code under test was given. */
const guarded: typeof fetch = (input, init) => {
  const url = new URL(typeof input === 'string' || input instanceof URL ? input : input.url);
  if (url.hostname !== '127.0.0.1') throw new Error(`e2e: refused a request to ${url.host}`);
  return fetch(input, init);
};

/** A JPEG's size from its frame header. */
function jpegSize(bytes: Uint8Array): { width: number; height: number } | null {
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  for (let i = 2; i < bytes.length; ) {
    if (bytes[i] !== 0xff) return null;
    const marker = bytes[i + 1]!;
    const length = (bytes[i + 2]! << 8) | bytes[i + 3]!;
    if (marker >= 0xc0 && marker <= 0xc3) return { height: (bytes[i + 5]! << 8) | bytes[i + 6]!, width: (bytes[i + 7]! << 8) | bytes[i + 8]! };
    i += 2 + length;
  }
  return null;
}

/**
 * What the proof uses of Playwright, which lives in this Mac's npx cache rather than in the repository (so it has no
 * types here): a persistent context with the extension, its pages, the extension's service worker, and a DevTools
 * session on the browser.
 */
interface Session {
  send(method: string, params?: Record<string, unknown>): Promise<{ targetInfos: { targetId: string; type: string; url: string }[] } & Record<string, unknown>>;
}
interface Worker {
  url(): string;
  evaluate<R, A>(run: (arg: A) => R | Promise<R>, arg: A): Promise<R>;
}
interface Page {
  url(): string;
  goto(url: string): Promise<unknown>;
  bringToFront(): Promise<void>;
  evaluate<R>(run: () => R | Promise<R>): Promise<R>;
}
interface Context {
  serviceWorkers(): Worker[];
  waitForEvent(name: 'serviceworker'): Promise<Worker>;
  pages(): Page[];
  newPage(): Promise<Page>;
  browser(): { newBrowserCDPSession(): Promise<Session> } | null;
  close(): Promise<void>;
}
interface Playwright {
  chromium: { launchPersistentContext(dir: string, options: Record<string, unknown>): Promise<Context> };
}

/** One target's DevTools connection over its own socket: what drives the real popup, which Playwright does not attach to. */
class Cdp {
  private next = 0;
  private readonly waiting = new Map<number, { resolve: (v: unknown) => void; reject: (e: Error) => void }>();
  private constructor(private readonly socket: WebSocket) {
    socket.addEventListener('message', (event) => {
      const message = JSON.parse(String(event.data)) as { id?: number; result?: unknown; error?: { message: string } };
      const waiter = message.id === undefined ? undefined : this.waiting.get(message.id);
      if (!waiter) return;
      this.waiting.delete(message.id!);
      if (message.error) waiter.reject(new Error(message.error.message));
      else waiter.resolve(message.result);
    });
  }

  static open(url: string): Promise<Cdp> {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(url);
      socket.addEventListener('open', () => resolve(new Cdp(socket)));
      socket.addEventListener('error', () => reject(new Error(`could not reach ${url}`)));
    });
  }

  send<T>(method: string, params: Record<string, unknown> = {}): Promise<T> {
    const id = ++this.next;
    this.socket.send(JSON.stringify({ id, method, params }));
    return new Promise<T>((resolve, reject) => this.waiting.set(id, { resolve: resolve as (v: unknown) => void, reject }));
  }

  close(): void {
    this.socket.close();
  }
}

/** The popup as the person has it: what they type, choose and press, and what it shows. */
class Popup {
  constructor(private readonly cdp: Cdp) {}

  async eval<T>(expression: string): Promise<T> {
    const answer = await this.cdp.send<{ result: { value: T }; exceptionDetails?: { text: string; exception?: { description?: string } } }>('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true, userGesture: true });
    if (answer.exceptionDetails) throw new Error(answer.exceptionDetails.exception?.description ?? answer.exceptionDetails.text);
    return answer.result.value;
  }

  async waitFor(expression: string, timeout = 30_000): Promise<void> {
    const until = Date.now() + timeout;
    for (;;) {
      if (await this.eval<boolean>(`Boolean(${expression})`).catch(() => false)) return;
      if (Date.now() > until) throw new Error(`the popup never showed ${expression}; it says: ${await this.eval<string>('document.body.innerText').catch(() => '?')}`);
      await new Promise((r) => setTimeout(r, 100));
    }
  }

  fill(selector: string, value: string): Promise<void> {
    return this.eval(`(() => { const el = document.querySelector(${JSON.stringify(selector)}); el.focus(); el.value = ${JSON.stringify(value)}; el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); el.blur(); })()`);
  }

  choose(selector: string, label: string): Promise<void> {
    return this.eval(`(() => { const el = document.querySelector(${JSON.stringify(selector)}); const o = [...el.options].find((o) => o.textContent === ${JSON.stringify(label)}); if (!o) throw new Error('no option ' + ${JSON.stringify(label)}); el.value = o.value; el.dispatchEvent(new Event('change', { bubbles: true })); })()`);
  }

  click(selector: string): Promise<void> {
    return this.eval(`document.querySelector(${JSON.stringify(selector)}).click()`);
  }

  text(selector: string): Promise<string> {
    return this.eval(`document.querySelector(${JSON.stringify(selector)})?.textContent ?? ''`);
  }

  value(selector: string): Promise<string> {
    return this.eval(`document.querySelector(${JSON.stringify(selector)}).value`);
  }

  attr(selector: string, name: string): Promise<string | null> {
    return this.eval(`document.querySelector(${JSON.stringify(selector)})?.getAttribute(${JSON.stringify(name)}) ?? null`);
  }

  /**
   * The popup as drawn, its whole height, at twice its size so the type can be read. A headless browser keeps a popup
   * at the height it opened at (on a screen Chrome grows it to what it holds, up to 600 px), so what is below is
   * scrolled to and drawn a window at a time, and the pieces put together; DevTools' own size label is kept off it.
   */
  async shot(path: string): Promise<{ width: number; height: number }> {
    await this.cdp.send('Overlay.enable').catch(() => undefined);
    await this.cdp.send('Overlay.setShowViewportSizeOnResize', { show: false }).catch(() => undefined);
    await new Promise((r) => setTimeout(r, 200));
    const size = await this.eval<{ width: number; height: number; inner: number }>('({ width: document.documentElement.clientWidth, height: Math.ceil(document.querySelector("main").getBoundingClientRect().height), inner: innerHeight })');
    const { PNG } = (await import(/* @vite-ignore */ PNGJS)) as { PNG: { new (o: { width: number; height: number }): { data: Buffer; width: number }; sync: { read(b: Buffer): { data: Buffer; width: number; height: number }; write(p: unknown): Buffer } } };
    const whole = new PNG({ width: size.width * 2, height: size.height * 2 });
    for (let y = 0; y < size.height; y += size.inner) {
      const top = await this.eval<number>(`(scrollTo(0, ${y}), scrollY)`);
      const h = Math.min(size.inner, size.height - y);
      const { data } = await this.cdp.send<{ data: string }>('Page.captureScreenshot', { format: 'png', clip: { x: 0, y: top + (y - top), width: size.width, height: h, scale: 2 } });
      const piece = PNG.sync.read(Buffer.from(data, 'base64'));
      for (let row = 0; row < piece.height && (y * 2 + row) < size.height * 2; row += 1) piece.data.copy(whole.data, ((y * 2 + row) * whole.width) * 4, row * piece.width * 4, (row + 1) * piece.width * 4);
    }
    await this.eval('scrollTo(0, 0)');
    writeFileSync(path, PNG.sync.write(whole));
    return size;
  }

  close(): void {
    this.cdp.close();
  }
}

describe.skipIf(!ON)('the clipper, end to end', () => {
  const handle = `clip${Date.now().toString(36)}`;
  const password = 'correct horse battery';
  let context: Context;
  let worker: Worker;
  let browser: Session;
  let extensionId = '';
  let page: Page;
  let claude: GlyphAccount;
  let notebookId = '';
  const titles: Record<string, string> = {};

  beforeAll(async () => {
    // The account, as a phone makes one: the app's own sign-up, at the real rounds.
    await signUp(handle, password, { keys: memoryKeys(), rounds: ROUNDS, fetcher: guarded });
    claude = new GlyphAccount(await GlyphAccount.signIn(API_BASE, handle, password, { fetcher: guarded }), { fetcher: guarded });
    // A workspace and a notebook, as the connector would make them, for the popup to offer.
    await claude.changePrefs((prefs) => ({ ...prefs, workspaces: { list: [{ id: 'w-reading', name: 'Reading room' }], notes: {}, current: null } }));
    notebookId = (await claude.create(bookNoteBody('Reading list', []))).note.id;

    const { chromium } = (await import(/* @vite-ignore */ PLAYWRIGHT)) as Playwright;
    context = await chromium.launchPersistentContext(join(OUT, 'profile'), {
      channel: 'chromium',
      headless: process.env.HEADED !== '1',
      viewport: { width: 1200, height: 800 },
      // DevTools may press the toolbar button (`Extensions.triggerAction`) and reach the popup it opens.
      args: [`--disable-extensions-except=${EXT}`, `--load-extension=${EXT}`, '--enable-unsafe-extension-debugging', `--remote-debugging-port=${process.env.E2E_DEBUG_PORT}`],
    });
    worker = context.serviceWorkers()[0] ?? (await context.waitForEvent('serviceworker'));
    extensionId = new URL(worker.url()).host;
    browser = await context.browser()!.newBrowserCDPSession();
    page = context.pages()[0] ?? (await context.newPage());
  }, 120_000);

  afterAll(async () => {
    await context?.close();
  });

  async function tabOf(p: Page): Promise<number> {
    const url = p.url();
    const id = await worker.evaluate(async (u: string) => (await chrome.tabs.query({})).find((t: chrome.tabs.Tab) => t.url === u)?.id ?? null, url);
    if (id === null) throw new Error(`no tab for ${url}`);
    return id;
  }

  /** The person presses the clipper's toolbar button on `p`'s tab: the real popup, with the `activeTab` grant a press gives. */
  async function popupFor(p: Page): Promise<Popup> {
    await p.bringToFront();
    const { targetInfos } = await browser.send('Target.getTargets', { filter: [{ type: 'tab' }] });
    const tab = targetInfos.find((t) => t.url === p.url());
    if (!tab) throw new Error(`no tab for ${p.url()}`);
    await browser.send('Extensions.triggerAction' as never, { id: extensionId, targetId: tab.targetId } as never);
    const list = `http://127.0.0.1:${process.env.E2E_DEBUG_PORT}/json/list`;
    for (let tries = 0; tries < 100; tries += 1) {
      const targets = (await (await fetch(list)).json()) as { id: string; type: string; url: string; webSocketDebuggerUrl?: string }[];
      const popup = targets.find((t) => t.type === 'page' && t.url === `chrome-extension://${extensionId}/popup.html` && t.webSocketDebuggerUrl);
      if (popup) {
        const opened = new Popup(await Cdp.open(popup.webSocketDebuggerUrl!));
        await opened.waitFor('document.readyState === "complete"');
        return opened;
      }
      await new Promise((r) => setTimeout(r, 100));
    }
    throw new Error('the popup did not open');
  }

  /** A picture of the popup; and the popup must fit a popup's 600 px, Save in sight without scrolling. */
  async function shot(popup: Popup, name: string): Promise<void> {
    const size = await popup.shot(join(OUT, 'shots', `${name}.png`));
    expect(size.height, `${name} is ${size.height} px tall`).toBeLessThanOrEqual(600);
  }

  async function ready(popup: Popup): Promise<void> {
    await popup.waitFor('document.getElementById("save") && !document.getElementById("save").disabled');
  }

  /** Save, and the popup closed by its own Done. */
  async function save(popup: Popup, picture?: string): Promise<string> {
    await popup.click('#save');
    await popup.waitFor('document.getElementById("done")', 60_000);
    if (picture) await shot(popup, picture);
    const title = (await popup.text('#done .title')).trim();
    done = await popup.text('#done');
    await popup.click('#close').catch(() => undefined);
    popup.close();
    return title;
  }
  let done = '';

  async function note(title: string): Promise<NoteRecord> {
    await claude.pull();
    const found = await claude.byTitle(title);
    if (!found) throw new Error(`no note called ${title}`);
    return found;
  }

  /** A note's pictures, fetched from the service and opened as a phone would, kept beside its words in e2e/out/notes. */
  async function pictures(record: NoteRecord): Promise<Record<string, Bytes>> {
    const session = (claude as unknown as { session: { token: string; accountKey: string } }).session;
    const got: Record<string, Bytes> = {};
    const ctx = { token: session.token, key: await importAccountKey(session.accountKey), fetcher: guarded, state: { files: {} }, files: { read: async () => null, write: async (_k: string, name: string, bytes: Bytes) => void (got[name] = bytes) } };
    for (const name of imageNames(record.note.body)) expect(await fetchFile(ctx, 'image', name)).toBe(true);
    const dir = join(OUT, 'notes');
    mkdirSync(join(dir, 'image'), { recursive: true });
    writeFileSync(join(dir, `${noteTitle(record.note.body).replace(/[^\w .()-]/g, '_')}.md`), record.note.body);
    for (const [name, bytes] of Object.entries(got)) writeFileSync(join(dir, 'image', name), bytes);
    return got;
  }

  it('signs in through the popup, and clips an article with everything the popup offers', async () => {
    await page.goto(`${SITE}/article.html`);
    const popup = await popupFor(page);
    await popup.waitFor('document.getElementById("signin")');
    await popup.fill('#handle-in', handle);
    await popup.fill('#password-in', password);
    await shot(popup, 'popup-sign-in');
    await popup.click('#signin-button');
    await ready(popup);
    await popup.waitFor('document.getElementById("notebook").options.length > 1');
    expect(await popup.attr('[data-mode="article"]', 'aria-pressed')).toBe('true');
    expect(await popup.value('#title')).toBe('The Quiet Garden');
    await shot(popup, 'popup-article');

    await popup.fill('#tags', 'reading, garden');
    await popup.choose('#workspace', 'Reading room');
    await popup.choose('#notebook', 'Reading list');
    await popup.fill('#comment', 'For the spring planting.');
    await shot(popup, 'popup-article-filled');
    titles.article = await save(popup, 'popup-saved');
    expect(titles.article).toBe('The Quiet Garden');
    expect(done).toContain('2 pictures kept in the note.');

    const record = await note('The Quiet Garden');
    const body = record.note.body;
    expect(frontMatterValue(body, 'source')).toBe(`${SITE}/article.html`);
    expect(frontMatterValue(body, 'clipped')).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(frontMatterValue(body, 'tags')).toBe('[reading, garden]');
    expect(body).toContain('# The Quiet Garden\n\nFor the spring planting.\n\n---\n\nMost of the work in a *winter* garden');
    expect(body).toContain('## What we covered the beds with');
    expect(body).toContain('  - oak takes longest to break down,');
    expect(record.images).toHaveLength(2);
    const got = await pictures(record);
    for (const bytes of Object.values(got)) expect(jpegSize(bytes)).not.toBeNull();
    expect(jpegSize(got[record.images![0]!]!)).toEqual({ width: 600, height: 400 });
    const { prefs } = await claude.readPrefs();
    expect((prefs.workspaces as { notes: Record<string, string> }).notes[record.note.id]).toBe('w-reading');
    expect((await claude.get(notebookId))?.note.body).toContain('- [[The Quiet Garden]]');
  });

  it('clips the full page, a table and code among it, still signed in', async () => {
    await page.goto(`${SITE}/table-code.html`);
    const popup = await popupFor(page);
    await ready(popup);
    await popup.click('[data-mode="page"]');
    await popup.waitFor('document.querySelector("#preview pre")?.textContent?.includes("| Method | Average | Stable |")');
    await ready(popup);
    await shot(popup, 'popup-full-page');
    titles.page = await save(popup);
    const { body } = (await note(titles.page)).note;
    expect(body).toContain('| Method | Average | Stable |\n| --- | ---: | --- |');
    expect(body).toContain('```js\nfunction insertionSort(a) {');
    expect(body).toContain('- [x] Read the paper\n- [ ] Try it on real data');
  });

  it('clips a selection, which the popup opens on, and nothing round it', async () => {
    await page.goto(`${SITE}/selection.html`);
    await page.evaluate(() => {
      const range = document.createRange();
      range.setStartBefore(document.getElementById('first')!);
      range.setEndAfter(document.getElementById('last')!);
      getSelection()!.removeAllRanges();
      getSelection()!.addRange(range);
    });
    const popup = await popupFor(page);
    await ready(popup);
    expect(await popup.attr('[data-mode="selection"]', 'aria-pressed')).toBe('true');
    await popup.fill('#title', 'Chosen words');
    await shot(popup, 'popup-selection');
    titles.selection = await save(popup);
    const record = await note('Chosen words');
    expect(record.note.body).toContain(`The first chosen paragraph, with a [relative link](${SITE}/linked) and **bold words**.`);
    expect(record.note.body).toContain('- Another item, with `inline code`');
    expect(record.note.body).not.toContain('must not be clipped');
    expect(record.images).toHaveLength(1);
  });

  it('clips a bookmark: the link, the description and the preview picture', async () => {
    await page.goto(`${SITE}/article.html`);
    const popup = await popupFor(page);
    await ready(popup);
    await popup.click('[data-mode="bookmark"]');
    await popup.waitFor('document.querySelector(".bookmark")');
    await ready(popup);
    await popup.fill('#title', 'The Quiet Garden, bookmarked');
    await shot(popup, 'popup-bookmark');
    titles.bookmark = await save(popup);
    const record = await note('The Quiet Garden, bookmarked');
    expect(record.note.body).toContain('How a small city garden keeps its soil alive through the winter.');
    expect(record.note.body).toContain(`](${SITE}/2026/10/the-quiet-garden)`);
    const got = await pictures(record);
    expect(jpegSize(Object.values(got)[0]!)).toEqual({ width: 640, height: 360 });
  });

  it('clips a screenshot of the visible tab, by the activeTab grant alone, as a picture the app keeps', async () => {
    await page.goto(`${SITE}/article.html`);
    const popup = await popupFor(page);
    await ready(popup);
    await popup.click('[data-mode="screenshot"]');
    await popup.waitFor('document.querySelector(".preview.picture img") || document.getElementById("error").textContent');
    expect(await popup.text('#error')).toBe('');
    await ready(popup);
    await popup.fill('#title', 'The garden, as it looked');
    await shot(popup, 'popup-screenshot');
    titles.screenshot = await save(popup);
    const record = await note('The garden, as it looked');
    expect(record.note.body).toMatch(/!\[Screenshot of The Quiet Garden\]\(image\/clip-[\w-]+\.jpg\)/);
    const size = jpegSize(Object.values(await pictures(record))[0]!);
    expect(size?.width).toBe(1200);
    expect(size?.height).toBe(800);
  });

  it('keeps a picture from its own site smaller, one from a site that shares it, and links the rest', async () => {
    await page.goto(`${SITE}/pictures.html`);
    const popup = await popupFor(page);
    await ready(popup);
    await popup.waitFor('document.getElementById("allow-line")');
    expect(await popup.text('#allow-line')).toContain('2 pictures are on another site');
    await shot(popup, 'popup-pictures');
    titles.pictures = await save(popup);
    expect(done).toContain('2 pictures kept in the note. 2 pictures stay links.');
    const record = await note('Pictures from three places');
    const got = await pictures(record);
    expect(record.images!.map((name) => jpegSize(got[name]!))).toEqual([
      { width: 1600, height: 800 },
      { width: 600, height: 400 },
    ]);
    expect(record.note.body).toContain(`![From a site that does not](${CDN}/closed.png)`);
    expect(record.note.body).toContain(`![Too big to keep](${SITE}/pictures/huge.png)`);
  });

  it('saves a selection straight from the menu item, and the article from the shortcut', async () => {
    await page.goto(`${SITE}/table-code.html`);
    await page.evaluate(() => {
      const range = document.createRange();
      range.selectNode(document.querySelector('table')!);
      getSelection()!.removeAllRanges();
      getSelection()!.addRange(range);
    });
    // A right-click on the menu item gives the clipper the same activeTab grant as the button: the button stands in for it here.
    (await popupFor(page)).close();
    await claude.pull();
    const before = (await claude.list()).length;
    const quick = (tab: number, mode: string | null) =>
      worker.evaluate(([id, m]: readonly [number, string | null]) => (globalThis as unknown as { ghostClipper: { quickSave(t: number, m: string | null): Promise<{ ok: boolean; title?: string; error?: string }> } }).ghostClipper.quickSave(id as number, m as string | null), [tab, mode] as const);
    // What the menu item and the shortcut call (src/background.ts `quickSave`): a test cannot open the browser's own menu.
    expect(await quick(await tabOf(page), 'selection')).toEqual({ ok: true, title: 'Sorting in place' });
    await page.goto(`${SITE}/article.html`);
    (await popupFor(page)).close();
    expect(await quick(await tabOf(page), null)).toEqual({ ok: true, title: 'The Quiet Garden' });
    await claude.pull();
    const all = await claude.list();
    expect(all.length).toBe(before + 2);
    const fromMenu = all.filter((r) => r.note.body.includes('| Insertion | O(n²) | yes |') && !r.note.body.includes('```js'));
    expect(fromMenu).toHaveLength(1);
    expect(fromMenu[0]!.note.body).not.toContain('Three ways to sort');
  });

  it('left every note readable by the connector, with nothing it could not open', async () => {
    await claude.pull();
    expect(claude.notices()).toEqual([]);
    const all = await claude.list();
    // The notebook, the six clips from the popup, and the two saved straight away.
    expect(all.length).toBe(1 + 6 + 2);
    // Every note and its pictures, opened, beside each other in e2e/out/notes: a library folder as the app keeps one.
    for (const record of all) await pictures(record);
    writeFileSync(join(OUT, 'notes.json'), JSON.stringify(all.map((r) => ({ id: r.note.id, title: noteTitle(r.note.body), images: r.images ?? [] })), null, 2));
  });
});
