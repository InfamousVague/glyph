import { MARKER } from './itemSyntax.ts';

/**
 * A sum's arithmetic: what a line that starts with `=` works out (Matt picked sums from the list of new formats), and
 * what a query's `total:` adds up.
 *
 *   = 450 + 120 * 2          → 690
 *   - = $1,200 / 3           → $400
 *
 * Only arithmetic: numbers, `+ - * /`, `^` for powers, `%` after a number for a percent, and brackets, worked out by a
 * small precedence-climbing evaluator and never by `eval`. A currency sign or thousands commas come back on the answer.
 * Anything else - a word, a sum that can't be done - answers nothing. editor/sums.ts draws the answer after the line.
 *
 * Here in core/ and not beside the drawing since 2026-09-30, because a reader away from the editor needs the same
 * answer (Matt asked for "notion and jira like features", and a query's `total: estimate` was one, docs/DESIGN.md
 * §158): the estimates a query lists are added as a sum of them would be, `$1,200` read the way a sum reads it and the
 * total written the way a sum writes its answer, so the two never disagree about the same numbers. core/fillFacts.ts
 * works a note's own totals out with it too. Pure, and it imports nothing that draws, so the MCP server can bundle it.
 */

/** The start of a line, past an indent, a bullet and a quote mark, then `=` and a space. */
const LEAD = new RegExp(String.raw`^(\s*(?:${MARKER}\s+)?(?:>\s*)?)=\s+(.+)$`);
const CURRENCY = /[$€£¥₹]/;
/** A number as a sum reads one: a currency sign, digits with or without thousands commas, a fraction, a percent. */
const WRITTEN = /^[$€£¥₹]?(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?%?/;

type Token = { kind: 'num'; value: number } | { kind: 'op'; value: string };

function tokens(expr: string): Token[] | null {
  const out: Token[] = [];
  const text = expr.replace(/\s+/g, '');
  let i = 0;
  while (i < text.length) {
    const rest = text.slice(i);
    const number = WRITTEN.exec(rest);
    if (number) {
      const digits = number[1]!.replace(/,/g, '') + (number[2] ?? '');
      let value = Number(digits);
      if (number[0].endsWith('%')) value /= 100;
      out.push({ kind: 'num', value });
      i += number[0].length;
      continue;
    }
    const op = /^[-+*/^()×÷]/.exec(rest);
    if (!op) return null;
    out.push({ kind: 'op', value: op[0] === '×' ? '*' : op[0] === '÷' ? '/' : op[0] });
    i += 1;
  }
  return out;
}

/** A small precedence-climbing evaluator: no `eval`, nothing but numbers in and a number out. */
function evaluate(list: Token[]): number | null {
  let at = 0;
  const peek = () => list[at];
  const take = () => list[at++];
  const isOp = (value: string) => {
    const token = peek();
    return token?.kind === 'op' && token.value === value;
  };
  const primary = (): number | null => {
    if (isOp('-')) {
      take();
      const value = power();
      return value === null ? null : -value;
    }
    if (isOp('+')) {
      take();
      return power();
    }
    if (isOp('(')) {
      take();
      const value = sum();
      if (!isOp(')')) return null;
      take();
      return value;
    }
    const token = take();
    return token?.kind === 'num' ? token.value : null;
  };
  const power = (): number | null => {
    const base = primary();
    if (base === null) return null;
    if (!isOp('^')) return base;
    take();
    const exponent = power();
    return exponent === null ? null : base ** exponent;
  };
  const product = (): number | null => {
    let value = power();
    while (value !== null && (isOp('*') || isOp('/'))) {
      const op = (take() as { value: string }).value;
      const right = power();
      if (right === null) return null;
      value = op === '*' ? value * right : value / right;
    }
    return value;
  };
  const sum = (): number | null => {
    let value = product();
    while (value !== null && (isOp('+') || isOp('-'))) {
      const op = (take() as { value: string }).value;
      const right = product();
      if (right === null) return null;
      value = op === '+' ? value + right : value - right;
    }
    return value;
  };
  const value = sum();
  return value !== null && at === list.length && Number.isFinite(value) ? value : null;
}

/** The answer to a sum as it should read, or null when the text isn't one. */
export function answer(expr: string): string | null {
  const list = tokens(expr);
  // A sum has at least one operator between numbers: `= 450` alone is a number, not a question.
  if (!list || !list.some((t) => t.kind === 'op' && t.value !== '(' && t.value !== ')')) return null;
  const value = evaluate(list);
  if (value === null) return null;
  const sign = CURRENCY.exec(expr)?.[0] ?? '';
  const grouped = /\d,\d{3}/.test(expr) || Boolean(sign);
  const rounded = Math.round(value * 100) / 100;
  const decimals = sign && !Number.isInteger(rounded) ? 2 : 0;
  const text = Math.abs(rounded).toLocaleString('en-US', {
    useGrouping: grouped,
    minimumFractionDigits: decimals,
    maximumFractionDigits: sign ? 2 : 6,
  });
  return `${rounded < 0 ? '−' : ''}${sign}${text}`;
}

/** The sum on a line, if the line is one: where its expression starts, and its answer. */
export function sumOnLine(text: string): { answer: string } | null {
  const found = LEAD.exec(text);
  if (!found) return null;
  const result = answer(found[2] ?? '');
  return result === null ? null : { answer: result };
}

/**
 * The number a value starts with, written as a sum reads one, with a minus before it where there is one: `3` of "3
 * days", `$1,200` of "$1,200 a month", `-2.5`. Null where the value does not start with a number.
 */
export function leadingNumber(value: string): string | null {
  const text = value.trim();
  const minus = /^[-−]\s*/.exec(text)?.[0] ?? '';
  const found = WRITTEN.exec(text.slice(minus.length));
  return found ? `${minus ? '-' : ''}${found[0]}` : null;
}

/** A value that is a number and nothing else, as a sum reads one: `3`, `$1,200`, `-2.5`, `50%`; null for anything else. */
export function writtenNumber(value: string): number | null {
  const text = value.trim();
  const minus = /^[-−]\s*/.exec(text)?.[0] ?? '';
  const rest = text.slice(minus.length);
  const found = WRITTEN.exec(rest);
  if (!found || found[0].length !== rest.length) return null;
  const magnitude = Number(`${found[1]!.replace(/,/g, '')}${found[2] ?? ''}`) / (found[0].endsWith('%') ? 100 : 1);
  return minus ? -magnitude : magnitude;
}

/**
 * The total of some values, answered as a sum of them would be: each value's leading number (`leadingNumber`) added,
 * the currency sign and the thousands commas they were written with coming back on the answer. `3`, `2.5 days` and
 * `1` total `6.5`; `$1,200` and `$300` total `$1,500`. A value with no number in it is left out; null where none had
 * one.
 */
export function totalOf(values: readonly string[]): string | null {
  const numbers = values.map(leadingNumber).filter((number): number is string => number !== null);
  if (!numbers.length) return null;
  // Nought first: a sum answers only where there is something to work out, and the total of one value is that value.
  return answer(['0', ...numbers].join(' + '));
}
