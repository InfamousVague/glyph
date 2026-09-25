import { useEffect, useLayoutEffect, useRef, useState, type RefObject } from 'react';
import { wispSides } from '../art/wispSides.ts';
import { prefersStill } from '../core/motion.ts';
import { motionScale } from '../core/preferences.ts';

/**
 * How the tab row (notes/NoteTabs.tsx) is drawn around its tabs rather than in them: the outline of the tab being
 * read and the gap it leaves in the row's line, the slide of that outline from tab to tab, and the smoke at whichever
 * end of the row has tabs past it. All three are measured from the row as it is drawn, so they live together, apart
 * from the tabs' own markup.
 *
 * The tab draws no outline of its own (`.glide` in NoteTabs.module.css): its sides would run straight down to the
 * line, and with the tab see-through there is nothing to cover their foot where the curves take over (Matt: "Add the
 * glass effect to the tabs"). This one stops a curve's height above the line, and its curves hang from its two lower
 * corners down onto it. It is the same outline that slides from tab to tab, so a slide needs no hand-over at either
 * end.
 */

export interface TabOutline {
  /** The outline's own element, for the row to draw first. */
  glide: RefObject<HTMLSpanElement | null>;
  /** Which ends of the row have tabs past them, and so fade. */
  ends: { start: boolean; end: boolean };
  /** Puts the outline and the gap under the tab being read now: after anything moves a tab without a render. */
  place: () => void;
}

/**
 * `row` is the row's scroller; `tabs` changes whenever the row's contents do, `activeId` is the tab being read, and
 * `moving` the tab being dragged, which the outline follows rather than slides after.
 */
export function useTabOutline(row: RefObject<HTMLDivElement | null>, { tabs, activeId, moving }: { tabs: unknown; activeId: string; moving: string | null }): TabOutline {
  const glide = useRef<HTMLSpanElement>(null);
  /*
   * Measured in the row's scrolled coordinates, where both are drawn. The gap starts a pixel inside each curve's outer
   * end - the outline's 1px border, which the curves are placed inside - so the line runs on into the curve with no
   * break; placed from the tab's outer edge, it stopped a pixel short of both.
   */
  const outlineOf = (tab: HTMLElement | null | undefined) => {
    const box = row.current;
    if (!box || !tab) return null;
    const flare = parseFloat(getComputedStyle(box).getPropertyValue('--tab-flare')) || 0;
    const within = box.getBoundingClientRect();
    const at = tab.getBoundingClientRect();
    const left = at.left - within.left + box.scrollLeft;
    return {
      box: { left: `${left}px`, width: `${at.width}px`, top: `${at.top - within.top}px`, height: `${Math.max(0, at.height - flare)}px` },
      hole: { '--tab-hole-start': `${left + 1 - flare}px`, '--tab-hole-end': `${left + at.width - 1 + flare}px` },
    };
  };
  const place = () => {
    const box = row.current;
    const outline = glide.current;
    if (!box || !outline) return;
    const at = outlineOf(box.querySelector<HTMLElement>('[data-tab][data-active]'));
    if (at) {
      outline.dataset.on = '';
      Object.assign(outline.style, at.box);
    } else delete outline.dataset.on;
    for (const [name, value] of Object.entries(at?.hole ?? { '--tab-hole-start': '0px', '--tab-hole-end': '0px' })) box.style.setProperty(name, value);
  };
  // After every drawing of the row: a tab opened, closed, renamed, moved into a group or out of one each moves it.
  useLayoutEffect(place);

  /*
   * Which ends of the row go to smoke: the right while there are tabs past it, the left once the row has been scrolled
   * away from its start and never at the start itself (Matt: "Blur the right side of the tabs and the left when
   * scrolled with the wisp animation but don't apply it to the left when it's scrolled all the way"). Watched rather
   * than worked out once: tabs are added, closed, dragged and renamed, workspaces put a pill in front of a name, the
   * window changes width and the row is scrolled, and each of those can open an end or close one.
   *
   * Each open end fades (NoteTabs.module.css `[data-fade-start]`, `[data-fade-end]`) and wears the wisp
   * (art/wispSides.ts), the smoke a page makes under its header turned on its side. The filter is set here rather than
   * in the stylesheet because it is made for the row's size; where it can't be had - the wisp switched off, reduced
   * motion, a row too big for the filter's budget - the fade is left on its own.
   */
  const [ends, setEnds] = useState({ start: false, end: false });
  useEffect(() => {
    const el = row.current;
    if (!el) return undefined;
    const look = () => {
      const past = el.scrollWidth - el.clientWidth;
      const start = past > 1 && el.scrollLeft > 1;
      const end = past > 1 && el.scrollLeft < past - 1;
      setEnds((was) => (was.start === start && was.end === end ? was : { start, end }));
      el.style.filter = wispSides(el.clientWidth, el.clientHeight, start, end) ?? '';
      // A tab that changed width without the row being drawn again - its font arriving, the window resized.
      place();
    };
    look();
    const watch = new ResizeObserver(look);
    watch.observe(el);
    // Not the outline: it is sized by `look` itself, so watching it would answer every look with another.
    for (const tab of el.children) if (tab !== glide.current) watch.observe(tab);
    el.addEventListener('scroll', look, { passive: true });
    return () => {
      watch.disconnect();
      el.removeEventListener('scroll', look);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `place` reads only the row and the outline, which are refs, so a fresh one each render changes nothing worth watching again for
  }, [tabs]);

  /*
   * The tab being read slides to the one opened (Matt: "add an animation so the tab slides between items"). Measured
   * after the row has drawn the new tab as the active one, and before it is painted: the outline is sent back to the
   * last tab and slides to the new one, taking on its width as it goes, with the gap in the line beneath it. Nothing
   * slides from a tab that has closed, to or from the list, while a tab is being dragged, or for someone who has asked
   * their phone for less motion.
   */
  const wasActive = useRef(activeId);
  useLayoutEffect(() => {
    const from = wasActive.current;
    wasActive.current = activeId;
    const box = row.current;
    const outline = glide.current;
    if (!box || !outline || !from || !activeId || from === activeId || moving) return undefined;
    if (prefersStill()) return undefined;
    const tab = (id: string) => box.querySelector<HTMLElement>(`[data-tab-id="${CSS.escape(id)}"]`);
    const start = tab(from);
    const end = tab(activeId);
    if (!start || !end || typeof outline.animate !== 'function') return undefined;
    const leaving = outlineOf(start);
    const to = outlineOf(end);
    if (!leaving || !to) return undefined;
    const timing: KeyframeAnimationOptions = { duration: 220 * motionScale(), easing: 'cubic-bezier(0.2, 0.7, 0.2, 1)', fill: 'both' };
    const along = ({ left, width }: { left: string; width: string }) => ({ left, width });
    const slide = outline.animate([along(leaving.box), along(to.box)], timing);
    // The gap in the line under it travels with it (NoteTabs.module.css `@property --tab-hole-start`).
    const gap = box.animate([leaving.hole, to.hole], timing);
    const land = () => {
      slide.cancel();
      gap.cancel();
    };
    slide.onfinish = land;
    // Another tab chosen mid-slide: this one lands at once, and the next sets off from where the last tab was.
    return () => {
      slide.onfinish = null;
      land();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only a change of tab starts a slide; a drag in progress is read, not followed
  }, [activeId]);

  return { glide, ends, place };
}
