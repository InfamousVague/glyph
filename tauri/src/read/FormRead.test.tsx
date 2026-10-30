import { act } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { newEncryptionKey, publicKeyOf } from '../app/core/orgs/wrap.ts';
import type { Shared } from '../app/share/share.ts';
import { button, press, show, waitUntil } from '../test/render.tsx';
import { formOf } from './form.ts';

/*
 * A form from a share link, filled in on the reader page (FormRead.tsx, docs/FORMS.md): its introduction and fields,
 * what is missing said beside each, the answers sent sealed and the owner's thanks; a form paused, closed or taken
 * down saying so in place of its fields; and the reader drawing a shared form as a form rather than a note.
 */

await vi.hoisted(async () => (await import('../test/stubs.ts')).stubMatchMedia());

const BODY = [
  '# Report a bug',
  '',
  'Tell us what went wrong.',
  '',
  '```form',
  "thanks: Thanks, we'll look into it.",
  'button: Send report',
  '- Summary: short, required',
  '- What happened: long, required',
  '- How bad: choice (Annoying | Blocking)',
  '- Your email: email',
  '```',
].join('\n');

const shared: Shared = { v: 1, kind: 'note', title: 'Report a bug', pages: [{ title: 'Report a bug', body: BODY }], at: 1 };

vi.mock('../app/share/share.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../app/share/share.ts')>()),
  readShared: vi.fn(async () => shared),
}));

const { FormRead } = await import('./FormRead.tsx');
const { Reader } = await import('./Reader.tsx');

/** A service that answers each request in turn, and keeps what was sent. */
function service(answers: { status: number; body: unknown }[]) {
  const sent: { url: string; method: string; body: string | null }[] = [];
  const fetcher = vi.fn(async (url: string, init: RequestInit) => {
    sent.push({ url, method: init.method ?? 'GET', body: (init.body as string | undefined) ?? null });
    const next = answers.shift() ?? { status: 500, body: { error: 'nothing more' } };
    return new Response(JSON.stringify(next.body), { status: next.status, headers: { 'Content-Type': 'application/json' } });
  }) as unknown as typeof fetch;
  return { sent, fetcher };
}

/** `value` typed into a field, as React hears typing. */
function type(field: Element | null, value: string) {
  if (!(field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement)) throw new Error('no field to type into');
  const proto = field instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  act(() => {
    Object.getOwnPropertyDescriptor(proto, 'value')!.set!.call(field, value);
    field.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

const ID = 'Zm9ybS1vbmUtc2hhcmUtaWQ';

describe('a form on the reader page', () => {
  it('says what is missing, then sends only the seal and thanks the visitor in the owner’s words', async () => {
    const pub = await publicKeyOf(await newEncryptionKey());
    const { fetcher, sent } = service([
      { status: 200, body: { state: 'open', keys: [pub], ticket: 'ticket-1', wait: 0, limit: 65536, files: false } },
      { status: 202, body: { id: 'x' } },
    ]);
    const host = show(<FormRead id={ID} title="Report a bug" body={BODY} def={formOf(BODY)!} fetcher={fetcher} />);
    await waitUntil(() => expect(host.querySelector('form')).toBeTruthy());
    expect(host.querySelector('h1')?.textContent).toBe('Report a bug');
    expect(host.textContent).toContain('Tell us what went wrong.');
    expect([...host.querySelectorAll('label, legend')].map((l) => l.textContent)).toEqual(['Summary', 'What happened', 'How bad optional', 'Annoying', 'Blocking', 'Your email optional', 'Website']);
    // The hidden field is a bot's: out of the tab order, and hidden from a screen reader.
    const trap = host.querySelector<HTMLInputElement>('input[name="website"]')!;
    expect(trap.tabIndex).toBe(-1);
    expect(trap.closest('[aria-hidden="true"]')).toBeTruthy();

    press(button('Send report'));
    expect(host.textContent).toContain('This one is needed.');
    expect(host.querySelector('#field-Summary')?.getAttribute('aria-invalid')).toBe('true');
    expect(sent).toHaveLength(1);

    type(host.querySelector('#field-Summary'), 'Crash on launch');
    type(host.querySelector('#field-What-happened'), 'It closes at once.');
    type(host.querySelector('#field-Your-email'), 'ana@example.com');
    press(host.querySelector('input[value="Blocking"]'));
    press(button('Send report'));
    await waitUntil(() => expect(host.querySelector('h1')?.textContent).toBe('Sent'));
    expect(host.textContent).toContain("Thanks, we'll look into it.");
    expect(sent.map((s) => [s.method, s.url])).toEqual([
      ['GET', `https://ghostmarkdown.com/api/forms/${ID}`],
      ['POST', `https://ghostmarkdown.com/api/forms/${ID}`],
    ]);
    const body = JSON.parse(sent[1]!.body!) as Record<string, unknown>;
    expect(Object.keys(body).sort()).toEqual(['blob', 'hp', 'id', 'ticket', 'wraps']);
    for (const word of ['Crash', 'ana@example.com', 'Blocking', 'Summary']) expect(sent[1]!.body).not.toContain(word);
  });

  it('says why when the form takes no answers, in place of its fields', async () => {
    for (const [answer, words] of [
      [{ status: 200, body: { state: 'paused' } }, 'This form is paused'],
      [{ status: 200, body: { state: 'closed' } }, 'This form is closed.'],
      [{ status: 404, body: { error: 'There is no form at that link.' } }, 'This form was taken down.'],
    ] as const) {
      const { fetcher } = service([answer]);
      const host = show(<FormRead id={ID} title="Report a bug" body={BODY} def={formOf(BODY)!} fetcher={fetcher} />);
      await waitUntil(() => expect(host.textContent).toContain(words));
      expect(host.querySelector('form')).toBeNull();
      host.remove();
    }
  });

  it('shows the service’s refusal and keeps what was typed', async () => {
    const pub = await publicKeyOf(await newEncryptionKey());
    const { fetcher } = service([
      { status: 200, body: { state: 'open', keys: [pub], ticket: 't', wait: 0, limit: 65536, files: false } },
      { status: 429, body: { error: 'Too many answers from here in an hour. Try again later.' } },
    ]);
    const host = show(<FormRead id={ID} title="Report a bug" body={BODY} def={formOf(BODY)!} fetcher={fetcher} />);
    await waitUntil(() => expect(host.querySelector('form')).toBeTruthy());
    type(host.querySelector('#field-Summary'), 'Crash');
    type(host.querySelector('#field-What-happened'), 'It closes.');
    press(button('Send report'));
    await waitUntil(() => expect(host.querySelector('[role="alert"]')?.textContent).toBe('Too many answers from here in an hour. Try again later.'));
    expect(host.querySelector<HTMLInputElement>('#field-Summary')?.value).toBe('Crash');
  });

  it('is what the reader draws for a shared form, with no question of where to read it', async () => {
    globalThis.fetch = vi.fn(async () => new Response(JSON.stringify({ state: 'closed' }), { status: 200 })) as unknown as typeof fetch;
    history.replaceState(null, '', `/read.html#${ID}.${'b'.repeat(43)}`);
    const host = show(<Reader />);
    await waitUntil(() => expect(host.textContent).toContain('This form is closed.'));
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(host.querySelector('.cm-editor')).toBeNull();
  });
});
