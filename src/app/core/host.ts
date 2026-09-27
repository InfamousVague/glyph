/**
 * The page's two-way line to the Android activity.
 *
 * Inbound, the activity calls into `window.__glyph` - `refresh` when the app is
 * resumed, `capture` when the side key is held while Glyph is already open.
 * Outbound, the page calls `window.GlyphHost`, the JavascriptInterface
 * MainActivity registers.
 *
 * `window.__glyph` is ONE object shared by every module that answers the host,
 * and that is the reason this file exists. The notes store used to assign the
 * whole object for its refresh hook; the moment a second answer (capture) was
 * needed, each assignment would have wiped the other's, and the failure is a
 * side-key press that silently does nothing when the app is open - the one case
 * a desktop test never exercises. Registration merges; removal deletes one key.
 */

type Handler = () => void;

interface GlyphInbound {
  refresh?: Handler;
  capture?: Handler;
  /** Android answered the notification-permission prompt: update alerts' state may have changed. */
  alerts?: Handler;
  /** A picked picture, as JSON: `{ path }`, `{ cancelled: true }` or `{ error }` (core/images.ts). */
  image?: (json: string) => void;
  /** The back gesture: true if the page used it, false at the root (core/back.ts). */
  back?: () => boolean;
  /** The hinge angle in degrees, 0 closed to 180 flat, as it changes on a folding phone (core/unfold.ts). */
  hinge?: (angle: number) => void;
  /** The screen went off during a recording: the side key was pressed to stop (native generation 12). */
  screenOff?: Handler;
  /**
   * A meeting's service has something to say (native generation 20): it started, was muted or unmuted by another
   * app, stopped, was discarded from its notification, could not start, or the microphone was granted or refused.
   * JSON, one registrant (capture/meetingLive.ts), which parses it and fans it out.
   */
  meeting?: (json: string) => void;
  /** A meeting's write-up finished, however it finished: JSON `{ id, outcome }` (ai/summaries.ts). */
  recordingDone?: (json: string) => void;
  /** The meeting's own notification prompt was answered: whether Ghost.md may notify may have changed (capture/meetingLive.ts). */
  notified?: Handler;
}

interface GlyphHostBridge {
  takeLaunch(): string;
  isLocked(): boolean;
  endCapture(leave: boolean): void;
  /**
   * Hand a downloaded, verified APK to Android's installer: "started", or
   * "permission" when Glyph first has to be allowed to install apps (the
   * activity opens that settings page), or a short reason it could not.
   * Optional: builds from before OTA do not have it.
   */
  installApk?(path: string): string;
  // The assistant helpers, for the side-key guide. Optional: an over-the-air
  // page can be running on an APK from before they existed.
  /** Whether Glyph holds the digital assistant role, which the side key's press-and-hold opens. */
  isAssistant?(): boolean;
  /** Open the settings screen where the assistant app is chosen; true if one opened. */
  openAssistantSettings?(): boolean;
  /** `Build.MANUFACTURER`, e.g. "samsung". */
  deviceMaker?(): string;
  // Update alerts (0.3.2). Optional for the same reason.
  /** "off", "on", or "blocked" (on, but Android is not allowing Glyph's notifications). */
  updateAlerts?(): string;
  /** Turn update alerts on or off; answers the new state. May raise Android's permission prompt. */
  setUpdateAlerts?(on: boolean): string;
  // Pictures (native generation 8). Optional for the same reason.
  /** Open the phone's picture picker; "started", or why not. The picture arrives as an `image` event. */
  pickImage?(): string;
  // The side key to stop (native generation 12). Optional for the same reason.
  /** A recording started or ended: keeps the screen on, and reports it going off as `screenOff`. */
  setCapturing?(on: boolean): void;
  /** The clipboard as JSON: `{ text }`, `{ path }` for a picture, `{ error }`, or `{}` (generation 12). */
  readClipboard?(): string;
  // The system bars (native generation 15). Optional for the same reason.
  /** Dark status and navigation bar icons on a light page, light ones on a dark page. */
  setLightChrome?(light: boolean): void;
  // The notes' folder (native generation 18). Optional for the same reason.
  /** Opens the notes' folder in the phone's Files app (files/LibraryDocuments.kt). */
  browseFiles?(): void;
  // Meetings (native generation 20; docs/DESIGN.md §127 sections 3 to 5). Optional for the same reason: a page that
  // arrived over the air can be running on a binary from before the service existed.
  /**
   * Start recording a meeting into `noteId`'s tape (capture/MeetingService.kt): "started", "permission" when the
   * microphone has yet to be granted (the activity asks; the answer arrives as `meeting { event: "permission" }`),
   * "recording" when a meeting is already being recorded, or a short reason it could not.
   */
  startMeeting?(noteId: string, title: string): string;
  /** Done: the service stops recording and carries on as the write-up. */
  stopMeeting?(): void;
  /** The service stops and deletes the WAV; the page deletes the note itself. */
  discardMeeting?(): void;
  /** The meeting in hand and the write-ups, as JSON (capture/meetingLive.ts `MeetingState`). */
  meetingState?(): string;
  /** Ask to be allowed to notify: "allowed", "asked" (the answer arrives as `notified`) or "blocked". */
  requestNotifications?(): string;
  /** Whether a notification from Ghost.md would show at all. */
  canNotify?(): boolean;
  /** Queue the write-up of `noteId`, now or when the phone is charging: "queued", or why not. */
  writeUp?(noteId: string, now: boolean): string;
  /** Cancel one write-up, for a note put in the trash. */
  cancelWriteUp?(noteId: string): void;
  /** Cancel every write-up, before a reset. */
  cancelWriteUps?(): void;
  /** The page has deleted a note the notification's Discard threw away. */
  forgetDiscarded?(noteId: string): void;
  /** A `ghostmd://` link the activity was opened with, once; "" when there is none. */
  takeLink?(): string;
}

declare global {
  interface Window {
    __glyph?: GlyphInbound;
    GlyphHost?: GlyphHostBridge;
    /** This page load's launch reason, read from the host once; see takeCaptureLaunch. */
    __glyphLaunch?: string;
  }
}

/** Answer a call from the activity. Returns the unregister function. */
export function answerHost<K extends keyof GlyphInbound>(name: K, handler: NonNullable<GlyphInbound[K]>): () => void {
  window.__glyph = { ...window.__glyph, [name]: handler };
  return () => {
    if (window.__glyph?.[name] === handler) {
      const next = { ...window.__glyph };
      delete next[name];
      window.__glyph = next;
    }
  };
}

/**
 * Whether this launch was a request to record, consumed on read.
 *
 * The browser has no host, and a dev URL with `?capture` stands in for the side
 * key so the capture screen can be opened and iterated on without a phone.
 */
export function takeCaptureLaunch(): boolean {
  // The host's answer is consumed on read, so it is kept on the page: when an
  // over-the-air frontend starts rendering and the loader falls back to the
  // embedded one (index.html), the second App asks again in the same page, and
  // a side-key cold start must still open the capture screen rather than the list.
  if (window.GlyphHost) {
    window.__glyphLaunch ??= window.GlyphHost.takeLaunch();
    return window.__glyphLaunch === 'capture';
  }
  return new URLSearchParams(window.location.search).has('capture');
}

/** Whether the phone is locked. False wherever there is no host to ask. */
export function isLocked(): boolean {
  try {
    return window.GlyphHost?.isLocked() ?? false;
  } catch {
    return false;
  }
}

/** Tell the activity a capture is over; `leave` returns a locked phone to its lock screen. */
export function endCapture(leave: boolean): void {
  try {
    window.GlyphHost?.endCapture(leave);
  } catch {
    // No host, or a host from an older build: nothing to withdraw.
  }
}

/**
 * A recording started or ended. On a phone that can tell (generation 12) the
 * screen stays on while it runs, and pressing the side key, which turns the
 * screen off, stops it through `screenOff`. Answers whether this phone does
 * that, so the recorder can say "Press the side key to stop" only where it is
 * true.
 */
export function setCapturing(on: boolean): boolean {
  try {
    if (typeof window.GlyphHost?.setCapturing !== 'function') return false;
    window.GlyphHost.setCapturing(on);
    return true;
  } catch {
    return false;
  }
}

// ---- meetings (native generation 20) ---------------------------------------------------------
//
// Each call below reaches a method the activity may not have (an over-the-air page on an older APK) and answers a safe
// default when it does not, as `setCapturing` does: the page never throws over a bridge it cannot see.

/** What `startMeeting` answers where there is no service to start one: the page undoes and says this. */
export const NO_MEETING_SERVICE = 'Meetings need the newest Ghost.md.';

/** Ask the service to record a meeting into `noteId`'s tape; see `GlyphHostBridge.startMeeting` for the answers. */
export function startMeetingOnHost(noteId: string, title: string): string {
  try {
    return window.GlyphHost?.startMeeting?.(noteId, title) ?? NO_MEETING_SERVICE;
  } catch {
    return NO_MEETING_SERVICE;
  }
}

/** Done: the service stops recording and carries on as the write-up. */
export function stopMeetingOnHost(): void {
  try {
    window.GlyphHost?.stopMeeting?.();
  } catch {
    // No host, or one from before meetings: nothing is recording.
  }
}

/** The service stops and deletes the WAV; the note is the page's to delete. */
export function discardMeetingOnHost(): void {
  try {
    window.GlyphHost?.discardMeeting?.();
  } catch {
    // As above.
  }
}

/** The service's state as JSON text, or null where there is no service to ask. */
export function meetingStateJson(): string | null {
  try {
    return window.GlyphHost?.meetingState?.() ?? null;
  } catch {
    return null;
  }
}

export type NotificationsAnswer = 'allowed' | 'asked' | 'blocked';

/** Ask to be allowed to notify. "blocked" where there is nobody to ask. */
export function requestNotifications(): NotificationsAnswer {
  try {
    const answer = window.GlyphHost?.requestNotifications?.();
    return answer === 'allowed' || answer === 'asked' ? answer : 'blocked';
  } catch {
    return 'blocked';
  }
}

/** Whether a notification from Ghost.md would show. False where there is no host to say. */
export function canNotify(): boolean {
  try {
    return window.GlyphHost?.canNotify?.() === true;
  } catch {
    return false;
  }
}

/** Queue `noteId`'s write-up, now or when the phone is charging. False where there is no service. */
export function writeUpOnHost(noteId: string, now: boolean): boolean {
  try {
    return window.GlyphHost?.writeUp?.(noteId, now) === 'queued';
  } catch {
    return false;
  }
}

/** Cancel one write-up: a note put in the trash. */
export function cancelWriteUpOnHost(noteId: string): void {
  try {
    window.GlyphHost?.cancelWriteUp?.(noteId);
  } catch {
    // Nothing to cancel on this host.
  }
}

/** Cancel every write-up, before a reset. */
export function cancelWriteUpsOnHost(): void {
  try {
    window.GlyphHost?.cancelWriteUps?.();
  } catch {
    // As above.
  }
}

/** The page has deleted a note the notification's Discard threw away, so the host can stop listing it. */
export function forgetDiscardedOnHost(noteId: string): void {
  try {
    window.GlyphHost?.forgetDiscarded?.(noteId);
  } catch {
    // As above.
  }
}

/** A `ghostmd://` link the activity was opened with, taken once; '' when there is none or nobody to ask. */
export function takeHostLink(): string {
  try {
    return window.GlyphHost?.takeLink?.() ?? '';
  } catch {
    return '';
  }
}
