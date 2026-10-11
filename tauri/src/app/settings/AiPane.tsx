import { ModelCard } from './ModelCard.tsx';

/**
 * AI: the language model the app runs on this device, and how it fills a note's blanks. The Model card (ModelCard.tsx)
 * was on Recording until Matt asked for an AI section of its own ("move the Model sections into an AI setting
 * section"): the model writes the summaries and the review, but it also runs Format, Summarize and Enhance on a note
 * and fills its blanks, so it reads better under AI than under Recording. The card carries the model picker, what each
 * takes and the room they hold, and the switch for filling blanks on their own (editor/blanks.ts).
 *
 * Listed only where a model runs: the app on Android and the Mac, never a browser or an iPhone (SettingsSheet.tsx,
 * ai/available.ts). What the search finds here is AiPane.findable.ts, in this page's order.
 */
export function AiPane() {
  return <ModelCard />;
}
