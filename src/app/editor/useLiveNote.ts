import { useEffect } from 'react';
import type { EditorView } from '@codemirror/view';
import { liveEnabled } from '../core/live/enabled.ts';

/**
 * Live sync on the open note (docs/LIVE.md): the note open on another device too, typed into on either and arriving a
 * character at a time. Nothing at all unless the switch is on (core/live/enabled.ts), and even then the live code -
 * Yjs and its CodeMirror binding - is only loaded here, on demand, so the app is the same size for everyone with it
 * off.
 *
 * It says nothing on screen: a "Live" word and dot in the top bar did, while another device had the note open, and
 * went (Matt: "There is a strange live indicator in the top nav remove it"). The typing arriving is the sign.
 */
export function useLiveNote(view: EditorView | null, noteId: string): void {
  useEffect(() => {
    if (!view || !liveEnabled()) return undefined;
    let stop: (() => void) | null = null;
    let gone = false;
    void import('../core/live/open.ts')
      .then(({ goLive }) =>
        goLive(view, noteId, () => {
          // How many other devices are joined: nothing here shows it any more.
        }),
      )
      .then((stopping) => {
        if (gone) stopping();
        else stop = stopping;
      })
      .catch(() => {
        // Could not go live - no network, no account key: the note works as it always has, synced by the pass.
      });
    return () => {
      gone = true;
      stop?.();
    };
  }, [view, noteId]);
}
