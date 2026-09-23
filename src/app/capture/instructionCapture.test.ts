import { describe, expect, it, vi } from 'vitest';
import { placeWords } from './listAppend.ts';
import { Take, type Offer, type TakeHost } from './take.ts';

type TestNote = { id: string; body: string };

function harness() {
  const todo: TestNote = { id: 'todo', body: 'To-Do' };
  const notes = [{ id: todo.id, title: 'To-Do', note: todo }];
  let offered: Offer<TestNote> | null = null;
  const addItems = vi.fn((note: TestNote, spoken: string, placement: Parameters<typeof placeWords>[2]) => {
    note.body = placeWords(note.body, spoken, placement).body;
  });
  const host: TakeHost<TestNote> = {
    notes: () => notes,
    target: () => null,
    commandWord: () => true,
    instructionCommands: () => true,
    voiceCommands: () => [],
    itemTargets: () => [],
    route: () => undefined,
    offer: (next) => { offered = next; },
    table: () => undefined,
    itemWords: () => undefined,
    haptic: () => undefined,
    changed: () => undefined,
    addItems,
    changeNote: () => undefined,
    addTable: () => undefined,
    moveTo: () => undefined,
    carryOn: () => undefined,
    newNote: () => undefined,
    undo: () => null,
    runPlugin: () => null,
    describePlugin: () => ({ title: '', action: '' }),
    clip: () => '',
    log: () => undefined,
    said: () => undefined,
  };
  const take = new Take(host);
  return { take, todo, addItems, offered: () => offered };
}

describe('instruction-aware full capture utterances', () => {
  it('offers and confirms a no-wake To-Do append instead of keeping command prose', () => {
    const { take, todo, addItems, offered } = harness();
    take.phrase({ text: 'add to the to do list wash dishes, take out trash, and fold clothes', startMs: 0, endMs: 4200 }, 5000);

    expect(take.segments).toEqual([]);
    expect(offered()).toMatchObject({ kind: 'place', title: 'To-Do', added: ['- [ ] Wash dishes', '- [ ] Take out trash', '- [ ] Fold clothes'] });

    take.confirm(5100);
    expect(addItems).toHaveBeenCalledOnce();
    expect(todo.body).toBe('To-Do\n\n- [ ] Wash dishes\n- [ ] Take out trash\n- [ ] Fold clothes\n');
  });

  it.each([
    'my thoughts about the new iPhone, I like the folding display and want to add more later',
    'I told Sam to add wash dishes to the to do list when he gets home',
    'The phrase create a list appears in this ordinary explanation',
  ])('keeps near-miss prose as an ordinary new note: %s', (utterance) => {
    const { take, offered } = harness();
    take.phrase({ text: utterance, startMs: 0, endMs: 3000 }, 4000);
    expect(offered()).toBeNull();
    expect(take.segments.map((segment) => segment.text)).toEqual([utterance]);
  });
});
