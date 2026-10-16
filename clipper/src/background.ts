import { ApiError, API_BASE } from '../../tauri/src/app/core/account/api.ts';
import { fromBase64Url } from '../../tauri/src/app/core/sync/crypto.ts';
import { ClipperAccount } from './core/account.ts';
import { extensionRooms, keeper } from './core/keep.ts';
import { choicesOf, refreshLibrary, type LibraryCache } from './core/library.ts';
import type { Answers, Ask } from './core/messages.ts';
import type { Draft } from './core/note.ts';
import type { ClipMode, Extract, Peek } from './core/page.ts';
import { shrinkInBrowser, type Fetched, type PictureFetcher } from './core/pictures.ts';
import { saveClip } from './core/save.ts';
import type { PageClipper } from './content.ts';

/**
 * The clipper's background: the one place the account lives (core/account.ts), so its keys never reach a page or the
 * popup. It answers the popup (core/messages.ts), reads a tab when asked, and saves. The toolbar's popup, the context
 * menu's "Save selection to Ghost.md" and the keyboard shortcut all end here.
 *
 * Permissions, and why each (manifest.ts): `activeTab` and `scripting` to read the tab the person clicked the clipper
 * on, and only that tab, only then; `storage` for the session (core/keep.ts); `contextMenus` for the menu item; the
 * service's own address and nothing else as a host. A picture on another site than the page's is fetched by the page
 * where that site allows it, and otherwise only from a site the person has allowed the clipper to read
 * (`optional_host_permissions`, asked for by the popup's "Keep them" and never at install).
 */

const keep = keeper({ ...extensionRooms(), api: API_BASE });
let held: ClipperAccount | null | undefined;
let library: LibraryCache | null = null;

async function account(): Promise<ClipperAccount | null> {
  if (held === undefined) held = await ClipperAccount.kept({ keeper: keep });
  return held;
}

/** The notebooks as last read, from this browser session's memory: a service worker is stopped when idle and starts again empty. */
async function cachedLibrary(): Promise<LibraryCache | null> {
  if (library) return library;
  const kept = (await chrome.storage.session.get('ghost-library'))['ghost-library'] as LibraryCache | undefined;
  library = kept ?? null;
  return library;
}

async function keepLibrary(next: LibraryCache | null): Promise<void> {
  library = next;
  if (next) await chrome.storage.session.set({ 'ghost-library': next });
  else await chrome.storage.session.remove('ghost-library');
}

// --- the tab ------------------------------------------------------------------------------

/** One of the page's side's three answers (src/content.ts), the script put in the tab the first time it is asked. */
async function inTab<K extends keyof PageClipper>(tabId: number, name: K, args: Parameters<PageClipper[K]>): Promise<Awaited<ReturnType<PageClipper[K]>>> {
  const [present] = await chrome.scripting.executeScript({ target: { tabId }, func: () => Boolean((globalThis as { __ghostClipper?: unknown }).__ghostClipper) });
  if (!present?.result) await chrome.scripting.executeScript({ target: { tabId }, files: ['content.js'] });
  const [done] = await chrome.scripting.executeScript({
    target: { tabId },
    func: (method: string, given: unknown[]) => {
      const page = (globalThis as unknown as { __ghostClipper: Record<string, (...a: unknown[]) => unknown> }).__ghostClipper;
      return page[method]!(...given);
    },
    args: [name, args as unknown[]],
  });
  return done?.result as Awaited<ReturnType<PageClipper[K]>>;
}

const peekTab = (tabId: number) => inTab(tabId, 'peek', []);

/** A picture fetched by the page, as the page itself could have it. */
function fromPage(tabId: number | null): PictureFetcher {
  return async (url, limit) => {
    if (tabId === null) return null;
    const got = await inTab(tabId, 'fetchPicture', [url, limit]).catch(() => null);
    if (!got || got === 'too-big') return got;
    return { type: got.type, bytes: fromBase64Url(got.base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')) };
  };
}

/** A picture fetched by the clipper itself: only from a site the person allowed it to read. */
const fromHere: PictureFetcher = async (url, limit) => {
  let origin: string;
  try {
    origin = `${new URL(url).origin}/*`;
  } catch {
    return null;
  }
  if (!(await chrome.permissions.contains({ origins: [origin] }))) return null;
  const response = await fetch(url, { credentials: 'omit' });
  if (!response.ok) return null;
  const type = response.headers.get('content-type')?.split(';')[0]?.trim() ?? '';
  if (type && !type.startsWith('image/')) return null;
  if (Number(response.headers.get('content-length') ?? 0) > limit) return 'too-big';
  const bytes = new Uint8Array(await response.arrayBuffer());
  return bytes.length > limit ? 'too-big' : ({ type, bytes } satisfies Fetched);
};

/** The tab as the screenshot mode clips it: what the browser shows of it now. */
async function screenshot(tabId: number): Promise<Extract> {
  const tab = await chrome.tabs.get(tabId);
  const shot = await chrome.tabs.captureVisibleTab(tab.windowId, { format: 'png' });
  const page = await peekTab(tabId).catch(() => null);
  const title = page?.title ?? tab.title ?? 'Screenshot';
  return { mode: 'screenshot', url: page?.url ?? tab.url ?? '', title, markdown: '', pictures: [{ url: shot, alt: `Screenshot of ${title}` }] };
}

async function read(tabId: number, mode: ClipMode): Promise<Extract> {
  if (mode === 'screenshot') return screenshot(tabId);
  const answer = await inTab(tabId, 'extract', [mode]);
  if (!answer) throw new Error('This page can’t be clipped.');
  if (!answer.ok) throw new Error(answer.error);
  return answer.extract;
}

// --- saving ---------------------------------------------------------------------------------

async function save(tabId: number | null, draft: Draft) {
  const me = await account();
  if (!me) throw new ApiError(401, 'Sign in first.');
  const saved = await saveClip(me, draft, { fetchers: [fromPage(tabId), fromHere], shrink: shrinkInBrowser, library: await cachedLibrary() });
  await keepLibrary(saved.library);
  return saved;
}

/** Words for a failure, and whether it ended the session. */
function said(failure: unknown): { error: string; signedOut?: boolean } {
  if (failure instanceof ApiError) {
    if (failure.status === 401) return { error: failure.message || 'Your session has ended. Sign in again.', signedOut: true };
    return { error: failure.message };
  }
  const words = failure instanceof Error ? failure.message : String(failure);
  // The browser's own refusals to read a tab, in words a person can act on.
  if (/Cannot access|cannot be scripted|chrome:\/\/|extensions gallery|Missing host permission/i.test(words)) return { error: 'This page can’t be clipped. Browser pages and the extension store are off limits.' };
  return { error: words || 'Something went wrong.' };
}

async function answer(ask: Ask): Promise<Answers[keyof Answers]> {
  switch (ask.type) {
    case 'who': {
      const me = await account();
      return { ok: true, handle: me?.handle ?? null, stay: me?.stays ?? false };
    }
    case 'signIn': {
      held = await ClipperAccount.signIn(ask.handle, ask.password, { stay: ask.stay, keeper: keep });
      await keepLibrary(null);
      return { ok: true, handle: held.handle };
    }
    case 'signOut': {
      await (await account())?.signOut();
      held = null;
      await keepLibrary(null);
      return { ok: true };
    }
    case 'choices': {
      const me = await account();
      if (!me) throw new ApiError(401, 'Sign in first.');
      const next = await refreshLibrary(me, await cachedLibrary());
      await keepLibrary(next);
      return { ok: true, choices: choicesOf(next, (await me.readPrefs()).prefs) };
    }
    case 'peek':
      return { ok: true, page: await peekTab(ask.tabId) };
    case 'read':
      return { ok: true, extract: await read(ask.tabId, ask.mode) };
    case 'save': {
      const saved = await save(ask.tabId, ask.draft);
      return { ok: true, saved: { id: saved.id, title: saved.title, stored: saved.stored, linked: saved.linked } };
    }
  }
}

chrome.runtime.onMessage.addListener((ask: Ask, sender, reply) => {
  // Only the clipper's own pages: a page's script cannot reach this, and the clipper's script in a page never asks.
  if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL(''))) return false;
  answer(ask).then(reply, (failure: unknown) => {
    if (failure instanceof ApiError && failure.status === 401) held = null;
    reply({ ok: false, ...said(failure) });
  });
  return true;
});

// --- the menu, the shortcut, and the badge that answers them ----------------------------------------

const MENU = 'ghost-save-selection';

function menus(): void {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: MENU, title: 'Save selection to Ghost.md', contexts: ['selection'] });
  });
}
chrome.runtime.onInstalled.addListener(menus);
chrome.runtime.onStartup.addListener(menus);

/** A short word on the toolbar button for a save made without the popup, then gone. */
async function badge(tabId: number, text: string, title: string): Promise<void> {
  await chrome.action.setBadgeBackgroundColor({ tabId, color: '#1d1d1d' });
  await chrome.action.setBadgeText({ tabId, text });
  await chrome.action.setTitle({ tabId, title });
  setTimeout(() => {
    void chrome.action.setBadgeText({ tabId, text: '' });
    void chrome.action.setTitle({ tabId, title: 'Ghost.md clipper' });
  }, 6000);
}

/** A clip saved straight away: the selection from the menu, or from the shortcut whatever is selected, else the article. */
async function quickSave(tabId: number, mode: ClipMode | null): Promise<{ ok: boolean; title?: string; error?: string }> {
  try {
    if (!(await account())) {
      await badge(tabId, '!', 'Sign in to Ghost.md first: open the clipper from the toolbar.');
      return { ok: false, error: 'signed out' };
    }
    const chosen = mode ?? ((await peekTab(tabId)).selected ? 'selection' : 'article');
    const extract = await read(tabId, chosen);
    const saved = await save(tabId, { mode: extract.mode, url: extract.url, title: extract.title, markdown: extract.markdown, pictures: extract.pictures, ...(extract.description ? { description: extract.description } : {}), tags: [], comment: '', workspace: null, notebook: null });
    await badge(tabId, '✓', `Saved “${saved.title}” to Ghost.md`);
    return { ok: true, title: saved.title };
  } catch (failure) {
    const { error, signedOut } = said(failure);
    if (signedOut) held = null;
    await badge(tabId, '!', error);
    return { ok: false, error };
  }
}

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === MENU && tab?.id !== undefined) void quickSave(tab.id, 'selection');
});
chrome.commands.onCommand.addListener((command, tab) => {
  if (command === 'save-clip' && tab?.id !== undefined) void quickSave(tab.id, null);
});

// What the end-to-end proof calls in place of a right-click and a key press, which a test cannot make in the browser's
// own menus (e2e/clip.e2e.test.ts). The same function the menu and the shortcut call.
(globalThis as { ghostClipper?: unknown }).ghostClipper = { quickSave };
