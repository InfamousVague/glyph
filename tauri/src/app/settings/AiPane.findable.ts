import type { SettingsFindable } from './settingsSearch.ts';

/**
 * What Settings' search finds on AI (settings/AiPane.tsx), by the names the page draws, in its order. The model was on
 * Recording until it moved here, so it keeps that page's words - the Formatting page's (ModelCard.tsx was it until
 * docs/DESIGN.md §138) and the Developer page's "Choose your model", both of which went - and adds the switch for
 * filling blanks on their own.
 *
 * Listed only where a model runs (the app, not an iPhone): a browser has no model to fetch and an iPhone runs none.
 */
export function findable(): SettingsFindable[] {
  return [
    { name: 'Model', words: 'ai llm download formatting format enhance summarize choose your qwen gemma storage remove' },
    { name: 'Fill blanks on their own', words: 'auto fill blanks automatic weather live facts idle' },
  ];
}
