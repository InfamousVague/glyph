import type { Choices } from '../core/library.ts';
import type { SavedAnswer } from '../core/messages.ts';
import { parseTags, type Draft } from '../core/note.ts';
import type { ClipMode } from '../core/kinds.ts';
import type { Extract, Peek } from '../core/page.ts';

/**
 * The popup as states and events: pure, so every path through it is a test (test/popup-state.test.ts), and the popup
 * itself (popup.ts) only draws a state and does what an event asks of the world.
 *
 *   starting ──who──▶ signedOut ──signIn──▶ signingIn ──signedIn──▶ reading ──read──▶ ready ──save──▶ saving ──saved──▶ saved
 *                 └──────────────signedIn──────────────────────────┘    ▲   └─mode─┘                │
 *                                                                       └───────────────saveFailed──┘ (back to ready, said)
 *
 * A failure is said in words and leaves the person where they can try again. A refusal that ends the session (the
 * background answers `signedOut`) goes back to the sign-in, with the handle kept.
 */

export type Phase = 'starting' | 'signedOut' | 'signingIn' | 'reading' | 'ready' | 'saving' | 'saved';

export interface Form {
  title: string;
  tags: string;
  comment: string;
  workspace: string | null;
  notebook: string | null;
}

export interface State {
  phase: Phase;
  handle: string;
  /** What the person is typing, only while signed out; emptied once it is sent. */
  password: string;
  stay: boolean;
  mode: ClipMode;
  page: Peek | null;
  extract: Extract | null;
  form: Form;
  /** Whether the person changed the title: a mode chosen afterwards keeps theirs. */
  titled: boolean;
  choices: Choices;
  error: string | null;
  saved: SavedAnswer | null;
}

export type Event =
  | { type: 'signedOut'; error?: string }
  | { type: 'signedIn'; handle: string }
  | { type: 'type'; field: 'handle' | 'password'; value: string }
  | { type: 'stay'; value: boolean }
  | { type: 'signIn' }
  | { type: 'signInFailed'; error: string }
  | { type: 'peeked'; page: Peek }
  | { type: 'mode'; mode: ClipMode }
  | { type: 'read'; extract: Extract }
  | { type: 'readFailed'; error: string }
  | { type: 'choices'; choices: Choices }
  | { type: 'edit'; field: keyof Form; value: string | null }
  | { type: 'save' }
  | { type: 'saved'; saved: SavedAnswer }
  | { type: 'saveFailed'; error: string; signedOut?: boolean }
  | { type: 'again' };

export const MODE_NAMES: Readonly<Record<ClipMode, string>> = {
  article: 'Article',
  selection: 'Selection',
  page: 'Full page',
  bookmark: 'Bookmark',
  screenshot: 'Screenshot',
};

export function initial(): State {
  return {
    phase: 'starting',
    handle: '',
    password: '',
    stay: false,
    mode: 'article',
    page: null,
    extract: null,
    form: { title: '', tags: '', comment: '', workspace: null, notebook: null },
    titled: false,
    choices: { workspaces: [], notebooks: [] },
    error: null,
    saved: null,
  };
}

/** The mode a page opens on: what the person selected, else the article. */
export function startingMode(page: Peek): ClipMode {
  return page.selected ? 'selection' : 'article';
}

export function reduce(state: State, event: Event): State {
  switch (event.type) {
    case 'signedOut':
      return { ...initial(), phase: 'signedOut', handle: state.handle, stay: state.stay, error: event.error ?? null };
    case 'type':
      if (state.phase !== 'signedOut') return state;
      return { ...state, [event.field]: event.value, error: null };
    case 'stay':
      return state.phase === 'signedOut' ? { ...state, stay: event.value } : state;
    case 'signIn':
      if (state.phase !== 'signedOut') return state;
      if (!state.handle.trim() || !state.password) return { ...state, error: 'Type your handle and password.' };
      return { ...state, phase: 'signingIn', error: null };
    case 'signInFailed':
      return state.phase === 'signingIn' ? { ...state, phase: 'signedOut', password: '', error: event.error } : state;
    case 'signedIn':
      return { ...state, phase: 'reading', handle: event.handle, password: '', error: null };
    case 'peeked':
      return { ...state, page: event.page, mode: state.extract ? state.mode : startingMode(event.page) };
    case 'mode':
      if (state.phase !== 'ready' && state.phase !== 'reading') return state;
      return { ...state, phase: 'reading', mode: event.mode, error: null };
    case 'read': {
      if (state.phase !== 'reading' || event.extract.mode !== state.mode && !(state.mode === 'article' && event.extract.notice === 'no-article')) return state;
      const title = state.titled ? state.form.title : event.extract.title;
      return { ...state, phase: 'ready', extract: event.extract, form: { ...state.form, title } };
    }
    case 'readFailed':
      return state.phase === 'reading' ? { ...state, phase: 'ready', extract: null, error: event.error } : state;
    case 'choices': {
      // A workspace or notebook chosen before, and no longer there, is no choice.
      const workspace = event.choices.workspaces.some((w) => w.id === state.form.workspace) ? state.form.workspace : null;
      const notebook = event.choices.notebooks.some((n) => n.id === state.form.notebook) ? state.form.notebook : null;
      return { ...state, choices: event.choices, form: { ...state.form, workspace, notebook } };
    }
    case 'edit':
      if (state.phase !== 'ready' && state.phase !== 'reading') return state;
      return {
        ...state,
        form: { ...state.form, [event.field]: event.field === 'workspace' || event.field === 'notebook' ? event.value || null : (event.value ?? '') },
        titled: state.titled || event.field === 'title',
        error: null,
      };
    case 'save':
      if (!canSave(state)) return state.phase === 'ready' && !state.form.title.trim() ? { ...state, error: 'Give the note a title.' } : state;
      return { ...state, phase: 'saving', error: null };
    case 'saved':
      return state.phase === 'saving' ? { ...state, phase: 'saved', saved: event.saved } : state;
    case 'saveFailed':
      if (state.phase !== 'saving') return state;
      if (event.signedOut) return reduce(state, { type: 'signedOut', error: event.error });
      return { ...state, phase: 'ready', error: event.error };
    case 'again':
      return state.phase === 'saved' ? { ...state, phase: 'ready', saved: null } : state;
  }
}

/** Whether Save does anything: a page read for the mode, and a title. */
export function canSave(state: State): boolean {
  return state.phase === 'ready' && Boolean(state.extract) && Boolean(state.form.title.trim());
}

/** What is sent to be saved. */
export function draftOf(state: State): Draft {
  const extract = state.extract!;
  return {
    mode: extract.mode,
    url: extract.url,
    title: state.form.title.trim(),
    markdown: extract.markdown,
    pictures: extract.pictures,
    ...(extract.description ? { description: extract.description } : {}),
    tags: parseTags(state.form.tags),
    comment: state.form.comment,
    workspace: state.form.workspace,
    notebook: state.form.notebook,
  };
}
