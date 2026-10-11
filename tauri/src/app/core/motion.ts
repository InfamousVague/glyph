/**
 * Whether the phone has asked for less motion, for the motion the stylesheets
 * cannot reach.
 *
 * Most of the app's movement is CSS, and app.css answers
 * `prefers-reduced-motion` there once. What is left is motion a script drives -
 * the wisps' SVG filters stepped on the animation clock, the launch ghost, a
 * tab's slide, a smooth scroll asked for by name - and each of those asks here
 * before it starts. It is asked at the moment of starting, never cached: the
 * setting can change while the app is open, and the next animation should
 * already know.
 *
 * `matchMedia` is guarded because not every place the page runs has one:
 * jsdom does not, so a test that never stubbed it reads "move" rather than
 * throwing. Sixteen modules wrote this check out, three ways; two of them
 * called `window.matchMedia` unguarded.
 */

/** True when the phone asks for reduced motion (Settings > Accessibility, or the Mac's Reduce motion). */
export function prefersStill(): boolean {
  return typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches;
}
