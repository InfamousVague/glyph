import { API_BASE, ApiError } from '../app/core/account/api.ts';
import { wrapFor } from '../app/core/orgs/wrap.ts';
import { sealBytes, toBase64Url, type Bytes } from '../app/core/sync/crypto.ts';

/*
 * A form from a share link (docs/FORMS.md; Matt, 2026-10-30, the ninth of the plain-Markdown features he asked for:
 * "add all 12"): a shared note holding a ```form fence is drawn as a form a visitor fills in, and what they send is
 * sealed HERE, in their browser, to the form's owner (or to every member of the team whose form it is), so the service
 * only ever holds ciphertext (server/src/forms.rs). Their device files each answer as a ticket in a notebook
 * (lib/forms/form_inbox.dart).
 *
 * The fence, the same grammar lib/forms/form_def.dart reads:
 *
 *   ```form
 *   to: [[Bug reports]]          the notebook its tickets go into (left out of the share)
 *   ticket: Bug: {Summary}       a ticket's title, a field's answer in braces (left out of the share)
 *   template: Bug report         a ticket template to start from (left out of the share)
 *   thanks: Thanks, we'll look into it.
 *   button: Send report
 *   - Summary: short, required
 *   - What happened: long, required
 *   - How bad: choice (Annoying | Blocking | Lost work)
 *   - Your email: email, optional
 *   - Screenshot: file
 *   ```
 *
 * A field is `- Label: kind`, the kind short (one line), long (a paragraph), choice (one of the options in brackets,
 * split by `|` or `,`), email or file, then `required` or `optional` (optional unless it says). A field with no kind is
 * short. What the note says outside the fence is the form's introduction.
 */

export type FieldKind = 'short' | 'long' | 'choice' | 'email' | 'file';

export interface FormField {
  label: string;
  kind: FieldKind;
  required: boolean;
  options: string[];
}

export interface FormDef {
  fields: FormField[];
  thanks: string | null;
  button: string | null;
  to: string | null;
  ticket: string | null;
  template: string | null;
}

/** The most fields a form has, and how long a label or an option may be. */
export const MOST_FIELDS = 30;
const LABEL_LIMIT = 80;
/** How long an answer may be: a short one, a long one. */
export const SHORT_LIMIT = 300;
export const LONG_LIMIT = 10_000;
/** The most a file may be, before it is sealed: about two megabytes, under the service's 3 MB for a sealed answer. */
export const FILE_BYTES = 2 * 1024 * 1024;

const FENCE = /^(`{3,}|~{3,})\s*form\s*$/i;
const KINDS: Record<string, FieldKind> = {
  short: 'short', text: 'short', line: 'short',
  long: 'long', paragraph: 'long', textarea: 'long',
  choice: 'choice', select: 'choice', choose: 'choice',
  email: 'email',
  file: 'file', attachment: 'file', upload: 'file',
};
const FIELD = /^\s*[-*+]\s+(.+?)\s*$/;
const SPEC = /^(?:([a-z]+)\b\s*(?:\(([^)]*)\))?)?\s*(.*)$/i;
const SETTING = /^\s*(to|notebook|ticket|title|template|thanks|button)\s*:\s*(.*?)\s*$/i;

/** Where the first ```form fence of `body` is: its opening line and its closing one, or null for none. */
export function fenceIn(body: string): { open: number; close: number; lines: string[] } | null {
  const lines = body.split('\n');
  for (let at = 0; at < lines.length; at += 1) {
    const opened = FENCE.exec(lines[at]!.trim());
    if (!opened) continue;
    const mark = opened[1]!;
    for (let end = at + 1; end < lines.length; end += 1) {
      const line = lines[end]!.trim();
      if (line.startsWith(mark[0]!.repeat(mark.length)) && line.replace(/[`~]/g, '') === '') return { open: at, close: end, lines };
    }
    return { open: at, close: lines.length, lines };
  }
  return null;
}

const unlinked = (text: string) => text.replace(/^\[\[(.*)\]\]$/, '$1').trim();

/** One field out of what follows its `- `: its label and its spec, split at the last colon whose spec reads as one. */
function fieldOf(text: string): FormField | null {
  let label = text;
  let spec = '';
  for (let at = text.lastIndexOf(':'); at > 0; at = text.lastIndexOf(':', at - 1)) {
    const rest = text.slice(at + 1).trim();
    const word = /^[a-z]+/i.exec(rest)?.[0]?.toLowerCase() ?? '';
    if (rest === '' || word in KINDS || word === 'required' || word === 'optional') {
      label = text.slice(0, at);
      spec = rest;
      break;
    }
  }
  label = label.trim();
  let required = false;
  if (label.endsWith('*')) {
    required = true;
    label = label.slice(0, -1).trim();
  }
  if (!label) return null;
  const parts = SPEC.exec(spec)!;
  const word = (parts[1] ?? '').toLowerCase();
  const kind = KINDS[word];
  // A spec whose first word is no kind is all flags: `- Summary: required`.
  const flags = (kind ? parts[3] ?? '' : spec).toLowerCase().split(',').map((flag) => flag.trim());
  if (flags.includes('required')) required = true;
  if (flags.includes('optional')) required = false;
  const options = kind === 'choice' && parts[2] ? parts[2].split(/[|,]/).map((o) => o.trim().slice(0, LABEL_LIMIT)).filter((o, i, all) => o && all.indexOf(o) === i).slice(0, MOST_FIELDS) : [];
  return { label: label.slice(0, LABEL_LIMIT), kind: kind === 'choice' && options.length === 0 ? 'short' : kind ?? 'short', required, options };
}

/** The form `body` holds, or null for a note with no ```form fence. Two fields of one label are one, the first. */
export function formOf(body: string): FormDef | null {
  const fence = fenceIn(body);
  if (!fence) return null;
  const def: FormDef = { fields: [], thanks: null, button: null, to: null, ticket: null, template: null };
  for (const line of fence.lines.slice(fence.open + 1, fence.close)) {
    const setting = SETTING.exec(line);
    if (setting && !/^\s*[-*+]\s/.test(line)) {
      const value = setting[2]!.trim();
      if (!value) continue;
      switch (setting[1]!.toLowerCase()) {
        case 'to':
        case 'notebook':
          def.to = unlinked(value);
          break;
        case 'ticket':
        case 'title':
          def.ticket = value;
          break;
        case 'template':
          def.template = unlinked(value);
          break;
        case 'thanks':
          def.thanks = value;
          break;
        case 'button':
          def.button = value.slice(0, LABEL_LIMIT);
          break;
      }
      continue;
    }
    const item = FIELD.exec(line);
    if (!item || def.fields.length >= MOST_FIELDS) continue;
    const field = fieldOf(item[1]!);
    if (field && !def.fields.some((f) => f.label.toLowerCase() === field.label.toLowerCase())) def.fields.push(field);
  }
  return def;
}

/** What the note says around its fence, without its front matter: the form's introduction. */
export function introOf(body: string): string {
  const fence = fenceIn(body);
  const lines = body.split('\n');
  const kept = fence ? [...lines.slice(0, fence.open), ...lines.slice(fence.close + 1)] : lines;
  return kept.join('\n').replace(/^---\n[\s\S]*?\n---\n?/, '').replace(/\n{3,}/g, '\n\n').trim();
}

// ---- what is typed --------------------------------------------------------------------------------------------------

/** What a visitor has typed and chosen, by label; the file chosen, by label. */
export type Values = Record<string, string>;
export type Files = Record<string, File | null>;

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** What is wrong with each answer, in a sentence, by label; empty when it will do. */
export function problemsOf(def: FormDef, values: Values, files: Files = {}): Record<string, string> {
  const found: Record<string, string> = {};
  for (const field of def.fields) {
    const value = (values[field.label] ?? '').trim();
    if (field.kind === 'file') {
      const file = files[field.label] ?? null;
      if (!file && field.required) found[field.label] = 'Choose a file.';
      else if (file && file.size > FILE_BYTES) found[field.label] = 'That file is larger than 2 MB.';
      continue;
    }
    if (!value) {
      if (field.required) found[field.label] = field.kind === 'choice' ? 'Choose one.' : 'This one is needed.';
      continue;
    }
    if (field.kind === 'email' && !EMAIL.test(value)) found[field.label] = 'That doesn’t look like an email address.';
    else if (field.kind === 'choice' && !field.options.includes(value)) found[field.label] = 'Choose one of these.';
    else if (field.kind === 'long' ? value.length > LONG_LIMIT : value.length > SHORT_LIMIT) found[field.label] = `That is longer than ${field.kind === 'long' ? LONG_LIMIT : SHORT_LIMIT} characters.`;
  }
  return found;
}

/** What is sealed: the answers in the form's order, the file if one was chosen, and when it was sent (ms). */
export interface AnswerPayload {
  v: 1;
  answers: [string, string][];
  file?: { field: string; name: string; type: string; data: string };
  at: number;
}

export async function payloadOf(def: FormDef, values: Values, files: Files = {}, now = Date.now()): Promise<AnswerPayload> {
  const payload: AnswerPayload = { v: 1, answers: [], at: now };
  for (const field of def.fields) {
    if (field.kind === 'file') {
      const file = files[field.label];
      if (file && !payload.file) payload.file = { field: field.label, name: file.name.slice(0, 200), type: file.type || 'application/octet-stream', data: toBase64Url(new Uint8Array(await file.arrayBuffer())) };
      continue;
    }
    const value = (values[field.label] ?? '').trim();
    if (value) payload.answers.push([field.label, value]);
  }
  return payload;
}

// ---- the seal -------------------------------------------------------------------------------------------------------

/** The contexts an answer's key is wrapped in and its blob sealed in (server/src/forms.rs `wrap_context`, `seal_context`). */
export const wrapContext = (form: string, answer: string) => `form-key:${form}:${answer}`;
export const sealContext = (form: string, answer: string) => `form:${form}:${answer}`;

/** A fresh answer's id: 128 random bits. */
export const newAnswerId = () => toBase64Url(crypto.getRandomValues(new Uint8Array(16)));

export interface Sealed {
  wraps: { to: string; wrap: string }[];
  blob: string;
}

/** `payload` sealed for the recipients `keys`: under a fresh key, as `sealBytes` seals, that key wrapped to each. */
export async function sealAnswer(form: string, answer: string, keys: string[], payload: AnswerPayload): Promise<Sealed> {
  const raw = crypto.getRandomValues(new Uint8Array(32)) as Bytes;
  const key = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt']);
  const blob = toBase64Url(await sealBytes(key, new TextEncoder().encode(JSON.stringify(payload)) as Bytes, sealContext(form, answer)));
  const wraps = await Promise.all(keys.map(async (to) => ({ to, wrap: await wrapFor(to, raw, wrapContext(form, answer)) })));
  raw.fill(0);
  return { wraps, blob };
}

// ---- the service ----------------------------------------------------------------------------------------------------

/** What the form's link says: open with the keys to seal to and its ticket, or paused, closed, or gone. */
export type Standing =
  | { state: 'open'; keys: string[]; ticket: string; wait: number; limit: number; files: boolean }
  | { state: 'paused' }
  | { state: 'closed' }
  | { state: 'gone' };

async function answerOf(response: Response): Promise<unknown> {
  const text = await response.text();
  try {
    return text ? (JSON.parse(text) as unknown) : null;
  } catch {
    return null;
  }
}

function refused(status: number, body: unknown): ApiError {
  const words = body && typeof body === 'object' && 'error' in body && typeof (body as { error: unknown }).error === 'string' ? (body as { error: string }).error : 'The form could not be reached. Try again.';
  return new ApiError(status, words, body);
}

/** The form `id`'s standing, from the service. */
export async function standingOf(id: string, fetcher: typeof fetch = fetch): Promise<Standing> {
  const response = await fetcher(`${API_BASE}/forms/${encodeURIComponent(id)}`, { method: 'GET' });
  const body = await answerOf(response);
  if (response.status === 404) return { state: 'gone' };
  if (!response.ok) throw refused(response.status, body);
  const said = (body ?? {}) as Record<string, unknown>;
  if (said.state === 'paused' || said.state === 'closed') return { state: said.state };
  return {
    state: 'open',
    keys: Array.isArray(said.keys) ? said.keys.filter((k): k is string => typeof k === 'string') : [],
    ticket: typeof said.ticket === 'string' ? said.ticket : '',
    wait: typeof said.wait === 'number' ? said.wait : 3,
    limit: typeof said.limit === 'number' ? said.limit : 64 * 1024,
    files: said.files === true,
  };
}

const sleep = (ms: number) => new Promise((done) => setTimeout(done, ms));

/**
 * The answer sent: sealed for the keys the form's standing names, under its ticket, with the hidden field as the
 * visitor's browser filled it (a person never sees it, so it is empty). Waits out the seconds a form must be open
 * first; a form that changed while open (a member joined) is asked again and sent once more, as is one sent too soon.
 */
export async function sendAnswer(
  id: string,
  standing: Extract<Standing, { state: 'open' }>,
  payload: AnswerPayload,
  options: { hp?: string; openedAt?: number; fetcher?: typeof fetch; now?: () => number; wait?: (ms: number) => Promise<void> } = {},
): Promise<string> {
  const fetcher = options.fetcher ?? fetch;
  const now = options.now ?? Date.now;
  const wait = options.wait ?? sleep;
  const early = (options.openedAt ?? 0) + standing.wait * 1000 + 250 - now();
  if (early > 0) await wait(early);
  const answer = newAnswerId();
  let current = standing;
  for (let attempt = 0; ; attempt += 1) {
    const sealed = await sealAnswer(id, answer, current.keys, payload);
    if (sealed.blob.length > current.limit) throw new ApiError(413, current.files ? 'That is more than this form takes: a file of up to about 2 MB.' : 'That is more than this form takes.');
    const response = await fetcher(`${API_BASE}/forms/${encodeURIComponent(id)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: answer, ticket: current.ticket, wraps: sealed.wraps, blob: sealed.blob, hp: options.hp ?? '' }),
    });
    const body = await answerOf(response);
    if (response.ok) return answer;
    if (attempt === 0 && response.status === 425) {
      await wait(current.wait * 1000);
      continue;
    }
    if (attempt === 0 && response.status === 409) {
      const again = await standingOf(id, fetcher);
      if (again.state !== 'open') throw refused(response.status, body);
      current = again;
      await wait(current.wait * 1000);
      continue;
    }
    throw refused(response.status, body);
  }
}
