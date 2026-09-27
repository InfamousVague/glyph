import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { withTranscript } from '../capture/markdown.ts';
import { createNote, getNote, updateNote, type Note } from '../core/store.ts';
import { show, unmount, waitUntil } from '../../test/render.tsx';
import { useNoteSaving, type NoteSaving } from './useNoteSaving.ts';

/**
 * Saving the open note (editor/useNoteSaving.ts), against the page's own store: a save that conflicts because the
 * phone's write-up appended the transcript is made again over it, with the editor handed the result; any other
 * conflict stops the saving as it always has; and a note the write-up changed while nothing here was unsaved is
 * adopted whole.
 */

let saving: NoteSaving;
let handed: string[] = [];
function Probe({ note }: { note: Note }) {
  saving = useNoteSaving(note, null, { onExternalChange: (body) => void handed.push(body) });
  return null;
}

const TRANSCRIPT = '## Transcript\n\nWe settled the date.\n\nSam owns the press list.';

beforeEach(() => {
  localStorage.clear();
  handed = [];
});

afterEach(() => {
  unmount();
  vi.restoreAllMocks();
});

describe('a save that meets the transcript from the phone', () => {
  it('is made again over the transcript, and the editor is handed the words with it', async () => {
    const note = await createNote('m1', '# Meeting, 26 Sep 14:05\n', 'capture');
    show(<Probe note={note} />);
    // Rust appends the transcript under the note while it is open: the revision moves on.
    await updateNote('m1', withTranscript(note.body, TRANSCRIPT), note.revision ?? 1);
    // Typed here since, on the old revision.
    act(() => saving.onChange('# Meeting, 26 Sep 14:05\n\nMy own line.\n'));
    saving.flush();
    await waitUntil(async () => expect((await getNote('m1'))?.body).toBe(withTranscript('# Meeting, 26 Sep 14:05\n\nMy own line.\n', TRANSCRIPT)));
    expect(handed).toEqual([withTranscript('# Meeting, 26 Sep 14:05\n\nMy own line.\n', TRANSCRIPT)]);
    expect(saving.body.current).toBe(handed[0]);
    // Saving carries on from the new revision: the next words land.
    act(() => saving.onChange(`${saving.body.current.replace('My own line.', 'My own line, kept.')}`));
    saving.flush();
    await waitUntil(async () => expect((await getNote('m1'))?.body).toContain('My own line, kept.'));
  });

  it('keeps the words typed while the save was out, and puts the transcript under them', async () => {
    const note = await createNote('m1', '# Meeting, 26 Sep 14:05\n', 'capture');
    show(<Probe note={note} />);
    await updateNote('m1', withTranscript(note.body, TRANSCRIPT), note.revision ?? 1);
    act(() => saving.onChange('# Meeting, 26 Sep 14:05\n\nFirst.\n'));
    saving.flush();
    // More typed before the store answers the conflict: the words in hand have moved on.
    act(() => saving.onChange('# Meeting, 26 Sep 14:05\n\nFirst. Second.\n'));
    // They are not handed back (they are the editor's own), but they carry the transcript for the next save.
    await waitUntil(() => expect(saving.body.current).toBe(withTranscript('# Meeting, 26 Sep 14:05\n\nFirst. Second.\n', TRANSCRIPT)));
    expect(handed).toEqual([]);
    saving.flush();
    await waitUntil(async () => expect((await getNote('m1'))?.body).toBe(withTranscript('# Meeting, 26 Sep 14:05\n\nFirst. Second.\n', TRANSCRIPT)));
  });
});

describe('any other conflict', () => {
  it('stops the saving, as it always has', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const note = await createNote('n1', '# Plan\n\nOne.\n');
    show(<Probe note={note} />);
    await updateNote('n1', '# Plan\n\nOne, changed elsewhere.\n', note.revision ?? 1);
    act(() => saving.onChange('# Plan\n\nOne, changed here.\n'));
    saving.flush();
    await waitUntil(() => expect(warn).toHaveBeenCalledWith('[glyph] editor save stopped:', expect.anything()));
    expect((await getNote('n1'))?.body).toBe('# Plan\n\nOne, changed elsewhere.\n');
    expect(handed).toEqual([]);
    act(() => saving.onChange('# Plan\n\nOne, changed here again.\n'));
    saving.flush();
    await act(async () => {
      for (let i = 0; i < 5; i += 1) await Promise.resolve();
    });
    expect((await getNote('n1'))?.body).toBe('# Plan\n\nOne, changed elsewhere.\n');
  });
});

describe('a note the write-up changed', () => {
  it('is adopted whole when nothing here is unsaved, and left to the next save when something is', async () => {
    const note = await createNote('m1', '# Meeting, 26 Sep 14:05\n', 'capture');
    show(<Probe note={note} />);
    const stored = await updateNote('m1', withTranscript(note.body, TRANSCRIPT), note.revision ?? 1);
    expect(saving.adopt(stored)).toBe(true);
    expect(saving.body.current).toBe(stored.body);
    expect(handed).toEqual([stored.body]);
    // The revision came with it: a save from here now lands.
    act(() => saving.onChange(`${stored.body}\n\nAnd mine.`));
    saving.flush();
    await waitUntil(async () => expect((await getNote('m1'))?.body).toBe(`${stored.body}\n\nAnd mine.`));
    // With words waiting to be saved, nothing is taken: the save's own rebase looks after it.
    const again = await updateNote('m1', withTranscript(`${stored.body}\n\nAnd mine.`, `${TRANSCRIPT}\n\nMore was said.`), (await getNote('m1'))!.revision ?? 1);
    act(() => saving.onChange(`${saving.body.current}\n\nTyped since.`));
    expect(saving.adopt(again)).toBe(false);
    expect(handed).toHaveLength(1);
  });
});
