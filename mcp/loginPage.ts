import { GHOST_MARK, GHOST_MARK_BOX } from '../src/app/art/ghostMark.ts';
import { ROUNDS } from '../src/app/core/sync/crypto.ts';
// The app's typeface, for the sign-in page: scripts/build-mcp.mjs folds the file into the bundle as a data URL.
import INTER from '@fontsource-variable/inter/files/inter-latin-wght-normal.woff2';

/**
 * The hosted server's sign-in page (mcp/hosted.ts, `/authorize`): the one page a person sees when they connect
 * Claude to their account, which says what the connection can do and asks for the handle and password. Its own script
 * does what a phone does at sign-in (core/sync/crypto.ts) in the person's browser - derives the password's two halves,
 * sends the login half to the sync service, unwraps the account key with the other - and hands the key and the token
 * to the server; the password never leaves the browser. The rounds the password is stretched by are the app's own
 * `ROUNDS`, written into the script, so the two cannot drift; loginPage.test.ts runs the script against them.
 */

function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch] ?? ch);
}

/** The page's icons: strokes on currentColor on the app's own 24 grid (art/Icons.tsx), so they sit with the words. */
const ICON = {
  lock: 'M7 11V8a5 5 0 0 1 10 0v3M7.5 11h9a2.5 2.5 0 0 1 2.5 2.5v5a2.5 2.5 0 0 1-2.5 2.5h-9A2.5 2.5 0 0 1 5 18.5v-5A2.5 2.5 0 0 1 7.5 11z',
  key: 'M4 15a4 4 0 1 0 8 0a4 4 0 1 0-8 0zM10.8 12.2 20 3M17 6l2 2M14.5 8.5l2 2',
  leave: 'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9',
  arrow: 'M5 12h14M13 6l6 6-6 6',
  mark: 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0zM12 7.5V13M12 16.5v.01',
};
const icon = (d: string) => `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${d}" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

/**
 * The picture at the top: Ghost.md's mark (art/ghostMark.ts), its lines in the page's ink and its paper in the page's
 * paper, so it turns over with the page; the wisp over its head drifts, as the app's smoke does.
 */
function art(): string {
  const shapes = GHOST_MARK.map((shape) => `<path class="${shape.ink ? 'ink' : 'paper'} ${shape.part}" d="${shape.d}"/>`).join('');
  return `<svg class="art" viewBox="${GHOST_MARK_BOX}" aria-hidden="true">${shapes}</svg>`;
}

/**
 * The sign-in page, in the app's own clothes: Inter, carried in the bundle so the page needs nothing from anywhere;
 * the ink scale from ink.css, paper by day and the same page printed in reverse by night; the shape art above and
 * icons drawn on the same grid as the app's. A state is said with a word and a shape, not a colour, so the one
 * message the page can show is ink with a mark beside it. What the page does - derive, sign in, unwrap, hand over -
 * is the script at the bottom, and none of it moved.
 */
export function loginPage({ request, who, apiPublic, base, deny }: { request: string; who: string; apiPublic: string; base: string; deny: string }): string {
  const name = escapeHtml(who);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Ghost.md · Let ${name} use your notes</title>
<style>
  @font-face { font-family: 'Inter Variable'; font-style: normal; font-weight: 100 900; font-display: swap; src: url(${INTER}) format('woff2-variations'); }
  :root {
    color-scheme: light dark;
    --g1: oklch(0.995 0 0); --g3: oklch(0.955 0 0); --g4: oklch(0.925 0 0); --g5: oklch(0.895 0 0); --g7: oklch(0.8 0 0); --g9: oklch(0.56 0 0); --g11: oklch(0.36 0 0); --g12: oklch(0.16 0 0);
  }
  @media (prefers-color-scheme: dark) {
    :root { --g1: oklch(0.11 0 0); --g3: oklch(0.17 0 0); --g4: oklch(0.205 0 0); --g5: oklch(0.24 0 0); --g7: oklch(0.34 0 0); --g9: oklch(0.6 0 0); --g11: oklch(0.8 0 0); --g12: oklch(0.965 0 0); }
  }
  :root { --paper: var(--g1); --paper-2: var(--g3); --paper-3: var(--g5); --rule: var(--g4); --ink: var(--g12); --ink-2: var(--g11); --ink-3: var(--g9); --ink-4: var(--g7); }
  * { box-sizing: border-box; }
  html { background: var(--paper); }
  body {
    margin: 0; min-height: 100dvh; display: grid; place-items: center;
    padding: max(24px, env(safe-area-inset-top)) max(16px, env(safe-area-inset-right)) max(24px, env(safe-area-inset-bottom)) max(16px, env(safe-area-inset-left));
    background: var(--paper); color: var(--ink);
    font-family: 'Inter Variable', ui-sans-serif, system-ui, -apple-system, 'Segoe UI', sans-serif; font-size: 16px; line-height: 1.5;
    -webkit-font-smoothing: antialiased; -webkit-text-size-adjust: 100%;
  }
  main { width: 100%; max-width: 420px; }
  .art { display: block; width: 76px; height: 76px; overflow: visible; color: var(--ink); margin: 0 0 20px -8px; }
  .art * { transform-box: fill-box; }
  .art .ink { fill: var(--ink); }
  .art .paper { fill: var(--paper); }
  .art .wisp { transform-origin: bottom center; animation: wisp 4.8s ease-in-out infinite; }
  @keyframes wisp { 0%, 100% { transform: none; opacity: 1; } 50% { transform: translateY(-5%) rotate(-3deg); opacity: 0.7; } }
  @media (prefers-reduced-motion: reduce) { .art .wisp { animation: none; } }
  .brand { display: flex; align-items: center; gap: 0.5em; margin: 0 0 10px; font-size: 0.875rem; font-weight: 600; letter-spacing: -0.01em; color: var(--ink-3); }
  .brand b { color: var(--ink); font-weight: 700; }
  .brand i { font-style: normal; color: var(--ink-4); }
  h1 { margin: 0 0 12px; font-size: clamp(2rem, 6.4vw, 2.375rem); line-height: 1.06; font-weight: 700; letter-spacing: -0.04em; text-wrap: balance; }
  .lead { margin: 0 0 22px; font-size: 1.0625rem; color: var(--ink-2); text-wrap: pretty; }
  .facts { list-style: none; margin: 0 0 26px; padding: 0; border-top: 1px solid var(--rule); border-bottom: 1px solid var(--rule); }
  .facts li { display: flex; gap: 14px; padding: 13px 0; font-size: 0.9375rem; line-height: 1.45; color: var(--ink-2); text-wrap: pretty; }
  .facts li + li { border-top: 1px solid var(--rule); }
  .facts svg { flex: none; width: 1.35em; height: 1.35em; margin-top: 0.05em; color: var(--ink); }
  .facts strong { color: var(--ink); font-weight: 600; }
  form { display: grid; gap: 14px; }
  label { display: grid; gap: 6px; font-size: 0.875rem; font-weight: 500; color: var(--ink); }
  input {
    width: 100%; margin: 0; padding: 0.85rem 0.95rem; font: inherit; font-size: 1rem; line-height: 1.25; color: var(--ink);
    background: var(--paper-2); border: 1px solid var(--rule); border-radius: 0.625rem; appearance: none;
  }
  input::placeholder { color: var(--ink-4); }
  input:focus { outline: 2px solid var(--ink); outline-offset: 2px; border-color: var(--ink); }
  .actions { display: grid; gap: 10px; margin-top: 6px; }
  button {
    display: inline-flex; align-items: center; justify-content: center; gap: 0.5em; width: 100%; margin: 0; padding: 0.9rem 1.2rem;
    font: inherit; font-size: 1rem; font-weight: 600; line-height: 1.2; letter-spacing: -0.01em; border-radius: 999px; cursor: pointer;
    border: 1px solid var(--ink); background: var(--ink); color: var(--paper);
  }
  button svg { width: 1.1em; height: 1.1em; }
  button[disabled] { opacity: 0.55; cursor: wait; }
  button:focus-visible { outline: 2px solid var(--ink); outline-offset: 3px; }
  .quiet { background: transparent; color: var(--ink-2); border-color: var(--rule); }
  .quiet:hover { border-color: var(--ink-4); color: var(--ink); }
  .err { display: flex; gap: 10px; align-items: flex-start; margin: 0; padding: 12px 14px; font-size: 0.9375rem; line-height: 1.4; color: var(--ink); background: var(--paper-2); border-radius: 0.625rem; }
  .err[hidden] { display: none; }
  .err svg { flex: none; width: 1.3em; height: 1.3em; margin-top: 0.02em; }
</style>
</head>
<body>
<main data-request="${escapeHtml(request)}" data-api="${escapeHtml(apiPublic)}" data-base="${escapeHtml(base)}" data-deny="${escapeHtml(deny)}">
  ${art()}
  <p class="brand"><b>Ghost.md</b><i>·</i><span>Connect</span></p>
  <h1>Let <b>${name}</b> use your notes.</h1>
  <p class="lead">Sign in to your Ghost.md account. ${name} will be able to read your notes, add to them and change them, until you disconnect it.</p>
  <ul class="facts">
    <li>${icon(ICON.lock)}<span><strong>Still end-to-end encrypted.</strong> Your password stays in this browser; the sync service sees the same login half it sees from your phone.</span></li>
    <li>${icon(ICON.key)}<span><strong>Your key, held in memory.</strong> Signing in unlocks your account key here and hands it to Ghost.md's server, which keeps it in memory only, never on disk, while this connection lasts. In that time the server can read your notes: that is what lets ${name}.</span></li>
    <li>${icon(ICON.leave)}<span><strong>Disconnect ${name} and it ends.</strong> So does a week of not using it.</span></li>
  </ul>
  <form id="form" novalidate>
    <label>Handle<input name="handle" autocomplete="username" autocapitalize="none" autocorrect="off" spellcheck="false" required></label>
    <label>Password<input name="password" type="password" autocomplete="current-password" required></label>
    <p class="err" id="err" role="alert" hidden>${icon(ICON.mark)}<span id="err-words"></span></p>
    <div class="actions">
      <button type="submit" id="go"><span id="go-words">Allow</span>${icon(ICON.arrow)}</button>
      <button type="button" class="quiet" id="cancel">Cancel</button>
    </div>
  </form>
</main>
<script>
(() => {
  const main = document.querySelector('main');
  const REQUEST = main.dataset.request, API = main.dataset.api, BASE = main.dataset.base, DENY = main.dataset.deny;
  const form = document.getElementById('form'), go = document.getElementById('go'), goWords = document.getElementById('go-words'), err = document.getElementById('err'), errWords = document.getElementById('err-words');
  const enc = new TextEncoder();
  const b64u = (b) => btoa(String.fromCharCode(...b)).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');
  const unb64u = (t) => { const p = t.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((t.length + 3) % 4); const r = atob(p); const o = new Uint8Array(r.length); for (let i = 0; i < r.length; i++) o[i] = r.charCodeAt(i); return o; };
  const hex = (b) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
  const say = (words) => { errWords.textContent = words; err.hidden = false; go.disabled = false; goWords.textContent = 'Allow'; };
  // The same halves the app derives (core/sync/crypto.ts): the login half goes to the sync service, the wrap half opens the key here.
  async function derive(password, handle) {
    const base = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
    const bits = new Uint8Array(await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: enc.encode('glyph/v1/' + handle.trim().toLowerCase()), iterations: ${ROUNDS} }, base, 512));
    const wrapKey = await crypto.subtle.importKey('raw', bits.slice(32), { name: 'AES-GCM' }, false, ['decrypt']);
    return { login: hex(bits.slice(0, 32)), wrapKey };
  }
  async function unwrap(wrapped, wrapKey) {
    const b = unb64u(wrapped);
    return new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: b.slice(0, 12), additionalData: enc.encode('account-key') }, wrapKey, b.slice(12)));
  }
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    err.hidden = true;
    go.disabled = true;
    goWords.textContent = 'Signing in…';
    const handle = form.handle.value.trim(), password = form.password.value;
    if (!handle || !password) return say(handle ? 'The password is missing.' : 'The handle is missing.');
    try {
      const { login, wrapKey } = await derive(password, handle);
      const r = await fetch(API + '/v1/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ handle, loginSecret: login }) });
      const a = await r.json().catch(() => ({}));
      if (!r.ok) return say(a.error || 'The sync service refused the sign-in.');
      const raw = await unwrap(a.wrapped, wrapKey).catch(() => null);
      if (!raw) return say('This account’s key would not open with that password.');
      const c = await fetch(BASE + '/authorize/complete', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ request: REQUEST, handle: a.account.handle, token: a.token, accountKey: b64u(raw) }) });
      const j = await c.json().catch(() => ({}));
      if (!c.ok) return say(j.error || 'Could not finish signing in.');
      location.assign(j.redirect);
    } catch (failure) {
      // A fetch that never got an answer throws a TypeError; anything else is worth its own words.
      say(failure instanceof TypeError ? 'Could not reach Ghost.md’s sync service. Check the connection and try again.' : 'Something went wrong: ' + (failure && failure.message ? failure.message : failure));
    }
  });
  document.getElementById('cancel').addEventListener('click', () => location.assign(DENY));
})();
</script>
</body>
</html>`;
}
