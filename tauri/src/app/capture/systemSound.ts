import { useEffect, useState } from 'react';
import { meetingSoundOnHost } from '../core/host.ts';
import { hasNativeGeneration } from '../core/nativeGeneration.ts';
import { isAndroid, isMacApp } from '../core/platform.ts';
import { invoke, isTauri } from '../core/tauri.ts';

/**
 * A meeting with the device's own sound in it, beside the microphone (docs/DESIGN.md "Meetings with the computer's
 * sound"; Matt: "can you make it so that the app can listen to the microphone and system audio so that we can record
 * meetings with raw audio?"). One switch, `meetingSound` (core/preferences.ts), off by default, on the + sheet's
 * Meeting, in Settings › Recording, and on the Mac in the meeting recorder itself.
 *
 * On the Mac it is everything the Mac plays, through a Core Audio process tap (src-tauri/src/system_audio.rs, macOS
 * 14.2 and later; an older Mac records a meeting's microphone, and says so): the other side of a Zoom or a Meet call
 * is in the tape and in the live words, because Rust adds it into each microphone chunk before the transcriber hears
 * it. On Android it is other apps' sound through AudioPlaybackCapture (capture/OtherApps.kt, Android 10 and later),
 * which Android allows for media and games and never for calls: a call app's voices are USAGE_VOICE_COMMUNICATION,
 * which no app may record. The words below say that plainly, wherever the switch is.
 *
 * Both arrived with native generation 25 (`MEETING_SOUND_GENERATION`): a page that came over the air to an older
 * binary offers neither, and records the microphone as before.
 */

/** The binary generation with the Mac's tap commands and Android's `startMeetingWith` and `meetingSound`. */
export const MEETING_SOUND_GENERATION = 25;

export interface SoundSupport {
  supported: boolean;
  /** Why not, in the app's words; null when it is supported. */
  reason: string | null;
}

/** What the switch is called, and what it says under it, on this platform. */
export function meetingSoundWords(): { label: string; hint: string } {
  if (isAndroid) {
    return {
      label: 'Include sound from other apps',
      hint: 'Android lets Ghost.md hear media and games, never calls. It asks to share your screen each time; only the sound is kept.',
    };
  }
  return {
    label: "Record the computer's sound too",
    hint: 'Both sides of a call: what this Mac plays goes into the recording with the microphone. macOS asks the first time.',
  };
}

/** Said in the recorder when the tap is open and nothing has come through it for a while. */
export const NOTHING_FROM_THE_MAC =
  "Nothing from this Mac's sound yet. If it asked, allow Ghost.md in System Settings › Privacy & Security › Screen & System Audio Recording.";

/** Whether this device can put its own sound in a meeting: null where the question does not arise (a browser, iOS, an older binary). */
export async function meetingSoundSupport(): Promise<SoundSupport | null> {
  if (!isTauri() || !(isAndroid || isMacApp)) return null;
  if (!(await hasNativeGeneration(MEETING_SOUND_GENERATION))) return null;
  if (isAndroid) return meetingSoundOnHost();
  try {
    return await invoke<SoundSupport>('system_audio_available');
  } catch {
    return null;
  }
}

/** `meetingSoundSupport`, for a component: null until it has answered, and wherever it answers null. */
export function useMeetingSoundSupport(): SoundSupport | null {
  const [support, setSupport] = useState<SoundSupport | null>(null);
  useEffect(() => {
    let live = true;
    void meetingSoundSupport().then((answer) => {
      if (live) setSupport(answer);
    });
    return () => {
      live = false;
    };
  }, []);
  return support;
}

/** Whether a phone's meeting should ask for other apps' sound: the switch on, and a binary and an Android that have it. */
export async function wantsOtherApps(on: boolean): Promise<boolean> {
  if (!on || !isAndroid) return false;
  return (await meetingSoundSupport())?.supported === true;
}

// ---- the Mac's tap, for the recorder in meeting mode (capture/ComputerSound.tsx) ------------------------------------

export interface SoundStarted {
  capturing: boolean;
  reason: string | null;
}

/**
 * Opens the tap for the running capture: after `capture_start` has resolved, since a start closes any tap a reloaded
 * page left behind. The first one on a Mac raises the "System Audio Recording Only" consent.
 */
export async function startComputerSound(): Promise<SoundStarted> {
  try {
    return await invoke<SoundStarted>('system_audio_start');
  } catch (failure) {
    return { capturing: false, reason: String(failure) };
  }
}

/** Closes it; the capture's stop and cancel close it too, so this is for the switch turned off mid-meeting. */
export async function stopComputerSound(): Promise<void> {
  await invoke('system_audio_stop').catch(() => undefined);
}

/** Whether it is open, and whether anything but silence has come through it (a refused consent delivers zeros). */
export async function computerSoundStatus(): Promise<{ capturing: boolean; heard: boolean } | null> {
  try {
    return await invoke<{ capturing: boolean; heard: boolean }>('system_audio_status');
  } catch {
    return null;
  }
}
