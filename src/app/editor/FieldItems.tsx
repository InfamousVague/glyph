import {
  Ban,
  CalendarDays,
  CalendarSearch,
  CalendarX,
  ChevronLeft,
  Sun,
  Sunrise,
  UserMinus,
  UserPlus,
  UserRound,
} from '@glacier/icons';
import type { CSSProperties, MouseEvent } from 'react';
import type { EditorView } from '@codemirror/view';
import { fireNativeHaptic } from '../core/haptics.ts';
import { PRIORITIES, samePerson, type PriorityName } from '../core/taskFields.ts';
import { capitalise } from '../core/text.ts';
import { useRedraw } from '../core/useRedraw.ts';
import { personShown, PRIORITY_ICON } from './fieldChips.ts';
import { dayChoices, lineFields, peopleIn, pickDay, setLineField, setLinePerson, startPerson, todayIs, type FieldPage } from './fieldMenu.ts';
import { MenuItem, MenuWord, type MenuIcon } from './MenuBand.tsx';
import styles from './ContextMenu.module.css';
import own from './FieldItems.module.css';

/**
 * The press-and-hold menu's pages for a to-do's fields (editor/ContextMenu.tsx; docs/DESIGN.md §158), in the band the
 * menu already is, as its Style page is (editor/StyleItems.tsx): a tapped chip opens its own page, and the menu's Due
 * date, Priority and Assign open theirs from a line's actions, with Back to them.
 *
 * - **A day** (the due day, or a start or scheduled day tapped): Today, Tomorrow, Next week, Pick a date - the phone's
 *   own calendar (editor/fieldMenu.ts `pickDay`) - and Remove when it has one. The day it has is lit.
 * - **Priority**: the five, the most urgent first, in the marks the chips draw, and None. The one it has is lit.
 * - **A person** tapped: Remove.
 * - **Assign**: the people the note already names, lit where they are on the line, each pressed on and off, and
 *   Someone new, which writes the at sign where a person goes and leaves the caret after it for the name.
 *
 * Every press writes through core/taskFields.ts (§156) and closes the menu, but a person pressed on Assign, which
 * stays so a second can be added. The editor gets its focus back only where it had it: a chip tapped on a note being
 * read must not raise the keyboard.
 */

const DAY_ICON = { today: Sun, tomorrow: Sunrise, 'next-week': CalendarDays } as const;

/** How many of the note's people Assign offers before Someone new: a band's width on a phone, about. */
const MOST_PEOPLE = 6;

interface FieldItemsProps {
  view: EditorView;
  /** The line the fields are on, counting from 1. */
  line: number;
  page: FieldPage;
  /** Back to the line's actions; absent for a page a chip opened, which has nothing to go back to. */
  onBack?: () => void;
  onClose: () => void;
  /** Whether the editor had its focus when the menu opened, and so gets it back. */
  refocus: boolean;
}

export function FieldItems({ view, line, page, onBack, onClose, refocus }: FieldItemsProps) {
  const redraw = useRedraw();
  const fields = lineFields(view, line);
  if (!fields) return null;
  const today = todayIs();

  /** A press that writes and closes: the menu first, then the edit, then the focus where it was. */
  const write = (run: () => void) => () => {
    fireNativeHaptic('selection');
    onClose();
    run();
    if (refocus) view.focus();
  };

  const back = onBack ? <MenuItem icon={ChevronLeft} label="Back" onPress={onBack} name="Back to the note's actions" /> : null;
  let i = 0;
  const next = () => i++;

  if (page.kind === 'date') {
    const current = fields[page.key];
    const what = page.key;
    return (
      <>
        {back}
        {dayChoices(today).map((choice) => (
          <FieldItem
            key={choice.id}
            icon={DAY_ICON[choice.id]}
            label={choice.label}
            name={`${capitalise(what)} ${choice.label.toLowerCase()}`}
            i={next()}
            lit={current === choice.day}
            onPress={write(() => setLineField(view, line, page.key, choice.day))}
          />
        ))}
        <FieldItem
          icon={CalendarSearch}
          label="Pick a date"
          i={next()}
          onPress={(event) => {
            const box = event.currentTarget.getBoundingClientRect();
            // Opened from the press itself, before the menu goes: the phone opens a picker only from a press.
            pickDay({ x: box.left, y: box.top }, current, (day) => {
              setLineField(view, line, page.key, day);
              if (refocus) view.focus();
            });
            fireNativeHaptic('selection');
            onClose();
          }}
        />
        {current ? <FieldItem icon={CalendarX} label="Remove" name={`Remove the ${what} date`} i={next()} onPress={write(() => setLineField(view, line, page.key, null))} /> : null}
      </>
    );
  }

  if (page.kind === 'priority') {
    return (
      <>
        {back}
        {PRIORITIES.map((priority) => (
          <FieldItem
            key={priority.name}
            icon={PRIORITY_ICON[priority.name]}
            label={priority.label}
            name={`${priority.label} priority`}
            tone={priority.name}
            i={next()}
            lit={fields.priority === priority.name}
            onPress={write(() => setLineField(view, line, 'priority', priority.name))}
          />
        ))}
        <FieldItem icon={Ban} label="None" name="No priority" i={next()} lit={fields.priority === null} onPress={write(() => setLineField(view, line, 'priority', null))} />
      </>
    );
  }

  if (page.kind === 'person') {
    const shown = personShown(page.name);
    return (
      <>
        {back}
        <FieldItem icon={UserMinus} label="Remove" name={`Take ${shown} off`} i={next()} onPress={write(() => setLinePerson(view, line, page.name, false))} />
      </>
    );
  }

  // Assign: who the note names, then someone new.
  const people = peopleIn(view.state.doc.toString()).slice(0, MOST_PEOPLE);
  return (
    <>
      {back}
      {people.map((person) => {
        const on = fields.assignees.some((name) => samePerson(name, person));
        const shown = personShown(person);
        return (
          <FieldItem
            key={person}
            icon={UserRound}
            label={shown}
            name={on ? `Take ${shown} off` : `Assign ${shown}`}
            i={next()}
            lit={on}
            onPress={() => {
              fireNativeHaptic('selection');
              setLinePerson(view, line, person, !on);
              redraw();
            }}
          />
        );
      })}
      <FieldItem
        icon={UserPlus}
        label="Someone new"
        i={next()}
        onPress={() => {
          fireNativeHaptic('selection');
          onClose();
          startPerson(view, line);
        }}
      />
    </>
  );
}

/**
 * A field's choice: its icon over its word, lit (printed in reverse) where the line has it, coming in out of smoke
 * after the ones before it, as a style does (editor/StyleItems.tsx). A priority's mark wears its chip's colour.
 */
function FieldItem({
  icon,
  label,
  name,
  i,
  lit,
  tone,
  onPress,
}: {
  icon: MenuIcon;
  label: string;
  name?: string;
  i: number;
  lit?: boolean;
  tone?: PriorityName;
  onPress: (event: MouseEvent<HTMLButtonElement>) => void;
}) {
  return (
    <button
      type="button"
      role={lit === undefined ? 'menuitem' : 'menuitemradio'}
      aria-checked={lit === undefined ? undefined : lit}
      aria-label={name}
      className={`${styles.item} ${styles.style} ${own.field}`}
      data-lit={lit || undefined}
      data-tone={tone}
      style={{ '--i': i } as CSSProperties}
      onClick={onPress}
    >
      <MenuWord icon={icon} label={label} />
    </button>
  );
}
