import { useEffect, useState } from 'react';

/** How long a Copy says Copied after it is pressed. */
const COPIED_MS = 1500;

/**
 * A Copy that says Copied for a moment: `copy` puts `text` on the clipboard, and `copied` is true for a second and a
 * half after, however often it is pressed in that time. The server address on the Claude page and each snippet in
 * its guide are one of these; the moment is cleared if the button goes before it is over.
 */
export function useCopied(text: string): { copied: boolean; copy: () => void } {
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return undefined;
    const timer = window.setTimeout(() => setCopied(false), COPIED_MS);
    return () => window.clearTimeout(timer);
  }, [copied]);
  return {
    copied,
    copy: () => {
      void navigator.clipboard?.writeText(text);
      setCopied(true);
    },
  };
}
