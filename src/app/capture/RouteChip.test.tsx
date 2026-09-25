import { describe, expect, it } from 'vitest';
import { show } from '../../test/render.tsx';
import { Opening } from './Opening.tsx';
import { RouteChip } from './RouteChip.tsx';
import type { RouteView } from './takeHost.ts';

/** What the recorder's chip says for each thing the take tells it (capture/RouteChip.tsx). */

const chip = (route: Exclude<RouteView, null>, itemWords = '') => {
  const host = show(<RouteChip route={route} itemWords={itemWords} />);
  const p = host.querySelector('p')!;
  return { text: p.textContent, phase: p.dataset.phase };
};

describe('the chip', () => {
  it('names the note it thinks is meant while the name is said, or what it is looking for', () => {
    expect(chip({ phase: 'hearing', name: 'work', guess: 'Work', lead: 'New item for' })).toEqual({ text: 'New item for Work', phase: 'hearing' });
    expect(chip({ phase: 'hearing', name: 'wor', guess: null, lead: 'Add to' })).toEqual({ text: 'Looking for “wor”', phase: 'hearing' });
  });

  it('asks for what a named note should get, and shows it as it is said', () => {
    expect(chip({ phase: 'waiting', title: 'Work', many: false, leave: false }).text).toBe('Say the item for Work');
    expect(chip({ phase: 'waiting', title: 'Work', many: true, leave: false }).text).toBe('Say the items for Work');
    expect(chip({ phase: 'waiting', title: 'Work', many: false, leave: true }).text).toBe('Say the note for Work');
    expect(chip({ phase: 'waiting', title: 'Work', many: false, leave: false }, 'call Sam').text).toBe('Work: call Sam');
  });

  it('shows a command as it is said after the keyword, and when the model is working it out', () => {
    expect(chip({ phase: 'command', words: '' }).text).toBe('Hey Ghost, listening for a command');
    expect(chip({ phase: 'command', words: 'add eggs' }, 'Hey Ghost, to work').text).toBe('Hey Ghost: add eggs to work');
    expect(chip({ phase: 'command', words: 'add eggs', thinking: true }).text).toBe('Hey Ghost: add eggs · working it out');
  });

  it('says what landed, where', () => {
    expect(chip({ phase: 'added', title: 'Work', body: '', added: ['- Call Sam'] })).toEqual({ text: 'Added to Work', phase: 'added' });
    expect(chip({ phase: 'added', title: 'Work', body: '', added: ['- Call Sam', '- Email Jo'] }).text).toBe('2 added to Work');
    expect(chip({ phase: 'moved', title: 'Work' })).toEqual({ text: 'Now on Work', phase: 'moved' });
    expect(chip({ phase: 'moved', title: 'New note' }).text).toBe('New note');
    expect(chip({ phase: 'done', text: 'Table added' })).toEqual({ text: 'Table added', phase: 'moved' });
  });

  it('says what did not happen', () => {
    expect(chip({ phase: 'missed', title: 'Oven' })).toEqual({ text: 'No note called “Oven”, so it stays here', phase: 'missed' });
    expect(chip({ phase: 'said', text: 'Not done.' })).toEqual({ text: 'Not done.', phase: 'missed' });
  });

  it('follows a plugin’s command from working to its answer', () => {
    expect(chip({ phase: 'plugin', state: 'working', lead: 'Sending to', title: 'Notion' })).toEqual({ text: 'Sending to Notion', phase: 'hearing' });
    expect(chip({ phase: 'plugin', state: 'done', lead: null, title: 'Sent' })).toEqual({ text: 'Sent', phase: 'moved' });
    expect(chip({ phase: 'plugin', state: 'failed', lead: 'Sending to', title: 'Notion said no' })).toEqual({ text: 'Notion said no', phase: 'missed' });
  });
});

describe('the recorder’s picture of sound beginning', () => {
  it('draws its three arcs, dashed when the microphone never opened', () => {
    const opening = show(<Opening />).querySelector('svg')!;
    expect(opening.querySelectorAll('path')).toHaveLength(3);
    expect(opening.dataset.failed).toBeUndefined();
    const failed = show(<Opening failed />).querySelector('svg')!;
    expect(failed.dataset.failed).toBe('');
    expect([...failed.querySelectorAll('path')].every((arc) => arc.getAttribute('stroke-dasharray') === '6 7')).toBe(true);
  });
});
