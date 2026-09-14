import { useEffect, useRef } from 'react';
import { answerHost } from './host.ts';

/**
 * The phone's back gesture, answered by the app.
 *
 * Android owns the back swipe. MainActivity catches it and asks the page
 * (`window.__glyph.back`) whether the app can use it; the answer is a walk
 * down a stack of handlers, newest first. An open note, the settings page, a
 * settings pane, the guide: each registers a handler while it is up, and the
 * first to take the gesture wins. Nothing took it means the app is at its
 * root, the list, and Android puts Glyph behind the home screen the way it
 * does every other app. It never closes it: a back swipe from the list used
 * to end the whole app, which is what Matt asked to fix.
 *
 * Handlers stack in the order they register, which - since screens register
 * when they OPEN - is opening order: the newest thing on screen is the first
 * thing a back swipe dismisses, which is the order a person expects.
 *
 * The same stack answers the Escape key, so the desktop and a browser get the
 * same behaviour from the keyboard.
 */

type BackHandler = () => boolean;

const handlers: BackHandler[] = [];

/** Puts a handler on top of the stack; returns its unregister. */
export function onBack(handler: BackHandler): () => void {
  handlers.push(handler);
  return () => {
    const at = handlers.indexOf(handler);
    if (at !== -1) handlers.splice(at, 1);
  };
}

/** Runs the newest handler that wants the gesture. True if one took it. */
export function goBack(): boolean {
  for (let i = handlers.length - 1; i >= 0; i -= 1) {
    const handler = handlers[i];
    if (handler && handler()) return true;
  }
  return false;
}

/**
 * While `active`, a back gesture runs `close` and is taken. The screen case in
 * one line: pass whether it is showing and what leaving it means.
 */
export function useBack(active: boolean, close: () => void): void {
  const closeRef = useRef(close);
  closeRef.current = close;
  useEffect(() => {
    if (!active) return undefined;
    return onBack(() => {
      closeRef.current();
      return true;
    });
  }, [active]);
}

/** Installs the page's answer for the activity, and Escape's. Call once. */
export function installBack(): () => void {
  const unanswer = answerHost('back', goBack);
  const onKey = (event: KeyboardEvent) => {
    if (event.key !== 'Escape' || event.defaultPrevented) return;
    if (goBack()) event.preventDefault();
  };
  window.addEventListener('keydown', onKey);
  return () => {
    unanswer();
    window.removeEventListener('keydown', onKey);
  };
}
