import { useCallback, useRef, useState } from 'react';
import { ArrowLeft, ArrowRight, PanelLeft, Plus, X } from '@glacier/icons';
import { newGroup, NO_GROUPS, renameGroup, toggleGroup, type TabGroups } from './tabGroups.ts';
import { isCanvasBody } from '../canvas/jsonCanvas.ts';
import { isBookBody } from '../book/book.ts';
import { noteTitle, type Note } from '../core/store.ts';
import { useWorkspaces } from '../core/workspaces.ts';
import { setTopBarTools } from '../core/topBarTools.ts';
import { House } from '../art/Icons.tsx';
import { scrollSideways } from '../core/scrollSideways.ts';
import { GroupChip } from './GroupChip.tsx';
import { GroupMenu, TabMenu } from './TabMenus.tsx';
import { useTabDrag } from './useTabDrag.ts';
import { useTabOutline } from './useTabOutline.ts';
import styles from './NoteTabs.module.css';

/**
 * The app's top bar: the notes that are open, and the way to the rest of them (Matt: "add tabs at the top of the app
 * for the different notes that are open", and "add a sidebar that opens as a floating card, add a sidebar icon on the
 * top left of the page").
 *
 * Two rows. The first is the controls - home, the sidebar's icon, back and forward, the slot the screen's own buttons
 * are drawn into, and the aside's icon at the far end. The second is the tabs, which scroll sideways when there are
 * more than fit, and is not drawn at all with nothing open. A tap changes note without leaving the screen; the cross
 * closes a tab, and the note behind it carries on existing, it is only no longer open.
 *
 * The bar is the app's, not any screen's: App.tsx draws it once, in the fixed `.app-tabBar`, on the home page, the
 * All notes grid and a note, and says how tall it is on the root (`data-tabs`, app.css `--app-tabs`), so every
 * screen's header clears it by `--app-safe-top` without knowing it is there. This file is its markup; the gesture on
 * the row is notes/useTabDrag.ts, the outline and the smoke at its ends notes/useTabOutline.ts, and the menus and a
 * group's chip notes/TabMenus.tsx and notes/GroupChip.tsx.
 */

interface NoteTabsProps {
  /** The open notes, in the order they were opened. */
  tabs: Note[];
  activeId: string;
  onOpen: (id: string) => void;
  onClose: (id: string) => void;
  /** A new note in a new tab: the + at the end of the row, as a browser and Obsidian have it. */
  onNew?: () => void;
  /** Chrome-style groups over the tabs (notes/tabGroups.ts); the tabs arrive already drawn in their groups' order. */
  groups?: TabGroups;
  onGroups?: (next: TabGroups) => void;
  /** Close several tabs at once: a whole group. */
  onCloseTabs?: (ids: string[]) => void;
  /** The floating list of every note; absent where the list is already beside the note (the desktop sidebar). */
  onSidebar?: () => void;
  sidebarOpen?: boolean;
  /** The right-hand aside (aside/Aside.tsx): a book's index, or a run of chapters; the icon is the sidebar's, mirrored. Absent when there's nothing for it to show, and so is the icon. */
  onAside?: () => void;
  asideOpen?: boolean;
  /** The home page (home/HomeScreen.tsx), and whether it is the page showing. */
  onHome?: () => void;
  atHome?: boolean;
  /**
   * A tab dragged to sit somewhere else in the row (notes/openTabs.ts). `grouped` says the drag has already settled
   * which group the tab is in (`onGroups`); without it - a move by the keys - the row works that out from where it lands.
   */
  onMove?: (id: string, to: number, grouped?: boolean) => void;
  /** Back and forward through where he has been (notes/visited.ts), beside the sidebar's button. */
  onGoBack?: () => void;
  onGoOn?: () => void;
  canGoBack?: boolean;
  canGoOn?: boolean;
  /**
   * A canvas renamed from its tab (Matt: "I also need a way to rename canvases maybe through the tabs context
   * menu?"). Only a canvas: a note is named by its first line, which is written in the note itself, where a
   * canvas has no line to write - it is named by `title:` in its front matter (core/frontMatter.ts), and the
   * only way to that was the cog. Absent, and no tab offers it.
   */
  onRename?: (id: string, title: string) => void;
}

export function NoteTabs({
  tabs,
  activeId,
  onOpen,
  onClose,
  onSidebar,
  sidebarOpen,
  onAside,
  asideOpen,
  onHome,
  atHome = false,
  onMove,
  onGoBack,
  onGoOn,
  canGoBack = false,
  canGoOn = false,
  onNew,
  onRename,
  groups = NO_GROUPS,
  onGroups,
  onCloseTabs,
}: NoteTabsProps) {
  /*
   * The menus a group's chip and a tab open, and the chip being renamed. A chip opens its menu on a right-click or a
   * long press - it is never dragged, so a finger's hold is free.
   *
   * A tab is dragged by a finger's hold, so its menu is the end of that hold rather than its start: held and moved,
   * the tab is carried; held and let go where it was, the menu opens (Matt: "Can't open tabs context menu on mobile
   * it just highlights the tab text"). A mouse keeps its right-click. The highlighting was the phone's own: a long
   * press with nothing to stop it selects the words under it, so the tabs take no selection at all (the stylesheet's
   * `user-select`), and the menu the phone would raise is refused here whatever raises it.
   */
  const [menu, setMenu] = useState<{ kind: 'group' | 'tab'; id: string } | null>(null);
  const [renaming, setRenaming] = useState<string | null>(null);
  /** The tab whose name is open as a field, and the words in it: a canvas being renamed in the row. */
  const [naming, setNaming] = useState<{ id: string; draft: string } | null>(null);
  /**
   * The end of a rename, however it ends: the field closes first, so the blur that follows it finds nothing open and
   * cannot keep the same name twice. A name is only sent on if it is a name and is not the one the tab already has.
   */
  const keepName = (id: string, was: string, keep: boolean) => {
    const kept = naming?.draft.trim() ?? '';
    setNaming(null);
    if (keep && kept && kept !== was) onRename?.(id, kept);
  };
  const pointer = useRef<string>('mouse');
  const change = (next: TabGroups) => onGroups?.(next);
  const startGroup = (noteId: string) => {
    const made = newGroup(groups, noteId);
    change(made.groups);
    // Named "Group" to begin with, and straight into its name to be called something better.
    setRenaming(made.id);
  };
  const spaces = useWorkspaces();
  const row = useRef<HTMLDivElement>(null);
  /** The tab being carried by a drag, while it is. */
  const [moving, setMoving] = useState<string | null>(null);
  const outline = useTabOutline(row, { tabs, activeId, moving });
  const drag = useTabDrag(row, { groups, onMove, onGroups, setMoving, onHeld: (id) => setMenu({ kind: 'tab', id }), placeOutline: outline.place });

  /** Moving a tab without a pointer: the arrow keys with the platform's own modifier, as a browser's tab strip does. */
  const nudge = (id: string, at: number) => (event: React.KeyboardEvent) => {
    if (!onMove || !(event.metaKey || event.ctrlKey)) return;
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    onMove(id, at + (event.key === 'ArrowLeft' ? -1 : 1));
  };

  /*
   * The slot the screen's own controls are drawn into (core/topBarTools.ts). The bar offers the place; the screen
   * that owns those buttons fills it, because they hold the editor's state and cannot be lifted up here without it.
   */
  const slot = useCallback((element: HTMLDivElement | null) => setTopBarTools(element), []);

  if (!onSidebar && !onGoBack && tabs.length === 0) return null;
  return (
    <div className={styles.bar}>
      <div className={styles.top}>
      {/* Home, first in the bar and before the sidebar's button (Matt: "Add a 'home' button", then "Move the home
          button to the left of the sidebar button"), drawn as a house (art/Icons.tsx). */}
      {onHome ? (
        <button
          type="button"
          className={styles.sidebar}
          onClick={onHome}
          aria-label="Home"
          title="Home"
          aria-current={atHome ? 'page' : undefined}
          data-on={atHome || undefined}
        >
          <House size={20} strokeWidth={2.1} />
        </button>
      ) : null}
      {onSidebar ? (
        <button
          type="button"
          className={styles.sidebar}
          onClick={onSidebar}
          data-sidebar-toggle
          aria-label="All your notes"
          aria-expanded={sidebarOpen ?? false}
          data-on={sidebarOpen || undefined}
        >
          <PanelLeft size={20} strokeWidth={2.1} aria-hidden="true" />
        </button>
      ) : null}
      {/* Where he has been: the same two arrows a browser has, in the same place, beside the sidebar's button. */}
      {onGoBack && onGoOn ? (
        <>
          <button type="button" className={styles.step} onClick={onGoBack} disabled={!canGoBack} aria-label="Back to where you were">
            <ArrowLeft size={19} strokeWidth={2.2} aria-hidden="true" />
          </button>
          <button type="button" className={styles.step} onClick={onGoOn} disabled={!canGoOn} aria-label="Forward again">
            <ArrowRight size={19} strokeWidth={2.2} aria-hidden="true" />
          </button>
        </>
      ) : null}
        {/* The screen's own controls, at the far end (Matt: "Move the controls for the note into the topbar"). */}
        <div ref={slot} className={styles.slot} />
        {/* The aside's toggle, last of all: the sidebar's icon reversed (Matt: "a sidebar toggle on the right with the icon reversed"). */}
        {onAside ? (
          <button
            type="button"
            className={`${styles.sidebar} ${styles.mirrored}`}
            onClick={onAside}
            data-aside-toggle
            aria-label="Book index"
            aria-expanded={asideOpen ?? false}
            data-on={asideOpen || undefined}
          >
            <PanelLeft size={20} strokeWidth={2.1} aria-hidden="true" />
          </button>
        ) : null}
      </div>
      {/*
        The tabs, on their own line under the controls (Matt: "put the tabs on the next line down"), and no line at
        all when nothing is open (Matt: "This row can be hidden when there are no tabs open") - a note opened from
        the list used to carry an empty strip for tabs it did not have.
      */}
      {tabs.length > 0 ? (
        <div
          ref={row}
          className={styles.tabs}
          data-fade-start={outline.ends.start || undefined}
          data-fade-end={outline.ends.end || undefined}
          role="tablist"
          aria-label="Notes you have open"
          onPointerDown={drag.takeHold}
          onWheel={scrollSideways}
          onClickCapture={drag.swallowClick}
        >
          <span ref={outline.glide} className={styles.glide} aria-hidden="true" />
          {tabs.map((note, at) => {
            const title = noteTitle(note.body) || 'Untitled';
            const active = note.id === activeId;
            const groupId = groups.of[note.id];
            const group = groupId ? groups.list.find((g) => g.id === groupId) : undefined;
            const firstOfGroup = !!group && groups.of[tabs[at - 1]?.id ?? ''] !== group.id;
            const chip = group && firstOfGroup ? (
              <GroupChip
                key={`group-${group.id}`}
                group={group}
                count={tabs.filter((t) => groups.of[t.id] === group.id).length}
                renaming={renaming === group.id}
                onToggle={() => change(toggleGroup(groups, group.id))}
                onMenu={() => setMenu({ kind: 'group', id: group.id })}
                onRename={(name) => {
                  change(renameGroup(groups, group.id, name));
                  setRenaming(null);
                }}
                menu={
                  menu?.kind === 'group' && menu.id === group.id ? (
                    <GroupMenu
                      group={group}
                      groups={groups}
                      tabIds={tabs.map((t) => t.id)}
                      onDismiss={() => setMenu(null)}
                      onRename={() => setRenaming(group.id)}
                      onGroups={change}
                      onCloseTabs={onCloseTabs}
                    />
                  ) : null
                }
              />
            ) : null;
            // A folded group draws only its chip.
            if (group?.collapsed) return chip;
            // The workspace the note is filed in, worn as its own coloured pill in front of the name (Matt: "show the
            // workspace pill first on the tab"). Two notes called Monday are told apart by colour before either is read.
            const space = spaces.list.find((w) => w.id === spaces.of[note.id]) ?? null;
            return [
              chip,
              <span
                key={note.id}
                data-tab
                data-tab-id={note.id}
                className={styles.tab}
                data-active={active || undefined}
                data-moving={moving === note.id || undefined}
                data-group={group ? group.hue : undefined}
                data-group-id={group ? group.id : undefined}
                onPointerDownCapture={(event) => {
                  pointer.current = event.pointerType;
                }}
                onContextMenu={(event) => {
                  // Always refused: on a phone this is the press-and-hold callout, which would land on top of the
                  // drag and the menu the hold itself opens (useTabDrag.ts). A mouse's right-click opens the menu here.
                  event.preventDefault();
                  if (pointer.current !== 'mouse' || !onGroups) return;
                  setMenu({ kind: 'tab', id: note.id });
                }}
              >
                {naming?.id === note.id ? (
                  /* The canvas's name, written where the tab's name was. Enter keeps it, Escape leaves it, and
                     leaving the field keeps it too - a phone has no Escape and losing the words to a stray tap
                     would be worse than a name kept by accident, which is one more rename to put right. */
                  <input
                    className={styles.name}
                    value={naming.draft}
                    aria-label="Canvas name"
                    autoFocus
                    onFocus={(event) => event.currentTarget.select()}
                    onChange={(event) => setNaming({ id: note.id, draft: event.currentTarget.value })}
                    onPointerDown={(event) => event.stopPropagation()}
                    onBlur={() => keepName(note.id, title, true)}
                    onKeyDown={(event) => {
                      // Enter keeps it here rather than by blurring the field: measured in the browser, the blur that
                      // a blur() raises never reached the handler, and the field sat open with the new name in it.
                      if (event.key === 'Enter') {
                        event.preventDefault();
                        keepName(note.id, title, true);
                      } else if (event.key === 'Escape') {
                        event.preventDefault();
                        keepName(note.id, title, false);
                      }
                    }}
                  />
                ) : (
                  <button
                    type="button"
                    role="tab"
                    aria-selected={active}
                    className={styles.name}
                    onKeyDown={nudge(note.id, at)}
                    onClick={() => onOpen(note.id)}
                    // Said rather than shown twice: the pill is a colour to the eye and the workspace's name to a reader.
                    aria-label={space ? `${title}, in ${space.name}` : title}
                  >
                    {space ? (
                      <span className={styles.space} data-hue={space.hue ?? 'ink'} aria-hidden="true">
                        {space.name}
                      </span>
                    ) : null}
                    <span className={styles.title}>{title}</span>
                  </button>
                )}
                <button type="button" data-close className={styles.close} onClick={() => onClose(note.id)} aria-label={`Close ${title}`}>
                  <X size={15} strokeWidth={2.4} aria-hidden="true" />
                </button>
                {/* The group's colour along the foot of each of its tabs, as Chrome draws a group - drawn in, not
                    taken away, under the one being read, which stays open onto the note (NoteTabs.module.css). */}
                {group ? <span className={styles.groupLine} data-hue={group.hue} aria-hidden="true" /> : null}
                {menu?.kind === 'tab' && menu.id === note.id ? (
                  <TabMenu
                    noteId={note.id}
                    title={title}
                    groups={groups}
                    onDismiss={() => setMenu(null)}
                    // A canvas or a book is named by its front matter and has no first line to write, so the row offers it.
                    onRename={onRename && (isCanvasBody(note.body) || isBookBody(note.body)) ? () => setNaming({ id: note.id, draft: title }) : undefined}
                    onNewGroup={() => startGroup(note.id)}
                    onGroups={change}
                    onCloseTab={() => onClose(note.id)}
                  />
                ) : null}
              </span>,
            ];
          })}
          {/* After the last tab, so it moves along with the row: a new note, in a tab of its own. Not a tab itself
              (no `data-tab`), so dragging and the hold never take it for one. */}
          {onNew ? (
            <button type="button" className={styles.newTab} data-new-tab onClick={onNew} aria-label="New note in a new tab" title="New note">
              <Plus size={15} strokeWidth={2.2} aria-hidden="true" />
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
