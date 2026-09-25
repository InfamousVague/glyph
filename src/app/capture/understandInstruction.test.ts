import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The take's second reader (capture/understand.ts `understandInstructionCommand`): the rules' plan when they have
 * one, and otherwise the on-device instruction model's answer mapped onto the plans the recorder confirms. The bridge
 * is a stand-in that answers `ai_infer_command` as the phone would.
 */

let answer: unknown = null;
const invoke = vi.fn(async (command: string) => (command === 'ai_infer_command' ? answer : true));

vi.mock('../core/tauri.ts', () => ({ isTauri: () => true, invoke }));

const { understandInstructionCommand } = await import('./understand.ts');

const attack = { id: 'attack', title: 'AttackFM', note: { id: 'attack', body: '# AttackFM' } };
const notes = [attack];
const unreadable = 'pop the thing about the seek bar somewhere';
const intent = (placement: string | null, content = 'the seek bar drifts') => ({ status: 'intent', model: 'qwen3.5-2b', intent: { action: 'append', target: 'AttackFM', content, placement } });

beforeEach(() => {
  invoke.mockClear();
  answer = null;
});

describe('the second reader', () => {
  it('takes the rules’ plan when they have one, and never asks the model', async () => {
    const plan = await understandInstructionCommand('add fix the login bug to AttackFM', notes).done;
    expect(plan).toMatchObject({ kind: 'place', note: attack, text: 'fix the login bug' });
    expect(invoke).not.toHaveBeenCalled();
  });

  it.each([
    [null, { how: 'leave', task: false }],
    ['notes', { how: 'paragraph', task: false }],
    ['list', { how: 'item', task: false }],
    ['tasks', { how: 'item', task: true }],
    ['bugs', { how: 'item', task: false, near: 'bugs' }],
  ])('puts what the model read where it said, %s', async (placement, expected) => {
    answer = intent(placement);
    const plan = await understandInstructionCommand(unreadable, notes).done;
    expect(plan).toEqual({ kind: 'place', note: attack, text: 'the seek bar drifts', many: false, target: null, ...expected });
  });

  it('writes the model’s words as words, whatever marks they would make', async () => {
    answer = intent(null, '# not a heading, [nor](a link)');
    const plan = await understandInstructionCommand(unreadable, notes).done;
    expect(plan).toMatchObject({ text: String.raw`\# not a heading, \[nor\]\(a link\)` });
  });

  it('makes a new list the model named, but not one it would fill with words of its own', async () => {
    answer = { status: 'intent', model: 'qwen3.5-2b', intent: { action: 'create', target: 'Comic books', content: null } };
    await expect(understandInstructionCommand(unreadable, notes).done).resolves.toEqual({ kind: 'create-list', title: 'Comic books' });
    answer = { status: 'intent', model: 'qwen3.5-2b', intent: { action: 'create', target: 'Comic books', content: 'Batman' } };
    await expect(understandInstructionCommand(unreadable, notes).done).resolves.toBeNull();
  });

  it('has no plan when the model has none, cannot answer, or names no note there is', async () => {
    answer = { status: 'intent', model: 'qwen3.5-2b', intent: { action: 'none', reason: 'unclear' } };
    await expect(understandInstructionCommand(unreadable, notes).done).resolves.toBeNull();
    answer = { status: 'unavailable', reason: 'No command model is on this phone.' };
    await expect(understandInstructionCommand(unreadable, notes).done).resolves.toBeNull();
    answer = { status: 'intent', model: 'qwen3.5-2b', intent: { action: 'append', target: 'Groceries', content: 'milk', placement: null } };
    await expect(understandInstructionCommand(unreadable, notes).done).resolves.toBeNull();
  });

  it('asks the model to stop when speech resumes', async () => {
    answer = intent(null);
    const run = understandInstructionCommand(unreadable, notes);
    run.cancel();
    await vi.waitFor(() => expect(invoke).toHaveBeenCalledWith('ai_cancel', expect.objectContaining({ id: expect.stringMatching(/^command-/) })));
  });
});
