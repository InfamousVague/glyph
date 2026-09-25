import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { button, buttonSaying, rerender, show, typeInto, unmount, waitUntil } from '../../test/render.tsx';
import { goBack } from '../core/back.ts';
import { removeWorkspace, workspaceOf, workspaces } from '../core/workspaces.ts';
import type { NoteAction, NoteEditing, NoteLink } from '../plugins/types.ts';

await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());

/**
 * The note's More sheet: the groups it shows only where they have rows, the rows plugins add and why one cannot be
 * used, the pages opened inside it and the way back through them, and the body its actions are judged by, read once
 * as it opens. The registry is the app's own, with this file's link and action standing in for a plugin's.
 */

const plugged = vi.hoisted(() => ({ links: [] as NoteLink[], actions: [] as NoteAction[] }));

vi.mock('../plugins/registry.ts', async (importOriginal) => {
  const real = await importOriginal<typeof import('../plugins/registry.ts')>();
  return { ...real, plugins: { ...real.plugins, noteLinks: () => plugged.links, noteActions: () => plugged.actions } };
});

const { NoteSettings } = await import('./NoteSettings.tsx');

type Props = Parameters<typeof NoteSettings>[0];

function editing(body = '- [ ] milk'): NoteEditing {
  return { noteId: 'n1', body: vi.fn(() => body), replaceLine: () => false, say: () => undefined };
}

function sheet(over: Partial<Props> = {}): Props {
  return { open: true, noteId: 'n1', title: 'Groceries', pinned: false, editing: editing(), onClose: vi.fn(), onPin: vi.fn(), onArchive: vi.fn(), onDelete: vi.fn(), ...over };
}

const Board = () => <svg />;

beforeEach(() => {
  plugged.links = [];
  plugged.actions = [];
});

afterEach(() => {
  unmount();
  for (const w of workspaces().list) removeWorkspace(w.id);
});

describe('the More sheet', () => {
  it('is nothing while closed', () => {
    show(<NoteSettings {...sheet({ open: false })} />);
    expect(document.querySelector('[role="dialog"]')).toBeNull();
  });

  it('shows Reading it only where it has a row, and each row does its one thing', () => {
    show(<NoteSettings {...sheet()} />);
    expect(document.body.textContent).not.toContain('Reading it');
    const onFind = vi.fn();
    const onView = vi.fn();
    rerender(<NoteSettings {...sheet({ onFind, view: 'mixed', onView })} />);
    expect(document.body.textContent).toContain('Reading it');
    const markdown = document.querySelector('[role="radio"][aria-checked="true"]');
    expect(markdown?.textContent).toBe('Markdown');
    act(() => button('Formatted').click());
    expect(onView).toHaveBeenCalledWith('formatted');
    act(() => button('Find and replace').click());
    expect(onFind).toHaveBeenCalledTimes(1);
  });

  it('marks the AI run that is on, and closes before starting one', () => {
    const order: string[] = [];
    show(<NoteSettings {...sheet({ running: 'summarize', onAi: (kind) => order.push(`ai ${kind}`), onClose: () => order.push('close') })} />);
    expect(buttonSaying(document.body, 'Summarize')?.getAttribute('aria-pressed')).toBe('true');
    expect(buttonSaying(document.body, 'Format')?.getAttribute('aria-pressed')).toBe('false');
    act(() => buttonSaying(document.body, 'Enhance')!.click());
    expect(order).toEqual(['close', 'ai enhance']);
  });

  it('pins or unpins, archives, and moves to the trash', () => {
    const props = sheet({ pinned: true });
    show(<NoteSettings {...props} />);
    act(() => button('Unpin').click());
    act(() => button('Archive').click());
    act(() => button('Move to Trash').click());
    expect(props.onPin).toHaveBeenCalledTimes(1);
    expect(props.onArchive).toHaveBeenCalledTimes(1);
    expect(props.onDelete).toHaveBeenCalledTimes(1);
  });

  it('names a canvas in its field', () => {
    const onChange = vi.fn();
    show(<NoteSettings {...sheet({ name: { value: 'Map', onChange } })} />);
    const field = document.querySelector<HTMLInputElement>('input[placeholder="What this canvas is called"]')!;
    expect(field.value).toBe('Map');
    typeInto(field, 'Trip map');
    expect(onChange).toHaveBeenCalledWith('Trip map');
  });

  it('closes on a tap on the dimmed note, and not on a tap inside the sheet', () => {
    const props = sheet();
    show(<NoteSettings {...props} />);
    act(() => (document.querySelector('[role="dialog"]') as HTMLElement).click());
    expect(props.onClose).not.toHaveBeenCalled();
    act(() => (document.querySelector('[role="dialog"]')!.parentElement as HTMLElement).click());
    expect(props.onClose).toHaveBeenCalledTimes(1);
  });
});

describe('what plugins add to it', () => {
  it('greys a link that cannot be used here, and says why in its place', async () => {
    plugged.links = [
      { id: 'board', label: 'A board', icon: Board, hint: () => 'Choose a board.', unavailable: async () => 'Works in the app on your phone.', Picker: () => null },
      { id: 'repo', label: 'A repo', icon: Board, hint: () => 'Choose a repo.', Picker: () => null },
    ];
    show(<NoteSettings {...sheet()} />);
    expect(buttonSaying(document.body, 'A board')?.disabled).toBe(false);
    await waitUntil(() => expect(buttonSaying(document.body, 'A board')?.disabled).toBe(true));
    expect(buttonSaying(document.body, 'A board')?.textContent).toContain('Works in the app on your phone.');
    expect(buttonSaying(document.body, 'A repo')?.disabled).toBe(false);
  });

  it('opens a link’s own page in the sheet, and back comes to the sheet before it closes it', () => {
    plugged.links = [{ id: 'board', label: 'A board', icon: Board, hint: () => 'Choose a board.', Picker: ({ onDone }) => <button onClick={onDone}>Pick this board</button> }];
    const props = sheet();
    show(<NoteSettings {...props} />);
    act(() => buttonSaying(document.body, 'A board')!.click());
    expect(document.querySelector('[role="dialog"]')?.getAttribute('aria-label')).toBe('A board');
    act(() => {
      goBack();
    });
    expect(props.onClose).not.toHaveBeenCalled();
    expect(document.querySelector('[role="dialog"]')?.getAttribute('aria-label')).toBe('Settings for Groceries');
    act(() => buttonSaying(document.body, 'A board')!.click());
    act(() => button('Pick this board').click());
    expect(document.querySelector('[role="dialog"]')?.getAttribute('aria-label')).toBe('Settings for Groceries');
    act(() => {
      goBack();
    });
    expect(props.onClose).toHaveBeenCalledTimes(1);
  });

  it('judges an action by the note as it was when the sheet opened, and runs it on the note', () => {
    const run = vi.fn(async () => undefined);
    const enabled = vi.fn((_id: string, body: string) => body.includes('[ ]'));
    plugged.actions = [{ id: 'send', label: 'Send the list', icon: Board, visible: () => true, hint: (_id, body) => `${body.split('\n').length} to send.`, enabled, run }];
    const note = editing('- [ ] milk\n- [ ] eggs');
    const props = sheet({ editing: note });
    show(<NoteSettings {...props} />);
    expect(buttonSaying(document.body, 'Send the list')?.textContent).toContain('2 to send.');
    rerender(<NoteSettings {...props} title="Groceries!" />);
    expect(note.body).toHaveBeenCalledTimes(1);
    act(() => buttonSaying(document.body, 'Send the list')!.click());
    expect(props.onClose).toHaveBeenCalledTimes(1);
    expect(run).toHaveBeenCalledWith(note);
  });

  it('greys an action with nothing to do, and leaves out one that is not for this note', () => {
    plugged.actions = [
      { id: 'send', label: 'Send the list', icon: Board, visible: () => true, hint: () => 'Every item is already there.', enabled: () => false, run: vi.fn() },
      { id: 'other', label: 'Not here', icon: Board, visible: () => false, hint: () => '', enabled: () => true, run: vi.fn() },
    ];
    show(<NoteSettings {...sheet()} />);
    expect(buttonSaying(document.body, 'Send the list')?.disabled).toBe(true);
    expect(buttonSaying(document.body, 'Not here')).toBeUndefined();
  });
});

describe('the Workspace page', () => {
  it('makes a workspace, files the note there, and the sheet then says where it is', () => {
    show(<NoteSettings {...sheet()} />);
    expect(buttonSaying(document.body, 'Workspace')?.textContent).toContain('None yet. Make one to sort your notes.');
    act(() => buttonSaying(document.body, 'Workspace')!.click());
    const field = [...document.querySelectorAll('input')].find((input) => input.closest('label')?.textContent?.includes('New workspace'))!;
    typeInto(field, 'Cabin');
    act(() => button('Add it and file this note there').click());
    expect(workspaceOf('n1')?.name).toBe('Cabin');
    expect(buttonSaying(document.body, 'Workspace')?.textContent).toContain('Cabin');
  });
});
