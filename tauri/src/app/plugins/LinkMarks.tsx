import { useNoteLinks } from './hooks.ts';
import styles from './LinkMarks.module.css';

/**
 * What a note is linked to, worn on the note: a small mark per link, with
 * the name of the thing - the Notion board its list goes to, the GitHub repo
 * the AI reads for it.
 *
 * Matt: "There should be some kind of indication if a note is linked to a
 * given notion board or git project." Until now the only place that said so
 * was the cog sheet, a tap away and out of sight. Now the note says it at its
 * top, under the tape (editor/NoteScreen.tsx). Each link's plugin says what
 * the note is linked to (`NoteLink.linked`, plugins/types.ts); a plugin
 * switched off says nothing, and its marks go. A tap opens the cog sheet,
 * where the link is changed or removed.
 *
 * The workspace the note is filed in was worn here too, as a pill first in the row, until the tab wore it (Matt:
 * "Remove the pill at the top of the notes it's already in the tab so it's redundant"): every note on screen has
 * its tab, and the tab's pill comes before its name in the workspace's hue (notes/NoteTabs.tsx). The note is filed
 * in its More sheet (editor/WorkspacePicker.tsx).
 */
export function LinkMarks({ noteId, onPress }: { noteId: string; onPress?: () => void }) {
  const links = useNoteLinks(noteId);
  if (!links.length) return null;
  const marks = links.map(({ link, name }) => {
    const Icon = link.icon;
    return (
      <span key={link.id} className={styles.mark} title={`${link.label}: ${name}`}>
        <span className={styles.icon} aria-hidden="true">
          <Icon />
        </span>
        <span className={styles.name}>{name}</span>
      </span>
    );
  });
  if (onPress) {
    const said = `Linked to ${links.map((l) => `${l.link.label} ${l.name}`).join(' and ')}`;
    return (
      <button type="button" className={styles.row} onClick={onPress} aria-label={`${said}. Change in this note’s settings.`}>
        {marks}
      </button>
    );
  }
  return <span className={styles.row}>{marks}</span>;
}
