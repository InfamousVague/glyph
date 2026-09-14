import { useEffect, useState } from 'react';
import { useBack } from '../core/back.ts';
import { ArchiveBox, ArrowLeft, Bin, Pin } from '../art/Icons.tsx';
import { SheetIcon } from '../plugins/kit.tsx';
import { plugins, usePlugins } from '../plugins/registry.ts';
import type { NoteEditing, NoteLink } from '../plugins/types.ts';
import styles from './NoteSettings.module.css';

/**
 * One note's settings, from the cog in its header: pin it, archive it, what it
 * is linked to, what can be done with it, then Delete, apart at the bottom.
 *
 * "Linked to" and the actions under it come from plugins (plugins/registry.ts):
 * the Projects plugin's Project row, the Notion plugin's board and "Send list
 * to Notion". A link's row opens the plugin's own page inside the sheet. A
 * switched-off plugin's rows are simply not there.
 *
 * A sheet from the bottom over a dimmed note, where a thumb already is. Back
 * (the gesture or Escape) closes it before it leaves the note, and so does a
 * tap on the dimmed part. The links are shown before they work so a note can
 * be found where they will be; each says what it will do.
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
}

export function NoteSettings({ open, noteId, title, pinned, editing, onClose, onPin, onArchive, onDelete }: NoteSettingsProps) {
  // Re-rendered when a plugin is switched, so its rows come and go.
  usePlugins();
  const [page, setPage] = useState<NoteLink | null>(null);
  const [unavailable, setUnavailable] = useState<Record<string, string | null>>({});
  // The body when the sheet opened: the action rows' counts are read from it.
  const [body, setBody] = useState('');
  useEffect(() => {
    if (!open) {
      setPage(null);
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
  useBack(open, () => (page ? setPage(null) : onClose()));
  if (!open) return null;

  if (page) {
    const Picker = page.Picker;
    return (
      <div className={styles.scrim} onClick={onClose}>
        <section className={styles.sheet} role="dialog" aria-modal="true" aria-label={page.label} onClick={(e) => e.stopPropagation()}>
          <span className={styles.grip} aria-hidden="true" />
          <button type="button" className={styles.back} onClick={() => setPage(null)}>
            <ArrowLeft /> {title || 'This note'}
          </button>
          <Picker noteId={noteId} onDone={() => setPage(null)} />
        </section>
      </div>
    );
  }

  const links = plugins.noteLinks();
  const actions = plugins.noteActions().filter((action) => action.visible(noteId));
  return (
    <div className={styles.scrim} onClick={onClose}>
      <section className={styles.sheet} role="dialog" aria-modal="true" aria-label={`Settings for ${title || 'this note'}`} onClick={(e) => e.stopPropagation()}>
        <span className={styles.grip} aria-hidden="true" />
        <p className={styles.title}>{title || 'Untitled'}</p>

        <div className={styles.group}>
          <button type="button" className={styles.row} onClick={onPin}>
            <Pin className={styles.icon} />
            <span className={styles.label}>{pinned ? 'Unpin' : 'Pin to the top'}</span>
          </button>
          <button type="button" className={styles.row} onClick={onArchive}>
            <ArchiveBox className={styles.icon} />
            <span className={styles.label}>Archive</span>
          </button>
        </div>

        {links.length || actions.length ? (
          <>
            <p className={styles.heading}>Linked to</p>
            <div className={styles.group}>
              {links.map((link) => {
                const why = unavailable[link.id] ?? null;
                return (
                  <button key={link.id} type="button" className={styles.row} onClick={() => setPage(link)} disabled={why !== null}>
                    <SheetIcon icon={link.icon} />
                    <span className={styles.label}>
                      {link.label}
                      <span className={styles.hint}>{why ?? link.hint(noteId)}</span>
                    </span>
                  </button>
                );
              })}
              {actions.map((action) => (
                <button
                  key={action.id}
                  type="button"
                  className={styles.row}
                  onClick={() => {
                    onClose();
                    void action.run(editing);
                  }}
                  disabled={!action.enabled(noteId, body)}
                >
                  <SheetIcon icon={action.icon} />
                  <span className={styles.label}>
                    {action.label}
                    <span className={styles.hint}>{action.hint(noteId, body)}</span>
                  </span>
                </button>
              ))}
            </div>
          </>
        ) : null}

        <div className={styles.group}>
          <button type="button" className={`${styles.row} ${styles.danger}`} onClick={onDelete}>
            <Bin className={styles.icon} />
            <span className={styles.label}>Delete</span>
          </button>
        </div>
      </section>
    </div>
  );
}
