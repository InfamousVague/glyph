import type { CSSProperties } from 'react';
import styles from './Ghost.module.css';
import { GHOSTS, type GhostScene } from './ghosts.ts';
/**
 * The ghost, Ghost.md's mascot, for the app's empty pages and quiet moments (docs/GHOSTS.md).
 *
 * Matt picked the style - stipple dotwork - and the ghost: a sheet of paper with a dog-eared corner, a curl of smoke
 * from its head, and a pose for each moment. Each scene is one image, drawn as black dots on white and processed
 * into a mask: the dots are the image's alpha, and the element paints them in `currentColor`. So one file serves
 * both themes - black dots on the light paper, white on the dark - and a page sets the ghost's weight the way it sets
 * any ink (`--app-ink-3` under words, `--app-ink` where it leads). A plain `<img>` would have been black on the dark
 * theme too, where the paper is black.
 *
 * Decoration only: every ghost is `aria-hidden`, and the words beside it say what the moment is.
 */

/**
 * `lead`, where the picture leads a page (the empty home page): the column's width, up to 60% of the window's height
 * and 36rem. `small`, under or beside words: the column's width, up to 40% of the height and 28rem. `tiny`, inside a
 * card: 9rem. Matt asked for them bigger twice ("at least 4x more space", then "fill 100% width or available height
 * without going too big"), which is why the pictures are 1024px masks. They sit still; they used to drift.
 */
export type GhostSize = 'lead' | 'small' | 'tiny';

export function Ghost({
  scene,
  size = 'small',
  align = 'start',
  className,
}: {
  scene: GhostScene;
  size?: GhostSize;
  /** `center` sits it in the middle of a column, for a page that centres its words. */
  align?: 'start' | 'center';
  className?: string;
}) {
  const style = { '--ghost-image': `url("${GHOSTS[scene]}")` } as CSSProperties;
  return <span className={`${styles.ghost}${className ? ` ${className}` : ''}`} data-size={size} data-align={align} data-scene={scene} style={style} aria-hidden="true" />;
}
