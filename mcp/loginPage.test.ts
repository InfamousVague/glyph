import { webcrypto } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { derive, newAccountKey, passwordSalt, ROUNDS, toBase64Url, wrap } from '../src/app/core/sync/crypto.ts';
import { loginPage } from './loginPage.ts';

/**
 * The sign-in page's own script, run in a page as a browser runs it: typed into, submitted, and watched for what it
 * sends. It re-derives the password's halves and unwraps the key by hand, in the person's browser, with the app's
 * salt, rounds and associated data written into it - so this is the test that fails when those drift from
 * core/sync/crypto.ts, which every other hosted test plays with the app's own functions. jsdom has no WebCrypto of its
 * own; the page is given Node's, which is the same API a browser has.
 */

const API = 'https://api.test/glyph/api';
const BASE = 'https://mcp.test/glyph/api/mcp';
const DENY = 'https://claude.test/callback?error=access_denied&state=s1';

/** What the page sent, by address, and its body. */
type Sent = { url: string; body: Record<string, unknown> };

let sent: Sent[] = [];

/** The page put on the document and its script run, with `answer` standing in for the network. */
function openPage(answer: (url: string, body: Record<string, unknown>) => { status: number; body: unknown }) {
  const html = loginPage({ request: 'req-1', who: 'Claude', apiPublic: API, base: BASE, deny: DENY });
  document.body.innerHTML = /<body>([\s\S]*)<script>/.exec(html)![1]!;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init: RequestInit) => {
      const body = JSON.parse(String(init.body)) as Record<string, unknown>;
      sent.push({ url, body });
      const { status, body: reply } = answer(url, body);
      return new Response(JSON.stringify(reply), { status, headers: { 'Content-Type': 'application/json' } });
    }),
  );
  const form = document.getElementById('form') as HTMLFormElement;
  // A browser reaches a form's fields by name on the form itself (`form.handle`), which the script does; jsdom does not.
  for (const name of ['handle', 'password']) Object.defineProperty(form, name, { get: () => form.elements.namedItem(name) });
  new Function(/<script>([\s\S]*)<\/script>/.exec(html)![1]!)();
  const submit = (handle: string, password: string) => {
    (form.querySelector('[name="handle"]') as HTMLInputElement).value = handle;
    (form.querySelector('[name="password"]') as HTMLInputElement).value = password;
    form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
  };
  const said = () => {
    const err = document.getElementById('err')!;
    return err.hidden ? null : document.getElementById('err-words')!.textContent;
  };
  return { submit, said, go: document.getElementById('go') as HTMLButtonElement };
}

beforeEach(() => {
  sent = [];
  vi.stubGlobal('crypto', webcrypto);
});
afterEach(() => {
  vi.unstubAllGlobals();
  document.body.innerHTML = '';
});

describe('the sign-in page’s script', () => {
  it('signs in as the app does and hands over the account key it unwrapped, never the password', async () => {
    const key = await newAccountKey();
    const { login, wrapKey } = await derive('correct horse', passwordSalt('Matt'), ROUNDS);
    const wrapped = await wrap(key, wrapKey);
    const page = openPage((url) =>
      url === `${API}/v1/login` ? { status: 200, body: { token: 'tok-9', wrapped, account: { handle: 'matt', id: 7 } } } : { status: 200, body: { redirect: 'https://claude.test/callback?code=c1' } },
    );
    page.submit(' Matt ', 'correct horse');
    await vi.waitFor(() => expect(sent).toHaveLength(2), { timeout: 15_000, interval: 20 });
    // The login half the app sends, for the handle as typed, trimmed: the salt lower-cases it.
    expect(sent[0]).toEqual({ url: `${API}/v1/login`, body: { handle: 'Matt', loginSecret: login } });
    expect(sent[1]!.url).toBe(`${BASE}/authorize/complete`);
    expect(sent[1]!.body).toEqual({ request: 'req-1', handle: 'matt', token: 'tok-9', accountKey: toBase64Url(new Uint8Array(await webcrypto.subtle.exportKey('raw', key))) });
    expect(JSON.stringify(sent)).not.toContain('correct horse');
  });

  it('says what went wrong in words, and lets the person try again', async () => {
    const page = openPage(() => ({ status: 401, body: { error: 'Wrong handle or password.' } }));
    page.submit('matt', '');
    expect(page.said()).toBe('The password is missing.');
    expect(sent).toHaveLength(0);
    page.submit('', 'x');
    expect(page.said()).toBe('The handle is missing.');
    page.submit('matt', 'wrong horse');
    await vi.waitFor(() => expect(page.said()).toBe('Wrong handle or password.'), { timeout: 15_000, interval: 20 });
    expect(page.go.disabled).toBe(false);
    expect(sent).toHaveLength(1);
  });

  it('says so when the password opens no key, and does not hand anything over', async () => {
    const key = await newAccountKey();
    const { wrapKey } = await derive('another password', passwordSalt('matt'), ROUNDS);
    const wrapped = await wrap(key, wrapKey);
    const page = openPage(() => ({ status: 200, body: { token: 'tok-9', wrapped, account: { handle: 'matt', id: 7 } } }));
    page.submit('matt', 'correct horse');
    await vi.waitFor(() => expect(page.said()).toBe('This account’s key would not open with that password.'), { timeout: 15_000, interval: 20 });
    expect(sent.map((s) => s.url)).toEqual([`${API}/v1/login`]);
  });
});
