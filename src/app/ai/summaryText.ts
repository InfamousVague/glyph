/**
 * The summary section a note carries in its body, read and written by the page (docs/DESIGN.md §127 section 2):
 * `## Summary`, one prose line, then item lines. This module is where its shape lives - finding the section by its
 * shape, placing it after the first line of words, replacing it only when unchanged, carrying ticked to-dos over -
 * and it is pure, so each rule is a test.
 *
 * Only `summaryLine` is here yet, and it answers null for every body: no summary is written until section 2 lands.
 * The shelf's caption and its aria-label read it now, so the page already says "summarized" the moment a summary
 * exists (home/TapeShelf.tsx).
 */

/** The summary's first prose line, under `## Summary`, for the shelf, the toast and the notification; null without one. */
export function summaryLine(_body: string): string | null {
  // No section is written yet. Section 2 of §127 finds `## Summary` by its shape and answers the line under it.
  return null;
}
