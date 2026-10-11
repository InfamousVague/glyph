import { useSyncExternalStore } from 'react';

/**
 * A value that lives outside React and that React follows: the house's module store (docs/research/house-style.md,
 * "State management"), written once.
 *
 * The shape was written out by hand in every module that published state to the screen - a `let current`, a listener
 * set, a subscribe that returns the delete, a setter that tells every listener, and a hook round
 * `useSyncExternalStore` - and the copies had begun to differ in the parts that matter: which ones told their
 * listeners on a change that changed nothing, and what they answered for a render with no client yet. Here those are
 * decided once: `set` tells the listeners only when the value is a different one (`Object.is`, which is what React
 * compares by too), and the server snapshot is whatever the module says it is, or none, as it always was.
 *
 * What stays with each module is what its value MEANS - when it is written, what else happens when it is (storage,
 * the document), and the names it is known by (`accountState`, `useSyncStatus`, `onPreferences`). This is only the
 * channel. Values are replaced, never changed in place: a store holding an object is given a new one.
 */

export interface ExternalStore<T> {
  get(): T;
  /** Replaces the value, and tells every listener if it is a different one. */
  set(next: T): void;
  /** `set` with the value worked out from the one before. */
  update(fn: (was: T) => T): void;
  /** Called after every change; answers the way to stop. */
  subscribe(listener: () => void): () => void;
  /** The value, live: a component that calls this renders again when it changes. */
  use(): T;
}

/**
 * A store starting at `initial`. `server` is the snapshot for a render with no client yet (React's
 * `getServerSnapshot`); without one there is none, and React says so if such a render is ever tried.
 */
export function externalStore<T>(initial: T, { server }: { server?: () => T } = {}): ExternalStore<T> {
  let current = initial;
  const listeners = new Set<() => void>();
  const get = () => current;
  const subscribe = (listener: () => void) => {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  };
  const set = (next: T) => {
    if (Object.is(next, current)) return;
    current = next;
    for (const listener of listeners) listener();
  };
  return {
    get,
    set,
    update: (fn) => set(fn(current)),
    subscribe,
    use: () => useSyncExternalStore(subscribe, get, server),
  };
}
