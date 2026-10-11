import { afterEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import type { ModelInfo } from '../core/ai.ts';

/** The models on the phone, as the catalogue reports them; a phone that will not say throws. */
const catalogue = vi.hoisted(() => ({ models: [] as ModelInfo[], fails: false }));
vi.mock('../core/ai.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/ai.ts')>()),
  listModels: async () => {
    if (catalogue.fails) throw new Error('no bridge');
    return catalogue.models;
  },
}));

import { MODELS } from '../core/ai.ts';
import { reloadPreferences, setPreferences } from '../core/preferences.ts';
import { aiChanges, aiChangesField } from '../editor/aiChanges.ts';
import type { Finding } from '../review/findings.ts';
import { findingEdit, landFindings, thinkingModel, wordsOnly } from './review.ts';

let view: EditorView | null = null;
function open(doc: string): EditorView {
  view = new EditorView({ state: EditorState.create({ doc, extensions: [aiChanges()] }) });
  return view;
}
afterEach(() => {
  view?.destroy();
  view = null;
});

const finding = (patch: Partial<Finding> & { change: Finding['change'] }): Finding => ({ id: 'f', check: 'words', what: '', why: '', noteId: 'n', noteTitle: 'N', ...patch });

describe('a finding as an edit on the note', () => {
  it('replaces the last place the words are, marking the old words inline', () => {
    const edit = findingEdit('Fix the seat bar.\nThe seat bar again.\n', finding({ change: { kind: 'replace', find: 'seat bar', replace: 'seek bar' } }), 'r', 'c');
    expect(edit).toMatchObject({ from: 22, to: 30, insert: 'seek bar', record: { from: 22, to: 30, removed: 'seat bar', block: false } });
  });

  it('adds a line where the note would take it, marked as a block', () => {
    const edit = findingEdit('# Trip\n- eggs\n', finding({ change: { kind: 'add', line: '- milk' } }), 'r', 'c');
    expect(edit).toMatchObject({ insert: expect.stringMatching(/milk/i), record: { removed: '', block: true } });
  });

  it('answers null for words no longer there', () => {
    expect(findingEdit('nothing here\n', finding({ change: { kind: 'replace', find: 'seat bar', replace: 'seek bar' } }), 'r', 'c')).toBeNull();
  });
});

describe('landing findings in the note', () => {
  it('lands each in turn as a tracked change, and counts them', () => {
    const v = open('Fix the seat bar.\nCall Sam.\n');
    const landed = landFindings(
      v,
      [
        finding({ id: 'a', change: { kind: 'replace', find: 'seat bar', replace: 'seek bar' } }),
        finding({ id: 'b', change: { kind: 'replace', find: 'Sam', replace: 'Sam about the dog' } }),
        finding({ id: 'c', change: { kind: 'replace', find: 'gone', replace: 'x' } }),
      ],
      'run',
      { wisp: false },
    );
    expect(landed).toBe(2);
    expect(v.state.doc.toString()).toBe('Fix the seek bar.\nCall Sam about the dog.\n');
    expect(v.state.field(aiChangesField).map((c) => c.removed)).toEqual(['seat bar', 'Sam']);
  });
});

describe('the careful model’s words alone', () => {
  it('offers each change the note still has, as a replace', () => {
    const findings = wordsOnly([{ heard: 'seat bar.', careful: 'seek bar.', before: 'the', after: '' }], { id: 'n', title: 'N', body: 'Fix the seat bar.\n' });
    expect(findings).toMatchObject([{ check: 'words', change: { kind: 'replace', find: 'seat bar', replace: 'seek bar' } }]);
    expect(wordsOnly([{ heard: 'gone', careful: 'x', before: '', after: '' }], { id: 'n', title: 'N', body: 'Fix.\n' })).toEqual([]);
  });
});

describe('the model the review thinks with', () => {
  /** These catalogue models on the phone, in this order. */
  const on = (...ids: string[]): ModelInfo[] =>
    ids.map((id) => ({ id, file: `${id}.gguf`, bytes: MODELS.find((m) => m.id === id)!.bytes, present: true, path: `/models/${id}.gguf` }));
  afterEach(() => {
    catalogue.models = [];
    catalogue.fails = false;
    localStorage.clear();
    reloadPreferences();
  });

  it('is the one chosen for formatting, when it is a Qwen and on the phone', async () => {
    catalogue.models = on('qwen3.5-9b', 'qwen3.5-2b');
    setPreferences({ formatModel: 'qwen3.5-2b' });
    expect(await thinkingModel()).toBe('qwen3.5-2b');
  });

  it('is the largest Qwen on the phone when the chosen one does not reason, or is not there', async () => {
    catalogue.models = on('qwen3.5-2b', 'gemma-4-e4b', 'qwen3.5-4b');
    setPreferences({ formatModel: 'gemma-4-e4b' });
    expect(await thinkingModel()).toBe('qwen3.5-4b');
    setPreferences({ formatModel: 'qwen3.5-9b' });
    expect(await thinkingModel()).toBe('qwen3.5-4b');
  });

  it('is the chosen model when no Qwen is on the phone, and none when that is not there either', async () => {
    catalogue.models = on('gemma-4-e4b');
    setPreferences({ formatModel: 'gemma-4-e4b' });
    expect(await thinkingModel()).toBe('gemma-4-e4b');
    setPreferences({ formatModel: 'qwen3.5-4b' });
    expect(await thinkingModel()).toBeNull();
    // A model the catalogue knows but the phone has not downloaded is not there.
    catalogue.models = on('qwen3.5-9b').map((m) => ({ ...m, present: false }));
    expect(await thinkingModel()).toBeNull();
    catalogue.fails = true;
    expect(await thinkingModel()).toBeNull();
  });
});
