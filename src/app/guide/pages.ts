/**
 * The guide's pages, in order, named once so Settings can open the guide on
 * one of them without knowing the order. Kept out of Guide.tsx so that file
 * exports only components (fast refresh wants it that way).
 */
export const GUIDE_PAGES = ['welcome', 'theme', 'model', 'sidekey', 'markdown', 'tips'] as const;

export type GuidePage = (typeof GUIDE_PAGES)[number];

/** The page that picks the formatting model. */
export const GUIDE_MODEL_PAGE: number = GUIDE_PAGES.indexOf('model');
