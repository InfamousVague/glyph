/**
 * What jsdom does not have, stood in for by a test that needs it - one call each, opted into rather than installed
 * for every file.
 *
 * Opt-in on purpose. A missing browser API is itself an answer some code reads: NotePeek.tsx and canvas/Near.tsx take a
 * page with no IntersectionObserver as a page that cannot watch the screen, and draw every card at once, and their
 * tests rely on exactly that. A stub in setup.ts would change what every one of those files tests. So nothing here
 * runs until a test asks, and there is deliberately no IntersectionObserver.
 *
 * ORDER matters for matchMedia. The Glacier kit asks the window's resolution with `matchMedia` as its module loads,
 * so the stub has to be in before anything that imports the kit is imported - which static imports, hoisted above
 * the file's own code, would beat. A test whose imports reach the kit hoists the call with them:
 *
 *   await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
 *
 * (`vi.hoisted` runs before every import in the file, and the `await` holds the imports until the stub is in.) A
 * test that imports its component dynamically, after its mocks, can call `stubMatchMedia()` plainly before that
 * import instead.
 */

/**
 * A `matchMedia` that answers every query with `matches` - no by default, so no reduced motion, no dark scheme and no
 * narrow window - and never changes its mind. Replaces whatever the window had.
 */
export function stubMatchMedia(matches = false): void {
  window.matchMedia = (query: string) =>
    ({
      matches,
      media: query,
      onchange: null,
      addListener: () => undefined,
      removeListener: () => undefined,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
      dispatchEvent: () => false,
    }) as MediaQueryList;
}

/** A ResizeObserver that watches and never reports: jsdom lays nothing out, so nothing it watched would ever resize. */
export function stubResizeObserver(): void {
  globalThis.ResizeObserver ??= class StillObserver {
    observe(): void {}
    unobserve(): void {}
    disconnect(): void {}
  } as unknown as typeof ResizeObserver;
}
