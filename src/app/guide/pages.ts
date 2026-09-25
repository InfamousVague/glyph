/**
 * The guide's pages, in order, named once so Settings can open the guide on
 * one of them without knowing the order. Each page's words are a component of
 * its own in guide/pages/, and Guide.tsx draws them by these names. Kept out
 * of Guide.tsx so that file exports only components (fast refresh wants it
 * that way).
 *
 * The order is load-bearing past the dots: every page before 'sidekey' is a
 * reading page, where a press of the side key is someone who has not finished
 * (guide/tooSoon.ts), so a page put in before it changes which launches the
 * guide refuses.
 */
export const GUIDE_PAGES = ['welcome', 'theme', 'model', 'sidekey', 'marks', 'tips'] as const;

export type GuidePage = (typeof GUIDE_PAGES)[number];

/** The page that picks the formatting model. */
export const GUIDE_MODEL_PAGE: number = GUIDE_PAGES.indexOf('model');

/** The table of every mark, with an example of each (guide/MarksTable.tsx). */
export const GUIDE_MARKS_PAGE: number = GUIDE_PAGES.indexOf('marks');
