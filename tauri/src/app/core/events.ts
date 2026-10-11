import { isTauri } from './tauri.ts';

/**
 * Listening to what Rust says without being asked: a download's progress, a
 * phrase heard, a link that opened the app.
 *
 * The partner of `invoke` in tauri.ts, and built the same way: the Tauri
 * module is pulled in by a literal dynamic import, so the bundler can split it
 * off and a browser never loads it, and outside the webview the call rejects
 * rather than pretending to listen. Callers are expected to have chosen their
 * browser path already, as they have for `invoke`, so a rejection here is a
 * real failure. The handler is given the event's payload, which is all any
 * caller reads; the envelope's name and id stay here.
 *
 * Eight places took the event module for themselves: seven by a dynamic
 * import inline, and one (share/appLinks.ts) by a static import that put it
 * in the page's first bundle.
 *
 * Its own module rather than a line in tauri.ts, deliberately: tests stand in
 * for tauri.ts with a factory that lists only `isTauri` and `invoke`, and a
 * helper living there would vanish from under every module those tests load.
 * A test that wants to hear events mocks `@tauri-apps/api/event`, which this
 * imports by name.
 */

/** Calls `handler` with each `event`'s payload until the answer is called; rejects outside the webview. */
export async function listenTo<T>(event: string, handler: (payload: T) => void): Promise<() => void> {
  if (!isTauri()) throw new Error(`no Tauri runtime for event "${event}"`);
  const { listen } = await import('@tauri-apps/api/event');
  return listen<T>(event, (message) => handler(message.payload));
}
