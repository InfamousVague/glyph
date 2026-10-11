import { useEffect, useState } from 'react';
import { ArrowLeft, Book, Feather, Link2, SquarePen, Volume2, Workflow } from '@glacier/icons';
import { Cassette } from '../art/Icons.tsx';
import { meetingSoundWords, useMeetingSoundSupport } from '../capture/systemSound.ts';
import { setPreferences, usePreferences } from '../core/preferences.ts';
import { failureText } from '../core/failure.ts';
import { SheetField, SheetGroup, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import { Sheet } from '../editor/Sheet.tsx';
import sheetStyles from '../editor/NoteSettings.module.css';
import { entryStarts, startLine } from '../book/entryStarts.ts';

/**
 * What the + makes (Matt: "make the plus button ask if they want to create a canvas, note or memo"; memos were then
 * taken out of the app - "we're going to focus on notes and canvases"): a small sheet offering a note, a canvas or a
 * book (docs/BOOKS.md), in the note's settings' own look, from every + there is - the home dock's, the tab strip's and
 * the sidebar's - so a + means the same thing wherever it is. A tap on the scrim, the back gesture or a drag down
 * closes it and makes nothing.
 *
 * And a meeting (docs/DESIGN.md §127 section 3), only where one can be recorded (capture/meeting.ts): the Mac, and an
 * Android phone with the service. Under it, where this device can put its own sound in a meeting (capture/systemSound.ts,
 * native generation 25), the switch for that, ticked when on: "Record the computer's sound too" on a Mac, "Include sound
 * from other apps" on Android, with the limit said under it (media and games, never calls). And a copy of something shared with you (share/share.ts, docs/SHARING.md): "From a
 * shared link" takes a link to a shared note or book and saves it into this library as your own copy.
 *
 * And, with a journal, a new entry (docs/DESIGN.md §142), right after Note, in the pen an entry is written with: in the
 * journal on screen, else the one written in last. One row only, and no Journal row: a journal is made from Notebook.
 * The row asks what the entry starts with before it makes one (Matt: "when I click new page from within the journal I
 * still don't see a list of templates to choose from"): the sheet turns to the journal's templates, its usual one
 * first, as New entry on the journal's own page does (book/JournalView.tsx, book/entryStarts.ts).
 */
export interface NewSheetProps {
  open: boolean;
  onClose: () => void;
  onNote: () => void;
  onCanvas: () => void;
  onBook: () => void;
  /**
   * A new entry in the journal on screen, else the one written in last: its name, what an entry starts with (`hint`, and
   * `usual`, the template itself), and the entry made from the template chosen: none for the usual one, which is read
   * from the journal afresh as the entry is made. Absent with no journal.
   */
  entry?: { journal: string; hint: string; usual: string; onPress: (template?: string) => void };
  /** Records a meeting; given only where one can be recorded here. */
  onMeeting?: () => void;
  /** Saves a copy of a shared note or book from its link; answers nothing, or throws what went wrong. */
  onFromLink?: (link: string) => Promise<void>;
}

export function NewSheet({ open, onClose, onNote, onCanvas, onBook, entry, onMeeting, onFromLink }: NewSheetProps) {
  /** The shared link being pasted, while its field is open; null when it is not. */
  const [link, setLink] = useState<string | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  /** The entry row pressed: the sheet shows what the entry can start with. */
  const [starting, setStarting] = useState(false);
  /** Whether a meeting here can have the device's own sound in it, and whether it will. */
  const sound = useMeetingSoundSupport();
  const prefs = usePreferences();
  /*
   * However it closed - the scrim, a drag down, the back gesture, a choice made - the next + opens on the choices,
   * not on the field and the words left in it. Only the scrim used to clear them.
   */
  useEffect(() => {
    if (open) return;
    setLink(null);
    setProblem(null);
    setStarting(false);
  }, [open]);
  if (!open) return null;

  const fork = async () => {
    if (!onFromLink || !link?.trim()) return;
    setBusy(true);
    setProblem(null);
    try {
      await onFromLink(link.trim());
      onClose();
    } catch (failure) {
      setProblem(failureText(failure));
    } finally {
      setBusy(false);
    }
  };

  const pick = (make: () => void) => () => {
    onClose();
    make();
  };
  if (entry && starting) {
    const now = new Date();
    // The way back at the top, as the More sheet's pages have it, and the back gesture steps back rather than closing.
    // Keyed apart from the choices, so each step opens at its own top rather than where the other was scrolled to.
    return (
      <Sheet key="start" label="New" onClose={onClose} onBack={() => setStarting(false)}>
        <button type="button" className={sheetStyles.back} onClick={() => setStarting(false)}>
          <ArrowLeft /> New
        </button>
        <SheetTitle>Start the entry with</SheetTitle>
        <SheetGroup>
          {entryStarts(entry.usual).map((start) => (
            <SheetRow
              key={start.id}
              icon={Feather}
              label={start.id === 'usual' ? `${start.name} · usual` : start.name}
              hint={clip(startLine(start.text, entry.journal, now))}
              onPress={pick(() => entry.onPress(start.id === 'usual' ? undefined : start.text))}
            />
          ))}
        </SheetGroup>
      </Sheet>
    );
  }
  return (
    <Sheet key="new" label="New" onClose={onClose}>
      <SheetTitle>New</SheetTitle>
      <SheetGroup>
        <SheetRow icon={SquarePen} label="Note" hint="A page of markdown, typed or said." onPress={pick(onNote)} />
        {entry ? <SheetRow icon={Feather} label={`Entry in ${entry.journal}`} hint={entry.hint} onPress={() => setStarting(true)} /> : null}
        <SheetRow icon={Workflow} label="Canvas" hint="Cards on a page with lines between them." onPress={pick(onCanvas)} />
        <SheetRow icon={Book} label="Notebook" hint="Notes in an order with an index, or a journal of dated entries." onPress={pick(onBook)} />
        {onMeeting ? <SheetRow icon={Cassette} label="Meeting" hint="Record a meeting. The screen can go off. It is written up afterwards." onPress={pick(onMeeting)} /> : null}
        {onMeeting && sound?.supported ? (
          <SheetRow
            icon={Volume2}
            label={meetingSoundWords().label}
            hint={meetingSoundWords().hint}
            chosen={prefs.meetingSound}
            // A switch, not a choice that makes something: the sheet stays open for Meeting.
            onPress={() => setPreferences({ meetingSound: !prefs.meetingSound })}
          />
        ) : null}
        {onFromLink && link === null ? (
          <SheetRow icon={Link2} label="From a shared link" hint="A copy of a note or notebook someone shared with you." onPress={() => setLink('')} />
        ) : null}
      </SheetGroup>
      {onFromLink && link !== null ? (
        <SheetGroup>
          <SheetField
            label="Shared link"
            value={link}
            autoFocus
            placeholder="Paste the link"
            autoComplete="off"
            onChange={(e) => setLink(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') void fork();
            }}
          />
          <SheetRow icon={Link2} label={busy ? 'Saving…' : 'Save a copy'} hint={problem ?? 'Yours to change; the shared one stays as it is.'} onPress={() => void fork()} />
        </SheetGroup>
      ) : null}
    </Sheet>
  );
}

/** How long a template's line runs on its row before it stops: about two lines on a phone, as the journal page keeps it to one. */
const HINT_MOST = 90;

/** A template's line cut at a word near the end of the room, with an ellipsis. */
function clip(line: string): string {
  if (line.length <= HINT_MOST) return line;
  const cut = line.slice(0, HINT_MOST);
  const space = cut.lastIndexOf(' ');
  return `${(space > HINT_MOST * 0.6 ? cut.slice(0, space) : cut).trimEnd()}…`;
}
