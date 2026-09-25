/**
 * The two small measures every spoken-markdown rule takes of a sentence: its words without the stop Whisper put
 * after them, and how many words it has. A cue's content is written without its stop ("Heading, groceries." is
 * `## Groceries`), and most rules are held to short sentences, because a long one is prose however it starts.
 */

/** `text` without the spaces and stops at its end: "Groceries. " is "Groceries". */
export function stripEnd(text: string): string {
  return text.replace(/[\s.,;:!?]+$/, '');
}

/** How many words `text` has. */
export function words(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length;
}
