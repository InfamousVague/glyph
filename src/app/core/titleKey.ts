/**
 * A title as it is matched: what a person said, not what they typed.
 *
 * Lower case, every run of anything that is not a letter or a digit one space,
 * the ends trimmed - so "The Oaks!" and "the oaks" are one note, and a title
 * said aloud finds the note however it was punctuated. Every place that asks
 * whether two titles are the same note asks it this way: a link and the note
 * it opens (editor/wikiLinks.ts `sameTitle`), a book's index and its pages
 * (book/book.ts), the aside's groups (aside/aside.ts), a spoken link and the
 * titles it could mean (capture/markdown.ts). Four copies of it lived in those
 * modules, one of them written out again to dodge an import cycle.
 *
 * A leaf with no imports on purpose, so that nothing which needs the key can
 * make a cycle by importing it.
 */

/** `title` reduced to what is matched: "  The Oaks!  " -> "the oaks". Empty for a title with no letters or digits. */
export function titleKey(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}
