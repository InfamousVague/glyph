import { withFrontMatterValue } from '../app/core/frontMatter.ts';

/**
 * A page as the reader draws it: without the `title:` and `date:` a journal's entry is made with (book/journal.ts
 * `entryBody`), nor the `look:` a note is drawn by (core/look.ts), which the page draws instead of saying. A note's own
 * editor folds its front matter to one quiet line, but a read-only one draws it as it is, so every entry shared, a
 * journal being shared an entry at a time, opened on four lines of keys above its date. The heading names the page,
 * and the entry says its day and its time in its words. Any other key stays as it was sent.
 */
export function drawnBody(body: string): string {
  return ['title', 'date', 'look'].reduce((next, key) => withFrontMatterValue(next, key, null), body);
}
