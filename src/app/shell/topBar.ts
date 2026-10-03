import type { TopBar } from '../core/preferences.ts';

/**
 * The six ways the top bar can be laid out (core/preferences.ts `TopBar`; docs/DESIGN.md §178), in the order Settings
 * offers them, each with the sentence Settings says under its picture (settings/TopBarCards.tsx). What each one is, in
 * markup and stylesheet, is notes/NoteTabs.tsx; this is what the shell needs to know of them: how many lines the bar
 * is, and whether the tabs are at the foot of the screen instead.
 */
export const TOP_BAR_STYLES: readonly { id: TopBar; label: string; hint: string }[] = [
  { id: 'classic', label: 'Classic', hint: 'The controls on one line, the open notes as tabs on the next.' },
  { id: 'ledger', label: 'Ledger', hint: 'The tabs on top, as a browser has them; the open one holds its tools on the line below.' },
  { id: 'strip', label: 'Strip', hint: 'Everything on one line: the tabs scroll between the controls.' },
  { id: 'masthead', label: 'Masthead', hint: 'Words in place of rings, and the tabs as an index line under a rule.' },
  { id: 'islands', label: 'Islands', hint: 'No bar: three glass capsules float over the page, the tabs in one of them.' },
  { id: 'thumb', label: 'Thumb', hint: 'The open note named in the bar; the tabs at the foot of the screen, in thumb reach.' },
];

/**
 * How many lines the bar is, which is how tall it is (app.css `--app-tabs`): one, or the controls with the tabs under
 * them. The Strip is always one line, the tabs inside it; so is Thumb, whose tabs are at the foot. The Ledger's tab
 * row is always drawn, with Home pinned in it, so it is always two. The rest are two only with a note open.
 */
export function barRows(style: TopBar, open: number): 'on' | 'rows' {
  if (style === 'strip' || style === 'thumb') return 'on';
  if (style === 'ledger') return 'rows';
  return open > 0 ? 'rows' : 'on';
}

/** Whether a strip of tabs stands at the foot of the screen (Thumb, with a note open), which every screen pads for. */
export function barFoot(style: TopBar, open: number): boolean {
  return style === 'thumb' && open > 0;
}
