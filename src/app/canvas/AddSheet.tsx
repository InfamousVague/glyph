import { useRef, useState } from 'react';
import { ChartNoAxesCombined, FileText, Image, Link2, SquarePen, Table } from '@glacier/icons';
import { useBack } from '../core/back.ts';
import { useSheetDrag } from '../editor/sheetDrag.ts';
import { SheetGroup, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import sheet from '../editor/NoteSettings.module.css';
import styles from './AddSheet.module.css';

/**
 * The canvas's + sheet (canvas/CanvasView.tsx, choice 8), in the note settings' own look (notes/NewSheet.tsx): what
 * to add - words, a note, a link, a picture, a chart, a table - and then, for a note or a link, its title or its
 * address. The sheet is only mounted while it is open, so its back gesture is held for as long as it is there.
 */

/** Where the sheet is: choosing what to add, a note's title, or a web address. */
export type AddStep = 'what' | 'note' | 'link';

interface AddSheetProps {
  step: AddStep;
  /** Every note's title, to find one by part of it. */
  titles: string[];
  onClose: () => void;
  onWords: () => void;
  onNote: (title: string) => void;
  onLink: (url: string) => void;
  onPicture: () => void;
  onChart: () => void;
  onTable: () => void;
  onStep: (step: 'note' | 'link') => void;
}

export function AddSheet({ step, titles, onClose, onWords, onNote, onLink, onPicture, onChart, onTable, onStep }: AddSheetProps) {
  const panel = useRef<HTMLElement>(null);
  const drag = useSheetDrag(panel, onClose);
  useBack(true, onClose);
  const [words, setWords] = useState('');
  const found = step === 'note' ? titles.filter((t) => t.toLowerCase().includes(words.trim().toLowerCase())).slice(0, 12) : [];
  return (
    <div className={sheet.scrim} onClick={onClose} onPointerDown={(event) => event.stopPropagation()}>
      <section ref={panel} className={sheet.sheet} role="dialog" aria-modal="true" aria-label="Add a card" onClick={(e) => e.stopPropagation()}>
        <span className={sheet.grip} aria-hidden="true" {...drag} />
        <SheetTitle>{step === 'what' ? 'Add a card' : step === 'note' ? 'Which note?' : 'Which address?'}</SheetTitle>
        {step === 'what' ? (
          <SheetGroup>
            <SheetRow icon={SquarePen} label="Words" hint="A card to write on." onPress={onWords} />
            <SheetRow icon={FileText} label="A note" hint="One of your notes, drawn small; tap it to open." onPress={() => onStep('note')} />
            <SheetRow icon={Link2} label="A link" hint="A web address, opened with a tap." onPress={() => onStep('link')} />
            <SheetRow icon={Image} label="A picture" hint="From your phone or computer, kept with your notes' pictures." onPress={onPicture} />
            <SheetRow icon={ChartNoAxesCombined} label="A chart" hint="A diagram, written as Mermaid and drawn on the card." onPress={onChart} />
            <SheetRow icon={Table} label="A table" hint="Rows and columns to fill in." onPress={onTable} />
          </SheetGroup>
        ) : (
          <div className={styles.addField}>
            <input
              className={styles.addInput}
              autoFocus
              value={words}
              placeholder={step === 'note' ? 'Type part of its title' : 'attack.fm/glyph'}
              aria-label={step === 'note' ? 'Part of the note’s title' : 'The web address'}
              inputMode={step === 'link' ? 'url' : 'text'}
              onChange={(event) => setWords(event.currentTarget.value)}
              onKeyDown={(event) => {
                if (event.key !== 'Enter') return;
                if (step === 'link') onLink(words);
                else if (found[0]) onNote(found[0]);
              }}
            />
            {step === 'link' ? (
              <button type="button" className={`app-word ${styles.addGo}`} onClick={() => onLink(words)} disabled={!words.trim()}>
                Add
              </button>
            ) : (
              <ul className={styles.addList} aria-label="Notes">
                {found.map((title) => (
                  <li key={title}>
                    <button type="button" className={styles.addRow} onClick={() => onNote(title)}>
                      {title}
                    </button>
                  </li>
                ))}
                {!found.length ? <li className={styles.addNone}>{words.trim() ? 'No note by that name.' : 'No notes yet.'}</li> : null}
              </ul>
            )}
          </div>
        )}
      </section>
    </div>
  );
}
