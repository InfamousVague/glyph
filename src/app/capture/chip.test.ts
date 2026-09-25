import { describe, expect, it } from 'vitest';
import { chipPhase, lingerMs, partialCommand } from './chip.ts';

/** The recorder's chip (capture/chip.ts): which of its three looks it takes, and how long a settled one stays. */

describe('the chip’s look', () => {
  it('is hearing while a name or a command is under way', () => {
    expect(chipPhase({ phase: 'hearing', name: 'work', guess: 'Work', lead: 'Add to' })).toBe('hearing');
    expect(chipPhase({ phase: 'command', words: 'add eggs' })).toBe('hearing');
    expect(chipPhase({ phase: 'plugin', state: 'working', lead: 'Sending to', title: 'Notion' })).toBe('hearing');
  });

  it('is landed once something has, and missed when nothing could', () => {
    expect(chipPhase({ phase: 'done', text: 'Table added' })).toBe('moved');
    expect(chipPhase({ phase: 'plugin', state: 'done', lead: null, title: 'Sent' })).toBe('moved');
    expect(chipPhase({ phase: 'said', text: 'Not done.' })).toBe('missed');
    expect(chipPhase({ phase: 'plugin', state: 'failed', lead: null, title: 'Notion said no' })).toBe('missed');
    expect(chipPhase({ phase: 'missed', title: 'Oven' })).toBe('missed');
    expect(chipPhase({ phase: 'moved', title: 'Work' })).toBe('moved');
  });
});

describe('how long a chip stays', () => {
  it('lets a sentence or the items that landed be read, and a tick go sooner', () => {
    expect(lingerMs({ phase: 'said', text: 'Not done.' })).toBe(3200);
    expect(lingerMs({ phase: 'added', title: 'Work', body: '- Call Sam', added: ['- Call Sam'] })).toBe(3200);
    expect(lingerMs({ phase: 'done', text: 'Table added' })).toBe(2200);
    expect(lingerMs({ phase: 'moved', title: 'Work' })).toBe(2200);
    expect(lingerMs({ phase: 'missed', title: 'Oven' })).toBe(2200);
    expect(lingerMs({ phase: 'plugin', state: 'done', lead: null, title: 'Sent' })).toBe(2200);
  });

  it('keeps one still under way until the take says more', () => {
    expect(lingerMs(null)).toBeNull();
    expect(lingerMs({ phase: 'hearing', name: 'work', guess: null, lead: 'Add to' })).toBeNull();
    expect(lingerMs({ phase: 'command', words: '' })).toBeNull();
    expect(lingerMs({ phase: 'waiting', title: 'Work', many: false, leave: false })).toBeNull();
    expect(lingerMs({ phase: 'plugin', state: 'working', lead: null, title: 'Notion' })).toBeNull();
  });
});

describe('a command still being said', () => {
  it('shows without its keyword', () => {
    expect(partialCommand('Hey Ghost, add eggs to ')).toBe('add eggs to');
    expect(partialCommand(' add eggs ')).toBe('add eggs');
  });
});
