/**
 * Stand-ins while a spoken note is laid out: characters from Unicode's private use area, which no speech recogniser
 * writes, put where a mark is said and swapped for the mark once the lines are known.
 *
 * A line's name (`^ship-page`) and the bookmark (`§§`) belong at the end of their line, and a said line break at the
 * end of the sentence before it, but where a line ends is only known after the sentences have become blocks. So the
 * cue leaves a stand-in where it was said (spoken/extras.ts), and `finishLines` puts the real mark in its place at the
 * end. The raised and lowered words' glue holds a superscript to the word before it while the paragraph is still being
 * read (spoken/inline.ts).
 *
 * Defined once, here, because they are matched by code point in more places than they are made: the sentence
 * splitter treats a line break as a sentence's end, and the title rule refuses an opening sentence that holds any of
 * them (capture/markdown.ts). A regex that spelled `` out would go on matching the old character if one of these
 * ever moved.
 */

/** Where a line's name was said; the name sits between two of them. */
export const ANCHOR_MARK = '';
/** Where "bookmark this" was said. */
export const BOOKMARK_MARK = '';
/** Where "new line" was said. */
export const BREAK_MARK = '';
/** Where a raised or lowered mark joins its neighbours, while the paragraph is still being read. */
export const GLUE = '';
