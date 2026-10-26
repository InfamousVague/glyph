import { useEffect, useState } from 'react';

const dark = () => typeof matchMedia !== 'undefined' && matchMedia('(prefers-color-scheme: dark)').matches;

/** Light or dark as the reader's system is, and following it when it changes. */
export function useSystemDark(): boolean {
  const [isDark, setDark] = useState(dark);
  useEffect(() => {
    document.documentElement.dataset.theme = isDark ? 'dark' : 'light';
    const query = matchMedia('(prefers-color-scheme: dark)');
    const change = () => setDark(query.matches);
    query.addEventListener('change', change);
    return () => query.removeEventListener('change', change);
  }, [isDark]);
  return isDark;
}
