import { syntaxTree } from '@codemirror/language';
import { RangeSetBuilder, type EditorState, type Extension } from '@codemirror/state';
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from '@codemirror/view';
import { blankMatches } from '../core/blanks.ts';
import { isoDay } from '../core/days.ts';
import { taskBox } from '../core/itemSyntax.ts';
import { fieldsIn, type FieldSpan } from '../core/taskFields.ts';
import { frontMatter } from './extended.ts';
import { chipElement, chipLook, fieldChipTheme, sameLook, type ChipLook } from './fieldChips.ts';
import { tapField, type FieldPage } from './fieldMenu.ts';
import { forEachVisibleLine, selectedLines } from './lines.ts';
import { inQuietText } from './syntax.ts';

/**
 * A to-do's fields drawn (docs/DESIGN.md §158). Matt asked what "notion and jira like features" plain Markdown could
 * give the app, and the first he took was a to-do's due date, priority and person, shown as chips. Off the caret's
 * line each one is a small chip, and on it the characters are there as written, to be edited, as a shortcode's emoji
 * and a place's name are (editor/extended.ts, editor/placeCards.ts).
 *
 *   - [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03
 *
 * reads "Fix the login loop (S) sam #bug ⇈ Sat 3 Oct", the date red once it has passed, amber on the day and quiet
 * once the box is ticked (editor/fieldChips.ts says how each looks). What a field is, is core/taskFields.ts's (§156):
 * Obsidian Tasks' own signs, so the line is a task with a due date in Obsidian too, a person as `@sam`, and Dataview's
 * `[key:: value]`; this only says where one is drawn. Nothing in code, an address, HTML, a comment or maths is a
 * field, which the parser says (editor/syntax.ts `inQuietText`), as it does for a tag; nor is anything in a blank's
 * question, which reads as one quiet phrase (editor/tags.ts), or in the note's front matter, which is its properties
 * (editor/extended.ts `frontMatter`).
 *
 * A tap on a due, start or scheduled day, a priority or a person opens the press-and-hold menu on that field's page
 * (editor/FieldItems.tsx): the chip is the field's handle, as a counter is its count's. The press is kept from the
 * editor as the suggestion pill's is (editor/suggestions.ts), so the caret stays where it was and the keyboard does not
 * rise. A tap on any other chip - a recurrence, a named field, a done day - is the editor's, and puts the caret on its
 * line, where it is the characters again. On a page that cannot be edited the chips are drawn and a tap does nothing.
 *
 * While an IME composes, the line's DOM is left alone (editor/glyphLines.ts), and the chips with it.
 */

/**
 * What a line with a drawn field has in it: an at sign, a named field's `::`, or one of the signs. A line with none has
 * no chip, and is passed over without reading it: every to-do has a bracket, so the bracket alone says nothing.
 */
const SIGNS = /@|::|📅|📆|🗓|🛫|⏳|⌛|✅|➕|❌|🔁|🔺|⏫|🔼|🔽|⏬/u;

/** The menu a chip opens, as the page of the band it turns to; null for a chip a tap edits. */
function pageOf(look: ChipLook): FieldPage | null {
  if (look.menu === 'priority') return { kind: 'priority' };
  if (look.menu === 'person') return { kind: 'person', name: look.key };
  if (look.menu === 'date' && (look.key === 'due' || look.key === 'start' || look.key === 'scheduled')) return { kind: 'date', key: look.key };
  return null;
}

class FieldWidget extends WidgetType {
  constructor(
    readonly look: ChipLook,
    /** Whether a tap opens its menu: a chip that has one, on a page that can be edited. */
    readonly tappable: boolean,
  ) {
    super();
  }

  eq(other: FieldWidget): boolean {
    return other.tappable === this.tappable && sameLook(other.look, this.look);
  }

  toDOM(view: EditorView): HTMLElement {
    const chip = chipElement(this.look);
    const page = this.tappable ? pageOf(this.look) : null;
    if (!page) return chip;
    chip.setAttribute('role', 'button');
    chip.setAttribute('aria-haspopup', 'menu');
    // Kept from the editor, as a suggestion pill is (editor/suggestions.ts): a pointer's or a mouse's default is taken
    // away, which keeps the caret; a touch only stops here, or the phone never sends the click.
    for (const kind of ['pointerdown', 'mousedown'] as const) {
      chip.addEventListener(kind, (event) => {
        event.preventDefault();
        event.stopPropagation();
      });
    }
    chip.addEventListener('touchstart', (event) => event.stopPropagation());
    chip.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      // Read where it is now: the line may have moved since the chip was drawn, and the element is kept while it reads
      // the same (`eq`).
      const pos = view.posAtDOM(chip);
      const box = chip.getBoundingClientRect();
      tapField(view, { page, line: view.state.doc.lineAt(pos).number, x: (box.left + box.right) / 2, y: box.top });
    });
    return chip;
  }

  /** A chip with a menu answers its own taps; any other is the editor's, which puts the caret on its line. */
  ignoreEvent(): boolean {
    return this.tappable && pageOf(this.look) !== null;
  }
}

/** Whether a line's item is finished: its box ticked, or a done day written on it. */
function finished(text: string, spans: readonly FieldSpan[]): boolean {
  return taskBox(text)?.done === true || spans.some((span) => span.kind === 'date' && span.key === 'done');
}

function decorate(view: EditorView, today: string): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const state: EditorState = view.state;
  const editable = state.facet(EditorView.editable) && !state.readOnly;
  // The lines the selection touches show their fields as written, while the note is being written (editor/links.ts).
  const active = editable && view.hasFocus ? selectedLines(state) : new Set<number>();
  // The note's front matter is its properties, not a to-do's words, and the parser reads it as words.
  const front = frontMatter(state.doc);
  forEachVisibleLine(view, (line) => {
    if (active.has(line.number) || !SIGNS.test(line.text)) return;
    if (front && line.number >= front.from && line.number <= front.to) return;
    const spans = fieldsIn(line.text, line.from);
    if (!spans.length) return;
    const done = finished(line.text, spans);
    const blanks = line.text.includes('{?') ? blankMatches(line.text, line.from) : [];
    for (const span of spans) {
      if (inQuietText(state, span.from) || blanks.some((b) => span.from > b.from && span.from < b.to)) continue;
      const look = chipLook(span, { today, done });
      if (look) builder.add(span.from, span.to, Decoration.replace({ widget: new FieldWidget(look, editable) }));
    }
  });
  return builder.finish();
}

/** The fields drawn as chips, and a tap on one opening its page of the press-and-hold menu. */
export function taskFields(): Extension {
  return [
    ViewPlugin.fromClass(
      class {
        decorations: DecorationSet;
        /** The day the chips count from: "Today" is tomorrow's "Yesterday", so a new day draws them again. */
        today = isoDay(new Date());

        constructor(view: EditorView) {
          this.decorations = decorate(view, this.today);
        }

        update(update: ViewUpdate) {
          if (update.view.composing) {
            if (update.docChanged) this.decorations = this.decorations.map(update.changes);
            return;
          }
          const today = isoDay(new Date());
          const newDay = today !== this.today;
          if (newDay || update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged || syntaxTree(update.startState) !== syntaxTree(update.state)) {
            this.today = today;
            this.decorations = decorate(update.view, today);
          }
        }
      },
      { decorations: (plugin) => plugin.decorations },
    ),
    fieldChipTheme,
  ];
}
