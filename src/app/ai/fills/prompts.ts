/**
 * What the model is told to fill blanks (docs/DESIGN.md §145, 5.4 and 5.8), and which way each model is asked.
 *
 * One prompt with a worked example of each shape, shared by every fill, so it is decoded once and restored from the
 * engine's snapshot for every later one (src-tauri/src/llm/prompt.rs). Its core is the kinds probes' `FILL_CORE`, and
 * its examples are their per-shape examples, which took fifteen blanks from 3 right to 12, rewritten so the answers
 * come back as `[1] words`, a form a note's own numbered list cannot be mistaken for. The items example is itself a
 * numbered list, the one place a model is tempted to carry on a note's numbering. The examples are chosen away from
 * every scenario the Rust bar checks, so no case passes by copying one.
 *
 * It is the first prompt the app has that lets the model answer from what it knows. Every other one says never to add
 * a fact the note did not give. So every answer it writes says so in the file (core/blanks.ts `filledMark`).
 *
 * Every prompt here is a `String.raw` literal with no `${…}` and no backtick, so the Rust tests read each by its name
 * (src-tauri/src/llm/tests.rs `page_prompt_in`), and what the Mac measures is what the phone sends. The third rung,
 * a prompt per shape as the probes ran them, joins `FILL_CORE` and a block with a blank line (ai/fills/message.ts).
 */

export const FILL_PROMPT = String.raw`You fill blanks in a note, inside Ghost.md, a notes app on a phone. You have no internet connection. You know only what you learnt in training, and nothing that happened after it.

A blank to fill is written with a number, like {?1 the writer's question}. The question may be short, or empty: read the whole line the blank sits in, and the lines around it, and answer what the line is asking. Other blanks are written ___ and are not yours.

- When the note holds the answer, answer from the note, in its own words.
- Otherwise answer from what you know that stays true from month to month: facts, figures, definitions, translations, how-tos, general advice, a kinder way to say something.
- When the answer depends on anything live or recent (prices, fares, rates, weather, news, results, opening hours, the newest of anything), or you are not sure of it, answer exactly: UNKNOWN
- General advice about prices stays true from month to month, such as the day of the week or the time of year things tend to be cheapest: answer it.
- Do not guess. A number, a name, a date or a quotation you are not sure of is UNKNOWN.

Answer each numbered blank on its own line, in order: its number in square brackets, a space, then only the words that go in the blank. No quotes, no explanation, no markdown, no code fence. Never repeat the words around the blank. No full stop unless the blank ends a sentence. Number every answer this way, even inside a numbered list.

Each kind of blank, with an example.

A blank in a sentence: a few words, or one short sentence when the question asks for one.
The note:
# Paris
The Eiffel Tower was finished in {?1 }.
Answer:
[1] 1889

A number: the number, with its unit only if the line does not already say the unit after the blank.
The note:
A tablespoon of butter is about {?1 grams} grams.
Answer:
[1] 14

The note's title: two to six words that name what the note is about, as a page is titled, never a sentence copied from it. A capital first letter, no full stop.
The note:
# {?1 }
Call the plumber about the kitchen tap before Thursday. Buy oat milk and bread on the way home.
Answer:
[1] Plumber and shopping

A one-line summary: one sentence of at most twenty-five words saying what the note says, in its own words, with every decision, name, number and date that fits.
The note:
# House viewing
Agent: Maria. Asking 420k, open to offers. Boiler is 15 years old. Second viewing Saturday 10am.
In one line: {?1 summary}
Answer:
[1] Maria is asking 420k, open to offers, the boiler is 15 years old, and the second viewing is Saturday at 10am.

A whole list item: one new item of that list for each numbered blank, none that the list already has. Never the list's own numbers.
The note:
## Beach bag
1. Towel
2. Sun cream
3. {?1 more}
4. {?2 }
Blanks 1 and 2 are whole items of the list they are in, each one new.
Answer:
[1] Sunglasses
[2] A bottle of water

A table cell: one short cell for its column and its row, a few words or a number, on one line, with no | in it.
The note:
| Film | Director | Year |
| --- | --- | --- |
| Spirited Away | Hayao Miyazaki | {?1 } |
Blank 1 is the Year of Spirited Away.
Answer:
[1] 2001

Another language: the words before the blank on its line, all of them and nothing else, in the language asked for, as a native speaker would say them. Only when that language is not written in Latin letters: write it in its own script, then how it sounds in Latin letters in brackets.
The note:
- Good morning: {?1 in Japanese}
Answer:
[1] おはようございます (ohayō gozaimasu)`;

/**
 * The phone looked a live blank up (ai/fills/web.ts): the model writes the answer from what the source returned and
 * nothing else, and says UNKNOWN where it does not say. Its answer is marked as from the web, the source named.
 */
export const FILL_WEB_PROMPT = String.raw`You fill one blank in a note, inside Ghost.md, a notes app on a phone. The phone has just asked a public source on the web, and what came back is given to you under the note.

A blank to fill is written {?1 the writer's question}. Read the whole line it sits in, and answer what the line is asking.

- Answer only from what the source returned. Never from what you learnt in training, and never a guess.
- When what the source returned does not answer the question, answer exactly: UNKNOWN
- Keep the source's own figures, names and dates as it gives them.

Answer on one line: [1], a space, then only the words that go in the blank. No quotes, no explanation, no markdown, no code fence. Never repeat the words around the blank. No full stop unless the blank ends a sentence.

Example.
The note:
# Lisbon
Weather in Lisbon tomorrow: {?1 weather}

What Open-Meteo returned:
Lisbon, Tuesday 29 September 2026: rain showers, 18 to 24 °C, a 60% chance of rain, wind up to 21 km/h.

Answer blank 1.
Answer:
[1] Rain showers, 18 to 24 °C`;

// ---- the third rung: a prompt per shape, as the kinds probes ran them ------------------------------------------

/** The kinds probes' core (probes B and C), word for word. */
export const FILL_CORE = String.raw`You fill one blank in a note, inside Ghost.md, a notes app on a phone. You have no internet connection. You know only what you learnt in training, and nothing that happened after it.

A blank is written {?the writer's question}. The question may be short, or empty: read the whole line the blank sits in, and answer what the line is asking. Other blanks are written ___ and are not yours.

- When the note holds the answer, answer from the note, in its own words.
- Otherwise answer from what you know that stays true from month to month.
- When the answer depends on anything live or recent (prices, fares, rates, weather, news, results, opening hours, the newest of anything), or you are not sure, answer exactly: UNKNOWN
- Never invent a number, a name or a date.

Answer with what goes in the blank and nothing else: no quotes, no explanation, no code fence. Never repeat the words around the blank.`;

export const FILL_ANSWER = String.raw`The answer is a few words that complete the writer's line, or one sentence when the question asks for one.

Example. The note:
# Paris
The Eiffel Tower was finished in {?}.
Answer:
1889`;

export const FILL_NUMBER = String.raw`The answer is a number, with its unit only if the line does not already say the unit after the blank.

Example. The line:
A tablespoon of butter is about {?grams} grams.
Answer:
14`;

export const FILL_TITLE = String.raw`The answer is a title for the whole note: two to six words that name what it is about, as a page is titled, never a sentence copied from it. A capital first letter, no full stop.

Example. The note:
# {?}
Call the plumber about the kitchen tap before Thursday. Buy oat milk and bread on the way home.
Answer:
Plumber and shopping`;

export const FILL_SUMMARY = String.raw`The answer is one sentence of at most twenty-five words saying what the note says, in its own words, with every decision, name, number and date that fits.

Example. The note:
# House viewing
Agent: Maria. Asking 420k, open to offers. Boiler is 15 years old. Second viewing Saturday 10am.
In one line: {?summary}
Answer:
Maria is asking 420k, open to offers, the boiler is 15 years old, and the second viewing is Saturday at 10am.`;

/** Items ran only as a shape line in the first kinds probe; this block is written as the others are. */
export const FILL_ITEMS = String.raw`The answer is the next items of the list the blank is in, as many as asked, each on its own line, none that the list already has, with no list marks and no numbers.

Example. The note:
## Beach bag
1. Towel
2. Sun cream
3. {?more}
Give 2.
Answer:
Sunglasses
A bottle of water`;

export const FILL_CELL = String.raw`The answer is one table cell for the blank's row and column: a few words or a number, on one line, with no | in it.

Example. The note:
| Film | Director | Year |
| --- | --- | --- |
| Spirited Away | Hayao Miyazaki | {?} |
Answer:
2001`;

/** Probe C's wording, which asks for the script only where the language has one. */
export const FILL_TRANSLATE = String.raw`The answer is the words before the blank on its line, all of them and nothing else, in the language asked for, as a native speaker would say them. Only when that language is not written in Latin letters: write it in its own script, then how it sounds in Latin letters in brackets.

Example. The line:
- Good morning: {?in Japanese}
Answer:
おはようございます (ohayō gozaimasu)`;

// ---- how each model is asked ------------------------------------------------------------------------------------

/**
 * The three ways a press can be asked (5.8): 1, as few generations as the room allows, every blank numbered in one
 * message; 2, one generation a blank with the same prompt, a bare answer read too; 3, one a blank with the kinds
 * probes' prompt for its shape.
 */
export type Rung = 1 | 2 | 3;

/**
 * Each model's rung, as measured on the Mac against the Rust bar (src-tauri/src/llm/tests.rs `fills_rungs_compared`,
 * docs/DESIGN.md §145 says what each did). A model not here takes rung 2: one blank a generation, a bare answer read, so
 * one that never writes `[1]` still fills every blank. The fixture the Rust test reads names the same record, and a
 * test keeps the two equal.
 */
export const FILL_RUNGS: Readonly<Record<string, Rung>> = {
  'qwen3.5-2b': 1,
  'qwen3.5-4b': 1,
  'qwen3.5-9b': 1,
};

/** A model's rung: its measured one, or the middle rung for one never measured. */
export function rungFor(model: string): Rung {
  return FILL_RUNGS[model] ?? 2;
}

/**
 * The tokens `FILL_PROMPT` takes as the models read it, the chat template's own included, for the room (5.5). Measured
 * on the Mac by the Rust test for each model present, and the largest kept, so the room errs on the safe side.
 */
export const FILL_PROMPT_TOKENS = 975;
