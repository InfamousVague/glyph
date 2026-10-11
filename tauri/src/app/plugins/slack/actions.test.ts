import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { NoteEditing } from '../types.ts';

/**
 * Slack's two rows on a note's More sheet: shown only once a channel is added on a binary that can post, the summary's
 * only on a note with a meeting's summary, and each saying on the note where it went or why it didn't.
 */

const posts: { id: unknown; text: unknown }[] = [];
let refusal: string | null = null;
vi.mock('../../core/tauri.ts', () => ({
  isTauri: () => true,
  invoke: vi.fn(async (command: string, args?: { id?: string; payload?: { text?: string } }) => {
    if (command === 'ota_status') return { nativeGeneration: 25 };
    if (command === 'slack_post') {
      if (refusal) throw refusal;
      posts.push({ id: args?.id, text: args?.payload?.text });
    }
    return undefined;
  }),
}));
vi.mock('../../core/haptics.ts', () => ({ fireNativeHaptic: () => undefined }));

const { addChannel, setSlackReady } = await import('./channels.ts');
const { postNote, postSummary } = await import('./index.tsx');

const HOOK = 'https://hooks.slack.com/services/T0/B0/abc';
const MEETING = '# Standup\n\n## Summary\nWe agreed to ship on Friday.\n\n- [ ] Sam: write the post\n\n## Transcript\nSam: so…';

function noteOf(body: string): { editing: NoteEditing; said: string[] } {
  const said: string[] = [];
  return { said, editing: { noteId: 'n1', body: () => body, replaceLine: () => false, say: (m) => said.push(m) } };
}

beforeEach(() => {
  localStorage.clear();
  posts.length = 0;
  refusal = null;
  setSlackReady(true);
});

describe('Post to Slack', () => {
  it('shows only once a channel is added, on a binary that can post', async () => {
    expect(postNote.visible('n1', 'Hello')).toBe(false);
    await addChannel('#launch', HOOK);
    expect(postNote.visible('n1', 'Hello')).toBe(true);
    setSlackReady(false);
    expect(postNote.visible('n1', 'Hello')).toBe(false);
  });

  it('is greyed on a note with nothing in it, and names the one channel', async () => {
    await addChannel('#launch', HOOK);
    expect(postNote.enabled('n1', '---\nlocation: 1, 2\n---\n')).toBe(false);
    expect(postNote.hint('n1', '')).toBe('Nothing to post yet.');
    expect(postNote.enabled('n1', 'Hello')).toBe(true);
    expect(postNote.hint('n1', 'Hello')).toBe('The whole note goes to #launch, as it reads now.');
  });

  it('offers every channel to choose from, and posts to the one chosen', async () => {
    await addChannel('#launch', HOOK);
    const ops = await addChannel('#ops', HOOK);
    expect(postNote.choices?.('n1').map((c) => c.label)).toEqual(['#launch', '#ops']);
    expect(postNote.hint('n1', 'Hello')).toBe('The whole note goes to one of 2 channels, as it reads now.');
    const { editing, said } = noteOf('# Launch\n\nShip **Friday**.');
    await postNote.run(editing, ops.id);
    expect(posts).toEqual([{ id: ops.id, text: '*Launch*\nShip *Friday*.' }]);
    expect(said).toEqual(['Posted to #ops.']);
  });

  it('says why when Slack refuses, in its words', async () => {
    const launch = await addChannel('#launch', HOOK);
    refusal = 'Slack no longer knows this webhook. Make a new one in Slack and add the channel again.';
    const { editing, said } = noteOf('Hello');
    await postNote.run(editing, launch.id);
    expect(said).toEqual(['Not posted to #launch. Slack no longer knows this webhook. Make a new one in Slack and add the channel again.']);
  });

  it('says so when the channel chosen has gone meanwhile', async () => {
    await addChannel('#launch', HOOK);
    await addChannel('#ops', HOOK);
    const { editing, said } = noteOf('Hello');
    await postNote.run(editing, 'gone');
    expect(posts).toEqual([]);
    expect(said).toEqual(['That Slack channel isn’t on this device any more.']);
  });
});

describe('Post the summary to Slack', () => {
  it('shows only on a note with a meeting’s summary', async () => {
    await addChannel('#launch', HOOK);
    expect(postSummary.visible('n1', '# Standup\n\nWe met.')).toBe(false);
    expect(postSummary.visible('n1', MEETING)).toBe(true);
    expect(postSummary.enabled('n1', MEETING)).toBe(true);
  });

  it('posts the summary alone, under the note’s title', async () => {
    const launch = await addChannel('#launch', HOOK);
    const { editing, said } = noteOf(MEETING);
    await postSummary.run(editing, launch.id);
    expect(posts).toEqual([{ id: launch.id, text: '*Standup*\n*Summary*\nWe agreed to ship on Friday.\n\n☐ Sam: write the post' }]);
    expect(said).toEqual(['Posted to #launch.']);
  });

  it('says so when the summary was taken out before it went', async () => {
    const launch = await addChannel('#launch', HOOK);
    const { editing, said } = noteOf('# Standup\n\nWe met.');
    await postSummary.run(editing, launch.id);
    expect(posts).toEqual([]);
    expect(said).toEqual(['There is no summary in this note to post.']);
  });
});
