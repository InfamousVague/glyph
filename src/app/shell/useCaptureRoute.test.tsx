import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, useState } from 'react';
import { createNote, updateNote } from '../core/store.ts';
import { reloadPreferences } from '../core/preferences.ts';
import { addWorkspace, chooseWorkspace, workspaceOf } from '../core/workspaces.ts';
import { show } from '../../test/render.tsx';
import { useCaptureRoute, type CaptureRoute } from './useCaptureRoute.ts';
import type { Screen } from './screen.ts';

/**
 * Where a capture comes back to, and how the side key reads the moment it is pressed in: every ending a person can
 * meet, from the note with its run on it to a locked phone that shows nothing of what was said.
 */

let route: CaptureRoute;
let screen: Screen;
const refresh = vi.fn(async () => undefined);
const flushDeletes = vi.fn(async () => undefined);

function Probe({ from, tooSoon = false, sayTooSoon = () => undefined, clearStage = () => undefined }: { from: Screen; tooSoon?: boolean; sayTooSoon?: () => void; clearStage?: () => void }) {
  const [now, setNow] = useState<Screen>(from);
  screen = now;
  route = useCaptureRoute({ screen: now, setScreen: setNow, refresh, flushDeletes, atBoot: false, tooSoon: () => tooSoon, sayTooSoon, clearStage });
  return null;
}

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
  refresh.mockClear();
  flushDeletes.mockClear();
  delete window.__glyph;
});

const into = (noteId?: string): Screen => ({ name: 'capture', key: 1, fromAssistant: false, stop: 0, ...(noteId ? { noteId } : {}) });

describe('a capture ending', () => {
  it('files the note in the workspace being looked at, and opens it with the instruction said into it', async () => {
    const work = addWorkspace('Work')!;
    chooseWorkspace(work.id);
    const note = await createNote('n', '# Said');
    show(<Probe from={into()} />);
    await act(async () => route.finished(note, false, undefined, { kind: 'fix' }));
    expect(workspaceOf('n')?.id).toBe(work.id);
    expect(refresh).toHaveBeenCalled();
    expect(screen).toMatchObject({ name: 'note', note: { id: 'n' }, ask: { kind: 'fix' } });
  });

  it('opens the note read fresh for its review', async () => {
    const note = await createNote('n', '# Said');
    await updateNote('n', '# Said, better', note.revision ?? 1);
    show(<Probe from={into()} />);
    await act(async () => route.finished(note, false, { noteId: 'n', job: null, heard: 'said', commands: [], touched: [] }));
    expect(screen).toMatchObject({ name: 'note', note: { body: '# Said, better' }, review: { noteId: 'n', heard: 'said' } });
  });

  it('goes home from a locked phone, even from a note spoken into, so nothing of it shows', async () => {
    const note = await createNote('n', '# Said');
    show(<Probe from={into('n')} />);
    await act(async () => route.finished(note, true));
    expect(screen).toEqual({ name: 'list' });
  });

  it('goes back to the note spoken into when nothing new was made, and home when that note has gone', async () => {
    await createNote('n', '# Kept');
    show(<Probe from={into('n')} />);
    await act(async () => route.finished(null, false));
    expect(screen).toMatchObject({ name: 'note', note: { id: 'n' } });
    show(<Probe from={into('missing')} />);
    await act(async () => route.finished(null, false));
    expect(screen).toEqual({ name: 'list' });
  });
});

describe('a capture starting', () => {
  it('waits for the deferred deletes, then mounts afresh', async () => {
    show(<Probe from={{ name: 'list' }} />);
    await act(async () => route.start(false, 'n'));
    expect(flushDeletes).toHaveBeenCalledTimes(1);
    expect(screen).toMatchObject({ name: 'capture', fromAssistant: false, stop: 0, noteId: 'n' });
  });
});

describe('the side key with the app open', () => {
  it('clears the stage and records, and during a recording asks it to stop', async () => {
    const clearStage = vi.fn();
    show(<Probe from={{ name: 'list' }} clearStage={clearStage} />);
    await act(async () => window.__glyph!.capture!());
    expect(clearStage).toHaveBeenCalledTimes(1);
    expect(screen).toMatchObject({ name: 'capture', fromAssistant: true, stop: 0 });
    await act(async () => window.__glyph!.capture!());
    expect(screen).toMatchObject({ name: 'capture', stop: 1 });
  });

  it('on a page of the guide still to be read says "not yet" and records nothing', async () => {
    const sayTooSoon = vi.fn();
    show(<Probe from={{ name: 'list' }} tooSoon sayTooSoon={sayTooSoon} />);
    await act(async () => window.__glyph!.capture!());
    expect(sayTooSoon).toHaveBeenCalledTimes(1);
    expect(screen).toEqual({ name: 'list' });
  });
});
