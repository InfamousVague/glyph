import { useEffect, useRef, useState } from 'react';
import { fireNativeHaptic } from '../core/haptics.ts';
import { setPreferences, usePreferences } from '../core/preferences.ts';
import { computerSoundStatus, NOTHING_FROM_THE_MAC, startComputerSound, stopComputerSound, useMeetingSoundSupport } from './systemSound.ts';

/**
 * The Mac's own sound in the meeting recorder (capture/CaptureScreen.tsx in meeting mode; capture/systemSound.ts): one
 * word in the top line, which says whether this Mac's sound is going into the recording and turns it on or off then
 * and there, the switch (`meetingSound`) with it. The tap is opened once the capture is running in Rust (`live`), and
 * the capture's own stop and cancel close it.
 *
 * What it says: "With this Mac's sound" while the tap is open, "This Mac's sound: off" when it is not, and nothing on a
 * Mac that cannot (older than 14.2, or a binary before generation 25), whose meetings are the microphone as before. A
 * tap that opened and has heard nothing for a while gets one line, `onSay`, with where macOS keeps the switch, since a
 * refused consent is silence rather than an error; and a tap that would not open says why the same way.
 */
const NOTHING_AFTER_MS = 8_000;
const ASK_EVERY_MS = 1_500;

export function ComputerSound({ live, className, onSay }: { live: boolean; className?: string; onSay: (text: string) => void }) {
  const support = useMeetingSoundSupport();
  const prefs = usePreferences();
  const wanted = prefs.meetingSound && support?.supported === true;
  const [open, setOpen] = useState(false);
  const said = useRef(false);
  const latestSay = useRef(onSay);
  latestSay.current = onSay;

  useEffect(() => {
    if (!live || !wanted) return undefined;
    let alive = true;
    let opened = false;
    let timer = 0;
    const since = Date.now();
    void startComputerSound().then((started) => {
      if (!alive) {
        if (started.capturing) void stopComputerSound();
        return;
      }
      opened = started.capturing;
      setOpen(started.capturing);
      if (!started.capturing) {
        if (started.reason) latestSay.current(started.reason);
        return;
      }
      // Asked a few times a second's worth apart until something is heard, or once it is clear nothing will be.
      timer = window.setInterval(() => {
        void computerSoundStatus().then((status) => {
          if (!alive || !status) return;
          if (status.heard || !status.capturing) window.clearInterval(timer);
          if (!status.capturing) setOpen(false);
          else if (!status.heard && !said.current && Date.now() - since > NOTHING_AFTER_MS) {
            said.current = true;
            latestSay.current(NOTHING_FROM_THE_MAC);
          }
        });
      }, ASK_EVERY_MS);
    });
    return () => {
      alive = false;
      window.clearInterval(timer);
      if (opened) void stopComputerSound();
      setOpen(false);
    };
  }, [live, wanted]);

  if (support?.supported !== true) return null;
  const toggle = () => {
    fireNativeHaptic('selection');
    setPreferences({ meetingSound: !prefs.meetingSound });
  };
  return (
    <button type="button" className={`app-word ${className ?? ''}`} onClick={toggle} aria-pressed={wanted} title={wanted ? "Stop recording this Mac's sound" : "Record this Mac's sound too"}>
      {wanted ? (open ? "With this Mac's sound" : "This Mac's sound…") : "This Mac's sound: off"}
    </button>
  );
}
