import type { Answers, Ask } from '../core/messages.ts';
import { MODES, PICTURE_SCHEME, type ClipMode } from '../core/kinds.ts';
import { linkedWords } from '../core/pictures.ts';
import { canSave, draftOf, initial, MODE_NAMES, reduce, type Event, type State } from './state.ts';

/**
 * The popup: draws the state (state.ts) and does what each event asks of the world, by asking the background
 * (core/messages.ts). It holds no keys and no session, only what the person is typing and what the page answered.
 *
 * The tab it clips is the one the person opened it on. A `?tab=<id>` in its address names another, which only the
 * end-to-end proof uses: it opens the popup as a page of its own beside the page it clips (e2e/clip.e2e.test.ts).
 */

function ask<K extends Ask['type']>(question: Extract<Ask, { type: K }>): Promise<Answers[K]> {
  return chrome.runtime.sendMessage(question) as Promise<Answers[K]>;
}

let state = initial();
let tabId: number | null = null;
let shownView = '';
const app = document.getElementById('app')!;

function h<K extends keyof HTMLElementTagNameMap>(tag: K, props: Record<string, unknown> = {}, ...children: (Node | string | null | false)[]): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (value === undefined || value === null || value === false) continue;
    if (key.startsWith('on')) el.addEventListener(key.slice(2), value as EventListener);
    else if (key === 'className') el.className = String(value);
    else if (key in el && typeof value !== 'string') (el as unknown as Record<string, unknown>)[key] = value;
    else el.setAttribute(key, String(value));
  }
  for (const child of children) if (child !== null && child !== false) el.append(child);
  return el;
}

const byId = <T extends HTMLElement>(id: string) => document.getElementById(id) as T | null;

function top(signedIn: boolean): HTMLElement {
  return h(
    'div',
    { className: 'top' },
    h('img', { className: 'mark', src: 'icons/mark.svg', alt: '' }),
    h('span', { className: 'name' }, 'Ghost.md'),
    signedIn ? h('span', { className: 'who' }, h('span', { id: 'handle' }, state.handle), h('button', { className: 'quiet', id: 'signout', onclick: () => void signOut() }, 'Sign out')) : null,
  );
}

// --- the views ----------------------------------------------------------------------------

function signInView(): HTMLElement[] {
  const submit = (e: SubmitEvent) => {
    e.preventDefault();
    dispatch({ type: 'signIn' });
  };
  return [
    top(false),
    h('p', { className: 'lede' }, 'Sign in to save pages into your notes. A clip is encrypted here, with your account’s key, before it leaves this browser.'),
    h(
      'form',
      { id: 'signin', onsubmit: submit, style: 'display:flex;flex-direction:column;gap:var(--space-3)' },
      h('label', { className: 'field' }, 'Handle', h('input', { type: 'text', id: 'handle-in', autocomplete: 'username', spellcheck: 'false', value: state.handle, oninput: (e: InputEvent) => dispatch({ type: 'type', field: 'handle', value: (e.target as HTMLInputElement).value }) })),
      h('label', { className: 'field' }, 'Password', h('input', { type: 'password', id: 'password-in', autocomplete: 'current-password', value: state.password, oninput: (e: InputEvent) => dispatch({ type: 'type', field: 'password', value: (e.target as HTMLInputElement).value }) })),
      h(
        'label',
        { className: 'check' },
        h('input', { type: 'checkbox', id: 'stay', checked: state.stay, onchange: (e: Event & { target: HTMLInputElement }) => dispatch({ type: 'stay', value: e.target.checked }) }),
        h(
          'span',
          {},
          'Stay signed in',
          h('small', {}, 'Off, the clipper forgets you when the browser closes. On, it keeps an encrypted session on this computer and a key of its own to renew it, so anyone using this browser profile can save to your notes.'),
        ),
      ),
      h('div', { className: 'error', id: 'error', role: 'alert' }),
      h('button', { className: 'solid', type: 'submit', id: 'signin-button' }, 'Sign in'),
    ),
  ];
}

function clipView(): HTMLElement[] {
  const modes = h(
    'div',
    { className: 'modes', role: 'group', 'aria-label': 'What to clip' },
    ...MODES.map((mode) => h('button', { type: 'button', 'data-mode': mode, onclick: () => chooseMode(mode) }, MODE_NAMES[mode])),
  );
  const edit = (field: 'title' | 'tags' | 'comment' | 'workspace' | 'notebook') => (e: Event & { target: HTMLInputElement }) => dispatch({ type: 'edit', field, value: e.target.value });
  return [
    top(true),
    modes,
    h('label', { className: 'field' }, 'Title', h('input', { type: 'text', id: 'title', oninput: edit('title') })),
    h('div', { className: 'preview', id: 'preview' }),
    h('div', { className: 'facts', id: 'facts' }),
    h('label', { className: 'field' }, 'Tags', h('input', { type: 'text', id: 'tags', placeholder: 'reading, later', spellcheck: 'false', oninput: edit('tags') })),
    h(
      'div',
      { className: 'row' },
      h('label', { className: 'field' }, 'Workspace', h('select', { id: 'workspace', onchange: edit('workspace') })),
      h('label', { className: 'field' }, 'Notebook', h('select', { id: 'notebook', onchange: edit('notebook') })),
    ),
    h('label', { className: 'field' }, 'Comment', h('textarea', { id: 'comment', rows: 2, placeholder: 'Why you kept it (optional)', oninput: edit('comment') })),
    h('div', { className: 'error', id: 'error', role: 'alert' }),
    h('button', { className: 'solid', type: 'button', id: 'save', onclick: () => void save() }, 'Save to Ghost.md'),
  ];
}

function savedView(): HTMLElement[] {
  const saved = state.saved!;
  const linked = saved.linked.length;
  const pictures = [saved.stored ? `${saved.stored === 1 ? '1 picture' : `${saved.stored} pictures`} kept in the note.` : '', linked ? `${linkedWords(linked)}.` : ''].filter(Boolean).join(' ');
  return [
    top(true),
    h(
      'div',
      { className: 'done', id: 'done' },
      h('h1', {}, 'Saved to Ghost.md'),
      h('p', {}, h('span', { className: 'title' }, saved.title)),
      h('p', {}, `It is on your devices at their next sync.${pictures ? ` ${pictures}` : ''}`),
    ),
    h(
      'div',
      { className: 'actions' },
      h('button', { className: 'outline', type: 'button', id: 'again', onclick: () => dispatch({ type: 'again' }) }, 'Clip again'),
      h('button', { className: 'solid', type: 'button', id: 'close', onclick: () => window.close() }, 'Done'),
    ),
  ];
}

// --- drawing a state into the view it is in -------------------------------------------------------

function viewOf(s: State): string {
  if (s.phase === 'starting') return 'starting';
  if (s.phase === 'signedOut' || s.phase === 'signingIn') return 'signin';
  if (s.phase === 'saved') return 'saved';
  return 'clip';
}

function setValue(el: HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | null, value: string): void {
  if (el && document.activeElement !== el && el.value !== value) el.value = value;
}

function options(select: HTMLSelectElement | null, items: { id: string; name: string }[], none: string, chosen: string | null): void {
  if (!select) return;
  const want = JSON.stringify(items);
  if (select.dataset.items !== want) {
    select.dataset.items = want;
    select.replaceChildren(h('option', { value: '' }, none), ...items.map((item) => h('option', { value: item.id }, item.name)));
  }
  select.disabled = items.length === 0;
  select.value = chosen ?? '';
}

/** A few lines of what will be saved: the words as Markdown, with pictures said as pictures. */
function previewText(markdown: string): string {
  return markdown
    .replace(new RegExp(`!\\[([^\\]]*)\\]\\(${PICTURE_SCHEME.replace(/\//g, '\\/')}\\d+\\)`, 'g'), (_m, alt: string) => `[picture${alt ? `: ${alt}` : ''}]`)
    .split('\n')
    .slice(0, 14)
    .join('\n');
}

function words(markdown: string): number {
  return markdown.replace(/\(([^)]*)\)/g, ' ').split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w)).length;
}

function drawPreview(s: State): void {
  const preview = byId<HTMLDivElement>('preview');
  const facts = byId<HTMLDivElement>('facts');
  if (!preview || !facts) return;
  const extract = s.extract;
  const key = s.phase === 'reading' ? `reading:${s.mode}` : extract ? `${extract.mode}:${extract.url}:${extract.markdown.length}:${extract.pictures.length}` : 'none';
  if (preview.dataset.key !== key) {
    preview.dataset.key = key;
    preview.className = 'preview';
    if (s.phase === 'reading') {
      preview.classList.add('quiet');
      preview.replaceChildren(h('span', { className: 'quietline' }, s.mode === 'screenshot' ? 'Taking the picture.' : 'Reading the page.'));
    } else if (!extract) {
      preview.classList.add('quiet');
      preview.replaceChildren(h('span', { className: 'quietline' }, 'Nothing to clip here yet.'));
    } else if (extract.mode === 'screenshot') {
      preview.classList.add('picture');
      preview.replaceChildren(h('img', { src: extract.pictures[0]?.url ?? '', alt: 'The visible part of the page' }));
    } else if (extract.mode === 'bookmark') {
      preview.classList.add('quiet');
      preview.replaceChildren(
        h(
          'div',
          { className: 'bookmark' },
          extract.image ? h('img', { src: extract.image, alt: '' }) : null,
          h('div', {}, h('strong', {}, extract.title), extract.description ?? '', h('div', { className: 'quietline' }, extract.url)),
        ),
      );
    } else preview.replaceChildren(h('pre', {}, previewText(extract.markdown)));
  }
  const bits: (string | HTMLElement)[] = [];
  if (extract && s.phase !== 'reading') {
    if (extract.mode !== 'screenshot' && extract.mode !== 'bookmark') bits.push(`${words(extract.markdown).toLocaleString()} words`);
    const pictures = extract.pictures.length;
    if (pictures && extract.mode !== 'screenshot') bits.push(pictures === 1 ? '1 picture' : `${pictures} pictures`);
  }
  facts.replaceChildren(...bits.flatMap((b, i) => (i ? [' · ', b] : [b])));
  if (extract?.notice === 'no-article') facts.append(h('div', { className: 'note' }, 'This page has no article, so the whole page will be clipped.'));
  void offerPictures(facts, s);
}

/** Pictures on other sites than the page's, which the person may let the clipper fetch: a site at a time, never all. */
async function offerPictures(facts: HTMLElement, s: State): Promise<void> {
  const extract = s.extract;
  if (!extract || s.phase === 'reading' || extract.mode === 'screenshot') return;
  let page = '';
  try {
    page = new URL(extract.url).origin;
  } catch {
    return;
  }
  const origins = [...new Set(extract.pictures.map((p) => (/^https?:/.test(p.url) ? new URL(p.url).origin : '')).filter((o) => o && o !== page))];
  if (!origins.length) return;
  const wanted: string[] = [];
  for (const origin of origins) if (!(await chrome.permissions.contains({ origins: [`${origin}/*`] }))) wanted.push(`${origin}/*`);
  if (!wanted.length || facts.querySelector('#allow')) return;
  const count = extract.pictures.filter((p) => wanted.includes(`${/^https?:/.test(p.url) ? new URL(p.url).origin : ''}/*`)).length;
  const line = h(
    'div',
    { className: 'note', id: 'allow-line' },
    `${count === 1 ? '1 picture is' : `${count} pictures are`} on ${wanted.length === 1 ? 'another site' : 'other sites'}, which may keep ${count === 1 ? 'it' : 'them'} from the clipper. `,
    h(
      'button',
      {
        className: 'quiet',
        id: 'allow',
        type: 'button',
        onclick: async () => {
          // The browser asks the person, naming each site; the clipper reads nothing else of them.
          const granted = await chrome.permissions.request({ origins: wanted });
          line.replaceChildren(granted ? 'The clipper may fetch those pictures now.' : 'They stay links if their site keeps them back.');
        },
      },
      'Keep them',
    ),
  );
  facts.append(line);
}

function draw(s: State): void {
  const view = viewOf(s);
  if (view !== shownView) {
    shownView = view;
    if (view === 'starting') app.replaceChildren(top(false), h('p', { className: 'lede' }, 'Opening.'));
    else app.replaceChildren(...(view === 'signin' ? signInView() : view === 'saved' ? savedView() : clipView()));
    if (view === 'signin') (s.handle ? byId<HTMLInputElement>('password-in') : byId<HTMLInputElement>('handle-in'))?.focus();
  }
  const error = byId<HTMLDivElement>('error');
  if (error && error.textContent !== (s.error ?? '')) error.textContent = s.error ?? '';
  if (view === 'signin') {
    const button = byId<HTMLButtonElement>('signin-button');
    if (button) {
      button.disabled = s.phase === 'signingIn';
      button.textContent = s.phase === 'signingIn' ? 'Signing in' : 'Sign in';
    }
    setValue(byId('password-in'), s.password);
  }
  if (view === 'clip') {
    const handle = byId('handle');
    if (handle) handle.textContent = s.handle;
    for (const button of Array.from(app.querySelectorAll<HTMLButtonElement>('.modes button'))) {
      const mode = button.dataset.mode as ClipMode;
      button.setAttribute('aria-pressed', String(mode === s.mode));
      button.disabled = s.phase === 'saving' || (mode === 'selection' && Boolean(s.page) && !s.page!.selected);
      button.title = mode === 'selection' && s.page && !s.page.selected ? 'Select something on the page first' : '';
    }
    setValue(byId('title'), s.form.title);
    setValue(byId('tags'), s.form.tags);
    setValue(byId('comment'), s.form.comment);
    options(byId('workspace'), s.choices.workspaces, 'None', s.form.workspace);
    options(
      byId('notebook'),
      s.choices.notebooks.map((n) => ({ id: n.id, name: n.title })),
      'None',
      s.form.notebook,
    );
    drawPreview(s);
    const save = byId<HTMLButtonElement>('save');
    if (save) {
      save.disabled = !canSave(s) && s.phase !== 'saving';
      if (s.phase === 'saving') save.disabled = true;
      save.textContent = s.phase === 'saving' ? 'Saving' : 'Save to Ghost.md';
    }
  }
}

function dispatch(event: Event): void {
  const before = state;
  state = reduce(state, event);
  draw(state);
  // The one step a state starts by itself: the sign-in, sent once, as the phase becomes signingIn.
  if (before.phase !== 'signingIn' && state.phase === 'signingIn') void signIn(state);
}

// --- what each step asks of the world ---------------------------------------------------------

/** The password goes to the clipper's background, which stretches it (600 000 rounds, a second or two) and sends only the login half. */
async function signIn(s: State): Promise<void> {
  const answer = await ask({ type: 'signIn', handle: s.handle, password: s.password, stay: s.stay });
  if (answer.ok) await signedIn(answer.handle);
  else dispatch({ type: 'signInFailed', error: answer.error });
}

async function signOut(): Promise<void> {
  await ask({ type: 'signOut' });
  dispatch({ type: 'signedOut' });
}

async function signedIn(handle: string): Promise<void> {
  dispatch({ type: 'signedIn', handle });
  if (tabId === null) {
    dispatch({ type: 'readFailed', error: 'There is no page to clip here.' });
    return;
  }
  const choices = ask({ type: 'choices' }).then((answer) => {
    if (answer.ok) dispatch({ type: 'choices', choices: answer.choices });
    else if (answer.signedOut) dispatch({ type: 'signedOut', error: answer.error });
  });
  const peeked = await ask({ type: 'peek', tabId });
  if (!peeked.ok) {
    dispatch({ type: 'readFailed', error: peeked.error });
    return;
  }
  dispatch({ type: 'peeked', page: peeked.page });
  await read(state.mode);
  await choices;
}

async function read(mode: ClipMode): Promise<void> {
  if (tabId === null) return;
  const answer = await ask({ type: 'read', tabId, mode });
  if (state.mode !== mode) return;
  if (answer.ok) dispatch({ type: 'read', extract: answer.extract });
  else dispatch({ type: 'readFailed', error: answer.error });
}

function chooseMode(mode: ClipMode): void {
  if (mode === state.mode && state.extract?.mode === mode) return;
  dispatch({ type: 'mode', mode });
  void read(mode);
}

async function save(): Promise<void> {
  dispatch({ type: 'save' });
  if (state.phase !== 'saving' || tabId === null) return;
  const answer = await ask({ type: 'save', tabId, draft: draftOf(state) });
  if (answer.ok) dispatch({ type: 'saved', saved: answer.saved });
  else dispatch({ type: 'saveFailed', error: answer.error, ...(answer.signedOut ? { signedOut: true } : {}) });
}

async function start(): Promise<void> {
  draw(state);
  const named = Number(new URLSearchParams(location.search).get('tab'));
  if (Number.isInteger(named) && named > 0) tabId = named;
  else tabId = (await chrome.tabs.query({ active: true, currentWindow: true }))[0]?.id ?? null;
  const who = await ask({ type: 'who' });
  if (who.ok && who.handle) await signedIn(who.handle);
  else dispatch({ type: 'signedOut' });
}

void start();
