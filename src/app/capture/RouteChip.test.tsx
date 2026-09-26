import { describe, expect, it } from 'vitest';
import { show } from '../../test/render.tsx';
import { RouteChip } from './RouteChip.tsx';
import type { RouteView } from './takeHost.ts';

/** What the recorder's chip says for each thing the take tells it (capture/RouteChip.tsx). */

const chip = (route: Exclude<RouteView, null>, itemWords = '') => {
  const host = show(<RouteChip route={route} itemWords={itemWords} />);
  const p = host.querySelector('p')!;
  return { text: p.textContent, phase: p.dataset.phase };
};

describe('the chip', () => {
  it('says what name it is looking for while the name is said', () => {
    expect(chip({ phase: 'hearing', name: 'wor' })).toEqual({ text: 'Looking for “wor”', phase: 'hearing' });
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
    expect(chip({ phase: 'added', title: 'Work', body: '', added: ['- Call Sam'] })).toEqual({ text: 'Added to Work', phase: 'added' });
    expect(chip({ phase: 'added', title: 'Work', body: '', added: ['- Call Sam', '- Email Jo'] }).text).toBe('2 added to Work');
    expect(chip({ phase: 'moved', title: 'Work' })).toEqual({ text: 'Now on Work', phase: 'moved' });
    expect(chip({ phase: 'moved', title: 'New note' }).text).toBe('New note');
    expect(chip({ phase: 'done', text: 'Added to the note you named' })).toEqual({ text: 'Added to the note you named', phase: 'moved' });
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
