import { useLayoutEffect, useState, type RefObject } from 'react';

/**
 * How many of a toolbar's spare buttons fit beside the ones it always shows (Matt: "I'd like the top toolbar to
 * automatically adapt to show more or less icons if there is real estate on the screen for it"): the note's tools in
 * the app's top bar (editor/NoteTools.tsx), or in the note's own header where there is no bar.
 *
 * The room is the row's width less everything else on it, so the answer does not depend on the buttons already shown
 * and settles at once rather than flickering: the row is the nearest `[data-tool-row]` around the tools (the bar's
 * control row, notes/NoteTabs.tsx, or the header's), its other controls count at their width, a group the tools sit in
 * (the Islands bar's capsule) at its width less the tools', and the open tabs, where they share the row
 * (`[data-tab-row]`), at the width of their tabs rather than the room they stretch into. It is measured again whenever
 * the row changes size or what is in it.
 */

const width = (element: Element) => element.getBoundingClientRect().width;

function gapOf(element: Element): number {
  const style = getComputedStyle(element);
  return parseFloat(style.columnGap) || parseFloat(style.gap) || 0;
}

/** The width `row`'s children take, the tools' own `slot` aside; the group that holds the slot counts without it. */
function taken(row: Element, slot: Element): number {
  const kids = [...row.children].filter((kid) => width(kid) > 0 || kid === slot || kid.contains(slot));
  let sum = Math.max(0, kids.length - 1) * gapOf(row);
  for (const kid of kids) {
    if (kid === slot) continue;
    if (kid.contains(slot)) sum += width(kid) - width(slot);
    else if (kid instanceof HTMLElement && kid.matches('[data-tab-row]')) sum += Math.min(width(kid), kid.scrollWidth);
    else sum += width(kid);
  }
  return sum;
}

/**
 * How many spare buttons of the tools at `tools` would fit, `spare` of them being on offer; a spare one drawn is marked
 * `data-tool`. None where there is nothing to measure (a test, a page with no layout), as on the narrowest phone; the
 * measure runs before the first paint, so a desktop never draws the bar without them.
 */
export function useToolRoom(tools: RefObject<HTMLElement | null>, spare: number): number {
  const [fits, setFits] = useState(0);
  useLayoutEffect(() => {
    const element = tools.current;
    const slot = element?.parentElement;
    const row = element?.closest<HTMLElement>('[data-tool-row]');
    if (!element || !slot || !row || typeof ResizeObserver !== 'function') {
      setFits(0);
      return undefined;
    }
    let frame = 0;
    const measure = () => {
      frame = 0;
      const style = getComputedStyle(row);
      const inner = row.clientWidth - (parseFloat(style.paddingLeft) || 0) - (parseFloat(style.paddingRight) || 0);
      const buttons = [...element.children].filter((child): child is HTMLElement => child instanceof HTMLElement);
      const ring = buttons.length ? width(buttons[buttons.length - 1]!) : 0;
      if (!ring) return setFits(0);
      const step = ring + gapOf(element);
      // What the tools need with no spare buttons drawn: their width now, less the spare ones shown.
      const always = width(element) - element.querySelectorAll('[data-tool]').length * step;
      const room = inner - taken(row, slot) - always - 4;
      setFits(Math.max(0, Math.min(spare, Math.floor(room / step))));
    };
    const soon = () => {
      if (!frame) frame = requestAnimationFrame(measure);
    };
    measure();
    const sizes = new ResizeObserver(soon);
    sizes.observe(row);
    const changes = new MutationObserver(soon);
    changes.observe(row, { childList: true, subtree: true });
    return () => {
      sizes.disconnect();
      changes.disconnect();
      if (frame) cancelAnimationFrame(frame);
    };
  }, [tools, spare]);
  return fits;
}
