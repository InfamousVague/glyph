// The popup: a thin view over the worker. It sends typed messages and renders the status the worker returns; the
// worker holds the account and does the crypto and syncing.
interface ServiceStatus {
  id: string;
  name: string;
  signInUrl: string;
  ready: boolean;
  missing: string[];
  synced: boolean;
  syncedAt: number | null;
}
interface Status {
  signedIn: boolean;
  google?: { synced: boolean; syncedAt: number | null; open: boolean; incognito: boolean };
  address: string | null;
  username: string | null;
  services: ServiceStatus[];
  error?: string;
  note?: string;
  needsCode?: boolean;
}

const $ = <T extends HTMLElement>(id: string): T => document.getElementById(id) as T;
const send = (msg: Record<string, unknown>): Promise<Status> => chrome.runtime.sendMessage(msg) as Promise<Status>;

function say(text: string, tone: 'bad' | 'good' | '' = ''): void {
  const m = $('message');
  if (!text) {
    m.hidden = true;
    return;
  }
  m.hidden = false;
  m.textContent = text;
  m.className = `message${tone ? ` ${tone}` : ''}`;
}

function when(at: number | null): string {
  if (!at) return '';
  const mins = Math.round((Date.now() - at) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs} h ago`;
  return `${Math.round(hrs / 24)} d ago`;
}

function render(s: Status): void {
  $('signedout').hidden = s.signedIn;
  $('signedin').hidden = !s.signedIn;
  ($('signout') as HTMLButtonElement).hidden = !s.signedIn;
  if (s.error) say(s.error, 'bad');
  else if (s.note) say(s.note);
  else say('');

  if (!s.signedIn) return;
  $('who').textContent = s.username ? `@${s.username}` : (s.address ?? 'Signed in');
  const list = $('services');
  list.innerHTML = '';
  for (const svc of s.services) {
    const li = document.createElement('li');
    li.className = 'svc';
    const badge = svc.synced
      ? `<span class="badge ok">Synced · ${when(svc.syncedAt)}</span>`
      : svc.ready
        ? '<span class="badge">Signed in here</span>'
        : '<span class="badge off">Not signed in here</span>';
    const actions = svc.ready
      ? `<button data-sync="${svc.id}">${svc.synced ? 'Re-sync' : 'Sync now'}</button>${svc.synced ? `<button data-forget="${svc.id}">Stop syncing</button>` : ''}`
      : `<a href="${svc.signInUrl}" target="_blank" rel="noreferrer">Open ${svc.name} to sign in</a>`;
    li.innerHTML = `<div class="svc-top"><span class="svc-name">${svc.name}</span>${badge}</div><div class="svc-row">${actions}</div>`;
    list.appendChild(li);
  }
  // Google Messages, set up in a private window (GMFB-10).
  const g = s.google;
  if (g) {
    const badge = $('google-badge');
    badge.textContent = g.synced ? `Synced · ${when(g.syncedAt)}` : g.open ? 'Waiting for sign-in' : 'Not set up';
    badge.className = `badge${g.synced ? ' ok' : g.open ? '' : ' off'}`;
    $('google-incognito').hidden = g.incognito;
    ($('google-setup') as HTMLButtonElement).textContent = g.synced ? 'Set up again' : 'Set up Google Messages';
    ($('google-forget') as HTMLButtonElement).hidden = !g.synced;
  }
  list.querySelectorAll<HTMLButtonElement>('[data-sync]').forEach((b) =>
    b.addEventListener('click', () => act(() => send({ type: 'sync', serviceId: b.dataset.sync }), 'Synced.')),
  );
  list.querySelectorAll<HTMLButtonElement>('[data-forget]').forEach((b) =>
    b.addEventListener('click', () => act(() => send({ type: 'forget', serviceId: b.dataset.forget }), 'Stopped syncing that service.')),
  );
}

async function act(run: () => Promise<Status>, ok?: string): Promise<void> {
  say('Working…');
  try {
    const s = await run();
    render(s);
    if (ok && !s.error) say(ok, 'good');
  } catch (e) {
    say((e as Error).message || 'Something went wrong.', 'bad');
  }
}

// Tabs.
function tab(which: 'password' | 'words'): void {
  $('tab-password').classList.toggle('on', which === 'password');
  $('tab-words').classList.toggle('on', which === 'words');
  $('form-password').hidden = which !== 'password';
  $('form-words').hidden = which !== 'words';
}
$('tab-password').addEventListener('click', () => tab('password'));
$('tab-words').addEventListener('click', () => tab('words'));

$('form-password').addEventListener('submit', (e) => {
  e.preventDefault();
  const username = ($('username') as HTMLInputElement).value.trim();
  const password = ($('password') as HTMLInputElement).value;
  const code = ($('code') as HTMLInputElement).value.trim() || undefined;
  const stay = ($('stay-p') as HTMLInputElement).checked;
  if (!username || !password) return say('Enter your username and password.', 'bad');
  act(async () => {
    const s = await send({ type: 'signInPassword', username, password, code, stay });
    if (s.needsCode) $('code-row').hidden = false;
    return s;
  });
});

$('form-words').addEventListener('submit', (e) => {
  e.preventDefault();
  const words = ($('words') as HTMLTextAreaElement).value.trim().toLowerCase().split(/[\s,]+/).filter(Boolean);
  const stay = ($('stay-w') as HTMLInputElement).checked;
  if (words.length < 12) return say('Enter all 12 of your recovery words.', 'bad');
  act(() => send({ type: 'signInWords', words, stay }));
});

$('syncall').addEventListener('click', () => act(() => send({ type: 'sync' }), 'Captured and synced.'));
$('google-setup').addEventListener('click', () => act(() => send({ type: 'googleSetup' })));
$('google-forget').addEventListener('click', () => act(() => send({ type: 'forget', serviceId: 'gmessages' }), 'Stopped syncing Google Messages.'));
$('signout').addEventListener('click', () => act(() => send({ type: 'signOut' })));

act(() => send({ type: 'status-note' }));
