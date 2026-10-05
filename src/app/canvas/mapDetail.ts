/**
 * What a card looks like small (canvas/Minimap.tsx): its words as the bars a page of text makes when it is too far
 * away to read - a heavier bar for a heading, a dot and a bar for a list's line, a paragraph as the lines it wraps
 * to, a table as its rows. Matt: "the canvas minimap could also be far more detailed with modern displays": a card
 * was one flat block, and on a screen of three pixels to the point there is room in that block for the shape of
 * what is written on it, which is what tells one card from the next at a glance.
 *
 * Pure, and in the card's own box: every bar is placed from the card's top-left corner, in the canvas's pixels, so
 * the map draws them inside the same transform as the card and nothing is measured on the screen.
 */

export interface MapBar {
  x: number;
  y: number;
  width: number;
  height: number;
  /** A heading, or a note's title: drawn heavier. */
  strong?: boolean;
}

/** The room inside a card, the pitch of its lines and the weight of a line, in the canvas's pixels: about what the card itself draws. */
const PAD = 14;
const PITCH = 20;
const BAR = 8;
const HEADING = 12;
/** A character's width, near enough, at the size a card's words are drawn. */
const CHAR = 7;
/** No card is drawn with more bars than this: past it they are a grey, and a canvas may hold hundreds of cards. */
const MOST = 28;

/** The bars for a card of words this size. Nothing for a card too small to hold a line. */
export function wordBars(text: string, width: number, height: number): MapBar[] {
  const room = width - PAD * 2;
  const bars: MapBar[] = [];
  if (room < 24) return bars;
  let y = PAD;
  const fits = (h: number) => y + h <= height - PAD / 2 && bars.length < MOST;
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line) {
      // A blank line is a paragraph's gap, half a line of air.
      if (bars.length) y += PITCH / 2;
      continue;
    }
    // A fence's own lines draw nothing: what is inside it does.
    if (/^(```|~~~)/.test(line)) continue;
    const heading = /^#{1,6}\s+(.*)$/.exec(line);
    if (heading) {
      if (!fits(HEADING)) break;
      bars.push({ x: PAD, y, width: Math.min(room, Math.max(40, heading[1]!.length * CHAR * 1.35)), height: HEADING, strong: true });
      y += PITCH + 6;
      continue;
    }
    // A table's row runs the card's width; its rule under the head is the row's own line.
    if (/^\|.*\|$/.test(line)) {
      if (/^\|[\s:|-]+\|$/.test(line)) continue;
      if (!fits(BAR)) break;
      bars.push({ x: PAD, y, width: room, height: BAR });
      y += PITCH;
      continue;
    }
    const item = /^(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?(.*)$/.exec(line);
    const words = item ? item[1]! : line;
    const indent = item ? 16 : 0;
    if (item) {
      if (!fits(BAR)) break;
      bars.push({ x: PAD, y, width: BAR, height: BAR });
    }
    // A paragraph wraps: full lines, then what is left over, three lines of it at the most.
    let left = Math.max(24, words.length * CHAR);
    const across = room - indent;
    for (let wrapped = 0; left > 0 && wrapped < 3; wrapped += 1) {
      if (!fits(BAR)) return bars;
      const w = Math.min(across, left);
      bars.push({ x: PAD + indent, y, width: Math.max(16, w), height: BAR });
      left -= across;
      y += PITCH;
    }
  }
  return bars;
}

/** The bars for a note card: its title, heavier, and a few lines of the note under it. */
export function noteBars(title: string, width: number, height: number): MapBar[] {
  const room = width - PAD * 2;
  if (room < 24 || height < PAD * 2 + HEADING) return [];
  const bars: MapBar[] = [{ x: PAD, y: PAD, width: Math.min(room, Math.max(40, title.length * CHAR * 1.2)), height: HEADING, strong: true }];
  const widths = [1, 0.86, 0.62];
  for (let n = 0; n < widths.length; n += 1) {
    const y = PAD + HEADING + 12 + n * PITCH;
    if (y + BAR > height - PAD / 2) break;
    bars.push({ x: PAD, y, width: room * widths[n]!, height: BAR });
  }
  return bars;
}

/** A rectangle with round corners as an SVG path, for cutting the screen's box out of the map's shade. */
export function roundedBox(x: number, y: number, width: number, height: number, radius: number): string {
  const r = Math.max(0, Math.min(radius, width / 2, height / 2));
  return `M${x + r} ${y}h${width - r * 2}a${r} ${r} 0 0 1 ${r} ${r}v${height - r * 2}a${r} ${r} 0 0 1 ${-r} ${r}h${-(width - r * 2)}a${r} ${r} 0 0 1 ${-r} ${-r}v${-(height - r * 2)}a${r} ${r} 0 0 1 ${r} ${-r}Z`;
}
