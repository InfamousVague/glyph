import type { EditorView } from '@codemirror/view';
import type { Item } from '../../core/boards.ts';
import { isoDay } from '../../core/days.ts';
import { fieldsIn, type FieldSpan } from '../../core/taskFields.ts';
import { chipElement, chipLook } from '../fieldChips.ts';
import { tapField, type FieldPage } from '../fieldMenu.ts';
import { press } from './press.ts';

/**
 * A card's fields: its item's due day, priority and people as small chips of the card's own, in the footer beside the
 * plugin's mark and the arrows (docs/DESIGN.md §158, docs/BOARDS.md). The card's words leave them out
 * (core/boards/items.ts `cardText`), so "Fix the login loop @sam ⏫ 📅 2026-10-03" is a card that says "Fix the login
 * loop", with "(S) sam ⇈ Sat 3 Oct" under it, drawn as the note's line draws them (editor/fieldChips.ts): red once the
 * day has passed, quiet once the card is ticked.
 *
 * Only those three: a card is a glance, and a recurrence, a start day or a named field is the line's to show. A chip
 * is pressed as every control on a board is (editor/boards/press.ts), and opens the press-and-hold menu on its page,
 * as the chip on the line does (editor/FieldItems.tsx): the item's line is the one changed, and the card follows it.
 */

/** Whether a card shows this field. */
function onCard(span: FieldSpan): boolean {
  return span.kind === 'priority' || span.kind === 'person' || (span.kind === 'date' && span.key === 'due');
}

/** The page a card's chip opens. */
function pageOf(span: FieldSpan): FieldPage {
  if (span.kind === 'priority') return { kind: 'priority' };
  if (span.kind === 'person') return { kind: 'person', name: span.value };
  return { kind: 'date', key: 'due' };
}

/** The card's chips, in the order its line has them, or null for an item with none to show. */
export function cardFields(view: EditorView, item: Item): HTMLElement | null {
  const today = isoDay(new Date());
  const done = item.done === true;
  const chips: HTMLElement[] = [];
  for (const span of fieldsIn(item.text)) {
    if (!onCard(span)) continue;
    const look = chipLook(span, { today, done });
    if (!look) continue;
    // A button where a press can change the line; on a page that cannot be edited, only what it says.
    const editable = !view.state.readOnly;
    const chip = chipElement(look, editable ? 'button' : 'span');
    if (editable) {
      (chip as HTMLButtonElement).type = 'button';
      chip.setAttribute('aria-haspopup', 'menu');
      const page = pageOf(span);
      press(chip, () => {
        const box = chip.getBoundingClientRect();
        tapField(view, { page, line: item.line, x: (box.left + box.right) / 2, y: box.top });
      });
    }
    chips.push(chip);
  }
  if (!chips.length) return null;
  const row = document.createElement('span');
  row.className = 'cm-boardFields';
  row.append(...chips);
  return row;
}
