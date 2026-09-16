import { useEffect, useRef, useState } from 'react';
import { TextSearch } from '@glacier/icons';
import { useBack } from '../core/back.ts';
import { ArchiveBox, ArrowLeft, Bin, Pin, Workspace as WorkspaceIcon } from '../art/Icons.tsx';
import { useWorkspaces, workspaceOf } from '../core/workspaces.ts';
import { SheetIcon } from '../plugins/kit.tsx';
import { plugins, usePlugins } from '../plugins/registry.ts';
import type { NoteEditing, NoteLink } from '../plugins/types.ts';
import { MODES, type Mode } from '../format/modes.ts';
import { Robot } from '../art/Icons.tsx';
import { WorkspacePicker } from './WorkspacePicker.tsx';
import type { NoteView } from './viewMode.ts';
import styles from './NoteSettings.module.css';
import { useSheetDrag } from './sheetDrag.ts';

/**
 * One note's settings, from the cog in its header: pin it, archive it, which
 * workspace it is in (core/workspaces.ts), what it is linked to, what can be
 * done with it, then Delete, apart at the bottom.
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
  /** Opens find and replace in the note; absent where the note can't be searched (the robot's view is showing). */
  onFind?: () => void;
  /** How the note is shown, when the header has no room for its switch (a folded phone); absent, no row. */
  view?: NoteView;
  /** What the robot is showing over the note, and how to choose (format/modes.ts). Absent on a note that can't be read to. */
  mode?: Mode | null;
  onMode?: (mode: Mode | null) => void;
  onView?: (view: NoteView) => void;
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
  view,
  onView,
  mode,
  onMode,
}: NoteSettingsProps) {
  // Re-rendered when a plugin is switched, so its rows come and go.
  usePlugins();
  const [page, setPage] = useState<NoteLink | 'workspace' | null>(null);
  // Re-rendered as the note is filed, so the row says where it is.
  const spaces = useWorkspaces();
  const filed = workspaceOf(noteId);
  const [unavailable, setUnavailable] = useState<Record<string, string | null>>({});
  // The body when the sheet opened: the action rows' counts are read from it.
  const [body, setBody] = useState('');
  // The sheet takes a pull on its handle: down far enough and it closes (editor/sheetDrag.ts).
  const panel = useRef<HTMLElement>(null);
  const drag = useSheetDrag(panel, onClose);
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
    const Picker = page === 'workspace' ? WorkspacePicker : page.Picker;
    return (
      <div className={styles.scrim} onClick={onClose}>
        <section
          ref={panel}
          className={styles.sheet}
          role="dialog"
          aria-modal="true"
          aria-label={page === 'workspace' ? 'Workspace' : page.label}
          onClick={(e) => e.stopPropagation()}
        >
          <span className={styles.grip} aria-hidden="true" {...drag} />
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
      <section
        ref={panel}
        className={styles.sheet}
        role="dialog"
        aria-modal="true"
        aria-label={`Settings for ${title || 'this note'}`}
        onClick={(e) => e.stopPropagation()}
      >
        <span className={styles.grip} aria-hidden="true" {...drag} />
        <p className={styles.title}>{title || 'Untitled'}</p>

        {onFind || (view && onView) ? (
          <div className={styles.group}>
            {view && onView ? (
              <div className={styles.row} aria-disabled>
                <span className={styles.label}>Show</span>
                <div className={styles.viewChoice} role="radiogroup" aria-label="How the note is shown">
                  {(
                    [
                      ['mixed', 'Markdown'],
                      ['formatted', 'Formatted'],
                    ] as const
                  ).map(([value, label]) => (
                    <button
                      key={value}
                      type="button"
                      role="radio"
                      aria-checked={view === value}
                      data-on={view === value || undefined}
                      onClick={() => onView(value)}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </div>
            ) : null}
            {onFind ? (
              <button type="button" className={styles.row} onClick={onFind}>
                <span className={styles.icon} aria-hidden="true">
                  <TextSearch size={18} strokeWidth={2.2} />
                </span>
                <span className={styles.label}>Find and replace</span>
              </button>
            ) : null}
          </div>
        ) : null}

        {onMode ? (
          <>
            <p className={styles.heading}>AI</p>
            <div className={styles.group}>
              {MODES.map((words) => (
                <button
                  key={words.id}
                  type="button"
                  className={styles.row}
                  aria-pressed={mode === words.id}
                  onClick={() => {
                    onClose();
                    onMode(mode === words.id ? null : words.id);
                  }}
                >
                  <span className={styles.icon} aria-hidden="true">
                    <Robot />
                  </span>
                  <span className={styles.label}>
                    {words.label}
                    <span className={styles.hint}>{words.hint}</span>
                  </span>
                  {mode === words.id ? <span className={styles.chosen} aria-hidden="true" /> : null}
                </button>
              ))}
            </div>
          </>
        ) : null}

        <div className={styles.group}>
          <button type="button" className={styles.row} onClick={onPin}>
            <span className={styles.icon} aria-hidden="true">
              <Pin />
            </span>
            <span className={styles.label}>{pinned ? 'Unpin' : 'Pin to the top'}</span>
          </button>
          <button type="button" className={styles.row} onClick={onArchive}>
            <span className={styles.icon} aria-hidden="true">
              <ArchiveBox />
            </span>
            <span className={styles.label}>Archive</span>
          </button>
          <button type="button" className={styles.row} onClick={() => setPage('workspace')}>
            <span className={styles.icon} aria-hidden="true">
              <WorkspaceIcon />
            </span>
            <span className={styles.label}>
              Workspace
              <span className={styles.hint}>{filed ? filed.name : spaces.list.length ? 'Not in one' : 'None yet. Make one to sort your notes.'}</span>
            </span>
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
            <span className={styles.icon} aria-hidden="true">
              <Bin />
            </span>
            <span className={styles.label}>Delete</span>
          </button>
        </div>
      </section>
    </div>
  );
}
