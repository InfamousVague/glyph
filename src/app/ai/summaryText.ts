/**
 * The summary section a note carries in its body, as the page reads it (docs/DESIGN.md §127 section 2): `## Summary`
 * and the line under it. Only `summaryLine` is here yet, and it answers null for every body: no summary is written
 * until section 2 lands, and that section's shape, place and rules are its to write here when it does. The shelf's
 * caption and its aria-label read it now, so the page already says "summarized" the moment a summary exists
 * (home/TapeShelf.tsx).
 */

/** The summary's first prose line, under `## Summary`, for the shelf, the toast and the notification; null without one. */
export function summaryLine(_body: string): string | null {
  // No section is written yet. Section 2 of §127 finds `## Summary` by its shape and answers the line under it.
  return null;
}
