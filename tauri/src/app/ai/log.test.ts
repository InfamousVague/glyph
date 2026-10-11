import { beforeEach, describe, expect, it } from 'vitest';
import { forgetRuns, recordChange, recordRun, recordUndone, runsOf, type RunRecord } from './log.ts';

const record = (id: string, noteId = 'n', at = 0): RunRecord => ({ id, noteId, kind: 'format', instruction: null, model: 'qwen3.5-4b', at, ms: 1000, outputTokens: 5, outcome: 'done', message: null, truncated: false });

beforeEach(() => localStorage.clear());

describe('the run log', () => {
  it('keeps a note’s runs newest first, a handful at most', () => {
    for (let i = 0; i < 10; i += 1) recordRun(record(`r${i}`, 'n', i));
    const kept = runsOf('n');
    expect(kept.length).toBe(8);
    expect(kept[0]?.id).toBe('r9');
    expect(kept[7]?.id).toBe('r2');
    expect(runsOf('other')).toEqual([]);
  });

  it('replaces a record written twice, and keeps notes apart', () => {
    recordRun(record('r1', 'a'));
    recordRun({ ...record('r1', 'a'), outcome: 'stopped' });
    recordRun(record('r2', 'b'));
    expect(runsOf('a').map((r) => r.outcome)).toEqual(['stopped']);
    expect(runsOf('b').map((r) => r.id)).toEqual(['r2']);
  });

  it('remembers the words before and after a run that changed the note, until it is undone', () => {
    recordRun(record('r1'));
    recordChange('n', 'r1', 'before', 'after');
    expect(runsOf('n')[0]).toMatchObject({ before: 'before', after: 'after' });
    recordUndone('n', 'r1');
    expect(runsOf('n')[0]?.before).toBeUndefined();
    // A run the log never had is left alone.
    recordChange('n', 'nope', 'b', 'a');
    expect(runsOf('n').length).toBe(1);
  });

  it('forgets a deleted note', () => {
    recordRun(record('r1'));
    forgetRuns('n');
    expect(runsOf('n')).toEqual([]);
  });
});
