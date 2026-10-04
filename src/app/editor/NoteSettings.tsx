import { useEffect, useState, type FormEvent } from 'react';
import { ArrowUp, Bookmark, Feather, History, ListChecks, Mic, TextSearch } from '@glacier/icons';
import { ArchiveBox, ArrowLeft, Bin, Board, Locate, Pin, Workspace as WorkspaceIcon } from '../art/Icons.tsx';
import { CheatSheet } from '../guide/CheatSheet.tsx';
import { tagLabel, type GeoTag } from '../core/geotag.ts';
import type { LocateFailure } from '../core/location.ts';
import { useWorkspaces, workspaceOf } from '../core/workspaces.ts';
import { SheetField, SheetGroup, SheetHeading, SheetNote, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import { plugins } from '../plugins/registry.ts';
import { usePlugins } from '../plugins/hooks.ts';
import type { NoteAction, NoteEditing, NoteLink } from '../plugins/types.ts';
import { KIND_ICONS } from '../ai/icons.ts';
import { KINDS, type KindWords, type RunKind } from '../ai/kinds.ts';
import { isMacApp } from '../core/platform.ts';
import { WorkspacePicker } from './WorkspacePicker.tsx';
import { VersionHistory } from './VersionHistory.tsx';
import { setKeepsVersions, versionsByDefault } from '../core/versions/record.ts';
import type { Version } from '../core/versions/file.ts';
import { ShareRows } from '../share/ShareRows.tsx';
import { DEFAULT_TEMPLATE, PLACE_SENTENCE, templateSentence } from '../book/journal.ts';
import { TemplatePicker } from '../book/TemplatePicker.tsx';
import { keyProblem } from '../book/tickets.ts';
import { preferences } from '../core/preferences.ts';
import type { Look } from '../core/look.ts';
import { Sheet } from './Sheet.tsx';
import styles from './NoteSettings.module.css';

/**
 * One note's More sheet, from the three dots in its tools (editor/NoteTools.tsx): how it is read, the AI's runs on
 * it, its sharing, where it sits (pin, archive, the workspace it is in, core/workspaces.ts), what it is linked to and
 * what can be done with it, help, then Move to Trash, apart at the bottom.
 *
 * "Linked to" and the actions under it come from plugins (plugins/registry.ts): the GitHub plugin's repo row, the
 * Notion plugin's board and "Send list to Notion". A link's row opens the plugin's own page inside the sheet, as the
 * Workspace row and the cheat sheet do, under one way back; back returns to the sheet before it closes it. A
 * switched-off plugin's rows are simply not there. A link's row says, once the sheet is open, why it cannot be used
 * here when it cannot, and is greyed; an action's row is greyed while there is nothing for it to do in the note as
 * it was when the sheet opened.
 *
 * A notebook can be kept as a journal from here, and a journal changed or made a notebook again (docs/DESIGN.md
 * §142): a row under its name opens a page of the sheet with what each entry starts with (book/TemplatePicker.tsx).
 * Keeping it as a journal leaves every page where it is; the journal's view orders them by when each was written.
 *
 * A notebook takes a ticket key under its name, `GHO` (docs/DESIGN.md §157): its new tickets are numbered from it, as a
 * Jira project's are, and its index offers New ticket (book/BookView.tsx). Typed in capitals or not, written as capitals
 * the moment it is a key, and said what is wrong with while it is not one.
 *
 * A sheet from the bottom over a dimmed note, where a thumb already is (editor/Sheet.tsx). The links are shown before
 * they work so a note can be found where they will be; each says what it will do.
 */

interface NoteSettingsProps {
  open: boolean;
  noteId: string;
  title: string;
  pinned: boolean;
  /** The note on screen, for plugin actions that change it. */
  editing: NoteEditing;
  onClose: () => void;
  onPin: () => void;
  onArchive: () => void;
  onDelete: () => void;
  /**
   * The bookmark, moved here from the bar (Matt: "put bookmark in the more menu"): set at the caret's line, moved, or
   * taken off (editor/useBookmark.ts). Absent while the transcript is showing.
   */
  bookmark?: { marked: boolean; onPress: () => void };
  /** Opens find and replace in the note; absent where the note can't be searched (the transcript is showing). */
  onFind?: () => void;
  /** Lays the note's list out as a board (core/boards.ts); absent where there is nothing to make one of. */
  onMakeBoard?: () => void;
  /**
   * A field to name the note by, for a note with no heading to be named in: a canvas (docs/CANVAS.md) or a notebook
   * (docs/BOOKS.md), whose name is its `title:` front matter, and which of the two it is, for the field's placeholder.
   * Absent on a note of words, which is named by its first line.
   */
  name?: { value: string; onChange: (title: string) => void; kind: 'canvas' | 'notebook' | 'journal' };
  /**
   * A notebook that can be kept as a journal, or a journal (book/journal.ts): its template and its place switch as
   * the note says them, and the writes, each through the note as typing is. Absent on anything else, and on the Guide,
   * which is a manual and not a diary.
   */
  journal?: {
    on: boolean;
    template: string;
    place: boolean;
    /** The notebook kept as a journal, with this template and place switch. */
    keep: (template: string, place: boolean) => void;
    setTemplate: (text: string) => void;
    setPlace: (on: boolean) => void;
    /** The journal made a notebook again: its entries stay as pages. */
    unkeep: () => void;
  };
  /** A notebook's ticket key (book/tickets.ts), as its front matter says it, and its write; absent on anything else. */
  ticketKey?: { value: string; onChange: (typed: string) => void };
  /** Talk into this note, or, on a journal, speak a new entry; absent where the note's tape has its own Add. */
  speak?: { label: string; onPress: () => void };
  /**
   * How the note looks (core/look.ts; docs/DESIGN.md §144): Plain, a page to read, or its map as a header, the last only
   * for a note with a place to draw. Absent on a canvas or a notebook, which have looks of their own.
   */
  look?: { value: Look | null; canMap: boolean; onChange: (look: Look | null) => void };
  /** The AI's kind of run on this note now, if one is on, and how to ask for one (ai/start.ts). Absent on a note that can't be read to. */
  running?: RunKind | null;
  onAi?: (kind: RunKind, instruction?: string) => void;
  /**
   * What a press of Fill the blanks would take (editor/blanks.ts `fillPlanOf`), read as the sheet opens: how many, and
   * the public sources its live blanks would be looked up at. The row shows only with one.
   */
  blanks?: { count: number; online: string[] };
  /**
   * Where the note was written (core/geotag.ts, core/location.ts): its tag, whether a fix can be asked for here and
   * why not, whether the place's name would be asked for, why the last automatic tag did not come, and the two
   * presses. Absent where the note has no such row (a canvas's JSON aside, every note has one).
   */
  location?: {
    tag: GeoTag | null;
    can: { ok: true } | { ok: false; why: LocateFailure };
    asksName: boolean;
    refused: LocateFailure | null;
    /** The Android app, which asks again after a first refusal; a browser that was refused does not. */
    onPhone?: boolean;
    onAdd: () => void;
    onRemove: () => void;
  };
  /**
   * The note's version history (core/versions/record.ts): whether it keeps one, its words now, and how a version is put
   * back - through the editor, as one change. Absent where a note has no history to keep (a transcript showing).
   */
  history?: { keeps: boolean; current: () => string; onRestore: (text: string, version: Version) => void };
}

/** Why a fix cannot be asked for here, as the row says it under "Add my location". */
const CANNOT: Record<LocateFailure, string> = {
  'local-only': 'Local only is on. A location fix would ask the phone’s location service.',
  mac: 'This Mac can’t say where it is yet. Tag it on the phone and it syncs here.',
  ios: 'Ghost.md can’t find where you are on this device yet.',
  unavailable: 'Update Ghost.md to tag notes with where they were written.',
  none: 'This browser can’t say where you are.',
  refused: 'Ghost.md wasn’t allowed to know where you are.',
  blocked: 'Location is off for Ghost.md.',
  timeout: 'Couldn’t find where you are.',
};

/**
 * The location row's hint on an untagged note: why it was not tagged on its own, or what a press will do. Android asks
 * again after a first refusal, so a tap there asks; a browser that was refused does not ask again, so on a page the
 * way back is its own settings, then a tap.
 */
function locationHint(location: NonNullable<NoteSettingsProps['location']>): string {
  if (!location.can.ok) return CANNOT[location.can.why];
  if (location.refused === 'blocked') return 'Location is off for Ghost.md, so this note wasn’t tagged. Allow it in the phone’s settings, or tap to try again.';
  if (location.refused && location.onPhone) return 'Ghost.md wasn’t allowed to know where you are, so this note wasn’t tagged. Tap to ask again.';
  if (location.refused) return 'Ghost.md wasn’t allowed to know where you are, so this note wasn’t tagged. Allow location for this site in the browser’s settings, then tap to try again.';
  return location.asksName ? 'Where you are now, kept in the note. Its name is asked of OpenStreetMap once.' : 'Where you are now, kept in the note.';
}

/**
 * The AI's runs in the sheet, in order (docs/DESIGN.md §145, 11): Format, Summarize and Enhance, then Fix spelling, Make
 * a list and Continue, which were reachable only by voice and would have gone with voice behind its switch. Their own
 * words and icons (ai/kinds.ts, ai/icons.ts). Ask is its own field under them, and Fill the blanks follows when the note
 * has a blank for the model.
 */
const SHEET_KINDS: readonly KindWords[] = (['format', 'summarize', 'enhance', 'fix', 'shape', 'continue'] as const).map((id) => KINDS.find((kind) => kind.id === id)!);

/**
 * Fill the blanks' hint, with the count, on this device. It says nothing leaves only when nothing will: a press that
 * looks live blanks up names who is asked, since only their questions go there.
 */
function fillHint(plan: { count: number; online: string[] }): string {
  const device = isMacApp ? 'this Mac' : 'the phone';
  const what = plan.count === 1 ? 'Answers the question written {?like this}.' : `Answers the ${plan.count} questions written {?like this}.`;
  if (!plan.online.length) return `${what} Nothing leaves ${device}.`;
  const who = plan.online.length === 1 ? plan.online[0]! : `${plan.online.slice(0, -1).join(', ')} and ${plan.online.at(-1)!}`;
  return `${what} Some are looked up online: only their questions go, to ${who}.`;
}

/**
 * The Ask field (Matt: "Those, plus an Ask field"): any instruction for the note, typed, run as the spoken Ask always
 * was (ai/start.ts), its changes marked with Keep and the log's Undo. A field in the AI group rather than the AI bar
 * that was taken off the note (§122): it is there only when the sheet is.
 */
function AskField({ onAsk }: { onAsk: (instruction: string) => void }) {
  const [words, setWords] = useState('');
  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (words.trim()) onAsk(words.trim());
  };
  const Icon = KIND_ICONS.ask;
  return (
    <form className={styles.ask} onSubmit={submit} aria-label="Ask the AI">
      <span className={styles.icon} aria-hidden="true">
        <Icon size={20} strokeWidth={2.1} />
      </span>
      <input className={styles.askInput} value={words} onChange={(e) => setWords(e.target.value)} placeholder="Ask it to do something with this note" aria-label="What to do with this note" enterKeyHint="send" autoComplete="off" />
      <button type="submit" className={styles.askSend} disabled={!words.trim()} aria-label="Ask">
        <ArrowUp size={18} strokeWidth={2.2} aria-hidden="true" />
      </button>
    </form>
  );
}

/** The two drawn icons from the kit, at the weight the sheet's own are drawn: the rings size every icon to 18 px. */
const FindIcon = () => <TextSearch size={18} strokeWidth={2.2} />;
const BookmarkIcon = () => <Bookmark size={18} strokeWidth={2.2} />;
const CheatSheetIcon = () => <ListChecks size={18} strokeWidth={2.2} />;
/** A journal's mark, the pen an entry is written with, as the + sheet's entry row wears it. */
const JournalIcon = () => <Feather size={18} strokeWidth={2.2} />;

/**
 * A notebook's ticket key, typed: written whenever what is typed is a key (core/properties.ts `PROJECT_KEY`) or nothing,
 * which takes it off, and what is wrong with it said under it while it is neither.
 */
function TicketKeyField({ ticketKey }: { ticketKey: NonNullable<NoteSettingsProps['ticketKey']> }) {
  const [typed, setTyped] = useState(ticketKey.value);
  const problem = keyProblem(typed);
  const key = typed.trim().toUpperCase();
  return (
    <>
      <SheetGroup>
        <SheetField
          label="Ticket key"
          value={typed}
          placeholder="GHO"
          autoComplete="off"
          autoCapitalize="characters"
          spellCheck={false}
          onChange={(event) => {
            const next = event.target.value.toUpperCase();
            setTyped(next);
            if (keyProblem(next) === null) ticketKey.onChange(next);
          }}
        />
      </SheetGroup>
      <SheetNote>{problem ?? (key ? `Its tickets are numbered ${key}-1, ${key}-2 and on. [[${key}-1]] links to the first.` : 'Give it a key, and New ticket numbers its tickets, like a Jira project.')}</SheetNote>
    </>
  );
}

/** A journal's page of the sheet: what its entries start with, then keeping it as one, or making it a notebook again. */
function JournalPage({ journal, name }: { journal: NonNullable<NoteSettingsProps['journal']>; name: string }) {
  // A notebook's choice is a draft until it is kept; a journal's is written as it is made.
  const [template, setTemplate] = useState(journal.on ? journal.template : DEFAULT_TEMPLATE);
  const [place, setPlace] = useState(journal.on ? journal.place : preferences().tagNewNotes);
  const chooseTemplate = (text: string) => {
    setTemplate(text);
    if (journal.on) journal.setTemplate(text);
  };
  const choosePlace = (on: boolean) => {
    setPlace(on);
    if (journal.on) journal.setPlace(on);
  };
  return (
    <>
      <TemplatePicker
        template={template}
        onTemplate={chooseTemplate}
        place={place}
        onPlace={choosePlace}
        name={name}
        note={journal.on ? 'Entries you have written stay as they are.' : undefined}
      />
      <SheetGroup>
        {journal.on ? (
          <SheetRow label="Make it a notebook again" hint="Its entries stay as pages. New pages start plain." onPress={journal.unkeep} />
        ) : (
          <SheetRow label="Make it a journal" hint="Its pages stay where they are." onPress={() => journal.keep(template, place)} />
        )}
      </SheetGroup>
    </>
  );
}

export function NoteSettings({
  open,
  noteId,
  title,
  pinned,
  editing,
  onClose,
  onPin,
  onArchive,
  onDelete,
  onFind,
  bookmark,
  onMakeBoard,
  name,
  journal,
  ticketKey,
  speak,
  running,
  onAi,
  blanks = { count: 0, online: [] },
  location,
  look,
  history,
}: NoteSettingsProps) {
  // Re-rendered when a plugin is switched, so its rows come and go.
  usePlugins();
  const [page, setPage] = useState<NoteLink | 'workspace' | 'cheatsheet' | 'journal' | 'history' | null>(null);
  // A plugin's action with several places to go (a Slack channel among a few), open as a page of them.
  const [choosing, setChoosing] = useState<NoteAction | null>(null);
  // Re-rendered as the note is filed, so the row says where it is.
  const spaces = useWorkspaces();
  const filed = workspaceOf(noteId);
  const [unavailable, setUnavailable] = useState<Record<string, string | null>>({});
  // The body when the sheet opened: the action rows' counts are read from it.
  const [body, setBody] = useState('');
  useEffect(() => {
    if (!open) {
      setPage(null);
      setChoosing(null);
      return;
    }
    setBody(editing.body());
    let live = true;
    for (const link of plugins.noteLinks()) {
      void link.unavailable?.().then((why) => live && setUnavailable((was) => ({ ...was, [link.id]: why })));
    }
    return () => {
      live = false;
    };
    // `editing` is read when the sheet opens, not followed.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);
  if (!open) return null;

  const back = () => (choosing ? setChoosing(null) : page ? setPage(null) : onClose());

  /** An action run on the note, the sheet closed first; with several places to go, their page opens instead. */
  const runAction = (action: NoteAction) => {
    const choices = action.choices?.(noteId) ?? [];
    if (choices.length > 1) {
      setChoosing(action);
      return;
    }
    onClose();
    void (choices.length === 1 ? action.run(editing, choices[0]!.id) : action.run(editing));
  };

  if (choosing) {
    return (
      <Sheet label={choosing.label} onClose={onClose} onBack={back}>
        <button type="button" className={styles.back} onClick={() => setChoosing(null)}>
          <ArrowLeft /> {title || 'This note'}
        </button>
        <SheetTitle>{choosing.label}</SheetTitle>
        <SheetNote>{choosing.hint(noteId, body)}</SheetNote>
        <SheetGroup>
          {(choosing.choices?.(noteId) ?? []).map((choice) => (
            <SheetRow
              key={choice.id}
              icon={choosing.icon}
              label={choice.label}
              hint={choice.hint}
              onPress={() => {
                onClose();
                void choosing.run(editing, choice.id);
              }}
            />
          ))}
        </SheetGroup>
      </Sheet>
    );
  }

  if (page === 'journal' && journal) {
    return (
      <Sheet label="Journal" onClose={onClose} onBack={back}>
        <button type="button" className={styles.back} onClick={() => setPage(null)}>
          <ArrowLeft /> {title || 'This note'}
        </button>
        <JournalPage
          journal={{
            ...journal,
            keep: (template, place) => {
              journal.keep(template, place);
              setPage(null);
            },
            unkeep: () => {
              journal.unkeep();
              setPage(null);
            },
          }}
          name={title}
        />
      </Sheet>
    );
  }

  if (page === 'history' && history) {
    return (
      <Sheet label="Version history" onClose={onClose} onBack={back}>
        <VersionHistory
          noteId={noteId}
          title={title}
          current={history.current}
          onRestore={(text, version) => {
            history.onRestore(text, version);
            onClose();
          }}
          onBack={() => setPage(null)}
        />
      </Sheet>
    );
  }

  if (page && page !== 'journal' && page !== 'history') {
    // The cheat sheet is read here rather than picked from, so it is shown whole instead of through a plugin's picker.
    const Picker = page === 'cheatsheet' ? null : page === 'workspace' ? WorkspacePicker : page.Picker;
    const label = page === 'cheatsheet' ? 'Formatting cheat sheet' : page === 'workspace' ? 'Workspace' : page.label;
    return (
      <Sheet label={label} onClose={onClose} onBack={back}>
        <button type="button" className={styles.back} onClick={() => setPage(null)}>
          <ArrowLeft /> {title || 'This note'}
        </button>
        {Picker ? <Picker noteId={noteId} onDone={() => setPage(null)} /> : <CheatSheet />}
      </Sheet>
    );
  }

  const links = plugins.noteLinks();
  const actions = plugins.noteActions().filter((action) => action.visible(noteId, body));
  return (
    <Sheet label={`Settings for ${title || 'this note'}`} onClose={onClose} onBack={back}>
      <SheetTitle>{title || 'Untitled'}</SheetTitle>
      {/* The mic, from the top bar: the first thing here, as it was the first thing a thumb reached there. */}
      {speak ? (
        <SheetGroup>
          <SheetRow
            icon={Mic}
            label={speak.label}
            onPress={() => {
              onClose();
              speak.onPress();
            }}
          />
        </SheetGroup>
      ) : null}
      {name ? (
        <SheetGroup>
          <SheetField label="Name" value={name.value} onChange={(e) => name.onChange(e.target.value)} placeholder={`What this ${name.kind} is called`} autoComplete="off" />
          {journal ? (
            journal.on ? (
              <SheetRow icon={JournalIcon} label="Journal" hint={`${templateSentence(journal.template)}${journal.place ? ` ${PLACE_SENTENCE}` : ''}`} onPress={() => setPage('journal')} />
            ) : (
              <SheetRow icon={JournalIcon} label="Keep it as a journal" hint="New pages start dated, from a template." onPress={() => setPage('journal')} />
            )
          ) : null}
        </SheetGroup>
      ) : null}
      {name && ticketKey ? <TicketKeyField ticketKey={ticketKey} /> : null}

      {onFind || onMakeBoard || look || bookmark ? (
        <>
          <SheetHeading>Reading it</SheetHeading>
          <SheetGroup>
            {/* Rows of choices, not rows to press: marked for their look, never `aria-disabled`, which said their radios were off. */}
            {look ? (
              <div className={styles.row} data-choice>
                <span className={styles.label}>Look</span>
                <div className={styles.viewChoice} role="radiogroup" aria-label="How this note looks">
                  {(
                    [
                      [null, 'Plain'],
                      ['reading', 'Reading'],
                      ...(look.canMap ? ([['map', 'Map']] as const) : []),
                    ] as const
                  ).map(([value, label]) => (
                    <button key={label} type="button" role="radio" aria-checked={look.value === value} data-on={look.value === value || undefined} onClick={() => look.onChange(value)}>
                      {label}
                    </button>
                  ))}
                </div>
              </div>
            ) : null}
            {bookmark ? (
              <SheetRow
                icon={BookmarkIcon}
                label={bookmark.marked ? 'Move or remove the bookmark' : 'Bookmark this line'}
                hint={bookmark.marked ? 'Moves it to the line the caret is on, or takes it off when it is already there.' : 'Marks the line the caret is on, to come back to.'}
                onPress={bookmark.onPress}
              />
            ) : null}
            {onFind ? <SheetRow icon={FindIcon} label="Find and replace" onPress={onFind} /> : null}
            {/* A list laid out as columns, in the note's own words (docs/BOARDS.md). */}
            {onMakeBoard ? <SheetRow icon={Board} label="Make a board" hint="Every item in this note becomes a card." onPress={onMakeBoard} /> : null}
          </SheetGroup>
        </>
      ) : null}

      {onAi ? (
        <>
          <SheetHeading>AI</SheetHeading>
          <SheetGroup>
            {[...SHEET_KINDS, ...(blanks.count > 0 ? [{ ...KINDS.find((kind) => kind.id === 'fill')!, hint: fillHint(blanks) }] : [])].map((words) => {
              const Icon = KIND_ICONS[words.id];
              // Pressed, with a dot at its end, while that run is on - rather than the kit's tick, which marks a choice.
              return (
                <button
                  key={words.id}
                  type="button"
                  className={styles.row}
                  aria-pressed={running === words.id}
                  onClick={() => {
                    onClose();
                    onAi(words.id);
                  }}
                >
                  <span className={styles.icon} aria-hidden="true">
                    <Icon size={20} strokeWidth={2.1} />
                  </span>
                  <span className={styles.label}>
                    {words.label}
                    <span className={styles.hint}>{words.hint}</span>
                  </span>
                  {running === words.id ? <span className={styles.chosen} aria-hidden="true" /> : null}
                </button>
              );
            })}
            <AskField
              onAsk={(instruction) => {
                onClose();
                onAi('ask', instruction);
              }}
            />
          </SheetGroup>
        </>
      ) : null}

      {/* Read by anyone with its link, and nobody else (share/share.ts, docs/SHARING.md). */}
      <ShareRows noteId={noteId} kind={name?.kind === 'journal' ? 'journal' : name?.kind === 'notebook' ? 'notebook' : 'note'} />

      {/* The group under AI, named like the rest of them (Matt: "the section under AI is not labeled"). */}
      <SheetHeading>Where it sits</SheetHeading>
      <SheetGroup>
        <SheetRow icon={Pin} label={pinned ? 'Unpin' : 'Pin to the top'} onPress={onPin} />
        <SheetRow icon={ArchiveBox} label="Archive" onPress={onArchive} />
        <SheetRow icon={WorkspaceIcon} label="Workspace" hint={filed ? filed.name : spaces.list.length ? 'Not in one' : 'None yet. Make one to sort your notes.'} onPress={() => setPage('workspace')} />
        {/* Every version kept, to go back to (Matt: "allow versioning on personal notes by enabling it under the more menu"). */}
        {history ? (
          history.keeps ? (
            <SheetRow icon={History} label="Version history" hint={versionsByDefault(noteId) ? 'Kept for an organization’s notes. Go back to any version.' : 'Every version kept. Go back to any of them.'} onPress={() => setPage('history')} />
          ) : (
            <SheetRow
              icon={History}
              label="Keep version history"
              hint="Saves a version as you write, to go back to like git. Kept beside the note as a .versions file."
              onPress={() => {
                setKeepsVersions(noteId, true);
                setPage('history');
              }}
            />
          )
        ) : null}
        {/* Where it was written, last of where it sits (core/location.ts): the tag added or taken off, and why it can't be here. */}
        {location ? (
          location.tag ? (
            <SheetRow icon={Locate} label="Remove location" hint={tagLabel(location.tag)} onPress={location.onRemove} />
          ) : (
            <SheetRow icon={Locate} label="Add my location" hint={locationHint(location)} onPress={location.can.ok ? location.onAdd : undefined} />
          )
        ) : null}
      </SheetGroup>

      {links.length || actions.length ? (
        <>
          <SheetHeading>Linked to</SheetHeading>
          <SheetGroup>
            {links.map((link) => {
              const why = unavailable[link.id] ?? null;
              return <SheetRow key={link.id} icon={link.icon} label={link.label} hint={why ?? link.hint(noteId)} onPress={() => setPage(link)} disabled={why !== null} />;
            })}
            {actions.map((action) => (
              <SheetRow
                key={action.id}
                icon={action.icon}
                label={action.label}
                hint={action.hint(noteId, body)}
                onPress={() => runAction(action)}
                disabled={!action.enabled(noteId, body)}
              />
            ))}
          </SheetGroup>
        </>
      ) : null}

      {/* Matt: "i want the glossary / lexicon / cheat sheet added for all formatting rules in the help section of the more menu". */}
      <SheetHeading>Help</SheetHeading>
      <SheetGroup>
        <SheetRow icon={CheatSheetIcon} label="Formatting cheat sheet" hint="Every mark you can type, and what it looks like, on one page." onPress={() => setPage('cheatsheet')} />
      </SheetGroup>

      {/* Into the trash, from where it is brought back or deleted for good (core/trash.ts). */}
      <SheetGroup>
        <SheetRow icon={Bin} label="Move to Trash" onPress={onDelete} danger />
      </SheetGroup>
    </Sheet>
  );
}
