import { beforeEach, describe, expect, it, vi } from 'vitest';

/*
 * The recordings' commands and the write-up's two AI calls came with native generation 20 (docs/DESIGN.md §127), and
 * a page that arrived over the air runs on older binaries: below 20 each answers nothing and asks nothing of Rust,
 * so a generation-19 phone never hears of a command it does not have.
 */

let generation = 19;
const invoked: string[] = [];
vi.mock('./tauri.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./tauri.ts')>()),
  isTauri: () => true,
  invoke: async (command: string) => {
    invoked.push(command);
    if (command === 'recording_job_state') return [];
    if (command === 'recording_delete') return { removed: ['n1'], freedBytes: 10 };
    return null;
  },
}));
vi.mock('./nativeGeneration.ts', () => ({ hasNativeGeneration: async (wanted: number) => generation >= wanted }));

const recordings = await import('./recordings.ts');
const ai = await import('./ai.ts');

beforeEach(() => {
  invoked.length = 0;
  localStorage.clear();
});

describe('on a binary before generation 20', () => {
  it('asks Rust nothing and answers as if there were nothing', async () => {
    generation = 19;
    expect(await recordings.takeRecordingResult('n1')).toBeNull();
    expect(await recordings.recordingJobState()).toEqual([]);
    expect(await recordings.recordingDigest('n1')).toBeNull();
    expect(await recordings.deleteRecordings(['n1'])).toEqual({ removed: [], freedBytes: 0 });
    await ai.unloadModel();
    await ai.keepJobConfig({ model: 'qwen3.5-4b', prompts: { summary: '', notes: '', piece: '', parts: '' }, onePassChars: 1, pieceChars: 1, temperature: 0.3, writeUp: 'charging', summaries: 'meetings' });
    expect(invoked).toEqual([]);
    expect(recordings.audioRemoved('n1')).toBe(false);
  });
});

describe('on generation 20', () => {
  it('asks Rust, and remembers the audio it removed', async () => {
    generation = 20;
    await recordings.takeRecordingResult('n1');
    await recordings.recordingJobState();
    await recordings.recordingDigest('n1');
    await recordings.deleteRecordings(['n1']);
    await ai.unloadModel();
    expect(invoked).toEqual(['recording_result_take', 'recording_job_state', 'recording_digest', 'recording_delete', 'ai_unload']);
    expect(recordings.audioRemoved('n1')).toBe(true);
  });
});
