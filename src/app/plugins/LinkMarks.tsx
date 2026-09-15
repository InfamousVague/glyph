import { useNoteLinks } from './registry.ts';
import styles from './LinkMarks.module.css';

/**
 * What a note is linked to, worn on the note: a small mark per link, with
 * the name of the thing - the Notion board its list goes to, the GitHub repo
 * the AI reads for it.
 *
 * Matt: "There should be some kind of indication if a note is linked to a
 * given notion board or git project." Until now the only place that said so
 * was the cog sheet, a tap away and out of sight. Now the note says it at its
 * top, under the tape, and the list says it on the row (`compact`: the mark
 * alone, so a row stays one line). Each link's plugin says what the note is
 * linked to (`NoteLink.linked`, plugins/types.ts); a plugin switched off says
 * nothing, and its marks go. A tap opens the cog sheet, where the link is
 * changed or removed.
 */
export function LinkMarks({ noteId, compact = false, onPress }: { noteId: string; compact?: boolean; onPress?: () => void }) {
  const links = useNoteLinks(noteId);
  if (!links.length) return null;
  const marks = links.map(({ link, name }) => {
    const Icon = link.icon;
    return (
      <span key={link.id} className={styles.mark} title={`${link.label}: ${name}`} data-compact={compact || undefined}>
        <span className={styles.icon} aria-hidden="true">
          <Icon />
        </span>
        {compact ? <span className={styles.hidden}>{`${link.label}: ${name}`}</span> : <span className={styles.name}>{name}</span>}
      </span>
    );
  });
  if (onPress) {
    return (
      <button type="button" className={styles.row} onClick={onPress} aria-label={`Linked to ${links.map((l) => `${l.link.label} ${l.name}`).join(' and ')}. Change in this note’s settings.`}>
        {marks}
      </button>
    );
  }
  return (
    <span className={styles.row} data-compact={compact || undefined}>
      {marks}
    </span>
  );
}
