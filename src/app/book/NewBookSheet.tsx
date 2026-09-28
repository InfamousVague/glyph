import { useEffect, useMemo, useRef, useState } from 'react';
import { Check, ChevronDown, ChevronUp, GripVertical, X } from '@glacier/icons';
import { useRowDrag } from './rowDrag.ts';
import { toggledTitle } from './book.ts';
import { DEFAULT_TEMPLATE } from './journal.ts';
import { CanvasMark } from './CanvasMark.tsx';
import { TemplatePicker } from './TemplatePicker.tsx';
import { preferences } from '../core/preferences.ts';
import { Sheet } from '../editor/Sheet.tsx';
import { sameTitle } from '../editor/wikiLinks.ts';
import { SheetField, SheetGroup, SheetNote, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import choiceStyles from '../editor/NoteSettings.module.css';
import styles from './NewBookSheet.module.css';

/**
 * Making a book (Matt: "expand the UI/UX for creating books, allow choosing existing notes as pages"): a sheet in
 * the New sheet's own look that asks for the name, then which notes are its pages and in what order. The library's
 * notes are listed under a search; a tap puts one in the book and a second tap takes it out, and the pages so far
 * stand above the list in the order they were chosen, each movable a place or removable. Making the book writes
 * one note with those pages as its index (book/book.ts `bookNoteBody`) and opens it. Nothing is written until then:
 * closing the sheet makes nothing.
 *
 * Or a journal (docs/DESIGN.md §142): a choice under the name, Notebook or Journal, and with Journal chosen the pages
 * give way to what each entry starts with and whether it keeps where it was written (book/TemplatePicker.tsx). Its
 * place switch starts as this device's Tag new notes, whatever the device can do, so a journal made on the Mac keeps
 * the places of the entries made on the phone. There is no Journal row on the + sheet: a journal is a kind of notebook.
 */

export interface NewBookSheetProps {
  open: boolean;
  onClose: () => void;
  /** Every note that could be a page: the library's titles, less the books (a book of books is not a page). */
  titles: readonly string[];
  onCreate: (title: string, pages: readonly string[]) => void;
  /** Makes a journal with its template and its place switch; absent, no Journal choice. */
  onCreateJournal?: (title: string, template: string, place: boolean) => void;
  /** Which is chosen as the sheet opens: the palette's New journal opens it on Journal. */
  kind?: 'notebook' | 'journal';
  /** Whether a title is a canvas, to give it the canvas's mark as the book's index does; absent, none is marked. */
  isCanvas?: (title: string) => boolean;
}

export function NewBookSheet({ open, onClose, titles, onCreate, onCreateJournal, kind: opening = 'notebook', isCanvas }: NewBookSheetProps) {
  const [name, setName] = useState('');
  const [find, setFind] = useState('');
  const [pages, setPages] = useState<string[]>([]);
  const [kind, setKind] = useState(opening);
  const [template, setTemplate] = useState(DEFAULT_TEMPLATE);
  const [place, setPlace] = useState(() => preferences().tagNewNotes);
  // Each opening starts on the kind it was opened for, and a journal's switch on this device's Tag new notes. Only an
  // opening: App hands a new `onCreateJournal` on every render, and a sync, the app coming back or the phone's own
  // location prompt answered each draws App again while the sheet is up, which put the choices back under the person.
  const journals = onCreateJournal !== undefined;
  useEffect(() => {
    if (!open) return;
    setKind(journals ? opening : 'notebook');
    setPlace(preferences().tagNewNotes);
  }, [open, opening, journals]);
  const journal = kind === 'journal';
  const pageEls = useRef<(HTMLElement | null)[]>([]);
  const rows = useRowDrag(
    () => pageEls.current,
    (from, to) =>
      setPages((was) => {
        const next = [...was];
        const [moved] = next.splice(from, 1);
        if (moved !== undefined) next.splice(to, 0, moved);
        return next;
      }),
  );
  const found = useMemo(() => {
    const needle = find.trim().toLowerCase();
    return titles.filter((t) => t.trim() && (!needle || t.toLowerCase().includes(needle))).slice(0, 60);
  }, [titles, find]);
  if (!open) return null;

  const chosen = (title: string) => pages.some((p) => sameTitle(p, title));
  const toggle = (title: string) => setPages((was) => toggledTitle(was, title));
  const move = (title: string, by: -1 | 1) =>
    setPages((was) => {
      const at = was.findIndex((p) => sameTitle(p, title));
      const to = at + by;
      if (at < 0 || to < 0 || to >= was.length) return was;
      const next = [...was];
      [next[at], next[to]] = [next[to]!, next[at]!];
      return next;
    });
  const make = () => {
    const title = name.trim();
    if (!title) return;
    onClose();
    if (journal && onCreateJournal) onCreateJournal(title, template, place);
    else onCreate(title, pages);
    setName('');
    setFind('');
    setPages([]);
    setTemplate(DEFAULT_TEMPLATE);
  };
  const heading = journal ? 'New journal' : 'New notebook';

  return (
    <Sheet label={heading} onClose={onClose} className={styles.sheet}>
      <SheetTitle>{heading}</SheetTitle>
      <form
        className={styles.form}
        onSubmit={(event) => {
          event.preventDefault();
          make();
        }}
      >
        <SheetField label="Name" value={name} placeholder={journal ? 'Diary' : 'Field guide'} autoFocus onChange={(event) => setName(event.target.value)} />
        {onCreateJournal ? (
          <div className={styles.kind}>
            <div className={choiceStyles.viewChoice} role="radiogroup" aria-label="What it is">
              {(
                [
                  ['notebook', 'Notebook'],
                  ['journal', 'Journal'],
                ] as const
              ).map(([value, label]) => (
                <button key={value} type="button" role="radio" aria-checked={kind === value} data-on={kind === value || undefined} onClick={() => setKind(value)}>
                  {label}
                </button>
              ))}
            </div>
          </div>
        ) : null}
        {journal ? (
          <>
            <TemplatePicker template={template} onTemplate={setTemplate} place={place} onPlace={setPlace} name={name} />
            <SheetGroup>
              <SheetRow label="Make the journal" hint="Empty, ready for its first entry." onPress={make} disabled={!name.trim()} />
            </SheetGroup>
          </>
        ) : (
          <>
            <SheetNote>Its pages are notes, in the order you choose. Pick any now, or add them later from the notebook's index.</SheetNote>

            {pages.length ? (
              <ol className={styles.pages} aria-label="Pages in this notebook">
                {pages.map((title, i) => (
                  <li
                    key={title}
                    ref={(el) => {
                      pageEls.current[i] = el;
                    }}
                    className={styles.page}
                    data-lifted={rows.lifted?.index === i || undefined}
                    style={rows.rowStyle(i)}
                  >
                    <span className={styles.grip} aria-hidden="true" {...rows.grip(i)}>
                      <GripVertical size={16} />
                    </span>
                    <span className={styles.number} aria-hidden="true">
                      {i + 1}
                    </span>
                    <span className={styles.pageTitle}>
                      {title}
                      {isCanvas?.(title) ? <CanvasMark /> : null}
                    </span>
                    <span className={styles.tools}>
                      <button type="button" className={styles.tool} aria-label={`Move ${title} up`} disabled={i === 0} onClick={() => move(title, -1)}>
                        <ChevronUp size={16} aria-hidden="true" />
                      </button>
                      <button type="button" className={styles.tool} aria-label={`Move ${title} down`} disabled={i === pages.length - 1} onClick={() => move(title, 1)}>
                        <ChevronDown size={16} aria-hidden="true" />
                      </button>
                      <button type="button" className={styles.tool} aria-label={`Leave ${title} out`} onClick={() => toggle(title)}>
                        <X size={16} aria-hidden="true" />
                      </button>
                    </span>
                  </li>
                ))}
              </ol>
            ) : null}

            <SheetField label="Find a note" value={find} placeholder="Type to find" onChange={(event) => setFind(event.target.value)} />
            <ul className={styles.found} aria-label="Notes">
              {found.length === 0 ? <li className={styles.none}>{titles.length ? 'No note by that name.' : 'No notes yet: the notebook starts empty, and pages can be added from its index.'}</li> : null}
              {found.map((title) => {
                const on = chosen(title);
                return (
                  <li key={title}>
                    <button type="button" className={styles.pick} aria-pressed={on} onClick={() => toggle(title)}>
                      <span className={styles.pickMark} aria-hidden="true">
                        {on ? <Check size={14} /> : null}
                      </span>
                      <span className={styles.pickTitle}>
                        {title}
                        {isCanvas?.(title) ? <CanvasMark /> : null}
                      </span>
                    </button>
                  </li>
                );
              })}
            </ul>

            <SheetGroup>
              <SheetRow label="Make the notebook" hint={pages.length ? `${pages.length} page${pages.length === 1 ? '' : 's'}, in this order.` : 'Empty, with its index ready.'} onPress={make} disabled={!name.trim()} />
            </SheetGroup>
          </>
        )}
      </form>
    </Sheet>
  );
}
