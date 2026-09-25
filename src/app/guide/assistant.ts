/**
 * What the guide can learn about the phone it is on, and the one thing it can do to it, for the side-key page
 * (guide/pages/SideKey.tsx): who made the phone, whether Ghost.md is its digital assistant yet, the settings screen
 * where it becomes one, and the rows to tap on the way there.
 *
 * Android will not let an app make itself the assistant (the role is marked not requestable), and the side key's own
 * setting belongs to the phone maker, so the page opens the right screen, prints THIS phone's rows, and looks again
 * when the person comes back. The rows differ by maker: Samsung's are under Advanced features, Google's under
 * Gestures, and anyone else's are found by searching Settings.
 *
 * The activity's helpers (MainActivity.GlyphHost, core/host.ts) are every one optional: they arrive in native 0.3.1,
 * and an over-the-air page can be running on an older APK that has none of them, or one whose bridge throws. So each
 * is asked inside a try, and a helper that is not there answers as a phone that will not say.
 */

export type PhoneKind = 'samsung' | 'pixel' | 'other';

/** `Build.MANUFACTURER`, as the activity reports it: "samsung", "Google". Empty where it will not say. */
export function deviceMaker(): string {
  try {
    return window.GlyphHost?.deviceMaker?.() ?? '';
  } catch {
    return '';
  }
}

/** Whether Ghost.md holds the assistant role now; null where the activity cannot say. */
export function isAssistantNow(): boolean | null {
  try {
    const host = window.GlyphHost;
    return host?.isAssistant ? host.isAssistant() : null;
  } catch {
    return null;
  }
}

/** Whether this build can open the phone's assistant settings, for the button that does. */
export function canOpenAssistantSettings(): boolean {
  return Boolean(window.GlyphHost?.openAssistantSettings);
}

/** Opens the phone's assistant settings. */
export function openAssistantSettings(): void {
  try {
    window.GlyphHost?.openAssistantSettings?.();
  } catch {
    // Nothing to open on this build; the written steps still stand.
  }
}

/** Which way the side key is set up on a phone, by its maker and, failing that, its model in the user agent. */
export function phoneKind(maker: string, userAgent: string): PhoneKind {
  if (/samsung/i.test(maker) || /\bSM-[A-Z0-9]/.test(userAgent)) return 'samsung';
  if (/google/i.test(maker) || /\bPixel\b/.test(userAgent)) return 'pixel';
  return 'other';
}

/** This phone's kind. */
export function thisPhone(): PhoneKind {
  return phoneKind(deviceMaker(), typeof navigator === 'undefined' ? '' : navigator.userAgent);
}

/** The rows from Settings to the assistant choice, the last one the row to pick. */
export function assistantPath(kind: PhoneKind): string[] {
  return kind === 'samsung'
    ? ['Settings', 'Apps', 'Choose default apps', 'Digital assistant app', 'Device assistance app', 'Ghost.md']
    : ['Settings', 'Apps', 'Default apps', 'Digital assistant app', 'Default digital assistant app', 'Ghost.md'];
}

/** The rows from Settings to what holding the side key does, the last one the row to pick. */
export function sideKeyPath(kind: PhoneKind): string[] {
  if (kind === 'samsung') return ['Settings', 'Advanced features', 'Side button', 'Press and hold', 'Digital assistant'];
  if (kind === 'pixel') return ['Settings', 'System', 'Gestures', 'Press and hold power button', 'Digital assistant'];
  return ['Settings', 'search “press and hold”', 'Digital assistant'];
}
