import { useState, type ComponentType, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { Braces, Lock, Pencil, Plus, Ticket as TicketMark, X } from '@glacier/icons';
import { waitingOn, type TicketChoice } from '../book/tickets.ts';
import { isoDay } from '../core/days.ts';
import { DEFAULT_STATUSES, propertiesOf, propertyList, statusCategory, TICKET_PROPERTIES, ticketOf, type StatusCategory } from '../core/properties.ts';
import { PRIORITIES, priorityOf, samePerson } from '../core/taskFields.ts';
import { SheetField, SheetGroup, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import { Sheet } from './Sheet.tsx';
import { dayLabel, dueState, hiddenRows, linksValue, linkTo, otherKeys, panelRows, type PanelKey } from './ticketRows.ts';
import type { TicketOptions } from './tickets.ts';
import styles from './TicketPanel.module.css';

/**
 * A ticket's properties, drawn over its words in place of its front matter (editor/tickets.ts; docs/DESIGN.md §157):
 * Matt asked for tickets as notes, with "the quiet front matter" becoming "a Notion-style properties panel with pickers
 * for status, person and date". Its key heads it; each row is a property's name and its value, and a tap on the value
 * picks a new one - from a sheet for a status, a person, a priority and other tickets, from the phone's own date
 * picker for a day, typed for a number and labels - and writes it into the front matter (`write`), which is the only
 * place any of it is kept. A ticket waiting on one that is not done says so first, with a lock.
 *
 * Read, with nothing to pick, where the note cannot be edited.
 */

export interface TicketPanelProps {
  /** The front matter's lines, fences and all. */
  front: string;
  /** The library's tickets and people; null draws the ticket from its own lines alone. */
  options: TicketOptions | null;
  /** Whether the note can be changed here. */
  editable: boolean;
  /** Writes one property: a value, a list, or null to take it off. */
  write: (key: string, value: string | readonly string[] | null) => void;
  /** Shows the front matter as its lines, the caret in them. */
  openLines: () => void;
}

/** What a sheet is open to pick. */
type Picking = 'status' | 'assignee' | 'priority' | 'blocked-by' | 'parent';

/** A property's name, as the panel says it (core/properties.ts `TICKET_PROPERTIES`). */
const LABEL = new Map<string, string>(TICKET_PROPERTIES.map((property) => [property.key, property.label]));
const labelOf = (key: string) => LABEL.get(key) ?? key;

/** A status's colour, as a dot: one component a category, for the sheet's rows to wear as their icon. */
const TodoDot = () => <span className={styles.dot} data-category="todo" aria-hidden="true" />;
const DoingDot = () => <span className={styles.dot} data-category="doing" aria-hidden="true" />;
const DoneDot = () => <span className={styles.dot} data-category="done" aria-hidden="true" />;
const DOTS: Record<StatusCategory, ComponentType> = { todo: TodoDot, doing: DoingDot, done: DoneDot };

export function TicketPanel({ front, options, editable, write, openLines }: TicketPanelProps) {
  const [more, setMore] = useState(false);
  const [picking, setPicking] = useState<Picking | null>(null);
  const statuses = options?.statuses() ?? DEFAULT_STATUSES;
  const ticket = ticketOf(front, statuses);
  if (!ticket) return null;
  const raw = (key: string) => propertiesOf(front).find((property) => property.key.toLowerCase() === key)?.value ?? '';
  const today = isoDay(new Date());
  const rows = panelRows(front, more);
  const hidden = editable && !more ? hiddenRows(front) : [];
  const others = otherKeys(front);
  const waits = options ? waitingOn(ticket, options.find) : [];
  const find = (target: string): TicketChoice => options?.find(target) ?? { key: null, title: target, status: null, category: 'todo' };
  const pick = (what: Picking) => (editable ? () => setPicking(what) : undefined);
  // A ticket made with no key (a Bug report from the blank page) takes its notebook's next, a tap away.
  const offered = !ticket.id && editable ? (options?.nextId?.() ?? null) : null;

  const value = (key: PanelKey): ReactNode => {
    switch (key) {
      case 'status':
        return (
          <Value onPress={pick('status')} label="Status" empty={!ticket.status}>
            <span className={styles.dot} data-category={ticket.category} aria-hidden="true" />
            {ticket.status ?? 'Empty'}
          </Value>
        );
      case 'assignee':
        return (
          <Value onPress={pick('assignee')} label="Assignee" empty={!ticket.assignee}>
            {ticket.assignee ? (
              <span className={styles.avatar} aria-hidden="true">
                {ticket.assignee.slice(0, 1).toUpperCase()}
              </span>
            ) : null}
            {ticket.assignee ?? 'Empty'}
          </Value>
        );
      case 'priority': {
        const priority = priorityOf(ticket.priority);
        return (
          <Value onPress={pick('priority')} label="Priority" empty={!priority}>
            {priority ? `${priority.emoji} ${priority.label}` : 'Empty'}
          </Value>
        );
      }
      case 'due':
      case 'start': {
        const day = key === 'due' ? ticket.due : ticket.start;
        return <DayValue day={day} written={raw(key)} label={labelOf(key)} state={key === 'due' ? dueState(day, today, ticket.category) : null} today={today} editable={editable} onChange={(next) => write(key, next)} />;
      }
      case 'estimate':
        return <TypedValue value={raw('estimate')} label="Estimate" mode="decimal" editable={editable} onCommit={(typed) => write('estimate', typed || null)} />;
      case 'labels':
        return <TypedValue value={propertyList(raw('labels')).join(', ')} label="Labels" mode="text" editable={editable} onCommit={(typed) => write('labels', propertyList(typed))} />;
      case 'blocked-by':
      case 'parent': {
        const targets = key === 'parent' ? (ticket.parent ? [ticket.parent] : []) : ticket.blockedBy;
        return (
          <span className={styles.links}>
            {targets.map((target) => (
              <LinkChip key={target} choice={find(target)} waiting={key === 'blocked-by' && waits.some((wait) => wait.target === target)} onOpen={options ? () => options.open(target) : undefined} />
            ))}
            {editable ? (
              <button type="button" className={styles.edit} aria-label={`Change ${labelOf(key)}`} onClick={() => setPicking(key)}>
                {targets.length ? <Pencil size={13} aria-hidden="true" /> : <Plus size={13} aria-hidden="true" />}
                {targets.length ? null : <span>Add</span>}
              </button>
            ) : targets.length ? null : (
              <span className={styles.empty}>Empty</span>
            )}
          </span>
        );
      }
    }
  };

  return (
    <section className={styles.panel} aria-label={ticket.id ? `Ticket ${ticket.id}` : 'Ticket'}>
      <header className={styles.head}>
        <TicketMark size={14} strokeWidth={2.1} aria-hidden="true" />
        <span className={styles.key}>{ticket.id ?? 'Ticket'}</span>
        {offered ? (
          <button type="button" className={styles.give} onClick={() => write('id', offered)}>
            Give it {offered}
          </button>
        ) : null}
        {editable ? (
          <button type="button" className={styles.asText} aria-label="Show the properties as text" title="Show the properties as text" onClick={openLines}>
            <Braces size={14} aria-hidden="true" />
          </button>
        ) : null}
      </header>
      {waits.length ? (
        <p className={styles.waiting}>
          <Lock size={13} strokeWidth={2.2} aria-hidden="true" />
          <span>Waiting on</span>
          {waits.map((wait) => (
            <button key={wait.target} type="button" className={styles.waitOn} onClick={() => options?.open(wait.target)}>
              {wait.found.key ?? wait.found.title}
              {wait.found.key && wait.found.title ? <span className={styles.waitTitle}>{wait.found.title}</span> : null}
            </button>
          ))}
        </p>
      ) : null}
      <dl className={styles.rows}>
        {rows.map((key) => (
          <div key={key} className={styles.row}>
            <dt className={styles.name}>{labelOf(key)}</dt>
            <dd className={styles.value}>{value(key)}</dd>
          </div>
        ))}
      </dl>
      {hidden.length || (others.length && editable) ? (
        <div className={styles.foot}>
          {hidden.length ? (
            <button type="button" className={styles.more} onClick={() => setMore(true)}>
              <Plus size={13} aria-hidden="true" /> {hidden.map(labelOf).join(', ')}
            </button>
          ) : null}
          {others.length && editable ? (
            <button type="button" className={styles.others} onClick={openLines} title="Show the properties as text">
              {others.join(' · ')}
            </button>
          ) : null}
        </div>
      ) : null}
      {picking && options
        ? createPortal(
            <Picker
              what={picking}
              ticket={ticket}
              statuses={statuses}
              options={options}
              write={write}
              onClose={() => setPicking(null)}
            />,
            document.body,
          )
        : null}
    </section>
  );
}

/** A value: a button that opens its picker where the note can be changed, its words alone where it cannot. */
function Value({ onPress, label, empty, children }: { onPress?: () => void; label: string; empty: boolean; children: ReactNode }) {
  if (!onPress) {
    return (
      <span className={styles.chip} data-empty={empty || undefined}>
        {children}
      </span>
    );
  }
  return (
    <button type="button" className={styles.chip} data-empty={empty || undefined} data-property={label} aria-haspopup="dialog" onClick={onPress}>
      {children}
    </button>
  );
}

/**
 * A day: said in words, Today or Sat 3 Oct, red once a due day has passed; the phone's own date picker under it, which
 * a tap opens, and a cross to take it off. A day written by hand that is not one is shown as written.
 */
function DayValue({ day, written, label, state, today, editable, onChange }: { day: string | null; written: string; label: string; state: 'overdue' | 'today' | null; today: string; editable: boolean; onChange: (day: string | null) => void }) {
  const said = day ? dayLabel(day, today) : written || 'Empty';
  const empty = !day && !written;
  if (!editable) {
    return (
      <span className={styles.chip} data-empty={empty || undefined} data-due={state ?? undefined}>
        {said}
      </span>
    );
  }
  return (
    <span className={styles.day}>
      <span className={styles.chip} data-empty={empty || undefined} data-due={state ?? undefined}>
        {said}
        <input
          type="date"
          className={styles.dayInput}
          aria-label={label}
          value={day ?? ''}
          onChange={(event) => onChange(event.target.value || null)}
          onClick={(event) => {
            // Where the browser has it, the calendar opens on the tap rather than on a second one on its icon.
            try {
              event.currentTarget.showPicker();
            } catch {
              // Not offered here: the field takes the tap as a field does.
            }
          }}
        />
      </span>
      {day || written ? (
        <button type="button" className={styles.clear} aria-label={`Take ${label.toLowerCase()} off`} onClick={() => onChange(null)}>
          <X size={12} aria-hidden="true" />
        </button>
      ) : null}
    </span>
  );
}

/** A value typed in place, a number or a list with commas, written when the field is left or Enter is pressed. */
function TypedValue({ value, label, mode, editable, onCommit }: { value: string; label: string; mode: 'decimal' | 'text'; editable: boolean; onCommit: (typed: string) => void }) {
  const [draft, setDraft] = useState<string | null>(null);
  if (!editable) {
    return (
      <span className={styles.chip} data-empty={!value || undefined}>
        {value || 'Empty'}
      </span>
    );
  }
  const commit = () => {
    if (draft === null) return;
    setDraft(null);
    if (draft.trim() !== value.trim()) onCommit(draft.trim());
  };
  return (
    <input
      className={styles.typed}
      aria-label={label}
      inputMode={mode}
      enterKeyHint="done"
      autoComplete="off"
      placeholder="Empty"
      value={draft ?? value}
      onChange={(event) => setDraft(event.target.value)}
      onBlur={commit}
      onKeyDown={(event) => {
        if (event.key === 'Enter') event.currentTarget.blur();
        if (event.key === 'Escape') {
          setDraft(null);
          event.currentTarget.blur();
        }
      }}
    />
  );
}

/** Another ticket, as a property links it: its status's dot, its key and its title; a lock where this one waits on it. */
function LinkChip({ choice, waiting, onOpen }: { choice: TicketChoice; waiting: boolean; onOpen?: () => void }) {
  const words = (
    <>
      {waiting ? <Lock size={12} strokeWidth={2.2} aria-label="Waiting on it" /> : <span className={styles.dot} data-category={choice.category} aria-hidden="true" />}
      {choice.key ? <span className={styles.linkKey}>{choice.key}</span> : null}
      <span className={styles.linkTitle}>{choice.key && choice.title === choice.key ? '' : choice.title}</span>
    </>
  );
  return onOpen ? (
    <button type="button" className={styles.link} data-waiting={waiting || undefined} onClick={onOpen}>
      {words}
    </button>
  ) : (
    <span className={styles.link}>{words}</span>
  );
}

/** The sheet a value is picked from. */
function Picker({ what, ticket, statuses, options, write, onClose }: { what: Picking; ticket: NonNullable<ReturnType<typeof ticketOf>>; statuses: readonly string[]; options: TicketOptions; write: TicketPanelProps['write']; onClose: () => void }) {
  const [typed, setTyped] = useState('');
  const chose = (key: string, value: string | readonly string[] | null) => {
    write(key, value);
    onClose();
  };
  if (what === 'status') {
    return (
      <Sheet label="Status" onClose={onClose}>
        <SheetTitle>Status</SheetTitle>
        <SheetGroup>
          {statuses.map((status) => (
            <SheetRow key={status} icon={DOTS[statusCategory(status, statuses)]} label={status} chosen={!!ticket.status && ticket.status.toLowerCase() === status.toLowerCase()} onPress={() => chose('status', status)} />
          ))}
        </SheetGroup>
      </Sheet>
    );
  }
  if (what === 'priority') {
    return (
      <Sheet label="Priority" onClose={onClose}>
        <SheetTitle>Priority</SheetTitle>
        <SheetGroup>
          {PRIORITIES.map((priority) => (
            <SheetRow key={priority.name} label={`${priority.emoji}  ${priority.label}`} chosen={ticket.priority === priority.name} onPress={() => chose('priority', priority.name)} />
          ))}
          <SheetRow label="None" chosen={!ticket.priority} onPress={() => chose('priority', null)} />
        </SheetGroup>
      </Sheet>
    );
  }
  if (what === 'assignee') {
    const name = typed.trim();
    const people = options.people().filter((person) => !name || person.toLowerCase().includes(name.toLowerCase()));
    const known = people.some((person) => samePerson(person, name));
    return (
      <Sheet label="Assignee" onClose={onClose}>
        <SheetTitle>Assignee</SheetTitle>
        <SheetField label="Name" value={typed} placeholder="Type a name" autoComplete="off" onChange={(event) => setTyped(event.target.value)} onKeyDown={(event) => event.key === 'Enter' && name && chose('assignee', name)} />
        <SheetGroup>
          {name && !known ? <SheetRow label={`Assign to ${name}`} onPress={() => chose('assignee', name)} /> : null}
          {people.slice(0, 30).map((person) => (
            <SheetRow key={person} label={person} chosen={!!ticket.assignee && samePerson(ticket.assignee, person)} onPress={() => chose('assignee', person)} />
          ))}
          <SheetRow label="No one" chosen={!ticket.assignee} onPress={() => chose('assignee', null)} />
        </SheetGroup>
      </Sheet>
    );
  }
  // Another ticket, or several: found by its key or its title as it is typed.
  const many = what === 'blocked-by';
  const current = many ? ticket.blockedBy : ticket.parent ? [ticket.parent] : [];
  const holds = (choice: TicketChoice) => current.some((target) => (choice.key !== null && target.toUpperCase() === choice.key) || target.toLowerCase() === choice.title.toLowerCase());
  const needle = typed.trim().toLowerCase();
  const choices = options.choices().filter((choice) => !needle || `${choice.key ?? ''} ${choice.title}`.toLowerCase().includes(needle));
  const toggle = (choice: TicketChoice) => {
    const kept = current.filter((target) => !((choice.key !== null && target.toUpperCase() === choice.key) || target.toLowerCase() === choice.title.toLowerCase()));
    const links = (holds(choice) ? kept : [...kept, choice.key ?? choice.title]).map((target) => linkTo(options.find(target) ?? { key: null, title: target, status: null, category: 'todo' }));
    write('blocked-by', linksValue(links));
  };
  return (
    <Sheet label={labelOf(what)} onClose={onClose}>
      <SheetTitle>{labelOf(what)}</SheetTitle>
      <SheetField label="Find a ticket" value={typed} placeholder="Its key or its title" autoComplete="off" onChange={(event) => setTyped(event.target.value)} />
      <SheetGroup>
        {choices.length === 0 ? <SheetRow label={needle ? 'No ticket by that key or title.' : 'No other tickets yet.'} /> : null}
        {choices.slice(0, 40).map((choice) => (
          <SheetRow
            key={`${choice.key ?? ''}-${choice.title}`}
            icon={DOTS[choice.category]}
            label={choice.key ? `${choice.key}  ${choice.title}` : choice.title}
            hint={choice.status ?? undefined}
            chosen={holds(choice)}
            onPress={() => (many ? toggle(choice) : chose('parent', holds(choice) ? null : linkTo(choice)))}
          />
        ))}
        {!many && current.length ? <SheetRow label="No parent" onPress={() => chose('parent', null)} /> : null}
      </SheetGroup>
    </Sheet>
  );
}
