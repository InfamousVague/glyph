import { listenTo } from '../core/events.ts';
import { takeHostLink } from '../core/host.ts';
import { invoke, isTauri } from '../core/tauri.ts';

/**
 * Links that opened the app. Two kinds: a share link, `ghostmd://fork#<id>.<key>`, the reader page's "Open in the
 * Ghost.md app" (src/read/Reader.tsx); and a note link, `ghostmd://note/<id>`, the tap on the notification that says
 * a meeting was written up (docs/DESIGN.md §127 section 5). The native side keeps each until asked
 * (src-tauri/src/links.rs); this takes them once the app has its notes, and again whenever one arrives while it runs,
 * and hands every one to `open`, which sorts them (`readNoteLink`, share/share.ts `readShareLink`).
 *
 * A notification's tap is carried two ways, and both are taken here. The deep-link plugin's channel into Rust is set
 * once per activity, and an activity recreated inside a live process - the app swiped away during the write-up, then
 * the notification tapped - may have none, so the activity keeps the link it was opened with as well
 * (`GlyphHost.takeLink`). The same link from both is opened once. On an older binary, or in a browser, there is
 * nothing to take and nothing is done.
 */

/** The note a `ghostmd://note/<id>` link names, or null for any other link. The id is a plain one (src-tauri/src/fsx.rs `plain_id`). */
export function readNoteLink(link: string): string | null {
  return /^ghostmd:\/\/note\/([A-Za-z0-9_-]+)\/?$/.exec(link.trim())?.[1] ?? null;
}

export function followAppLinks(open: (link: string) => void): () => void {
  if (!isTauri()) return () => undefined;
  let gone = false;
  const take = () =>
    void invoke<string[]>('links_take')
      .catch((): string[] => [])
      .then((links) => {
        if (gone) return;
        const activity = takeHostLink();
        const seen = new Set<string>();
        for (const link of [...links, ...(activity ? [activity] : [])]) {
          if (seen.has(link)) continue;
          seen.add(link);
          open(link);
        }
      });
  take();
  let unlisten: (() => void) | null = null;
  void listenTo('glyph://link', take)
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
