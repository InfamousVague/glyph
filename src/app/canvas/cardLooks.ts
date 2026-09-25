import type { CSSProperties } from 'react';
import type { CanvasColor, CanvasNode } from './jsonCanvas.ts';

/**
 * What a card is, as it is drawn (canvas/Card.tsx, canvas/Minimap.tsx): its colour in the page's own hues, the note
 * a file card names, whether it is one of Ghost.md's own pictures, and whether a card of words is only a table. The
 * format says what a node holds (jsonCanvas.ts); this says what the screen makes of it.
 */

/** The page's hues (ink.css `[data-hue]`), which are what a workspace wears too (core/workspaces.ts). */
export type CanvasHue = 'rose' | 'ember' | 'amber' | 'moss' | 'sea' | 'violet';

/**
 * The spec's six presets - red, orange, yellow, green, cyan, purple, their exact values "intentionally not defined"
 * so each app paints them its own way - as the page's own hues (Matt: workspace hues, not a palette of the canvas's
 * own). A hex colour is a colour someone chose in Obsidian and is kept as it is.
 */
export function paintOf(color: CanvasColor | undefined): { hue: CanvasHue } | { hex: string } | null {
  switch (color) {
    case '1':
      return { hue: 'rose' };
    case '2':
      return { hue: 'ember' };
    case '3':
      return { hue: 'amber' };
    case '4':
      return { hue: 'moss' };
    case '5':
      return { hue: 'sea' };
    case '6':
      return { hue: 'violet' };
    default:
      return color && color.startsWith('#') ? { hex: color } : null;
  }
}

/**
 * A colour as a drawn element wears it: a preset as the page's `data-hue`, a hex as `--app-space` on its style,
 * which is what the canvas's stylesheets paint both from (CanvasView.module.css, Minimap.module.css). Nothing for no
 * colour.
 */
export function paintProps(color: CanvasColor | undefined): { hue?: CanvasHue; style?: CSSProperties } {
  const paint = paintOf(color);
  if (!paint) return {};
  return 'hue' in paint ? { hue: paint.hue } : { style: { '--app-space': paint.hex } as CSSProperties };
}

/** A file node's name as a note's title: the last part of the path, without `.md`. `Plans/Cabin trip.md` is "Cabin trip". */
export function fileTitle(file: string): string {
  const name = file.split('/').pop() ?? file;
  return name.replace(/\.md$/i, '');
}

/** Whether a file node points at a picture rather than a note. */
export function isImageFile(file: string): boolean {
  return /\.(png|jpe?g|gif|webp|avif|svg|bmp)$/i.test(file);
}

/**
 * A file node that is one of Ghost.md's own pictures: its name in the picture store (core/images.ts), or null. A
 * picture from another vault has a folder in its name and no such picture here, and is drawn as being elsewhere.
 */
export function ownPicture(node: CanvasNode): string | null {
  return node.type === 'file' && isImageFile(node.file) && !node.file.includes('/') ? node.file : null;
}

/** Whether a card of words is nothing but a table, which is then drawn edge to edge (canvas/Card.tsx). */
export function isOnlyTable(text: string): boolean {
  const lines = text.trim().split('\n');
  return lines.length >= 2 && lines.every((line) => /^\s*\|.*\|\s*$/.test(line));
}
