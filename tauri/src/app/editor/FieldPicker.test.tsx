import { act } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { show } from '../../test/render.tsx';
import { DEFAULT_STATUSES } from '../core/properties.ts';
import { FieldPicker } from './FieldPicker.tsx';
import type { FieldPick } from './fieldPicks.ts';

vi.mock('../core/haptics.ts', () => ({ fireNativeHaptic: vi.fn() }));

/*
 * The sheet a query's value or an index's status opens (editor/FieldPicker.tsx; docs/DESIGN.md §169): every choice with
 * its mark in its colour, the one it has lit, and a choice written and the sheet closed.
 */

const TODAY = '2026-10-05';

function open(pick: FieldPick, label = 'Status') {
  const onPick = vi.fn<(value: string | null) => void>();
  const onClose = vi.fn();
  show(<FieldPicker pick={pick} label={label} record="GHO-1 · Fix the login loop" onPick={onPick} onClose={onClose} />);
  const dialog = document.querySelector<HTMLElement>('[role="dialog"]')!;
  const buttons = () => [...dialog.querySelectorAll<HTMLButtonElement>('button')];
  /** A row's label, as said: its words without its mark, its hint or its tick. */
  const said = (button: HTMLButtonElement) => [...button.children].find((child) => !child.hasAttribute('aria-hidden'))?.firstChild?.textContent?.trim() ?? '';
  const rows = () => buttons().map(said);
  const row = (text: string) => buttons().find((button) => said(button) === text)!;
  return { dialog, rows, row, onPick, onClose };
}

describe('a field picked from its sheet', () => {
  it('offers the workflow, each status with its mark in its colour, the one it has lit', () => {
    const { dialog, rows, row } = open({ kind: 'status', value: 'In progress', workflow: DEFAULT_STATUSES });
    expect(dialog.getAttribute('aria-label')).toBe('Status');
    expect(dialog.textContent).toContain('GHO-1 · Fix the login loop');
    expect(rows()).toEqual([...DEFAULT_STATUSES, 'No status']);
    expect([...dialog.querySelectorAll('[data-status]')].map((mark) => mark.getAttribute('data-status'))).toEqual(['backlog', 'todo', 'doing', 'review', 'done']);
    expect(row('In progress').getAttribute('aria-pressed')).toBe('true');
    expect(row('Done').getAttribute('aria-pressed')).toBe('false');
  });

  it('writes the status chosen and closes', () => {
    const { row, onPick, onClose } = open({ kind: 'status', value: 'In progress', workflow: DEFAULT_STATUSES });
    act(() => row('Done').click());
    expect(onPick).toHaveBeenCalledWith('Done');
    expect(onClose).toHaveBeenCalled();
  });

  it('keeps a status the workflow does not name, so the one it has is never hidden', () => {
    const { rows } = open({ kind: 'status', value: 'Blocked', workflow: DEFAULT_STATUSES });
    expect(rows()).toContain('Blocked');
  });

  it('takes a to-do’s status as its box', () => {
    const { rows, row, onPick } = open({ kind: 'box', done: false });
    expect(rows()).toEqual(['To do', 'Done']);
    act(() => row('Done').click());
    expect(onPick).toHaveBeenCalledWith('done');
  });

  it('offers the five priorities in their chevrons’ colours, and None to take it off', () => {
    const { dialog, row, onPick } = open({ kind: 'priority', value: 'high' }, 'Priority');
    expect([...dialog.querySelectorAll('[data-priority]')].map((mark) => mark.getAttribute('data-priority'))).toEqual(['highest', 'high', 'medium', 'low', 'lowest']);
    expect(row('High').getAttribute('aria-pressed')).toBe('true');
    act(() => row('None').click());
    expect(onPick).toHaveBeenCalledWith(null);
  });

  it('offers the people with their initials, and No one', () => {
    const { dialog, row, onPick } = open({ kind: 'person', value: 'Sam', people: ['Sam', 'Priya Shah'] }, 'Assignee');
    expect([...dialog.querySelectorAll('[data-hue]')].map((mark) => mark.textContent)).toEqual(['S', 'P']);
    expect(row('Sam').getAttribute('aria-pressed')).toBe('true');
    act(() => row('Priya Shah').click());
    expect(onPick).toHaveBeenCalledWith('Priya Shah');
  });

  it('offers today, tomorrow and next week, a date of your own, and Remove where there is a day', () => {
    const { rows, row, onPick } = open({ kind: 'day', value: '2026-10-06', today: TODAY }, 'Due');
    expect(rows()).toEqual(['Today', 'Tomorrow', 'Next week', 'Pick a date', 'Remove']);
    expect(row('Tomorrow').getAttribute('aria-pressed')).toBe('true');
    act(() => row('Today').click());
    expect(onPick).toHaveBeenCalledWith(TODAY);
  });

  it('has no Remove for a day not set', () => {
    const { rows } = open({ kind: 'day', value: null, today: TODAY }, 'Due');
    expect(rows()).not.toContain('Remove');
  });
});
