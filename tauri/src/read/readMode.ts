import { useCallback, useState } from 'react';

/**
 * How the reader page shows a page's words (Matt, 2026-10-29: "make code view a segmented toggle that's off by default
 * on the web preview page"): Read, the page drawn as a page (Rendered.tsx), or Markdown, its source in the app's own
 * editor, as the page always drew it. Read unless this browser chose Markdown, remembered here and nowhere else: a
 * browser that keeps nothing (a private window, storage turned off) reads every page as Read.
 */

export type ReadMode = 'read' | 'markdown';

/** Where this browser keeps its choice. */
export const READ_MODE_KEY = 'glyph-reader-view';

export function storedReadMode(): ReadMode {
  try {
    return localStorage.getItem(READ_MODE_KEY) === 'markdown' ? 'markdown' : 'read';
  } catch {
    return 'read';
  }
}

export function keepReadMode(mode: ReadMode): void {
  try {
    localStorage.setItem(READ_MODE_KEY, mode);
  } catch {
    // Nowhere to keep it: this visit has it all the same.
  }
}

/** The choice, and a way to make it that this browser remembers. */
export function useReadMode(): [ReadMode, (mode: ReadMode) => void] {
  const [mode, setMode] = useState<ReadMode>(storedReadMode);
  const choose = useCallback((next: ReadMode) => {
    keepReadMode(next);
    setMode(next);
  }, []);
  return [mode, choose];
}
