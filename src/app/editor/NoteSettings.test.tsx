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

  it('offers the runs that were only spoken, in order, each running its own kind (docs/DESIGN.md §145)', () => {
    const asked: string[] = [];
    show(<NoteSettings {...sheet({ onAi: (kind) => asked.push(kind) })} />);
    const labels = [...document.querySelectorAll('button[aria-pressed]')].map((b) => b.querySelector('span:nth-child(2)')?.firstChild?.textContent);
    expect(labels).toEqual(['Format', 'Summarize', 'Enhance', 'Fix spelling', 'Make a list', 'Continue']);
    act(() => buttonSaying(document.body, 'Fix spelling')!.click());
    rerender(<NoteSettings {...sheet({ onAi: (kind) => asked.push(kind) })} />);
    act(() => buttonSaying(document.body, 'Make a list')!.click());
    rerender(<NoteSettings {...sheet({ onAi: (kind) => asked.push(kind) })} />);
    act(() => buttonSaying(document.body, 'Continue')!.click());
    expect(asked).toEqual(['fix', 'shape', 'continue']);
  });

  it('shows Fill the blanks only with a blank for the model, its hint counting them', () => {
    show(<NoteSettings {...sheet({ onAi: vi.fn() })} />);
    expect(buttonSaying(document.body, 'Fill the blanks')).toBeFalsy();
    const onAi = vi.fn();
    rerender(<NoteSettings {...sheet({ onAi, blanks: 3 })} />);
    expect(buttonSaying(document.body, 'Fill the blanks')?.textContent).toContain('Answers the 3 questions written {?like this}. Nothing leaves the phone.');
    act(() => buttonSaying(document.body, 'Fill the blanks')!.click());
    expect(onAi).toHaveBeenCalledWith('fill');
  });

  it('asks the AI anything typed in its field, as the spoken Ask', () => {
    const order: string[] = [];
    show(<NoteSettings {...sheet({ onAi: (kind, instruction) => order.push(`${kind}: ${instruction}`), onClose: () => order.push('close') })} />);
    const field = document.querySelector('input[aria-label="What to do with this note"]') as HTMLInputElement;
    expect((document.querySelector('button[aria-label="Ask"]') as HTMLButtonElement).disabled).toBe(true);
    typeInto(field, 'make it shorter');
    act(() => (document.querySelector('button[aria-label="Ask"]') as HTMLButtonElement).click());
    expect(order).toEqual(['close', 'ask: make it shorter']);
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
    show(<NoteSettings {...sheet({ name: { value: 'Map', onChange, kind: 'canvas' } })} />);
    const field = document.querySelector<HTMLInputElement>('input[placeholder="What this canvas is called"]')!;
    expect(field.value).toBe('Map');
    typeInto(field, 'Trip map');
    expect(onChange).toHaveBeenCalledWith('Trip map');
  });

  it('names a notebook in its field, and says it is one', () => {
    show(<NoteSettings {...sheet({ name: { value: 'Field guide', onChange: vi.fn(), kind: 'notebook' } })} />);
    const field = document.querySelector<HTMLInputElement>('input[placeholder="What this notebook is called"]')!;
    expect(field.value).toBe('Field guide');
    expect(document.querySelector('input[placeholder="What this canvas is called"]')).toBeNull();
    rerender(<NoteSettings {...sheet({ name: { value: 'Diary', onChange: vi.fn(), kind: 'journal' } })} />);
    expect(document.querySelector<HTMLInputElement>('input[placeholder="What this journal is called"]')?.value).toBe('Diary');
  });

  it('keeps a notebook as a journal from a page of its own, and back comes to the sheet first', () => {
    const journal = { on: false, template: '', place: false, keep: vi.fn(), setTemplate: vi.fn(), setPlace: vi.fn(), unkeep: vi.fn() };
    show(<NoteSettings {...sheet({ title: 'Trip', name: { value: 'Trip', onChange: vi.fn(), kind: 'notebook' }, journal })} />);
    act(() => buttonSaying(document.body, 'Keep it as a journal')!.click());
    expect(document.body.textContent).toContain('Each entry starts with');
    act(() => void goBack());
    expect(buttonSaying(document.body, 'Keep it as a journal')).toBeDefined();
    expect(journal.keep).not.toHaveBeenCalled();
    act(() => buttonSaying(document.body, 'Keep it as a journal')!.click());
    // A notebook's choice is a draft until it is kept.
    act(() => button('A morning page').click());
    expect(journal.setTemplate).not.toHaveBeenCalled();
    act(() => buttonSaying(document.body, 'Make it a journal')!.click());
    expect(journal.keep).toHaveBeenCalledWith('# {{date}}\n\n> What is on your mind this morning?\n\n', true);
    expect(document.body.textContent).toContain('Where it sits');
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

describe('where the note was written', () => {
  const LONDON = { lat: 51.5074, lon: -0.1278, place: null, rough: false };
  const location = (over: Partial<NonNullable<Props['location']>> = {}): NonNullable<Props['location']> => ({ tag: null, can: { ok: true }, asksName: true, refused: null, onAdd: vi.fn(), onRemove: vi.fn(), ...over });
  const row = () => buttonSaying(document.body, 'Add my location') ?? [...document.querySelectorAll('[aria-disabled="true"]')].find((el) => el.textContent?.includes('Add my location'));

  it('offers to add the location where a fix can be asked for, saying whether the name will be asked too', () => {
    const here = location();
    show(<NoteSettings {...sheet({ location: here })} />);
    expect(row()?.textContent).toContain('Where you are now, kept in the note. Its name is asked of OpenStreetMap once.');
    act(() => buttonSaying(document.body, 'Add my location')!.click());
    expect(here.onAdd).toHaveBeenCalledTimes(1);
    rerender(<NoteSettings {...sheet({ location: location({ asksName: false }) })} />);
    expect(row()?.textContent).toContain('Where you are now, kept in the note.');
    expect(row()?.textContent).not.toContain('OpenStreetMap');
  });

  it('offers to remove a tag, naming the place or the coordinates', () => {
    const here = location({ tag: { ...LONDON, place: 'Trafalgar Square, London' } });
    show(<NoteSettings {...sheet({ location: here })} />);
    expect(buttonSaying(document.body, 'Remove location')?.textContent).toContain('Trafalgar Square, London');
    act(() => buttonSaying(document.body, 'Remove location')!.click());
    expect(here.onRemove).toHaveBeenCalledTimes(1);
    rerender(<NoteSettings {...sheet({ location: location({ tag: { ...LONDON, lat: 51.51, lon: -0.13, rough: true } }) })} />);
    expect(buttonSaying(document.body, 'Remove location')?.textContent).toContain('Roughly 51.51, -0.13');
  });

  it('greys the row and says why where no fix can be asked for', () => {
    const why = {
      'local-only': 'Local only is on. A location fix would ask the phone’s location service.',
      mac: 'This Mac can’t say where it is yet. Tag it on the phone and it syncs here.',
      unavailable: 'Update Ghost.md to tag notes with where they were written.',
      none: 'This browser can’t say where you are.',
    } as const;
    for (const [reason, words] of Object.entries(why)) {
      unmount();
      show(<NoteSettings {...sheet({ location: location({ can: { ok: false, why: reason as keyof typeof why } }) })} />);
      expect(buttonSaying(document.body, 'Add my location')).toBeUndefined();
      expect(row()?.textContent).toContain(words);
    }
  });

  it('says why the note was not tagged on its own after a refusal, and still offers to try, in the words of where it runs', () => {
    // The Android app asks again after a first refusal: a tap is the way.
    show(<NoteSettings {...sheet({ location: location({ refused: 'refused', onPhone: true }) })} />);
    expect(buttonSaying(document.body, 'Add my location')?.textContent).toContain('Ghost.md wasn’t allowed to know where you are, so this note wasn’t tagged. Tap to ask again.');
    rerender(<NoteSettings {...sheet({ location: location({ refused: 'blocked', onPhone: true }) })} />);
    expect(buttonSaying(document.body, 'Add my location')?.textContent).toContain('Location is off for Ghost.md, so this note wasn’t tagged.');
    // A browser that was refused does not ask again: its own settings first, and no phone in the words.
    rerender(<NoteSettings {...sheet({ location: location({ refused: 'refused' }) })} />);
    const said = buttonSaying(document.body, 'Add my location')?.textContent ?? '';
    expect(said).toContain('Allow location for this site in the browser’s settings, then tap to try again.');
    expect(said).not.toContain('Tap to ask again');
    expect(said).not.toContain('phone');
  });

  it('has no such row where the screen offers none', () => {
    show(<NoteSettings {...sheet()} />);
    expect(document.body.textContent).not.toContain('Add my location');
  });
});
