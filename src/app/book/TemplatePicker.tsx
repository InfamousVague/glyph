import { useLayoutEffect, useRef, useState } from 'react';
import { Switch } from '@glacier/react';
import { Locate } from '../art/Icons.tsx';
import { askFromPress, autoTagRefusal, canLocate, type LocateFailure } from '../core/location.ts';
import { isDarkNow, usePreferences } from '../core/preferences.ts';
import { Editor } from '../editor/Editor.tsx';
import { SheetGroup, SheetHeading, SheetIcon, SheetRow } from '../plugins/kit.tsx';
import { entryPlaceHint } from './entryPlace.ts';
import { entryTitle, OWN, PRESETS, presetOf, type PresetId } from './journal.ts';
import { fillTemplate } from './template.ts';
import styles from './TemplatePicker.module.css';

/**
 * What a journal's entries start with, and whether they keep where they were written (docs/DESIGN.md §142): the one
 * page for both, in the New notebook sheet with Journal chosen and on a notebook's More sheet (book/NewBookSheet.tsx,
 * editor/NoteSettings.tsx).
 *
 * Five choices, the presets and your own (book/journal.ts). Your own opens a box to write it in, in the note's own
 * face, with the placeholders under it to tap in at the caret, and the one rule a format has (book/template.ts: words
 * go in square brackets). Under the choice, the page an entry would start as now, filled with this minute and drawn by
 * the note's own editor, read-only and formatted, as the cheat sheet draws a mark (guide/MarkExample.tsx). On the
 * Fold opened out the preview sits beside the choice.
 *
 * "With where you are" is the journal's choice, and travels in its file. What protects a device stays that device's:
 * Local only, a Mac that cannot say where it is, a refusal kept, and the system's prompt only ever from a press. So
 * turning it on asks here, where the prompt has never been answered, and the hint says why it cannot keep a place on
 * this device when it cannot.
 */

export interface TemplatePickerProps {
  template: string;
  onTemplate: (text: string) => void;
  place: boolean;
  onPlace: (on: boolean) => void;
  /** The journal's name, for `{{journal}}` in the preview. */
  name: string;
}

/** The placeholders a tap puts in at the caret. */
const CHIPS = ['{{date}}', '{{time}}', '{{weekday}}', '{{title}}', '{{journal}}'];

export function TemplatePicker({ template, onTemplate, place, onPlace, name }: TemplatePickerProps) {
  const prefs = usePreferences();
  /** Which choice is ticked: your own stays your own while its words happen to be a preset's. */
  const [choice, setChoice] = useState<PresetId>(() => presetOf(template));
  const box = useRef<HTMLTextAreaElement>(null);
  /** Where the caret goes once a chip's words are in. */
  const caret = useRef<number | null>(null);
  const [refusedHere, setRefused] = useState<LocateFailure | null>(null);
  const refused = refusedHere ?? autoTagRefusal();

  useLayoutEffect(() => {
    const at = caret.current;
    const field = box.current;
    if (at === null || !field) return;
    caret.current = null;
    field.focus();
    field.setSelectionRange(at, at);
  });

  const pick = (id: PresetId) => {
    setChoice(id);
    if (id !== OWN.id) onTemplate(PRESETS.find((preset) => preset.id === id)!.text);
  };
  const insert = (chip: string) => {
    const field = box.current;
    const from = field?.selectionStart ?? template.length;
    const to = field?.selectionEnd ?? template.length;
    caret.current = from + chip.length;
    onTemplate(`${template.slice(0, from)}${chip}${template.slice(to)}`);
  };
  const flipPlace = (on: boolean) => {
    onPlace(on);
    setRefused(null);
    // The prompt from this press, where it has never been answered: the first entry is not the first ask.
    if (on) void askFromPress().then((why) => setRefused(why === 'refused' || why === 'blocked' ? why : null));
  };

  const now = new Date();
  const filled = fillTemplate(template, { at: now, title: entryTitle(now.getTime()), journal: name.trim() || 'Journal' });
  const hint = entryPlaceHint({ can: canLocate(), refused, asksName: prefs.placeNames && !prefs.localOnly });

  return (
    <div className={styles.picker}>
      <div className={styles.choice}>
        <SheetHeading>Each entry starts with</SheetHeading>
        <SheetGroup>
          {PRESETS.map((preset) => (
            <SheetRow key={preset.id} label={preset.name} chosen={choice === preset.id} onPress={() => pick(preset.id)} />
          ))}
          <SheetRow label={OWN.name} chosen={choice === OWN.id} onPress={() => pick(OWN.id)} />
        </SheetGroup>
        {choice === OWN.id ? (
          <div className={styles.own}>
            <textarea
              ref={box}
              className={styles.box}
              aria-label="Your own template"
              value={template}
              rows={4}
              spellCheck={false}
              placeholder="# {{date}}"
              onChange={(event) => onTemplate(event.target.value)}
            />
            <div className={styles.chips} aria-label="Placeholders">
              {CHIPS.map((chip) => (
                <button key={chip} type="button" className={styles.chip} onClick={() => insert(chip)}>
                  {chip}
                </button>
              ))}
            </div>
            <p className={styles.rule}>Words inside a format go in square brackets, as in {'{{date:D MMMM [at] HH:mm}}'}.</p>
          </div>
        ) : null}
      </div>
      <div className={styles.preview} aria-label="How a new entry starts">
        {place ? <p className={styles.where}>Where you are, with the map, at the top.</p> : null}
        {filled.trim() ? (
          <div className={styles.page}>
            <Editor value={filled} onChange={keep} dark={isDarkNow(prefs.theme)} assist={false} readOnly display="formatted" grow />
          </div>
        ) : (
          <p className={styles.where}>An empty page.</p>
        )}
      </div>
      <div className={styles.place}>
        <SheetGroup>
          <div className={styles.switchRow}>
            <SheetIcon icon={Locate} />
            <span className={styles.label}>
              With where you are
              <span className={styles.hint}>{hint}</span>
            </span>
            <Switch aria-label="With where you are" checked={place} onCheckedChange={flipPlace} />
          </div>
        </SheetGroup>
      </div>
    </div>
  );
}

/** The preview is read-only: nothing typed there comes back. */
const keep = (_value: string) => undefined;
