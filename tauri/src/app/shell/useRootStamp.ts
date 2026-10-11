import { useEffect } from 'react';

/**
 * A `data-*` attribute on the page's root, there while `value` is and gone when it is null or the Shell unmounts.
 *
 * How the Shell tells the stylesheets about its layout without handing them a number: app.css and settings.css ask
 * `[data-tabs]` how tall the tab bar is and `[data-split]` whether the window is in two panes, where each used to keep
 * its own copy of a width or a height, and each copy was a chance to disagree with the others. A stamp has no number
 * in it, so the chrome that reads it can only agree with the Shell that wrote it.
 */
export function useRootStamp(name: string, value: string | null): void {
  useEffect(() => {
    const root = document.documentElement;
    if (value === null) delete root.dataset[name];
    else root.dataset[name] = value;
    return () => {
      delete root.dataset[name];
    };
  }, [name, value]);
}
