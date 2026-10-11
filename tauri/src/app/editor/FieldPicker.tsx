import { useState, type ComponentType, type JSX } from 'react';
import { Ban, CalendarDays, CalendarSearch, CalendarX, Circle, CircleCheck, CircleDashed, CircleDot, Eye, Sun, Sunrise, UserMinus, type IconProps } from '@glacier/icons';
import { PRIORITIES, samePerson, type PriorityName } from '../core/taskFields.ts';
import { hueOf, statusLook, type FieldPick, type StatusLook } from './fieldPicks.ts';
import { SheetField, SheetGroup, SheetNote, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import { dayLabel, PRIORITY_ICON } from './fieldChips.ts';
import { dayChoices, pickDay } from './fieldMenu.ts';
import { Sheet } from './Sheet.tsx';
import styles from './FieldPicker.module.css';

/**
 * A field picked in a sheet: what a tap on a status, a priority, a person or a day in a query, a board or a notebook's
 * index opens (editor/QueryView.tsx, notes/TicketMark.tsx; docs/DESIGN.md §169). Matt: "make parts of query boards and
 * stuff intractable, I'd like to be able to click things like done labels in order to change the status … use modals
 * with iconography and color".
 *
 * Every choice wears its mark in its colour, the same marks the cells draw: a status its category's (a dashed ring for
 * a backlog, a ring not started, a dot under way, an eye in review, a tick done, in the faint ink, blue, purple and
 * green), a priority Jira's chevrons, a person their initial in a round, a day the sun, the sunrise or the calendar.
 * The one it has is lit with the sheet's tick. A choice writes and closes; the writing is the caller's (`onPick`, a
 * value or null to take it off), so the same sheet serves a record in this note and one in another.
 */

interface FieldPickerProps {
  pick: FieldPick;
  /** What the field is called, the sheet's title: "Status", "Due". */
  label: string;
  /** The record it is set on, said under the title. */
  record: string;
  /** A choice: the value written, or null to take the field off. A to-do's box is written as "done" or "todo". */
  onPick: (value: string | null) => void;
  onClose: () => void;
}

// ---- the marks ------------------------------------------------------------------------------------

const STATUS_ICON: Readonly<Record<StatusLook, ComponentType<IconProps>>> = {
  backlog: CircleDashed,
  todo: Circle,
  doing: CircleDot,
  review: Eye,
  done: CircleCheck,
};

/** A status's mark in its colour, for a sheet's row, a cell or an index (`look` from `statusLook`). */
export function StatusIcon({ look, size = '1em' }: { look: StatusLook; size?: number | string }) {
  const Icon = STATUS_ICON[look];
  return (
    <span className={styles.mark} data-status={look} aria-hidden="true">
      <Icon size={size} strokeWidth={2.4} />
    </span>
  );
}

function PriorityIcon({ name }: { name: PriorityName }) {
  const Icon = PRIORITY_ICON[name];
  return (
    <span className={styles.mark} data-priority={name} aria-hidden="true">
      <Icon size="1em" strokeWidth={2.6} />
    </span>
  );
}

/** A person's initial in a round, coloured by their name, so one person wears one colour wherever they are listed. */
export function Avatar({ name }: { name: string }) {
  return (
    <span className={styles.avatar} data-hue={hueOf(name)} aria-hidden="true">
      {name.replace(/^@+/, '').charAt(0).toUpperCase() || '?'}
    </span>
  );
}

/** A mark as a component with nothing to pass, which is what a sheet's row wears as its icon. */
function markOf(draw: () => JSX.Element): ComponentType {
  const Mark = () => draw();
  return Mark;
}

/** Plain icons in a tone, for the rows that are not a value: None, No one, Remove, and the days. */
function toned(Icon: ComponentType<IconProps>, tone: 'quiet' | 'day' | 'danger'): ComponentType {
  return markOf(() => (
    <span className={styles.mark} data-tone={tone} aria-hidden="true">
      <Icon size="1em" strokeWidth={2.2} />
    </span>
  ));
}

const DAY_ICON = { today: toned(Sun, 'day'), tomorrow: toned(Sunrise, 'day'), 'next-week': toned(CalendarDays, 'day') } as const;
const PICK_ICON = toned(CalendarSearch, 'day');
const REMOVE_DAY = toned(CalendarX, 'danger');
const NO_PRIORITY = toned(Ban, 'quiet');
const NO_ONE = toned(UserMinus, 'quiet');

// ---- the sheet ------------------------------------------------------------------------------------

export function FieldPicker({ pick, label, record, onPick, onClose }: FieldPickerProps) {
  const [typed, setTyped] = useState('');
  const choose = (value: string | null) => () => {
    onClose();
    onPick(value);
  };
  const head = (
    <>
      <SheetTitle>{label}</SheetTitle>
      {record ? <SheetNote>{record}</SheetNote> : null}
    </>
  );

  if (pick.kind === 'status') {
    const current = pick.value?.toLowerCase() ?? null;
    // The workflow, and the status it has where the workflow does not name it, so the choice it has is never hidden.
    const offered = current && !pick.workflow.some((status) => status.toLowerCase() === current) ? [...pick.workflow, pick.value!] : pick.workflow;
    return (
      <Sheet label={label} onClose={onClose}>
        {head}
        <SheetGroup>
          {offered.map((status) => {
            const look = statusLook(status, pick.workflow);
            return <SheetRow key={status} icon={markOf(() => <StatusIcon look={look} />)} label={status} chosen={current === status.toLowerCase()} onPress={choose(status)} />;
          })}
          <SheetRow icon={NO_PRIORITY} label="No status" chosen={current === null} onPress={choose(null)} />
        </SheetGroup>
      </Sheet>
    );
  }

  if (pick.kind === 'box') {
    return (
      <Sheet label={label} onClose={onClose}>
        {head}
        <SheetGroup>
          <SheetRow icon={markOf(() => <StatusIcon look="todo" />)} label="To do" chosen={!pick.done} onPress={choose('todo')} />
          <SheetRow icon={markOf(() => <StatusIcon look="done" />)} label="Done" chosen={pick.done} onPress={choose('done')} />
        </SheetGroup>
      </Sheet>
    );
  }

  if (pick.kind === 'priority') {
    return (
      <Sheet label={label} onClose={onClose}>
        {head}
        <SheetGroup>
          {PRIORITIES.map((priority) => (
            <SheetRow key={priority.name} icon={markOf(() => <PriorityIcon name={priority.name} />)} label={priority.label} chosen={pick.value === priority.name} onPress={choose(priority.name)} />
          ))}
          <SheetRow icon={NO_PRIORITY} label="None" chosen={pick.value === null} onPress={choose(null)} />
        </SheetGroup>
      </Sheet>
    );
  }

  if (pick.kind === 'person') {
    const name = typed.trim().replace(/^@+/, '');
    const people = pick.people.filter((person) => !name || person.toLowerCase().includes(name.toLowerCase()));
    const known = people.some((person) => samePerson(person, name));
    return (
      <Sheet label={label} onClose={onClose}>
        {head}
        <SheetField
          label="Name"
          value={typed}
          placeholder="Type a name"
          autoComplete="off"
          enterKeyHint="done"
          onChange={(event) => setTyped(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter' && name) choose(name)();
          }}
        />
        <SheetGroup>
          {name && !known ? <SheetRow icon={markOf(() => <Avatar name={name} />)} label={`Assign to ${name}`} onPress={choose(name)} /> : null}
          {people.slice(0, 30).map((person) => (
            <SheetRow key={person} icon={markOf(() => <Avatar name={person} />)} label={person} chosen={!!pick.value && samePerson(pick.value, person)} onPress={choose(person)} />
          ))}
          <SheetRow icon={NO_ONE} label="No one" chosen={!pick.value} onPress={choose(null)} />
        </SheetGroup>
      </Sheet>
    );
  }

  // A day: today, tomorrow and next week, the phone's own calendar, and Remove where it has one.
  const choices = dayChoices(pick.today);
  const other = pick.value && !choices.some((choice) => choice.day === pick.value) ? pick.value : null;
  const pickOther = () => {
    onClose();
    // The page's own date input (editor/fieldMenu.ts `pickDay`), in the middle of the screen where the sheet was: the
    // phone's calendar is a sheet of its own, and a desktop's opens beside it.
    pickDay({ x: window.innerWidth / 2, y: window.innerHeight / 2 }, pick.value, (day) => onPick(day));
  };
  return (
    <Sheet label={label} onClose={onClose}>
      {head}
      <SheetGroup>
        {choices.map((choice) => (
          <SheetRow key={choice.id} icon={DAY_ICON[choice.id]} label={choice.label} hint={dayLabel(choice.day, pick.today) === choice.label ? undefined : dayLabel(choice.day, pick.today)} chosen={pick.value === choice.day} onPress={choose(choice.day)} />
        ))}
        <SheetRow icon={PICK_ICON} label="Pick a date" hint={other ? dayLabel(other, pick.today) : undefined} chosen={other !== null} onPress={pickOther} />
        {pick.value ? <SheetRow icon={REMOVE_DAY} label="Remove" danger onPress={choose(null)} /> : null}
      </SheetGroup>
    </Sheet>
  );
}
