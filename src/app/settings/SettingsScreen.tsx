import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { ChevronRight } from '@glacier/icons';
import { ArrowLeft } from '../art/Icons.tsx';
import { onBack } from '../core/back.ts';
import { useSwipeNav } from '../core/swipe.ts';
import { useWispEdge } from '../art/wispEdge.ts';
import { useSidebar } from '../core/useWideScreen.ts';
import './settings.css';

/**
 * The settings surface: a full-screen page that opens on the list of
 * sections and pushes into one. The shape is AttackFM's MobileSettings; the
 * words are Glyph's: `← Notes` in the top bar to leave, "Settings" as the
 * page's title over the clustered list, a section's own word over its pane,
 * and `← Settings` to come back out of one. Both titles are title-sized rather
 * than display-sized, so the rows start near the top (Matt: "add back button
 * at the top of settings and make settings header smaller … make settings in
 * top bar like the ← notes").
 *
 * The page can also be left the way a person came: the phone's back gesture,
 * or a swipe to the right across it, steps out of a pane and then closes the
 * page; a swipe to the left goes forward again, back into the pane just left. One handler, registered while the page is open, answers by depth.
 * Every fresh open lands on the list, and the rows arrive one after another.
 */

export interface SettingsSection {
  id: string;
  label: string;
  icon: ReactNode;
  content: ReactNode;
  /** The row's second line: the section's state, read live. */
  summary?: string;
  /** Rows with the same group share one card. */
  group: number;
}

interface SettingsScreenProps {
  open: boolean;
  onClose: () => void;
  sections: SettingsSection[];
  /** Asked from inside a pane: land on another one (About's knock opens Developer). */
  goTo?: { id: string; nonce: number } | null;
}

/**
 * Each section's colour (Matt: "Add colors to the icons throughout the settings page make the icon background
 * semitransparent in the color and the icon full opacity on the same color"): its row's chip in the list, and the icons
 * on its own page. Names, not values: settings.css draws each, a shade deeper on the light page than on the dark.
 */
const HUES: Record<string, string> = {
  account: 'blue',
  type: 'indigo',
  theme: 'purple',
  recording: 'red',
  formatting: 'orange',
  feel: 'teal',
  'plugin:notion': 'graphite',
  'plugin:github': 'graphite',
  'plugin:claude': 'coral',
  plugins: 'green',
  animations: 'pink',
  cheatsheet: 'yellow',
  about: 'grey',
  developer: 'brown',
  'test-results': 'mint',
};

/** A section's colour by its id; a section added later without one is grey. */
function hueOf(id: string): string {
  return HUES[id] ?? 'grey';
}

export function SettingsScreen({ open, onClose, sections, goTo }: SettingsScreenProps) {
  const [activeId, setActiveId] = useState<string | null>(null);
  // Which way the pane came in: pushed from the right going deeper, from the
  // left coming back, so the motion says which.
  const [direction, setDirection] = useState<'in' | 'out'>('in');
  // The pane a back step just left, for a forward swipe to return to.
  const [left, setLeft] = useState<string | null>(null);
  const root = useRef<HTMLDivElement>(null);
  // The list or the pane showing goes to smoke under its header (art/wispEdge.ts).
  const scroller = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) {
      setActiveId(null);
      setLeft(null);
    }
  }, [open]);

  useEffect(() => {
    if (open && goTo) {
      setDirection('in');
      setActiveId(goTo.id);
    }
  }, [open, goTo]);

  // A section that left the array (developer mode switched off inside it)
  // drops back to the list rather than onto a pane that no longer exists.
  const active = sections.find((s) => s.id === activeId) ?? null;
  useEffect(() => {
    if (activeId && !active) setActiveId(null);
  }, [activeId, active]);

  const enter = useCallback((id: string) => {
    setDirection('in');
    setLeft(null);
    setActiveId(id);
  }, []);

  /**
   * On a window with room for the sidebar - a desktop, a large tablet, the Fold opened - Settings is a split view
   * (Matt: "on full screen and desktop and larger tablets show a split view for settings with the sidebar on the left
   * and the settings sections on the right"): the sections down the left, the chosen one's page on the right, and
   * the first section's page until one is chosen. There is no list page to go back to, so back leaves Settings.
   * Exactly the sidebar's line (core/useWideScreen.ts `useSidebar`), so the app changes shape once.
   */
  const split = useSidebar();

  const back = useCallback(() => {
    if (split) {
      onClose();
      return;
    }
    if (activeId !== null) {
      setDirection('out');
      setLeft(activeId);
      setActiveId(null);
    } else {
      onClose();
    }
  }, [activeId, onClose, split]);

  const forward = useCallback(() => {
    if (activeId === null && left && sections.some((s) => s.id === left)) {
      setDirection('in');
      setActiveId(left);
    }
  }, [activeId, left, sections]);

  useEffect(() => {
    if (!open) return undefined;
    return onBack(() => {
      back();
      return true;
    });
  }, [open, back]);

  useSwipeNav(root, { onBack: back, onForward: forward }, open);
  useWispEdge(scroller, open && (active?.id ?? 'list'));

  if (!open) return null;

  const clusters = sections.reduce<SettingsSection[][]>((groups, section) => {
    const last = groups[groups.length - 1];
    if (last && last[0]!.group === section.group) last.push(section);
    else groups.push([section]);
    return groups;
  }, []);

  let row = 0;
  /** The sections, clustered into cards: the list page on a phone, the left column of the split view. */
  const list = (current: string | null) => (
    <>
      {clusters.map((cluster) => (
        <div key={cluster[0]!.id} className="settingsScreen__cluster">
          <div className="settingsScreen__group">
            {cluster.map((section) => (
              <button
                key={section.id}
                type="button"
                className="settingsScreen__row"
                style={{ '--i': row++ } as React.CSSProperties}
                aria-current={section.id === current ? 'page' : undefined}
                data-current={section.id === current || undefined}
                onClick={() => enter(section.id)}
              >
                <span className="settingsScreen__rowIcon" data-hue={hueOf(section.id)}>
                  {section.icon}
                </span>
                <span className="settingsScreen__rowText">
                  <span className="settingsScreen__rowLabel">{section.label}</span>
                  {section.summary ? <span className="settingsScreen__rowSummary">{section.summary}</span> : null}
                </span>
                {split ? null : <ChevronRight size={18} className="settingsScreen__rowChevron" />}
              </button>
            ))}
          </div>
        </div>
      ))}
    </>
  );

  if (split) {
    const shown = active ?? sections[0] ?? null;
    return (
      <div ref={root} className="settingsScreen" role="dialog" aria-modal="true" aria-label="Settings" data-layout="split" data-view="pane" data-direction={direction}>
        <header className="settingsScreen__head">
          <button type="button" className="app-word settingsScreen__headWord" onClick={onClose} aria-label="Back to your notes">
            <ArrowLeft /> Settings
          </button>
        </header>
        <div className="settingsScreen__split">
          <nav className="settingsScreen__list settingsScreen__side" aria-label="Settings sections">
            {list(shown?.id ?? null)}
          </nav>
          {shown ? (
            <div ref={scroller} className="settingsScreen__pane" key={shown.id} data-hue={hueOf(shown.id)}>
              <h1 className="settingsScreen__display">{shown.label}</h1>
              {shown.content}
            </div>
          ) : null}
        </div>
      </div>
    );
  }

  return (
    <div ref={root} className="settingsScreen" role="dialog" aria-modal="true" aria-label="Settings" data-view={active ? 'pane' : 'list'} data-direction={direction}>
      {active ? (
        <>
          <header className="settingsScreen__head">
            <button type="button" className="app-word settingsScreen__headWord" onClick={back}>
              <ArrowLeft /> Settings
            </button>
          </header>
          <div ref={scroller} className="settingsScreen__pane" key={active.id} data-hue={hueOf(active.id)}>
            <h1 className="settingsScreen__display">{active.label}</h1>
            {active.content}
          </div>
        </>
      ) : (
        <>
          {/*
            The way out and the screen's name in one row (Matt: "move settings back arrow next to settings label,
            replace the back to notes with just putting the settings text there, remove some of the space on the
            top"). It read "← Notes" over a display-sized "Settings" underneath, which named the screen twice and
            spent a third of the first page saying so. The arrow still leaves for the notes, which is what it is
            told to say aloud.
          */}
          <header className="settingsScreen__head">
            <button type="button" className="app-word settingsScreen__headWord" onClick={onClose} aria-label="Back to your notes">
              <ArrowLeft /> Settings
            </button>
          </header>
          <nav ref={scroller} className="settingsScreen__list" key="list">
            {list(null)}
            {left ? <p className="settingsScreen__hint">Swipe left to go back into {sections.find((s) => s.id === left)?.label ?? 'the page'}.</p> : null}
          </nav>
        </>
      )}
    </div>
  );
}
