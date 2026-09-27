import { describe, expect, it } from 'vitest';
import { chipPhase, lingerMs, partialCommand } from './chip.ts';
import { LIVE_TIMING } from './liveRoute.ts';

/** The recorder's chip (capture/chip.ts): which of its three looks it takes, and how long a settled one stays. */

describe('the chip’s look', () => {
  it('is hearing while a name or a command is under way', () => {
    expect(chipPhase({ phase: 'hearing', name: 'work' })).toBe('hearing');
    expect(chipPhase({ phase: 'command', words: 'add eggs' })).toBe('hearing');
  });

  it('is landed once something has, and missed when nothing could', () => {
    expect(chipPhase({ phase: 'done', text: 'Added to the note you named' })).toBe('moved');
    expect(chipPhase({ phase: 'said', text: 'Not done.' })).toBe('missed');
    expect(chipPhase({ phase: 'missed', title: 'Oven' })).toBe('missed');
    expect(chipPhase({ phase: 'moved', title: 'Work' })).toBe('moved');
  });

  it('has its own look for the last thing said, taken back', () => {
    expect(chipPhase({ phase: 'tookBack', said: 'Call Sam', outcome: 'gone', undo: 3 })).toBe('tookBack');
  });
});

describe('how long a chip stays', () => {
  it('lets a sentence or the items that landed be read, and a tick go sooner', () => {
    expect(lingerMs({ phase: 'said', text: 'Not done.' })).toBe(3200);
    expect(lingerMs({ phase: 'added', title: 'Work', body: '- Call Sam', added: ['- Call Sam'] })).toBe(3200);
    expect(lingerMs({ phase: 'done', text: 'Added to the note you named' })).toBe(2200);
    expect(lingerMs({ phase: 'moved', title: 'Work' })).toBe(2200);
    expect(lingerMs({ phase: 'missed', title: 'Oven' })).toBe(2200);
  });

  it('keeps a take-back and its Undo for four seconds, inside the reader’s own window for it', () => {
    const chip = { phase: 'tookBack', said: 'Call Sam', outcome: 'gone', undo: 3 } as const;
    expect(lingerMs(chip)).toBe(4000);
    expect(lingerMs(chip)!).toBeLessThan(LIVE_TIMING.takeBackMs);
  });

  it('keeps one still under way until the recorder says more', () => {
    expect(lingerMs(null)).toBeNull();
    expect(lingerMs({ phase: 'hearing', name: 'work' })).toBeNull();
    expect(lingerMs({ phase: 'command', words: '' })).toBeNull();
    expect(lingerMs({ phase: 'waiting', title: 'Work' })).toBeNull();
  });
});

describe('a command still being said', () => {
  it('shows without its keyword', () => {
    expect(partialCommand('Hey Ghost, add eggs to ')).toBe('add eggs to');
    expect(partialCommand(' add eggs ')).toBe('add eggs');
  });
});
