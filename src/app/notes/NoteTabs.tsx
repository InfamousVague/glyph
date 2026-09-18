import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { ArrowLeft, ArrowRight, PanelLeft, Plus, X } from '@glacier/icons';
import { Menu, MenuItem, MenuSeparator, MenuSub } from '@glacier/react';
import {
  joinGroup,
  leaveGroup,
  membersOf,
  newGroup,
  NO_GROUPS,
  recolourGroup,
  renameGroup,
  toggleGroup,
  ungroup,
  type TabGroup,
  type TabGroups,
} from './tabGroups.ts';
import { noteTitle, type Note } from '../core/store.ts';
import { motionScale } from '../core/preferences.ts';
import { useWorkspaces, WORKSPACE_HUES } from '../core/workspaces.ts';
import { setTopBarTools } from '../core/topBarTools.ts';
import { scrollSideways } from '../core/scrollSideways.ts';
import styles from './NoteTabs.module.css';

/**
 * The row across the top of a note: the notes that are open, and the way to
 * the rest of them (Matt: "add tabs at the top of the app for the different
 * notes that are open", and "add a sidebar that opens as a floating card, add
 * a sidebar icon on the top left of the page").
 *
 * Both asks are one bar. The sidebar's icon is the row's first thing, which
 * puts it at the top left of the page without a second back word fighting the
 * note's own; the tabs run beside it and scroll sideways when there are more
 * than fit. A tap changes note without leaving the screen; the cross closes a
 * tab, and the note behind it carries on existing, it is only no longer open.
 *
 * The row lives inside the note's header pane (editor/NoteScreen.tsx), so the
 * note scrolls under it and the header's own height already accounts for it.
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
  /** A tab dragged to sit somewhere else in the row (notes/openTabs.ts). */
  onMove?: (id: string, to: number) => void;
  /** Back and forward through where he has been (notes/visited.ts), beside the sidebar's button. */
  onGoBack?: () => void;
  onGoOn?: () => void;
  canGoBack?: boolean;
  canGoOn?: boolean;
}

/** How far a pointer must travel before a press on a tab is a drag rather than a click. */
const TRAVEL = 6;
/** How long a press has to stay put before it picks the tab up rather than pulling the row along. */
const HOLD_MS = 220;

export function NoteTabs({
  tabs,
  activeId,
  onOpen,
  onClose,
  onSidebar,
  sidebarOpen,
  onMove,
  onGoBack,
  onGoOn,
  canGoBack = false,
  canGoOn = false,
  onNew,
  groups = NO_GROUPS,
  onGroups,
  onCloseTabs,
}: NoteTabsProps) {
  /*
   * The menus a group's chip and a tab open, and the chip being renamed. A chip opens its menu on a right-click or a
   * long press - it is never dragged, so a finger's hold is free. A tab opens its menu on a mouse's right-click only:
   * a finger's hold on a tab picks it up to move it (`takeHold`), and a menu there would fight the drag.
   */
  const [menu, setMenu] = useState<{ kind: 'group' | 'tab'; id: string } | null>(null);
  const [renaming, setRenaming] = useState<string | null>(null);
  const pointer = useRef<string>('mouse');
  const change = (next: TabGroups) => onGroups?.(next);
  const startGroup = (noteId: string) => {
    const made = newGroup(groups, noteId);
    change(made.groups);
    // Named "Group" to begin with, and straight into its name to be called something better.
    setRenaming(made.id);
  };
  const spaces = useWorkspaces();
  /*
   * Dragging a tab along the row (Matt: "Add dragging around tabs into different positions"). The row reorders under
   * the finger rather than a ghost following it: the tab being dragged is the tab in the row, and it swaps with a
   * neighbour the moment the pointer passes that neighbour's middle.
   *
   * The drag is followed on the window rather than on the tab, and deliberately: reordering moves the tab's own
   * element in the DOM, which drops a pointer capture held on it. Held that way, a drag lost its end - no pointerup
   * ever arrived at the tab - and every later tap was swallowed as "the click that ends a drag". The window sees the
   * whole gesture whatever React does to the row underneath.
   *
   * A mouse drags once it has actually travelled, since a plain click emits a move of no distance. A finger waits a
   * moment first, because the row scrolls sideways and a flick along it must stay a flick - the same reason a phone's
   * home screen waits before it lets you move an icon.
   */
  const row = useRef<HTMLDivElement>(null);
  const [moving, setMoving] = useState<string | null>(null);
  /** A drag ends in a click somewhere in the row, which must not also open a note. */
  const dragged = useRef(false);

  /**
   * Which place in the row the pointer is over: how many of the OTHER tabs' middles it has passed.
   *
   * The tab being dragged is skipped on purpose. It carries an offset so it can follow the finger, which moves the
   * box it would be measured by, and measuring it made the row swap and swap back as the offset chased the answer
   * that had caused it.
   */
  const placeAt = (x: number, dragging: string): number => {
    const items = row.current ? [...row.current.querySelectorAll<HTMLElement>('[data-tab]')] : [];
    let place = 0;
    for (const tab of items) {
      if (tab.dataset.tabId === dragging) continue;
      const box = tab.getBoundingClientRect();
      if (x > box.left + box.width / 2) place += 1;
    }
    return place;
  };

  const takeHold = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!onMove || (event.pointerType === 'mouse' && event.button !== 0)) return;
    const tab = (event.target as HTMLElement).closest<HTMLElement>('[data-tab]');
    const id = tab?.dataset.tabId;
    if (!id) return;
    // The cross is not a handle: pressing it means close, whatever the finger does next.
    if ((event.target as HTMLElement).closest('[data-close]')) return;

    const from = event.clientX;
    /*
     * One rule for a finger and a mouse alike: press and hold to pick a tab up (Matt: "the clicking and dragging is
     * eating me moving the tabs - the tabs should only move when I press and hold"). A mouse used to reorder the
     * moment it had travelled a few pixels, so a click that slid under the hand carried the tab with it.
     */
    let on = false;
    const hold = window.setTimeout(() => {
      on = true;
      setMoving(id);
    }, HOLD_MS);

    // Where along the tab it was taken hold of, so it hangs off the finger at the point it was picked up rather than
    // jumping its middle to the pointer.
    const grabbed = from - tab.getBoundingClientRect().left;

    const follow = (x: number) => {
      const el = row.current?.querySelector<HTMLElement>(`[data-tab-id="${CSS.escape(id)}"]`);
      if (!el) return;
      // Measured with the offset off, since a transform moves the box it would otherwise be measured from.
      el.style.transform = '';
      const home = el.getBoundingClientRect().left;
      el.style.transform = `translateX(${Math.round(x - grabbed - home)}px)`;
    };

    /*
     * Before the hold fires, a finger going sideways pans the row instead of picking a tab up (Matt: "I should be
     * able to scroll left or right on the tabs to see overflowing ones"). The row keeps `touch-action: pan-y`, so a
     * vertical swipe still scrolls the page natively and the sideways movement arrives here to be spent on
     * scrollLeft. It is the phone's own convention: swipe to move along, press and hold to pick something up.
     */
    let panned = from;
    const along = (moved: PointerEvent) => {
      // Not held yet: this is a drag across the row, so it moves the row rather than anything in it.
      if (!on) {
        const step = panned - moved.clientX;
        if (Math.abs(moved.clientX - from) >= TRAVEL && row.current) {
          window.clearTimeout(hold);
          row.current.scrollLeft += step;
          panned = moved.clientX;
          // A pan is not a tap: letting go must not open the tab it started on.
          dragged.current = true;
        }
        return;
      }
      dragged.current = true;
      onMove(id, placeAt(moved.clientX, id));
      // After the row has been told where the tab belongs, not before: the tab has to follow the finger even between
      // two places (Matt: "moving tabs doesn't look like you're actually moving it, doesn't follow my finger").
      follow(moved.clientX);
    };
    const done = () => {
      window.clearTimeout(hold);
      window.removeEventListener('pointermove', along);
      window.removeEventListener('pointerup', done);
      window.removeEventListener('pointercancel', done);
      // Let go and it settles into its place, rather than snapping there.
      const el = row.current?.querySelector<HTMLElement>(`[data-tab-id="${CSS.escape(id)}"]`);
      if (el) el.style.transform = '';
      setMoving(null);
      // The click that ends the drag is swallowed below; this clears the flag even when the gesture ends
      // somewhere that sends no click at all.
      if (dragged.current) window.setTimeout(() => {
        dragged.current = false;
      }, 0);
    };
    window.addEventListener('pointermove', along);
    window.addEventListener('pointerup', done);
    window.addEventListener('pointercancel', done);
  };

  /*
   * Whether the row has more tabs than fit, which is the only time its end should go to smoke (Matt: "only show the
   * wisp blur effect on the end of the scrolling tab list when it overflows the screen"). Watched rather than worked
   * out once: tabs are added, closed, dragged and renamed, workspaces put a pill in front of a name, and the window
   * changes width, and each of those can turn a row that fits into one that does not.
   */
  const [over, setOver] = useState(false);
  useEffect(() => {
    const el = row.current;
    if (!el) return undefined;
    const look = () => setOver(el.scrollWidth - el.clientWidth > 1);
    look();
    const watch = new ResizeObserver(look);
    watch.observe(el);
    for (const tab of el.children) watch.observe(tab);
    return () => watch.disconnect();
  }, [tabs]);

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

  /*
   * The tab being read slides to the one opened (Matt: "add an animation so the tab slides between items"). Measured
   * after the row has drawn the new tab as the active one, and before it is painted: an outline (`.glide`) is put
   * over the last tab and sent to the new one, taking on its width as it goes, while the new tab keeps its own
   * outline back until it lands. Nothing slides from a tab that has closed, to or from the list, while a tab is being
   * dragged, or for someone who has asked their phone for less motion.
   */
  const glide = useRef<HTMLSpanElement>(null);
  const wasActive = useRef(activeId);
  useLayoutEffect(() => {
    const from = wasActive.current;
    wasActive.current = activeId;
    const box = row.current;
    const outline = glide.current;
    if (!box || !outline || !from || !activeId || from === activeId || moving) return undefined;
    if (typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches) return undefined;
    const tab = (id: string) => box.querySelector<HTMLElement>(`[data-tab-id="${CSS.escape(id)}"]`);
    const start = tab(from);
    const end = tab(activeId);
    if (!start || !end || typeof outline.animate !== 'function') return undefined;
    const place = (el: HTMLElement) => ({ left: `${el.offsetLeft}px`, width: `${el.offsetWidth}px` });
    outline.style.top = `${end.offsetTop}px`;
    outline.style.height = `${end.offsetHeight}px`;
    outline.dataset.on = '';
    end.dataset.arriving = '';
    const slide = outline.animate([place(start), place(end)], {
      duration: 220 * motionScale(),
      easing: 'cubic-bezier(0.2, 0.7, 0.2, 1)',
      fill: 'both',
    });
    const land = () => {
      delete outline.dataset.on;
      delete end.dataset.arriving;
      slide.cancel();
    };
    slide.onfinish = land;
    // Another tab chosen mid-slide: this one lands at once, and the next sets off from where the last tab was.
    return () => {
      slide.onfinish = null;
      land();
    };
    // Only a change of tab starts a slide; a drag in progress is read, not followed.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeId]);

  if (!onSidebar && !onGoBack && tabs.length === 0) return null;
  return (
    <div className={styles.bar}>
      <div className={styles.top}>
      {onSidebar ? (
        <button
          type="button"
          className={styles.sidebar}
          onClick={onSidebar}
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
          data-over={over || undefined}
          role="tablist"
          aria-label="Notes you have open"
          onPointerDown={takeHold}
          onWheel={scrollSideways}
          onClickCapture={(event) => {
            if (!dragged.current) return;
            dragged.current = false;
            event.preventDefault();
            event.stopPropagation();
          }}
        >
          <span ref={glide} className={styles.glide} aria-hidden="true" />
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
                    <Menu open onOpenChange={(open) => !open && setMenu(null)} trigger={<span className={styles.menuAnchor} />} placement="bottom-start" aria-label={`${group.name} group`}>
                      <MenuItem onSelect={() => setRenaming(group.id)}>Rename</MenuItem>
                      <MenuSub label="Colour">
                        {WORKSPACE_HUES.map((hue) => (
                          <MenuItem key={hue} onSelect={() => change(recolourGroup(groups, group.id, hue))} icon={<span className={styles.hueDot} data-hue={hue} aria-hidden="true" />}>
                            {hue === 'ink' ? 'Ink' : hue[0]!.toUpperCase() + hue.slice(1)}
                          </MenuItem>
                        ))}
                      </MenuSub>
                      <MenuSeparator />
                      <MenuItem onSelect={() => change(ungroup(groups, group.id))}>Ungroup</MenuItem>
                      <MenuItem danger onSelect={() => onCloseTabs?.(membersOf(groups, group.id, tabs.map((t) => t.id)))}>
                        Close group
                      </MenuItem>
                    </Menu>
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
                onPointerDownCapture={(event) => {
                  pointer.current = event.pointerType;
                }}
                onContextMenu={(event) => {
                  // A mouse's right-click: the tab's own menu. A finger's hold is the drag's, so its menu is left alone.
                  if (pointer.current !== 'mouse' || !onGroups) return;
                  event.preventDefault();
                  setMenu({ kind: 'tab', id: note.id });
                }}
              >
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
                <button type="button" data-close className={styles.close} onClick={() => onClose(note.id)} aria-label={`Close ${title}`}>
                  <X size={14} strokeWidth={2.4} aria-hidden="true" />
                </button>
                {/* The group's colour along the foot of each of its tabs, as Chrome draws a group - not under the one
                    being read, which stays open onto the note. */}
                {group && !active ? <span className={styles.groupLine} data-hue={group.hue} aria-hidden="true" /> : null}
                {menu?.kind === 'tab' && menu.id === note.id ? (
                  <Menu open onOpenChange={(open) => !open && setMenu(null)} trigger={<span className={styles.menuAnchor} />} placement="bottom-start" aria-label={`${title} tab`}>
                    <MenuItem onSelect={() => startGroup(note.id)}>Add to a new group</MenuItem>
                    {groups.list.filter((g) => g.id !== groupId).length ? (
                      <MenuSub label="Add to group">
                        {groups.list
                          .filter((g) => g.id !== groupId)
                          .map((g) => (
                            <MenuItem key={g.id} onSelect={() => change(joinGroup(groups, note.id, g.id))} icon={<span className={styles.hueDot} data-hue={g.hue} aria-hidden="true" />}>
                              {g.name}
                            </MenuItem>
                          ))}
                      </MenuSub>
                    ) : null}
                    {groupId ? <MenuItem onSelect={() => change(leaveGroup(groups, note.id))}>Remove from group</MenuItem> : null}
                    <MenuSeparator />
                    <MenuItem onSelect={() => onClose(note.id)}>Close tab</MenuItem>
                  </Menu>
                ) : null}
              </span>,
            ];
          })}
          {/* After the last tab, so it moves along with the row: a new note, in a tab of its own. Not a tab itself
              (no `data-tab`), so dragging and the hold never take it for one. */}
          {onNew ? (
            <button type="button" className={styles.newTab} onClick={onNew} aria-label="New note in a new tab" title="New note">
              <Plus size={15} strokeWidth={2.2} aria-hidden="true" />
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

/**
 * A group's chip, before its first tab: its name in its colour, as Chrome draws one. A tap folds the group to the chip
 * and opens it again; a right-click or a long press opens its menu (rename, colour, ungroup, close). Folded, it says
 * how many tabs it holds. It is not a tab - no `data-tab` - so the drag and the hold pass it by.
 */
function GroupChip({
  group,
  count,
  renaming,
  onToggle,
  onMenu,
  onRename,
  menu,
}: {
  group: TabGroup;
  count: number;
  renaming: boolean;
  onToggle: () => void;
  onMenu: () => void;
  onRename: (name: string) => void;
  menu: React.ReactNode;
}) {
  const [draft, setDraft] = useState(group.name);
  useEffect(() => {
    if (renaming) setDraft(group.name);
  }, [renaming, group.name]);
  return (
    <span className={styles.group} data-hue={group.hue}>
      {renaming ? (
        <input
          className={styles.groupName}
          value={draft}
          aria-label="Group name"
          autoFocus
          onFocus={(event) => event.currentTarget.select()}
          onChange={(event) => setDraft(event.currentTarget.value)}
          onBlur={() => onRename(draft)}
          onKeyDown={(event) => {
            if (event.key === 'Enter') onRename(draft);
            else if (event.key === 'Escape') onRename(group.name);
          }}
        />
      ) : (
        <button
          type="button"
          className={styles.groupChip}
          aria-expanded={!group.collapsed}
          aria-label={`${group.name}, ${count} ${count === 1 ? 'tab' : 'tabs'}${group.collapsed ? ', folded' : ''}`}
          onClick={onToggle}
          onContextMenu={(event) => {
            event.preventDefault();
            onMenu();
          }}
        >
          {group.name}
          {group.collapsed ? <span className={styles.groupCount}>{count}</span> : null}
        </button>
      )}
      {menu}
    </span>
  );
}
