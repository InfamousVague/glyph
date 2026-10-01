import { act } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { inLocale } from '../../test/locale.ts';
import { show } from '../../test/render.tsx';
import type { TicketChoice } from '../book/tickets.ts';
import { DEFAULT_STATUSES } from '../core/properties.ts';
import { TicketPanel } from './TicketPanel.tsx';
import type { TicketOptions } from './tickets.ts';

/**
 * A ticket's properties panel (editor/TicketPanel.tsx; docs/DESIGN.md §157): each value picked writes one property,
 * as a status, a person, a priority, a day, a number, labels and other tickets; a ticket with no key is offered its
 * notebook's next; and a panel that cannot be edited picks nothing.
 */

const COOKIE: TicketChoice = { key: 'GHO-9', title: 'Fix the session cookie', status: 'In review', category: 'doing' };
const BETA: TicketChoice = { key: 'GHO-3', title: 'Ship the beta', status: 'Done', category: 'done' };

const FRONT = '---\ntype: ticket\nid: GHO-12\nstatus: In progress\nassignee: Sam\ndue: 2026-09-28\n---';

let write: ReturnType<typeof vi.fn<(key: string, value: string | readonly string[] | null) => void>>;
let openLines: ReturnType<typeof vi.fn<() => void>>;
const options = (over: Partial<TicketOptions> = {}): TicketOptions => ({
  statuses: () => DEFAULT_STATUSES,
  people: () => ['Sam', 'Priya Shah'],
  choices: () => [COOKIE, BETA],
  find: (target) => [COOKIE, BETA].find((choice) => choice.key === target.toUpperCase()) ?? null,
  open: vi.fn(),
  ...over,
});

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date(2026, 9, 1, 12));
  write = vi.fn();
  openLines = vi.fn();
});
afterEach(() => vi.useRealTimers());

const draw = (front = FRONT, editable = true, given: TicketOptions | null = options()) => show(<TicketPanel front={front} options={given} editable={editable} write={write} openLines={openLines} />);
const valueOf = (host: HTMLElement, name: string) => [...host.querySelectorAll('dt')].find((dt) => dt.textContent === name)!.nextElementSibling as HTMLElement;
const sheetRow = (label: string) => [...document.querySelectorAll<HTMLButtonElement>('[role="dialog"] button')].find((button) => button.textContent?.startsWith(label))!;
const type = (input: HTMLInputElement, text: string) => {
  const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    set.call(input, text);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
};

describe('the panel', () => {
  it('heads with the key and shows the four always asked, an overdue day in red', () => {
    const host = inLocale('en-GB', () => draw());
    expect(host.querySelector('header')?.textContent).toBe('GHO-12');
    expect([...host.querySelectorAll('dt')].map((dt) => dt.textContent)).toEqual(['Status', 'Assignee', 'Priority', 'Due']);
    expect(valueOf(host, 'Status').textContent).toBe('In progress');
    expect(valueOf(host, 'Priority').textContent).toBe('Empty');
    const due = valueOf(host, 'Due').querySelector<HTMLElement>('[data-due]')!;
    expect(due.dataset.due).toBe('overdue');
    expect(due.textContent).toBe('Mon 28 Sept');
  });

  it('shows the rest behind More, and the lines as text from its button', () => {
    const host = draw();
    const more = [...host.querySelectorAll('button')].find((button) => button.textContent?.includes('Start, Estimate, Blocked by, Parent, Labels'))!;
    act(() => more.click());
    expect([...host.querySelectorAll('dt')].map((dt) => dt.textContent)).toEqual(['Status', 'Assignee', 'Priority', 'Due', 'Start', 'Estimate', 'Blocked by', 'Parent', 'Labels']);
    act(() => host.querySelector<HTMLButtonElement>('[aria-label="Show the properties as text"]')!.click());
    expect(openLines).toHaveBeenCalledTimes(1);
  });
});

describe('a value picked', () => {
  it('writes a status from the notebook’s workflow, each in its category’s colour', () => {
    const host = draw(FRONT, true, options({ statuses: () => ['Ideas', 'Building', 'Live'] }));
    act(() => valueOf(host, 'Status').querySelector('button')!.click());
    const dots = [...document.querySelectorAll<HTMLElement>('[role="dialog"] [data-category]')].map((dot) => dot.dataset.category);
    expect(dots).toEqual(['todo', 'doing', 'done']);
    act(() => sheetRow('Live').click());
    expect(write).toHaveBeenCalledWith('status', 'Live');
    expect(document.querySelector('[role="dialog"]')).toBeNull();
  });

  it('writes a priority by its name, or takes it off', () => {
    const host = draw();
    act(() => valueOf(host, 'Priority').querySelector('button')!.click());
    act(() => sheetRow('⏫').click());
    expect(write).toHaveBeenLastCalledWith('priority', 'high');
    act(() => valueOf(host, 'Priority').querySelector('button')!.click());
    act(() => sheetRow('None').click());
    expect(write).toHaveBeenLastCalledWith('priority', null);
  });

  it('writes a person the library names, or one typed', () => {
    const host = draw();
    act(() => valueOf(host, 'Assignee').querySelector('button')!.click());
    act(() => sheetRow('Priya Shah').click());
    expect(write).toHaveBeenLastCalledWith('assignee', 'Priya Shah');
    act(() => valueOf(host, 'Assignee').querySelector('button')!.click());
    type(document.querySelector<HTMLInputElement>('[role="dialog"] input')!, 'Kit');
    act(() => sheetRow('Assign to Kit').click());
    expect(write).toHaveBeenLastCalledWith('assignee', 'Kit');
  });

  it('writes a day from the date field, and takes it off from its cross', () => {
    const host = draw();
    const field = valueOf(host, 'Due').querySelector<HTMLInputElement>('input[type="date"]')!;
    type(field, '2026-10-03');
    expect(write).toHaveBeenLastCalledWith('due', '2026-10-03');
    act(() => valueOf(host, 'Due').querySelector<HTMLButtonElement>('[aria-label="Take due off"]')!.click());
    expect(write).toHaveBeenLastCalledWith('due', null);
  });

  it('writes an estimate and labels when the field is left, and nothing for a field left as it was', () => {
    const host = draw(`${FRONT.slice(0, -3)}estimate: 3\nlabels: [bug]\n---`);
    const estimate = valueOf(host, 'Estimate').querySelector('input')!;
    act(() => estimate.focus());
    act(() => estimate.blur());
    expect(write).not.toHaveBeenCalled();
    act(() => estimate.focus());
    type(estimate, '5');
    act(() => estimate.blur());
    expect(write).toHaveBeenLastCalledWith('estimate', '5');
    const labels = valueOf(host, 'Labels').querySelector('input')!;
    expect(labels.value).toBe('bug');
    act(() => labels.focus());
    type(labels, 'bug, ui');
    act(() => labels.blur());
    expect(write).toHaveBeenLastCalledWith('labels', ['bug', 'ui']);
  });

  it('links another ticket by its key, and says it waits on one that is not done with a lock', () => {
    const host = draw(`${FRONT.slice(0, -3)}blocked-by: "[[GHO-9]]"\n---`);
    expect(host.querySelector('p')?.textContent).toBe('Waiting onGHO-9Fix the session cookie');
    act(() => valueOf(host, 'Blocked by').querySelector<HTMLButtonElement>('[aria-label="Change Blocked by"]')!.click());
    expect(sheetRow('GHO-9').getAttribute('aria-pressed')).toBe('true');
    act(() => sheetRow('GHO-3').click());
    expect(write).toHaveBeenLastCalledWith('blocked-by', ['[[GHO-9]]', '[[GHO-3]]']);
    act(() => sheetRow('GHO-9').click());
    expect(write).toHaveBeenLastCalledWith('blocked-by', null);
  });

  it('offers a ticket with no key its notebook’s next', () => {
    const host = draw('---\ntype: ticket\nstatus: To do\n---', true, options({ nextId: () => 'GHO-14' }));
    const give = [...host.querySelectorAll('button')].find((button) => button.textContent === 'Give it GHO-14')!;
    act(() => give.click());
    expect(write).toHaveBeenCalledWith('id', 'GHO-14');
  });
});

describe('a panel that cannot be edited', () => {
  it('picks nothing: no buttons to open a sheet, no fields', () => {
    const host = draw(FRONT, false);
    expect(host.querySelector('[aria-haspopup]')).toBeNull();
    expect(host.querySelector('input')).toBeNull();
    expect(valueOf(host, 'Status').textContent).toBe('In progress');
  });
});
