import { useRef } from 'react';
import { SquarePen, Workflow } from '@glacier/icons';
import { useBack } from '../core/back.ts';
import { SheetGroup, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import sheet from '../editor/NoteSettings.module.css';
import { useSheetDrag } from '../editor/sheetDrag.ts';

/**
 * What the + makes (Matt: "make the plus button ask if they want to create a canvas, note or memo"; memos were then
 * taken out of the app - "we're going to focus on notes and canvases"): a small sheet with the two, in the note's
 * settings' own look, from every + there is - the home dock's, the tab strip's and the sidebar's - so a + means the
 * same thing wherever it is. A tap on the scrim, the back gesture or a drag down closes it and makes nothing.
 */
export interface NewSheetProps {
  open: boolean;
  onClose: () => void;
  onNote: () => void;
  onCanvas: () => void;
}

export function NewSheet({ open, onClose, onNote, onCanvas }: NewSheetProps) {
  const panel = useRef<HTMLElement>(null);
  const drag = useSheetDrag(panel, onClose);
  useBack(open, onClose);
  if (!open) return null;

  const pick = (make: () => void) => () => {
    onClose();
    make();
  };
  return (
    <div className={sheet.scrim} onClick={onClose}>
      <section ref={panel} className={sheet.sheet} role="dialog" aria-modal="true" aria-label="New" onClick={(e) => e.stopPropagation()}>
        <span className={sheet.grip} aria-hidden="true" {...drag} />
        <SheetTitle>New</SheetTitle>
        <SheetGroup>
          <SheetRow icon={SquarePen} label="Note" hint="A page of markdown, typed or said." onPress={pick(onNote)} />
          <SheetRow icon={Workflow} label="Canvas" hint="Cards on a page with lines between them." onPress={pick(onCanvas)} />
        </SheetGroup>
      </section>
    </div>
  );
}
