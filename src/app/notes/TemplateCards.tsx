import { useEffect, useId, useMemo, useState } from 'react';
import { MapPicture } from '../editor/MapCard.tsx';
import { allowLocationWhere, locateHere, refusalStanding } from '../core/location.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { isDarkNow, usePreferences } from '../core/preferences.ts';
import { NotePeek } from './NotePeek.tsx';
import { BUILT_INS, DAY_TAKEN_SENTENCE, fillNoteTemplate, type NoteTemplate } from './noteTemplates.ts';
import styles from './TemplateCards.module.css';

/**
 * The templates on a new note's blank page (docs/DESIGN.md §144), under its names (editor/nameChips.ts). Matt, when he
 * chose where: "cards on the blank page". A card for each of the six (notes/noteTemplates.ts), one to a row on a phone
 * and as many as fit 15rem from 600px, each the top of the note it makes: its words drawn by the note's own editor,
 * formatted, in the note's ink and heading proportions (notes/NotePeek.tsx `whole`), with the map it would get above
 * them, then its name and its sentence. They go at the first letter or a tap elsewhere on the page (the screen's), and
 * a card's tap turns the blank note into that template, keeping the focus in its first line.
 *
 * **A card is a button**, as a home card is, named by the template and described by its sentence. What is drawn in it,
 * the words and the map, is one `inert` span that says nothing, and every map on a card is a picture (editor/MapCard.tsx
 * `MapPicture`): no button in a button, no tiles, no fix, nothing asked. **The press** keeps the editor's focus and its
 * keyboard: a pointer or mouse press has its default taken, and the click does the work, as a name's chip does.
 *
 * **Maps.** A map at the top always draws its header above its words: that is what it is. Every other card draws the
 * ordinary card's box above its words exactly when this note holds one (`smallMap`), so the difference is large
 * against small, and no card promises a map the note will not get. A map at the top is not drawn where the device can
 * never say where it is (the Mac, an older Android binary, a browser with no geolocation), and is dimmed with its
 * reason under Local only or a refusal that still stands (the + beside the line's rule for a row a setting turns off),
 * where a press only buzzes. **A day** whose name today is taken says so, and draws the `(2)` it will write.
 *
 * All six are drawn once the block is there, one editor at a time (NotePeek's `eager`), not as they come near the
 * screen, and kept as HTML for the next blank page. Their words follow the minute (`at`), so A meeting and A map at the
 * top are drawn again when it turns.
 */

export interface TemplateCardsProps {
  /** The minute the notes would be made in. */
  at: Date;
  /** Every note's title key, archived and in the Trash too. */
  taken: ReadonlySet<string>;
  /** This note holds a map's box: every card draws the small one it would get. */
  smallMap: boolean;
  onChoose: (template: NoteTemplate) => void;
}

/** Why A map at the top cannot be pressed here, or null where it can. */
type MapWhy = 'local-only' | 'refused' | null;

/** A press that keeps the editor's focus, the caret and the keyboard: its default taken, and the click does the work. */
const keepFocus = (event: React.PointerEvent | React.MouseEvent) => event.preventDefault();

export function TemplateCards({ at, taken, smallMap, onChoose }: TemplateCardsProps) {
  const prefs = usePreferences();
  const dark = isDarkNow(prefs.theme);
  const canHere = useMemo(() => locateHere().ok, []);
  // A refusal the device keeps is read as it stands, a few milliseconds after the cards are drawn.
  const [refused, setRefused] = useState(false);
  useEffect(() => {
    let live = true;
    void refusalStanding().then((standing) => {
      if (live) setRefused(standing);
    });
    return () => {
      live = false;
    };
  }, []);
  const mapWhy: MapWhy = prefs.localOnly ? 'local-only' : refused ? 'refused' : null;
  const cards = BUILT_INS.filter((template) => template.id !== 'map' || canHere);
  return (
    <div className={styles.cards} role="group" aria-label="Start from a template">
      {cards.map((template) => (
        <Card key={template.id} template={template} at={at} taken={taken} smallMap={smallMap} dark={dark} dimmed={template.id === 'map' ? mapWhy : null} onChoose={onChoose} />
      ))}
    </div>
  );
}

function Card({
  template,
  at,
  taken,
  smallMap,
  dark,
  dimmed,
  onChoose,
}: {
  template: NoteTemplate;
  at: Date;
  taken: ReadonlySet<string>;
  smallMap: boolean;
  dark: boolean;
  dimmed: MapWhy;
  onChoose: (template: NoteTemplate) => void;
}) {
  const described = useId();
  const filled = useMemo(() => fillNoteTemplate(template, at, taken), [template, at, taken]);
  const sentence =
    dimmed === 'local-only'
      ? 'Local only is on, so a note made here keeps no place.'
      : dimmed === 'refused'
        ? `${allowLocationWhere()} for a note to keep its place.`
        : template.id === 'day' && filled.renamed
          ? DAY_TAKEN_SENTENCE
          : template.sentence;
  const header = template.look === 'map';
  const drawn = (
    <span className={styles.drawn} inert aria-hidden="true">
      {header || smallMap ? <MapPicture size={header ? 'header' : 'card'} pin dark={dark} className={styles.map} /> : null}
      <NotePeek body={filled.words} whole look={template.look} openHeading eager />
    </span>
  );
  const words = (
    <>
      <span className={styles.name}>{template.name}</span>
      <span id={described} className={styles.sentence}>
        {sentence}
      </span>
    </>
  );
  if (dimmed) {
    // Not a button: nothing it could make here would keep a place. A press says so with the phone's own buzz.
    return (
      <div className={styles.card} data-template={template.id} data-dimmed aria-describedby={described} onPointerDown={keepFocus} onMouseDown={keepFocus} onClick={() => fireNativeHaptic('warning')}>
        {drawn}
        {words}
      </div>
    );
  }
  return (
    <button
      type="button"
      className={styles.card}
      data-template={template.id}
      aria-label={template.name}
      aria-describedby={described}
      onPointerDown={keepFocus}
      onMouseDown={keepFocus}
      onClick={() => onChoose(template)}
    >
      {drawn}
      {words}
    </button>
  );
}
