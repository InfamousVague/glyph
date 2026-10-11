/**
 * The guide's pages, in order, named once. Each page's words are a component
 * of its own in guide/pages/, and Guide.tsx draws them by these names. Kept
 * out of Guide.tsx so that file exports only components (fast refresh wants
 * it that way). Settings opened the guide on the model page alone from
 * Developer's "Choose your model" until docs/DESIGN.md §138, which took the
 * row away: Recording's Model card is the same choice.
 *
 * The order is load-bearing past the dots: every page before the last is a
 * reading page, where a launch by the side key is someone who has not finished
 * (guide/tooSoon.ts). The side-key page, the marks and the habits went on
 * 2026-10-02 (docs/DESIGN.md §173): the last page hands over to the Academy.
 */
export const GUIDE_PAGES = ['welcome', 'theme', 'model', 'start'] as const;

export type GuidePage = (typeof GUIDE_PAGES)[number];
