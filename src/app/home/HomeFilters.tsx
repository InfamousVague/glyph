import { useEffect, useId, useRef, useState, type FocusEvent, type KeyboardEvent, type ReactNode } from 'react';
import { flushSync } from 'react-dom';
import { Check, FileText, Search, SlidersHorizontal, X } from '@glacier/icons';
import { Popover } from '@glacier/react';
import { useBack } from '../core/back.ts';
import { chooseWorkspace, useWorkspaces, type Workspace } from '../core/workspaces.ts';
import { Grid, Notebook, Pin, Plus, Workspace as Folder } from '../art/Icons.tsx';
import { HOME_FILTERS, type HomeFilter } from './homeLayout.ts';
import look from './HomeLayouts.module.css';

/**
 * The home page's search, and its filters beside it (docs/DESIGN.md §148; Matt: "move the all, notebooks, notes,
 * pinned, and the workspaces into filters next to the search bar"). They were two rows of pills under the search -
 * All, Notebooks, Notes, Pinned, then the workspaces - which put two rows of choices between the search and the notes.
 *
 * Now the search has one button at its end, and the choices open from it in a panel: what to show, with how many of
 * each, and which workspace, with a new one and the chosen one's name and colour to change. Each is a radio, so a
 * person picks both in one opening; a tap outside, Escape, the phone's back, or the keyboard leaving it closes it. What
 * is chosen is never hidden: the button is inked while anything is, and under the search a chip names each choice, its
 * cross taking it off. With everything shown, nothing stands under the search.
 *
 * The keyboard is never dropped: the panel opens on the chosen Show, a chip's cross hands focus to the next chip or to
 * the button, and the workspace sheet hands it back to the button when it closes (HomeScreen.tsx).
 */

interface HomeFiltersProps {
  query: string;
  onQuery: (query: string) => void;
  filter: HomeFilter;
  onFilter: (filter: HomeFilter) => void;
  /** How many of each filter's notes, the archive left out and the search not applied (home/homeLayout.ts `homeCounts`). */
  counts: Record<HomeFilter, number>;
  /** A workspace to rename, colour or remove, or a new one (notes/WorkspaceSheet.tsx). */
  onManage: (which: Workspace | 'new') => void;
}

export function HomeFilters({ query, onQuery, filter, onFilter, counts, onManage }: HomeFiltersProps) {
  const field = useRef<HTMLInputElement>(null);
  const row = useRef<HTMLDivElement>(null);
  const chipRow = useRef<HTMLDivElement>(null);
  const id = useId();
  const [open, setOpen] = useState(false);
  // How tall the panel may be: the room under the button, measured as it opens, since the kit never clamps a panel's
  // height and a long list of workspaces would put New workspace below the screen's edge.
  const [room, setRoom] = useState<number | null>(null);
  // The kit wires the button's own ref, so it is found in its row rather than held.
  const trigger = () => row.current?.querySelector<HTMLButtonElement>('button[aria-haspopup="dialog"]') ?? null;
  const openPanel = (next: boolean) => {
    const below = trigger()?.getBoundingClientRect().bottom;
    if (next && below !== undefined) setRoom(Math.max(160, window.innerHeight - below - 44));
    setOpen(next);
  };
  // A chip's cross: the filter comes off, and the keyboard goes to the chip after it, or to the button.
  const takeOff = (clear: () => void) => {
    flushSync(clear);
    (chipRow.current?.querySelector<HTMLButtonElement>('button') ?? trigger())?.focus();
  };
  // The phone's back gesture closes the panel before it leaves the page; the kit's panel closes on Escape itself.
  useBack(open, () => setOpen(false));
  const { list: spaces, current } = useWorkspaces();
  const shown = HOME_FILTERS.find((each) => each.id === filter);
  const chosen = [filter !== 'all' ? shown?.label : null, current?.name].filter(Boolean).join(', ');
  const manage = (which: Workspace | 'new') => {
    setOpen(false);
    onManage(which);
  };
  // A workspace's radios: every workspace, then each by name.
  const places: { id: string | null; name: string; hue?: string }[] = [{ id: null, name: 'Every workspace' }, ...spaces.map((w) => ({ id: w.id, name: w.name, hue: w.hue ?? 'ink' }))];

  return (
    <>
      <div ref={row} className={look.searchRow}>
        <div className={look.search}>
          <Search size={17} strokeWidth={2.2} className={look.searchMark} aria-hidden="true" />
          <input
            ref={field}
            type="search"
            className={look.field}
            value={query}
            onChange={(event) => onQuery(event.target.value)}
            placeholder="Search notebooks and notes"
            aria-label="Search notebooks and notes"
            autoComplete="off"
            autoCorrect="off"
            autoCapitalize="off"
            spellCheck={false}
            enterKeyHint="search"
          />
          {query ? (
            <button
              type="button"
              className={look.clear}
              aria-label="Clear the search"
              onClick={() => {
                onQuery('');
                field.current?.focus();
              }}
            >
              <X size={14} strokeWidth={2.4} aria-hidden="true" />
            </button>
          ) : null}
        </div>
        <Popover
          open={open}
          onOpenChange={openPanel}
          placement="bottom-end"
          aria-label="Filters"
          className={look.panel}
          trigger={
            <button type="button" className={look.filterButton} data-on={chosen ? '' : undefined} aria-label={chosen ? `Filters: ${chosen}` : 'Filters'}>
              <SlidersHorizontal size={18} strokeWidth={2.2} aria-hidden="true" />
            </button>
          }
        >
          <PanelBody room={room} onLeave={() => setOpen(false)} isTrigger={(el) => el === trigger()}>
            <p className={look.panelHeading} id={`${id}-show`}>
              Show
            </p>
            <div className={look.choices} role="radiogroup" aria-labelledby={`${id}-show`}>
              {HOME_FILTERS.map((each, at) => (
                <button
                  key={each.id}
                  type="button"
                  role="radio"
                  aria-checked={filter === each.id}
                  tabIndex={filter === each.id ? 0 : -1}
                  className={look.choice}
                  onClick={() => onFilter(each.id)}
                  onKeyDown={(event) => step(event, at, HOME_FILTERS.length, (to) => onFilter(HOME_FILTERS[to]!.id))}
                >
                  <ShowMark filter={each.id} />
                  <span className={look.choiceWord}>{each.label}</span>
                  <span className={look.choiceCount}>{counts[each.id]}</span>
                  <Check size={16} strokeWidth={2.4} className={look.choiceTick} aria-hidden="true" />
                </button>
              ))}
            </div>
            <p className={look.panelHeading} id={`${id}-space`}>
              Workspace
            </p>
            {spaces.length ? (
              <div className={look.choices} role="radiogroup" aria-labelledby={`${id}-space`}>
                {places.map((place, at) => {
                  const on = (current?.id ?? null) === place.id;
                  return (
                    <button
                      key={place.id ?? 'every'}
                      type="button"
                      role="radio"
                      aria-checked={on}
                      tabIndex={on ? 0 : -1}
                      className={look.choice}
                      data-hue={place.hue}
                      onClick={() => chooseWorkspace(place.id)}
                      onKeyDown={(event) => step(event, at, places.length, (to) => chooseWorkspace(places[to]!.id))}
                    >
                      {place.hue ? <span className={look.hueDot} aria-hidden="true" /> : <Folder className={look.choiceMark} />}
                      <span className={look.choiceWord}>{place.name}</span>
                      <Check size={16} strokeWidth={2.4} className={look.choiceTick} aria-hidden="true" />
                    </button>
                  );
                })}
              </div>
            ) : (
              <p className={look.panelNote}>Notes filed in a workspace show together. A note made while one is chosen goes there.</p>
            )}
            <div className={look.panelActions}>
              <button type="button" className={look.panelAction} onClick={() => manage('new')}>
                <Plus className={look.choiceMark} />
                New workspace
              </button>
              {current ? (
                <button type="button" className={look.panelAction} onClick={() => manage(current)}>
                  <span className={look.hueDot} data-hue={current.hue ?? 'ink'} aria-hidden="true" />
                  Edit {current.name}
                </button>
              ) : null}
            </div>
          </PanelBody>
        </Popover>
      </div>
      {chosen ? (
        <div ref={chipRow} className={look.chips} role="group" aria-label="Filters on">
          {filter !== 'all' && shown ? (
            <button type="button" className={look.chip} onClick={() => takeOff(() => onFilter('all'))} aria-label={`${shown.label}: show everything`}>
              {filter === 'pinned' ? <Pin className={look.chipMark} /> : null}
              {shown.label}
              <X size={13} strokeWidth={2.4} aria-hidden="true" />
            </button>
          ) : null}
          {current ? (
            <button type="button" className={look.chip} data-hue={current.hue ?? 'ink'} onClick={() => takeOff(() => chooseWorkspace(null))} aria-label={`${current.name}: every workspace`}>
              <span className={look.hueDot} aria-hidden="true" />
              {current.name}
              <X size={13} strokeWidth={2.4} aria-hidden="true" />
            </button>
          ) : null}
        </div>
      ) : null}
    </>
  );
}

/**
 * Each Show choice's mark at its left, the one its things wear on the page (Matt: "all, notebooks, notes and 'Every
 * workspace' should have left icons"): the grid of every note, as the foot's All notes has it; a notebook; a page; the
 * pin. Every workspace wears the workspace's folder, where each workspace wears its colour.
 */
function ShowMark({ filter }: { filter: HomeFilter }) {
  if (filter === 'all') return <Grid className={look.choiceMark} />;
  if (filter === 'books') return <Notebook className={look.choiceMark} />;
  if (filter === 'notes') return <FileText size="1em" strokeWidth={2.2} className={look.choiceMark} aria-hidden="true" />;
  return <Pin className={look.choiceMark} />;
}

/**
 * The panel's contents, which it scrolls when they are taller than the room under the button. It opens on the chosen
 * Show, where the arrow keys work at once; the kit focuses the panel itself as it opens, so this waits a tick to follow
 * it. The keyboard leaving it for the page - Tab past its end, Shift+Tab before its start - closes it, since the kit
 * closes it only for a press outside or Escape. Leaving for nowhere (the window losing focus) leaves it open.
 */
function PanelBody({ room, onLeave, isTrigger, children }: { room: number | null; onLeave: () => void; isTrigger: (el: Element) => boolean; children: ReactNode }) {
  const body = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const timer = window.setTimeout(() => body.current?.querySelector<HTMLButtonElement>('[role="radio"][aria-checked="true"]')?.focus({ preventScroll: true }), 0);
    return () => window.clearTimeout(timer);
  }, []);
  const blur = (event: FocusEvent<HTMLDivElement>) => {
    const to = event.relatedTarget;
    if (!to || isTrigger(to) || event.currentTarget.closest('[role="dialog"]')?.contains(to)) return;
    onLeave();
  };
  return (
    <div ref={body} className={look.panelBody} style={room ? { maxBlockSize: room } : undefined} onBlur={blur}>
      {children}
    </div>
  );
}

/** The arrow keys in a radiogroup: the next or the previous choice, round the ends, chosen as it is reached, and focused. */
function step(event: KeyboardEvent<HTMLButtonElement>, at: number, count: number, choose: (to: number) => void) {
  const by = event.key === 'ArrowDown' || event.key === 'ArrowRight' ? 1 : event.key === 'ArrowUp' || event.key === 'ArrowLeft' ? -1 : 0;
  if (!by) return;
  event.preventDefault();
  const to = (at + by + count) % count;
  choose(to);
  const radios = event.currentTarget.parentElement?.querySelectorAll<HTMLButtonElement>('[role="radio"]');
  radios?.[to]?.focus();
}
