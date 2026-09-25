import { useEffect, useState } from 'react';
import { ListChecks, TextSearch } from '@glacier/icons';
import { ArchiveBox, ArrowLeft, Bin, Board, Pin, Workspace as WorkspaceIcon } from '../art/Icons.tsx';
import { CheatSheet } from '../guide/CheatSheet.tsx';
import { useWorkspaces, workspaceOf } from '../core/workspaces.ts';
import { SheetField, SheetGroup, SheetHeading, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import { plugins, usePlugins } from '../plugins/registry.ts';
import type { NoteEditing, NoteLink } from '../plugins/types.ts';
import { MODES } from '../format/modes.ts';
import { KIND_ICONS } from '../ai/icons.ts';
import type { RunKind } from '../ai/kinds.ts';
import { WorkspacePicker } from './WorkspacePicker.tsx';
import { ShareRows } from '../share/ShareRows.tsx';
import type { NoteView } from './viewMode.ts';
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
  /** Opens find and replace in the note; absent where the note can't be searched (the transcript is showing). */
  onFind?: () => void;
  /** Lays the note's list out as a board (core/boards.ts); absent where there is nothing to make one of. */
  onMakeBoard?: () => void;
  /**
   * A field to name the note by, for a note with no heading to be named in: a canvas (docs/CANVAS.md), whose name
   * is its `title:` front matter. Absent on a note of words, which is named by its first line.
   */
  name?: { value: string; onChange: (title: string) => void };
  /** How the note is shown, when the header has no room for its switch (a folded phone); absent, no row. */
  view?: NoteView;
  /** The AI's kind of run on this note now, if one is on, and how to ask for one (ai/start.ts). Absent on a note that can't be read to. */
  running?: RunKind | null;
  onAi?: (kind: RunKind) => void;
  onView?: (view: NoteView) => void;
}

/** The two drawn icons from the kit, at the weight the sheet's own are drawn: the rings size every icon to 18 px. */
const FindIcon = () => <TextSearch size={18} strokeWidth={2.2} />;
const CheatSheetIcon = () => <ListChecks size={18} strokeWidth={2.2} />;

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
  onMakeBoard,
  name,
  view,
  onView,
  running,
  onAi,
}: NoteSettingsProps) {
  // Re-rendered when a plugin is switched, so its rows come and go.
  usePlugins();
  const [page, setPage] = useState<NoteLink | 'workspace' | 'cheatsheet' | null>(null);
  // Re-rendered as the note is filed, so the row says where it is.
  const spaces = useWorkspaces();
  const filed = workspaceOf(noteId);
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
  if (!open) return null;

  const back = () => (page ? setPage(null) : onClose());

  if (page) {
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
  const actions = plugins.noteActions().filter((action) => action.visible(noteId));
  return (
    <Sheet label={`Settings for ${title || 'this note'}`} onClose={onClose} onBack={back}>
      <SheetTitle>{title || 'Untitled'}</SheetTitle>
      {name ? (
        <SheetGroup>
          <SheetField label="Name" value={name.value} onChange={(e) => name.onChange(e.target.value)} placeholder="What this canvas is called" autoComplete="off" />
        </SheetGroup>
      ) : null}

      {onFind || onMakeBoard || (view && onView) ? (
        <>
          <SheetHeading>Reading it</SheetHeading>
          <SheetGroup>
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
                    <button key={value} type="button" role="radio" aria-checked={view === value} data-on={view === value || undefined} onClick={() => onView(value)}>
                      {label}
                    </button>
                  ))}
                </div>
              </div>
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
            {MODES.map((words) => {
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
          </SheetGroup>
        </>
      ) : null}

      {/* Read by anyone with its link, and nobody else (share/share.ts, docs/SHARING.md). */}
      <ShareRows noteId={noteId} />

      {/* The group under AI, named like the rest of them (Matt: "the section under AI is not labeled"). */}
      <SheetHeading>Where it sits</SheetHeading>
      <SheetGroup>
        <SheetRow icon={Pin} label={pinned ? 'Unpin' : 'Pin to the top'} onPress={onPin} />
        <SheetRow icon={ArchiveBox} label="Archive" onPress={onArchive} />
        <SheetRow icon={WorkspaceIcon} label="Workspace" hint={filed ? filed.name : spaces.list.length ? 'Not in one' : 'None yet. Make one to sort your notes.'} onPress={() => setPage('workspace')} />
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
                onPress={() => {
                  onClose();
                  void action.run(editing);
                }}
                disabled={!action.enabled(noteId, body)}
              />
            ))}
          </SheetGroup>
        </>
      ) : null}

      {/* Matt: "i want the glossary / lexicon / cheat sheet added for all formatting rules in the help section of the more menu". */}
      <SheetHeading>Help</SheetHeading>
      <SheetGroup>
        <SheetRow icon={CheatSheetIcon} label="Formatting cheat sheet" hint="Every mark you can type, and every cue you can say." onPress={() => setPage('cheatsheet')} />
      </SheetGroup>

      {/* Into the trash, from where it is brought back or deleted for good (core/trash.ts). */}
      <SheetGroup>
        <SheetRow icon={Bin} label="Move to Trash" onPress={onDelete} danger />
      </SheetGroup>
    </Sheet>
  );
}
