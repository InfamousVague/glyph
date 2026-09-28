import { useEffect, useState } from 'react';
import { Book, Feather, Link2, SquarePen, Workflow } from '@glacier/icons';
import { Cassette } from '../art/Icons.tsx';
import { failureText } from '../core/failure.ts';
import { SheetField, SheetGroup, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import { Sheet } from '../editor/Sheet.tsx';

/**
 * What the + makes (Matt: "make the plus button ask if they want to create a canvas, note or memo"; memos were then
 * taken out of the app - "we're going to focus on notes and canvases"): a small sheet offering a note, a canvas or a
 * book (docs/BOOKS.md), in the note's settings' own look, from every + there is - the home dock's, the tab strip's and
 * the sidebar's - so a + means the same thing wherever it is. A tap on the scrim, the back gesture or a drag down
 * closes it and makes nothing.
 *
 * And a meeting (docs/DESIGN.md §127 section 3), only where one can be recorded (capture/meeting.ts): the Mac, and an
 * Android phone with the service. And a copy of something shared with you (share/share.ts, docs/SHARING.md): "From a
 * shared link" takes a link to a shared note or book and saves it into this library as your own copy.
 *
 * And, with a journal, a new entry in the one written in last (docs/DESIGN.md §142), right after Note, in the pen an
 * entry is written with: two taps from home, said plainly, rather than a word on the home page. One row only, and no
 * Journal row: a journal is made from Notebook.
 */
export interface NewSheetProps {
  open: boolean;
  onClose: () => void;
  onNote: () => void;
  onCanvas: () => void;
  onBook: () => void;
  /** A new entry in the journal written in last, with its name and what an entry starts with; absent with no journal. */
  entry?: { journal: string; hint: string; onPress: () => void };
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
  /*
   * However it closed - the scrim, a drag down, the back gesture, a choice made - the next + opens on the choices,
   * not on the field and the words left in it. Only the scrim used to clear them.
   */
  useEffect(() => {
    if (open) return;
    setLink(null);
    setProblem(null);
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
  return (
    <Sheet label="New" onClose={onClose}>
      <SheetTitle>New</SheetTitle>
      <SheetGroup>
        <SheetRow icon={SquarePen} label="Note" hint="A page of markdown, typed or said." onPress={pick(onNote)} />
        {entry ? <SheetRow icon={Feather} label={`Entry in ${entry.journal}`} hint={entry.hint} onPress={pick(entry.onPress)} /> : null}
        <SheetRow icon={Workflow} label="Canvas" hint="Cards on a page with lines between them." onPress={pick(onCanvas)} />
        <SheetRow icon={Book} label="Notebook" hint="Notes in an order with an index, or a journal of dated entries." onPress={pick(onBook)} />
        {onMeeting ? <SheetRow icon={Cassette} label="Meeting" hint="Record a meeting. The screen can go off. It is written up afterwards." onPress={pick(onMeeting)} /> : null}
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
