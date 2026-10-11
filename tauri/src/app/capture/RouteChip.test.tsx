import { describe, expect, it, vi } from 'vitest';
import { show } from '../../test/render.tsx';
import { RouteChip } from './RouteChip.tsx';
import type { RouteView } from './takeHost.ts';

/** What the recorder's chip says for each thing the recorder tells it (capture/RouteChip.tsx). */

const chip = (route: Exclude<RouteView, null>, itemWords = '', onUndo?: () => void) => {
  const host = show(<RouteChip route={route} itemWords={itemWords} onUndo={onUndo} />);
  const p = host.querySelector('p')!;
  return { text: p.textContent, phase: p.dataset.phase, undo: p.querySelector('button') };
};

describe('the chip', () => {
  it('says what name it is looking for while the name is said', () => {
    expect(chip({ phase: 'hearing', name: 'wor' })).toMatchObject({ text: 'Looking for “wor”', phase: 'hearing' });
  });

  it('asks for what a named note should get, and shows it as it is said', () => {
    expect(chip({ phase: 'waiting', title: 'Work' }).text).toBe('Say the note for Work');
    expect(chip({ phase: 'waiting', title: 'Work' }, 'call Sam').text).toBe('Work: call Sam');
  });

  it('shows a command as it is said after the keyword', () => {
    expect(chip({ phase: 'command', words: '' }).text).toBe('Hey Ghost, listening for a command');
    expect(chip({ phase: 'command', words: 'add eggs' }, 'Hey Ghost, to work').text).toBe('Hey Ghost: add eggs to work');
  });

  it('says what landed, where', () => {
    expect(chip({ phase: 'added', title: 'Work', body: '', added: ['- Call Sam'] })).toMatchObject({ text: 'Added to Work', phase: 'added' });
    expect(chip({ phase: 'added', title: 'Work', body: '', added: ['- Call Sam', '- Email Jo'] }).text).toBe('2 added to Work');
    expect(chip({ phase: 'moved', title: 'Work' })).toMatchObject({ text: 'Now on Work', phase: 'moved' });
    expect(chip({ phase: 'moved', title: 'New note' }).text).toBe('New note');
    expect(chip({ phase: 'done', text: 'Added to the note you named' })).toMatchObject({ text: 'Added to the note you named', phase: 'moved' });
  });

  it('says what was taken back, and where it went instead, with Undo only while it can be tapped', () => {
    expect(chip({ phase: 'tookBack', said: 'Call Sam', outcome: 'gone', undo: 3 })).toMatchObject({ text: 'Took back “Call Sam”', phase: 'tookBack', undo: null });
    expect(chip({ phase: 'tookBack', said: 'Oat milk', outcome: { sent: 'Groceries' }, undo: 3 }).text).toBe('Sent “Oat milk” to Groceries');
    expect(chip({ phase: 'tookBack', said: 'Buy fuses', outcome: { placed: 'in its list' }, undo: 3 }).text).toBe('Put “Buy fuses” in its list');
    expect(chip({ phase: 'tookBack', said: 'three', outcome: { changed: 'four' }, undo: 3 }).text).toBe('Changed “three” to “four”');
    expect(chip({ phase: 'tookBack', said: 'The meeting is at three', outcome: { replaced: 'The meeting is at four' }, undo: 3 }).text).toBe('Replaced “The meeting is at three” with “The meeting is at four”');
    const undo = vi.fn();
    const drawn = chip({ phase: 'tookBack', said: 'Call Sam', outcome: 'gone', undo: 3 }, '', undo);
    expect(drawn.text).toBe('Took back “Call Sam”Undo');
    expect(drawn.undo?.textContent).toBe('Undo');
    drawn.undo!.click();
    expect(undo).toHaveBeenCalledTimes(1);
  });

  it('says what did not happen', () => {
    expect(chip({ phase: 'missed', title: 'Oven' })).toMatchObject({ text: 'No note called “Oven”, so it stays here', phase: 'missed' });
    expect(chip({ phase: 'said', text: 'Not done.' })).toMatchObject({ text: 'Not done.', phase: 'missed' });
  });
});
