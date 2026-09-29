/**
 * The model's output read into answers, by blank (docs/DESIGN.md §145, 5.6). Pure.
 *
 * An answer line is `[N] words`, a space after the bracket: a note's own numbered lists are `1. ` and `1) `, a
 * reference definition is `[1]: `, and a `[1]` inside a line is not at its start, so a model carrying on a list with
 * `3. Rail pass` never fills blank 3. The same number on several lines is an items blank's items, in order. A number
 * that was not asked is passed over. With one blank asked, a bare answer is read too, so a model that never writes
 * `[1]` (the 2B, Gemma) still fills a single blank.
 */

const LINE = /^\s*\[(\d{1,2})\] +(.*)$/;

/** Every asked blank's lines, by its number; a blank with none has none. `asked` is the numbers asked, in order. */
export function readFill(text: string, asked: readonly number[]): Map<number, string[]> {
  const lines = text.replace(/\r/g, '').split('\n');
  const answers = new Map<number, string[]>(asked.map((n) => [n, []]));
  let numbered = false;
  for (const line of lines) {
    const found = LINE.exec(line);
    if (!found) continue;
    numbered = true;
    const n = Number(found[1]);
    const words = found[2]!.trim();
    if (answers.has(n) && words) answers.get(n)!.push(words);
  }
  if (!numbered && asked.length === 1) {
    const bare = lines.map((l) => l.trim()).filter(Boolean);
    answers.set(asked[0]!, bare);
  }
  return answers;
}

/** Whether every line with words is an `[N]` line for an asked blank: the bar rung 1 is held to (5.8). */
export function allNumbered(text: string, asked: readonly number[]): boolean {
  return text
    .split('\n')
    .filter((l) => l.trim())
    .every((l) => {
      const found = LINE.exec(l);
      return Boolean(found && asked.includes(Number(found[1])));
    });
}

/**
 * Each ask's answer lines, by the numbers the message wrote it with (ai/fills/message.ts `Built.numbers`): an items
 * blank's slots in order. With no numbered line at all and one ask, the bare answer is that ask's, every line of it.
 */
export function readAsks(text: string, numbers: readonly (readonly number[])[]): string[][] {
  const flat = numbers.flat();
  const read = readFill(text, flat);
  const numbered = text.split('\n').some((line) => LINE.test(line));
  if (!numbered && numbers.length === 1) {
    return [
      text
        .split('\n')
        .map((l) => l.trim())
        .filter(Boolean),
    ];
  }
  return numbers.map((mine) => mine.flatMap((n) => read.get(n) ?? []));
}

