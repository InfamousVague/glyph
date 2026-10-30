import { describe, expect, it } from 'vitest';
import { newEncryptionKey, publicKeyOf, unwrapWith } from '../app/core/orgs/wrap.ts';
import { fromBase64Url, openBytes } from '../app/core/sync/crypto.ts';
import { formOf, introOf, payloadOf, problemsOf, sealAnswer, sealContext, sendAnswer, standingOf, wrapContext, type AnswerPayload, type Sealed } from './form.ts';

/*
 * A form from a share link (form.ts, docs/FORMS.md): the fence read as lib/forms/form_def.dart reads it, what is typed
 * checked, the answers sealed to every recipient and opened with a recipient's pair alone, and the send - its wait,
 * its one retry when the form changed, and the service's refusals in its own words.
 */

const BUG = [
  '# Report a bug',
  '',
  'Tell us what went wrong. We read every one.',
  '',
  '```form',
  'to: [[Bug reports]]',
  'ticket: Bug: {Summary}',
  'template: Bug report',
  "thanks: Thanks, we'll look into it.",
  'button: Send report',
  '- Summary: short, required',
  '- What happened: long, required',
  '- How bad: choice (Annoying | Blocking | Lost work)',
  '- Your email: email, optional',
  '- Screenshot: file',
  '- Time: 10:30 or so',
  '- Summary: long',
  '```',
  '',
  'Thank you.',
].join('\n');

async function opened(pair: CryptoKeyPair, mine: string, form: string, answer: string, sealed: Sealed): Promise<AnswerPayload> {
  const wrap = sealed.wraps.find((w) => w.to === mine)!;
  const raw = await unwrapWith(pair, wrap.wrap, wrapContext(form, answer));
  const key = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['decrypt']);
  return JSON.parse(new TextDecoder().decode(await openBytes(key, fromBase64Url(sealed.blob), sealContext(form, answer)))) as AnswerPayload;
}

describe('a form’s fence', () => {
  it('reads its fields, their kinds and whether each is needed, and what it says around them', () => {
    const def = formOf(BUG)!;
    expect(def.to).toBe('Bug reports');
    expect(def.ticket).toBe('Bug: {Summary}');
    expect(def.template).toBe('Bug report');
    expect(def.thanks).toBe("Thanks, we'll look into it.");
    expect(def.button).toBe('Send report');
    expect(def.fields).toEqual([
      { label: 'Summary', kind: 'short', required: true, options: [] },
      { label: 'What happened', kind: 'long', required: true, options: [] },
      { label: 'How bad', kind: 'choice', required: false, options: ['Annoying', 'Blocking', 'Lost work'] },
      { label: 'Your email', kind: 'email', required: false, options: [] },
      { label: 'Screenshot', kind: 'file', required: false, options: [] },
      // A colon that starts no kind is the label's own.
      { label: 'Time: 10:30 or so', kind: 'short', required: false, options: [] },
    ]);
    expect(introOf(BUG)).toBe('# Report a bug\n\nTell us what went wrong. We read every one.\n\nThank you.');
  });

  it('is none for a note without one, and takes the plainer spellings', () => {
    expect(formOf('# Notes\n\n```js\nform\n```')).toBeNull();
    const def = formOf('~~~ form\n- Name*\n- Size: select (S, M, L), required\n- Notes: paragraph\n- Pick: choice\n~~~')!;
    expect(def.fields).toEqual([
      { label: 'Name', kind: 'short', required: true, options: [] },
      { label: 'Size', kind: 'choice', required: true, options: ['S', 'M', 'L'] },
      { label: 'Notes', kind: 'long', required: false, options: [] },
      // A choice with nothing to choose is a line to type.
      { label: 'Pick', kind: 'short', required: false, options: [] },
    ]);
  });
});

describe('what is typed', () => {
  const def = formOf(BUG)!;
  it('names what is missing or wrong, field by field', () => {
    expect(problemsOf(def, {})).toEqual({ Summary: 'This one is needed.', 'What happened': 'This one is needed.' });
    expect(problemsOf(def, { Summary: 'Crash', 'What happened': 'It crashed', 'Your email': 'not an address', 'How bad': 'Mild' })).toEqual({
      'Your email': 'That doesn’t look like an email address.',
      'How bad': 'Choose one of these.',
    });
    expect(problemsOf(def, { Summary: 'x'.repeat(301), 'What happened': 'y' })).toEqual({ Summary: 'That is longer than 300 characters.' });
    const big = new File([new Uint8Array(2 * 1024 * 1024 + 1)], 'big.png', { type: 'image/png' });
    expect(problemsOf(def, { Summary: 'a', 'What happened': 'b' }, { Screenshot: big })).toEqual({ Screenshot: 'That file is larger than 2 MB.' });
    expect(problemsOf(def, { Summary: 'a', 'What happened': 'b', 'Your email': 'ana@example.com', 'How bad': 'Blocking' })).toEqual({});
  });

  it('is sealed in the form’s order, blanks left out, the file beside the words', async () => {
    const file = new File([new Uint8Array([1, 2, 3])], 'shot.png', { type: 'image/png' });
    const payload = await payloadOf(def, { 'What happened': ' It crashed ', Summary: 'Crash', 'Your email': '' }, { Screenshot: file }, 1234);
    expect(payload).toEqual({ v: 1, answers: [['Summary', 'Crash'], ['What happened', 'It crashed']], file: { field: 'Screenshot', name: 'shot.png', type: 'image/png', data: 'AQID' }, at: 1234 });
  });
});

describe('the seal', () => {
  it('opens with each recipient’s pair, in its own form and answer only, and holds no word in the clear', async () => {
    const [sam, ali, stranger] = await Promise.all([newEncryptionKey(), newEncryptionKey(), newEncryptionKey()]);
    const [samPub, aliPub, strangerPub] = await Promise.all([publicKeyOf(sam), publicKeyOf(ali), publicKeyOf(stranger)]);
    const payload: AnswerPayload = { v: 1, answers: [['Summary', 'The app crashes on launch']], at: 1 };
    const sealed = await sealAnswer('form-1', 'answer-1', [samPub, aliPub], payload);
    expect(sealed.wraps.map((w) => w.to)).toEqual([samPub, aliPub]);
    // A wrap of a 32-byte key is 167 characters, the length the service insists on (server/src/forms.rs WRAP_LENGTH).
    expect(sealed.wraps.every((w) => w.wrap.length === 167)).toBe(true);
    expect(fromBase64Url(sealed.blob)[0]).toBe(1);
    expect(atob(sealed.blob.replace(/-/g, '+').replace(/_/g, '/'))).not.toContain('crashes');
    expect(await opened(sam, samPub, 'form-1', 'answer-1', sealed)).toEqual(payload);
    expect(await opened(ali, aliPub, 'form-1', 'answer-1', sealed)).toEqual(payload);
    await expect(opened(stranger, samPub, 'form-1', 'answer-1', sealed)).rejects.toThrow();
    await expect(opened(sam, samPub, 'form-2', 'answer-1', sealed)).rejects.toThrow();
    await expect(opened(sam, samPub, 'form-1', 'answer-2', sealed)).rejects.toThrow();
    expect(strangerPub).not.toBe(samPub);
  });
});

/** A service that answers each request in turn, and keeps what was sent. */
function service(answers: { status: number; body: unknown }[]) {
  const sent: { url: string; method: string; body: Record<string, unknown> | null }[] = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    sent.push({ url, method: init.method ?? 'GET', body: init.body ? (JSON.parse(init.body as string) as Record<string, unknown>) : null });
    const next = answers.shift() ?? { status: 500, body: { error: 'nothing more' } };
    return new Response(JSON.stringify(next.body), { status: next.status, headers: { 'Content-Type': 'application/json' } });
  }) as unknown as typeof fetch;
  return { sent, fetcher };
}

describe('sending', () => {
  it('reads the form’s standing: open with its keys and ticket, paused, closed or gone', async () => {
    const { fetcher, sent } = service([
      { status: 200, body: { state: 'open', keys: ['k1'], ticket: 't1', wait: 3, limit: 65536, files: false } },
      { status: 200, body: { state: 'paused' } },
      { status: 200, body: { state: 'closed' } },
      { status: 404, body: { error: 'There is no form at that link.' } },
    ]);
    expect(await standingOf('f1', fetcher)).toEqual({ state: 'open', keys: ['k1'], ticket: 't1', wait: 3, limit: 65536, files: false });
    expect(await standingOf('f1', fetcher)).toEqual({ state: 'paused' });
    expect(await standingOf('f1', fetcher)).toEqual({ state: 'closed' });
    expect(await standingOf('f1', fetcher)).toEqual({ state: 'gone' });
    expect(sent[0]!.url).toBe('https://ghostmarkdown.com/api/forms/f1');
  });

  it('waits out the form’s seconds, sends only the seal, and asks again once when the form changed', async () => {
    const pair = await newEncryptionKey();
    const mine = await publicKeyOf(pair);
    // A member who left while the page was open: their key was the form's when it opened, and is not now.
    const gone = await publicKeyOf(await newEncryptionKey());
    const { fetcher, sent } = service([
      { status: 409, body: { error: 'This form changed while it was open. Send it again.' } },
      { status: 200, body: { state: 'open', keys: [mine], ticket: 't2', wait: 3, limit: 65536, files: false } },
      { status: 202, body: { id: 'x' } },
    ]);
    const waited: number[] = [];
    const payload: AnswerPayload = { v: 1, answers: [['Summary', 'Crash']], at: 5 };
    const id = await sendAnswer('f1', { state: 'open', keys: [gone], ticket: 't1', wait: 3, limit: 65536, files: false }, payload, {
      fetcher,
      openedAt: 1000,
      now: () => 2000,
      wait: async (ms) => void waited.push(ms),
    });
    expect(waited).toEqual([2250, 3000]);
    expect(sent.map((s) => s.method)).toEqual(['POST', 'GET', 'POST']);
    const last = sent[2]!.body!;
    expect(Object.keys(last).sort()).toEqual(['blob', 'hp', 'id', 'ticket', 'wraps']);
    expect(last.ticket).toBe('t2');
    expect(last.hp).toBe('');
    expect(last.id).toBe(id);
    expect(JSON.stringify(last)).not.toContain('Crash');
    expect(await opened(pair, mine, 'f1', id, last as unknown as Sealed)).toEqual(payload);
  });

  it('says the service’s own words when it refuses', async () => {
    const { fetcher } = service([{ status: 410, body: { error: 'This form is closed.' } }]);
    await expect(sendAnswer('f1', { state: 'open', keys: [], ticket: 't', wait: 0, limit: 65536, files: false }, { v: 1, answers: [], at: 1 }, { fetcher, wait: async () => undefined })).rejects.toThrow('This form is closed.');
  });
});

/*
 * The seal's one contract with the service: formSeal.fixture.json beside this file is an answer this page sealed, to
 * a fixed key, which server/src/forms_tests.rs `the_reader_s_seal_opens_with_the_fixture_s_key` opens with that key's
 * private half, and which this test opens again. `GLYPH_WRITE_FORM_FIXTURE=1 npx vitest run src/read/form.test.ts`
 * writes it anew.
 */
describe('the seal, across languages', () => {
  it('is an answer sealed here that opens with the fixture’s key', async () => {
    const { readFileSync, writeFileSync } = await import('node:fs');
    const { join } = await import('node:path');
    const path = join(__dirname, 'formSeal.fixture.json');
    const { importEncryptionKey, exportPrivateKey } = await import('../app/core/orgs/wrap.ts');
    if (process.env.GLYPH_WRITE_FORM_FIXTURE === '1') {
      const pair = await newEncryptionKey();
      const pub = await publicKeyOf(pair);
      const payload: AnswerPayload = { v: 1, answers: [['Summary', 'Crash on launch ✓, “quoted”'], ['What happened', 'It closes\nat once.']], at: 1792275541000 };
      const form = 'Zm9ybS1vbmUtc2hhcmUtaWQ';
      const answer = 'YW5zd2VyLWZpeHR1cmUtMDAx';
      const sealed = await sealAnswer(form, answer, [pub], payload);
      writeFileSync(path, `${JSON.stringify({ jwk: await exportPrivateKey(pair), public: pub, form, answer, sealed, payload }, null, 2)}\n`);
    }
    const fixture = JSON.parse(readFileSync(path, 'utf8')) as { jwk: JsonWebKey; public: string; form: string; answer: string; sealed: Sealed; payload: AnswerPayload };
    const pair = await importEncryptionKey(fixture.jwk);
    expect(await publicKeyOf(pair)).toBe(fixture.public);
    expect(await opened(pair, fixture.public, fixture.form, fixture.answer, fixture.sealed)).toEqual(fixture.payload);
  });
});
