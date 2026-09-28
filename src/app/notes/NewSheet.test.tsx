import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { installBack } from '../core/back.ts';
import { buttonSaying, rerender, show, typeInto } from '../../test/render.tsx';
import { NewSheet } from './NewSheet.tsx';

/**
 * What the + makes, and the copy of a shared note it can save: a row that becomes a field, whose failure is said in
 * the row itself, and whose success closes the sheet.
 */

const sheet = () => document.querySelector('[role="dialog"][aria-label="New"]');
const noop = () => undefined;
/** Escape's answer, installed by the one test that closes the sheet by it. */
let uninstallBack: () => void = noop;
afterEach(() => {
  uninstallBack();
  uninstallBack = noop;
});

describe('the + sheet', () => {
  it('draws nothing while it is shut', () => {
    const host = show(<NewSheet open={false} onClose={noop} onNote={noop} onCanvas={noop} onBook={noop} />);
    expect(host.innerHTML).toBe('');
  });

  it('closes as it makes what was chosen', () => {
    const onClose = vi.fn();
    const onCanvas = vi.fn();
    show(<NewSheet open onClose={onClose} onNote={noop} onCanvas={onCanvas} onBook={noop} />);
    act(() => buttonSaying(sheet()!, 'Cards on a page')!.click());
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(onCanvas).toHaveBeenCalledTimes(1);
    // With no way to save a copy, the sheet does not offer one.
    expect(buttonSaying(sheet()!, 'From a shared link')).toBeUndefined();
  });

  it('offers a notebook by that name, and makes one on a tap', () => {
    const onBook = vi.fn();
    show(<NewSheet open onClose={noop} onNote={noop} onCanvas={noop} onBook={onBook} onFromLink={async () => undefined} />);
    // A journal is a kind of notebook, made from the same row (book/NewBookSheet.tsx): there is no Journal row.
    expect(buttonSaying(sheet()!, 'Notebook')?.textContent).toContain('Notes in an order with an index, or a journal of dated entries.');
    expect(buttonSaying(sheet()!, 'Journal')).toBeUndefined();
    act(() => buttonSaying(sheet()!, 'Notebook')!.click());
    expect(onBook).toHaveBeenCalledTimes(1);
    expect(sheet()?.textContent).not.toMatch(/\bbook\b/i);
  });

  it('offers a new entry in the journal written in last, right after Note, with what an entry starts with', () => {
    const onPress = vi.fn();
    const onClose = vi.fn();
    show(<NewSheet open onClose={onClose} onNote={noop} onCanvas={noop} onBook={noop} entry={{ journal: 'Diary', hint: 'Starts with the date and the time.', onPress }} />);
    const rows = [...sheet()!.querySelectorAll('button')].map((b) => b.textContent);
    expect(rows[1]).toBe('Entry in DiaryStarts with the date and the time.');
    act(() => buttonSaying(sheet()!, 'Entry in Diary')!.click());
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(onPress).toHaveBeenCalledTimes(1);
  });

  it('saves a copy from a pasted link, saying what went wrong in the row, and closes once it is saved', async () => {
    const onClose = vi.fn();
    const onFromLink = vi.fn(async (link: string) => {
      if (!link.includes('#')) throw new Error('This link is missing its key.');
    });
    show(<NewSheet open onClose={onClose} onNote={noop} onCanvas={noop} onBook={noop} onFromLink={onFromLink} />);
    act(() => buttonSaying(sheet()!, 'From a shared link')!.click());
    const field = sheet()!.querySelector<HTMLInputElement>('input')!;
    // Nothing pasted: nothing asked for.
    await act(async () => buttonSaying(sheet()!, 'Save a copy')!.click());
    expect(onFromLink).not.toHaveBeenCalled();
    typeInto(field, '  https://attack.fm/glyph/read.html  ');
    await act(async () => buttonSaying(sheet()!, 'Save a copy')!.click());
    expect(onFromLink).toHaveBeenLastCalledWith('https://attack.fm/glyph/read.html');
    expect(sheet()?.textContent).toContain('This link is missing its key.');
    expect(onClose).not.toHaveBeenCalled();
    typeInto(field, 'https://attack.fm/glyph/read.html#abc.def');
    await act(async () => void field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })));
    expect(onFromLink).toHaveBeenLastCalledWith('https://attack.fm/glyph/read.html#abc.def');
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('opens on its choices again however it was closed, not on the link and the words left in it', () => {
    uninstallBack = installBack();
    const onClose = vi.fn();
    const sheetFor = (open: boolean) => <NewSheet open={open} onClose={onClose} onNote={noop} onCanvas={noop} onBook={noop} onFromLink={async () => undefined} />;
    show(sheetFor(true));
    act(() => buttonSaying(sheet()!, 'From a shared link')!.click());
    typeInto(sheet()!.querySelector<HTMLInputElement>('input')!, 'half a li');
    // Closed by the back gesture, which is Escape on a desktop.
    act(() => void window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })));
    expect(onClose).toHaveBeenCalledTimes(1);
    rerender(sheetFor(false));
    rerender(sheetFor(true));
    expect(sheet()!.querySelector('input')).toBeNull();
    expect(buttonSaying(sheet()!, 'From a shared link')).toBeTruthy();
  });
});

describe('a meeting from the + sheet', () => {
  it('is offered only where one can be recorded, with the cassette, and starts one as the sheet closes', () => {
    const onClose = vi.fn();
    const onMeeting = vi.fn();
    show(<NewSheet open onClose={onClose} onNote={noop} onCanvas={noop} onBook={noop} />);
    expect(buttonSaying(sheet()!, 'Record a meeting')).toBeUndefined();
    rerender(<NewSheet open onClose={onClose} onNote={noop} onCanvas={noop} onBook={noop} onMeeting={onMeeting} />);
    const row = buttonSaying(sheet()!, 'Record a meeting. The screen can go off. It is written up afterwards.')!;
    expect(row.textContent).toContain('Meeting');
    expect(row.querySelector('svg')).not.toBeNull();
    act(() => row.click());
    expect(onMeeting).toHaveBeenCalledTimes(1);
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
