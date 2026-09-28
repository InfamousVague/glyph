/**
 * The guide's pages, in order, named once. Each page's words are a component
 * of its own in guide/pages/, and Guide.tsx draws them by these names. Kept
 * out of Guide.tsx so that file exports only components (fast refresh wants
 * it that way). Settings opened the guide on the model page alone from
 * Developer's "Choose your model" until docs/DESIGN.md §138, which took the
 * row away: Recording's Model card is the same choice.
 *
 * The order is load-bearing past the dots: every page before 'sidekey' is a
 * reading page, where a press of the side key is someone who has not finished
 * (guide/tooSoon.ts), so a page put in before it changes which launches the
 * guide refuses.
 */
export const GUIDE_PAGES = ['welcome', 'theme', 'model', 'sidekey', 'marks', 'tips'] as const;

export type GuidePage = (typeof GUIDE_PAGES)[number];
