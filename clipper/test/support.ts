import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { JSDOM } from 'jsdom';

/** A fixture page in a window of its own, at `url`, as a browser would have it (its scripts not run). */
export function loadPage(name: string, url = 'https://field.example/2026/10/the-quiet-garden'): Window {
  const html = readFileSync(join(__dirname, 'fixtures', `${name}.html`), 'utf8');
  return new JSDOM(html, { url }).window as unknown as Window;
}

/** A selection in `win` from the start of one element to the end of another. */
export function select(win: Window, fromId: string, toId: string): void {
  const range = win.document.createRange();
  range.setStartBefore(win.document.getElementById(fromId)!);
  range.setEndAfter(win.document.getElementById(toId)!);
  const selection = win.getSelection()!;
  selection.removeAllRanges();
  selection.addRange(range);
}
