import { act, type ReactElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach } from 'vitest';

/**
 * How a component test puts React on the page, and takes it off again: one host `div` in the document per `show`,
 * rendered inside `act`, and every one of them unmounted and removed after each test by the hook registered here -
 * so a test that forgets, or shows twice, leaves nothing behind for the next one to find.
 *
 * Twenty-odd test files each carried their own copy of this, and the copies had drifted: some set
 * IS_REACT_ACT_ENVIRONMENT and some did not (React then warns on every `act`), some kept only the last root and so
 * never took down a second `show`, and three different `button` finders matched three different ways. This is the
 * one copy. It stays the plain createRoot-and-act style the tests were written in rather than moving them to
 * @testing-library/react: the assertions read the DOM directly, and that is the part worth keeping.
 *
 * Importing this module is what registers the hook, at the file's top level. Vitest runs a file's `afterEach` hooks
 * in reverse order of registration, and this import comes first, so it runs LAST - after the file's own. A file
 * whose own `afterEach` must see the tree already gone (it changes a store the tree listens to, say) calls
 * `unmount()` first itself; the hook then finds nothing left to do.
 */

// React checks this before it will let `act` flush without warning. Set once, for every file that renders.
(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

/** Every tree `show` put on the page and nobody has taken down yet, oldest first. */
const shown: { host: HTMLDivElement; root: Root }[] = [];

/** Renders `element` into a fresh host at the end of the document's body, and answers the host. */
export function show(element: ReactElement): HTMLDivElement {
  const host = document.createElement('div');
  document.body.appendChild(host);
  const root = createRoot(host);
  shown.push({ host, root });
  act(() => root.render(element));
  return host;
}

/** Renders `element` again into the host `show` made last: the same tree with new props, as a parent re-rendering. */
export function rerender(element: ReactElement): void {
  const last = shown.at(-1);
  if (!last) throw new Error('rerender() before show(): there is no tree on the page to render again');
  act(() => last.root.render(element));
}

/** Unmounts every tree `show` drew, newest first, and removes their hosts. After each test, and mid-test to mount afresh. */
export function unmount(): void {
  for (const { host, root } of shown.splice(0).reverse()) {
    act(() => root.unmount());
    host.remove();
  }
}

afterEach(unmount);

/**
 * The button named `label`, by its accessible label or its words exactly (trimmed), in `within` or the whole
 * document. Throws when there is none, so a test cannot press nothing and pass.
 */
export function button(label: string, within: ParentNode = document): HTMLButtonElement {
  const found = [...within.querySelectorAll<HTMLButtonElement>('button')].find((b) => b.getAttribute('aria-label') === label || b.textContent?.trim() === label);
  if (!found) throw new Error(`no button ${label}`);
  return found;
}

/** The first button in `within` whose words include `words`, or undefined: for asking whether one is there. */
export function buttonSaying(within: ParentNode, words: string): HTMLButtonElement | undefined {
  return [...within.querySelectorAll<HTMLButtonElement>('button')].find((b) => b.textContent?.includes(words));
}

/**
 * A click on `el`, bubbling, inside `act`. Throws on nothing: a finder that came back empty is the test's failure,
 * not a press that quietly did nothing.
 */
export function press(el: Element | null | undefined): void {
  if (!el) throw new Error('press(): nothing to press');
  act(() => {
    el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
}

/**
 * Types `value` into a field the way a person's typing reaches React: through the element's own `value` setter,
 * then an `input` event. Setting `.value` directly does not - React keeps its own record of the value, and a plain
 * assignment updates both at once, so the change it listens for never looks like a change.
 */
export function typeInto(field: HTMLInputElement | HTMLTextAreaElement, value: string): void {
  const prototype = field instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
  if (!setter) throw new Error('typeInto(): this document has no value setter to type through');
  act(() => {
    setter.call(field, value);
    field.dispatchEvent(new Event('input', { bubbles: true }));
  });
}
