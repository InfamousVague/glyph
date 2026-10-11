import type { Notification } from './kinds.ts';

/**
 * The rows a pass of the feed brought, told to whoever asked to hear: the seam that lets something outside core act on
 * new news without core naming it. The Slack plugin is the first (plugins/slack/news.ts): an organization's news can
 * go to a channel the person chose for it. Core never imports a plugin; the registry listens here for all of them
 * (plugins/registry.ts `newRows`) and asks only the plugins switched on.
 *
 * Told after every look at the feed (core/sync/engine.ts), beside the phone's own notifications
 * (core/notifications/phone.ts `postNewRows`), with the same two things: `before`, the cursor the pass began at, and
 * the rows as this device now keeps them. Which rows are new is the listener's to decide, by the same rule the phone
 * uses: a row above `before`, and nothing at all from a device's first look (`before` of 0), which would be its whole
 * history. A listener that throws or rejects is its own trouble; the pass goes on.
 */

export type ArrivedListener = (before: number, rows: readonly Notification[]) => void | Promise<void>;

const listeners = new Set<ArrivedListener>();

/** Hears every pass's rows from now on; answers the way to stop. */
export function onArrived(listener: ArrivedListener): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** A pass of the feed is done: every listener is told, and none can stop the others or the pass. */
export function tellArrived(before: number, rows: readonly Notification[]): void {
  for (const listener of listeners) {
    try {
      void Promise.resolve(listener(before, rows)).catch(() => undefined);
    } catch {
      // A listener's failure is its own; the next one is still told.
    }
  }
}
