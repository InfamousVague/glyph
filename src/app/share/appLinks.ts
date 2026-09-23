import { invoke, isTauri } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { readShareLink } from './share.ts';

/**
 * Share links that opened the app: `ghostmd://fork#<id>.<key>`, the reader page's "Open in the Ghost.md app"
 * (src/read/Reader.tsx). The native side keeps each until asked (src-tauri/src/links.rs); this takes them once the
 * app has its notes, and again whenever one arrives while it runs, and hands every one that is a share to `open`.
 * On an older binary, or in a browser, there is nothing to take and nothing is done.
 */
export function followAppLinks(open: (link: string) => void): () => void {
  if (!isTauri()) return () => undefined;
  let gone = false;
  const take = () =>
    void invoke<string[]>('links_take')
      .then((links) => {
        if (gone) return;
        for (const link of links) if (readShareLink(link)) open(link);
      })
      .catch(() => undefined);
  take();
  let unlisten: (() => void) | null = null;
  void listen('glyph://link', take)
    .then((off) => {
      if (gone) off();
      else unlisten = off;
    })
    .catch(() => undefined);
  return () => {
    gone = true;
    unlisten?.();
  };
}
