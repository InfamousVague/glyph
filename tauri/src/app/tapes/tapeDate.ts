/**
 * The day and the month a tape was recorded, "26 Sep", in the device's own order: the label's small print on the
 * tape at the top of a note (tapes/NoteTape.tsx) and the line under a cassette on the home page's shelf
 * (home/TapeShelf.tsx). One formatter for both, so the two never drift.
 */
export const tapeDate = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short' });
