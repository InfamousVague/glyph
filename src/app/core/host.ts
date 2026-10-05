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
  /**
   * A picked film, as JSON (native generation 21): `{ copying: true }` once one is chosen, then `{ path, poster, ms,
   * width, height }`, `{ cancelled: true }` or `{ error }` (core/videos.ts). Its own event, never `image`'s, whose one
   * pending pick it must not answer.
   */
  video?: (json: string) => void;
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
  /** Android answered the location prompt (native generation 20): the page reads `locationAccess` again (core/location.ts). */
  location?: Handler;
  /**
   * Where an export goes (native generation 22; files/ExportTarget.kt): `{ fd, name }` for the file the picker made,
   * `{ cancelled: true }` or `{ error }` (core/exportAll.ts).
   */
  exportTarget?: (json: string) => void;
  /**
   * The folder picked for the library (native generation 25; files/LibraryTree.kt): `{ uri, name }` with its grant
   * kept, `{ cancelled: true }` or `{ error }` (plugins/folder/folder.ts).
   */
  libraryFolder?: (json: string) => void;
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
  /**
   * Open the Photo Picker for a film (native generation 21, docs/DESIGN.md §141, media/VideoPick.kt); "started". The
   * film, copied with its poster, arrives as a `video` event, and so does a phone with no picker, as `{ error }`.
   */
  pickVideo?(): string;
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
  /**
   * As `startMeeting`, with other apps' sound in the meeting when `otherApps` is set (native generation 25;
   * capture/OtherApps.kt): the activity asks Android's screen-share consent first, and the service starts once it is
   * answered, declined or not. Media and games only; Android never lets an app capture a call.
   */
  startMeetingWith?(noteId: string, title: string, otherApps: boolean): string;
  /** `{ supported, reason }` as JSON: whether this phone can put other apps' sound in a meeting (Android 10+). */
  meetingSound?(): string;
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
  // Location (native generation 20). Optional for the same reason; location/LocationAccess.kt.
  /** Whether the app may know where the phone is: "granted", "approximate", "ask" or "blocked" (denied twice, or off for the app). */
  locationAccess?(): string;
  /** Raises Android's location prompt; the answer arrives as a `location` event, after which `locationAccess` is read again. */
  requestLocation?(): void;
  /** Opens the app's own page in the phone's settings, where a blocked location is allowed again; true if it opened. */
  openLocationSettings?(): boolean;
  // The export of everything (native generation 22; files/ExportTarget.kt). Optional for the same reason.
  /** Opens the system's picker to make a zip of this name, a USB drive among its places: "started", or why not. */
  chooseExport?(name: string): string;
  /** The export failed or was stopped: the half-written file goes. */
  discardExport?(): void;
  /** The export is whole: the file stays. */
  exportDone?(): void;
  // The bell's rows as phone notifications (native generation 23; notices/NoticeAlerts.kt). Optional for the same reason.
  /** The session and switches the closed app's worker reads the feed with, as JSON, or "" to stop: "off", "on" or "blocked". */
  watchNotices?(json: string): string;
  /** One row as a notification, JSON `{ id, title, text?, link }`: "posted", "seen", "blocked", or a reason. */
  postNotice?(json: string): string;
  /** "off", "on" or "blocked". */
  noticesState?(): string;
  // The library in a folder of the person's (native generation 25; files/LibraryTree.kt). Optional for the same reason.
  /** Opens Android's folder picker: "started", or why not; the folder arrives as a `libraryFolder` event. */
  chooseLibraryFolder?(): string;
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

/**
 * Ask the service to record a meeting into `noteId`'s tape; see `GlyphHostBridge.startMeeting` for the answers. With
 * `otherApps`, other apps' sound too, where the binary has `startMeetingWith` (native generation 25); an older one
 * records the microphone, as it always has.
 */
export function startMeetingOnHost(noteId: string, title: string, otherApps = false): string {
  try {
    const host = window.GlyphHost;
    if (otherApps && host?.startMeetingWith) return host.startMeetingWith(noteId, title, true);
    return host?.startMeeting?.(noteId, title) ?? NO_MEETING_SERVICE;
  } catch {
    return NO_MEETING_SERVICE;
  }
}

/** Whether this phone can put other apps' sound in a meeting, as the activity said: null where it cannot be asked. */
export function meetingSoundOnHost(): { supported: boolean; reason: string | null } | null {
  try {
    const json = window.GlyphHost?.meetingSound?.();
    if (typeof json !== 'string') return null;
    const got = JSON.parse(json) as { supported?: unknown; reason?: unknown };
    if (typeof got.supported !== 'boolean') return null;
    return { supported: got.supported, reason: typeof got.reason === 'string' ? got.reason : null };
  } catch {
    return null;
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

/** What the phone does with the bell's rows: not watched, shown, or watched but kept from showing by Android. */
export type NoticesState = 'off' | 'on' | 'blocked';

function noticesStateOf(answer: unknown): NoticesState | null {
  return answer === 'off' || answer === 'on' || answer === 'blocked' ? answer : null;
}

/** The phone told what to watch for the closed app (JSON), or '' to stop; null where the binary cannot. */
export function watchNoticesOnHost(json: string): NoticesState | null {
  try {
    const host = window.GlyphHost;
    return host?.watchNotices ? noticesStateOf(host.watchNotices(json)) : null;
  } catch {
    return null;
  }
}

/**
 * One row as a phone notification: true when it was posted now or before. False where it could not be. A row with no
 * line under its title is sent without `text`, never `"text": null`: Android's `optString` reads a JSON null as the
 * word "null", and every such notification said it (Matt: "All the ghost notifications say "null" for the description").
 */
export function postNoticeOnHost(notice: { id: string; title: string; text?: string | null; link: string }): boolean {
  try {
    const { text, ...rest } = notice;
    const answer = window.GlyphHost?.postNotice?.(JSON.stringify(text?.trim() ? { ...rest, text } : rest));
    return answer === 'posted' || answer === 'seen';
  } catch {
    return false;
  }
}

/** The phone's notices as Android has them; null where the binary has none (a browser, the Mac, an older APK). */
export function noticesStateOnHost(): NoticesState | null {
  try {
    const host = window.GlyphHost;
    return host?.noticesState ? noticesStateOf(host.noticesState()) : null;
  } catch {
    return null;
  }
}
