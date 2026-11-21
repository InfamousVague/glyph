// The extension's worker: it holds the signed-in account (via the Keeper), captures each service's cookies, and
// keeps the ready ones synced to the account so every device signs in. The popup drives sign-in and manual captures;
// this also re-syncs on its own a few seconds after a service's cookies change, so a fresh sign-in in the browser
// reaches the other devices without another click.
import { GhostAccount, NeedsCode, type CaptureEntry } from './ghost/account.ts';
import { capture } from './ghost/cookies.ts';
import { Keeper } from './ghost/keeper.ts';
import { SERVICES, serviceById } from './ghost/services.ts';

type Reply = Record<string, unknown>;

/** The signed-in account, loaded lazily from the keeper. null = signed out. */
let account: GhostAccount | null = null;
let loaded = false;

async function current(): Promise<GhostAccount | null> {
  if (!loaded) {
    const held = await Keeper.load();
    account = held ? GhostAccount.fromSession(held) : null;
    loaded = true;
  }
  return account;
}

/** A short word for where a capture came from, shown on the other devices' side if ever surfaced. */
const FROM = 'Chrome';

/** What the popup sees about each service: its name, whether it is signed in in the browser, and what is synced. */
async function status(): Promise<Reply> {
  const acct = await current();
  const synced = acct ? await acct.entries().catch(() => ({} as Record<string, CaptureEntry>)) : {};
  const services = await Promise.all(
    SERVICES.map(async (s) => {
      const cap = await capture(s);
      return { id: s.id, name: s.name, signInUrl: s.signInUrl, ready: cap.ready, missing: cap.missing, synced: !!synced[s.id], syncedAt: synced[s.id]?.at ?? null };
    }),
  );
  return { signedIn: !!acct, address: acct?.address ?? null, username: acct?.username ?? null, services };
}

/** Captures the ready services (or just `only`) and syncs them. Returns the updated status. */
async function captureAndSync(only?: string): Promise<Reply> {
  const acct = await current();
  if (!acct) return { error: 'Sign in to your Ghost account first.' };
  const entries: Record<string, CaptureEntry> = {};
  for (const s of SERVICES) {
    if (only && s.id !== only) continue;
    const cap = await capture(s);
    if (cap.ready) entries[s.id] = { cookies: cap.cookies, at: Date.now(), from: FROM };
  }
  if (Object.keys(entries).length === 0) {
    return { ...(await status()), note: only ? 'You are not signed in to that service in this browser.' : 'No services are signed in to in this browser yet.' };
  }
  try {
    await acct.sync(entries);
    await rememberSynced(entries);
  } catch (e) {
    return { ...(await status()), error: (e as Error).message };
  }
  return status();
}

// --- auto-sync when a service's cookies change ----------------------------------------------------------------------

const DOMAINS = new Set(SERVICES.flatMap((s) => s.domains.map((d) => d.replace(/^\./, ''))));
let timer: ReturnType<typeof setTimeout> | undefined;

function domainWatched(domain: string): boolean {
  const d = domain.replace(/^\./, '');
  for (const base of DOMAINS) if (d === base || d.endsWith(`.${base}`)) return true;
  return false;
}

/** A per-service fingerprint of the cookies last synced, so we don't re-seal an unchanged login. */
async function rememberSynced(entries: Record<string, CaptureEntry>): Promise<void> {
  const prints: Record<string, string> = {};
  for (const [id, e] of Object.entries(entries)) prints[id] = fingerprint(e.cookies);
  const had = ((await chrome.storage.local.get('synced-prints'))['synced-prints'] as Record<string, string>) ?? {};
  await chrome.storage.local.set({ 'synced-prints': { ...had, ...prints } });
}

function fingerprint(cookies: Record<string, string>): string {
  return Object.keys(cookies).sort().map((k) => `${k}=${cookies[k]}`).join(';');
}

async function autoSync(): Promise<void> {
  const acct = await current();
  if (!acct) return;
  const prints = ((await chrome.storage.local.get('synced-prints'))['synced-prints'] as Record<string, string>) ?? {};
  const entries: Record<string, CaptureEntry> = {};
  for (const s of SERVICES) {
    const cap = await capture(s);
    if (cap.ready && fingerprint(cap.cookies) !== prints[s.id]) entries[s.id] = { cookies: cap.cookies, at: Date.now(), from: FROM };
  }
  if (Object.keys(entries).length === 0) return;
  try {
    await acct.sync(entries);
    await rememberSynced(entries);
  } catch {
    // Offline or signed out: the next cookie change, or a popup open, tries again.
  }
}

chrome.cookies.onChanged.addListener((info) => {
  if (!domainWatched(info.cookie.domain)) return;
  clearTimeout(timer);
  timer = setTimeout(() => void autoSync(), 4000);
});

// --- messages from the popup ----------------------------------------------------------------------------------------

chrome.runtime.onMessage.addListener((msg: { type: string; [k: string]: unknown }, _sender, sendResponse) => {
  (async (): Promise<Reply> => {
    switch (msg.type) {
      case 'status':
        return status();
      case 'signInWords': {
        try {
          const acct = await GhostAccount.signInWithWords(msg.words as string[]);
          await Keeper.save({ ...acct.session, stay: !!msg.stay });
          account = acct;
          loaded = true;
          return captureAndSync();
        } catch (e) {
          return { error: (e as Error).message };
        }
      }
      case 'signInPassword': {
        try {
          const acct = await GhostAccount.signInWithPassword(msg.username as string, msg.password as string, { number: msg.number as string | undefined, code: msg.code as string | undefined });
          await Keeper.save({ ...acct.session, stay: !!msg.stay });
          account = acct;
          loaded = true;
          return captureAndSync();
        } catch (e) {
          return { error: (e as Error).message, needsCode: e instanceof NeedsCode };
        }
      }
      case 'signOut':
        await Keeper.clear();
        account = null;
        loaded = true;
        await chrome.storage.local.remove('synced-prints');
        return { signedIn: false };
      case 'sync':
        return captureAndSync(msg.serviceId as string | undefined);
      case 'forget': {
        const acct = await current();
        if (acct && serviceById(msg.serviceId as string)) {
          await acct.forget(msg.serviceId as string).catch(() => undefined);
          const prints = ((await chrome.storage.local.get('synced-prints'))['synced-prints'] as Record<string, string>) ?? {};
          delete prints[msg.serviceId as string];
          await chrome.storage.local.set({ 'synced-prints': prints });
        }
        return status();
      }
      default:
        return { error: `unknown message ${msg.type}` };
    }
  })().then(sendResponse);
  return true; // reply is async
});
