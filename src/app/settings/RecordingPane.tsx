import { useEffect, useState } from 'react';
import { SegmentedControl, Slider, Switch } from '@glacier/react';
import { MEETING_GENERATION } from '../capture/meeting.ts';
import { canNotifyNow, useCanNotify } from '../capture/meetingLive.ts';
import { defaultHeight, saveHeight, savedHeight, useSideKeySpot } from '../capture/sideKey.ts';
import { SideKeyWaves } from '../capture/SideKeyWaves.tsx';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { requestNotifications } from '../core/host.ts';
import { hasNativeGeneration } from '../core/nativeGeneration.ts';
import { isAndroid } from '../core/platform.ts';
import { setPreferences, usePreferences, type Summaries, type WriteUp } from '../core/preferences.ts';
import { audioRemoved, deleteRecordings } from '../core/recordings.ts';
import { listNotes, type Note } from '../core/store.ts';
import { isTauri } from '../core/tauri.ts';
import { headStatus } from '../tapes/useTape.ts';
import { PaneSection, RowAction, SettingRow } from './kit/settingsKit.tsx';
import { oldTapes, tapeBytes, tapeSize, tapesHere } from './tapes.ts';

/**
 * Recording: how a take ends, whether a command needs its word first, what happens to the words afterwards, and - on
 * Android, where there is a side key - where that key is. Listed on Android and on the Mac (SettingsSheet.tsx): the
 * Mac records through Speak, runs the better words and the summaries, and its rows had no home there before
 * (docs/DESIGN.md §127 section 2). The side key's own section is Android's alone.
 *
 * Meetings (§127 section 4), on an Android phone with the service that records them (native generation 20): when a
 * meeting is written up with the app closed, and whether the phone may say when it is. And Tapes (§127 section 6),
 * on Android and the Mac: how much room the recordings take, said from their lengths (an hour is about 115 MB),
 * and the way to give the room back for the old ones, keeping every word and phrase. That asks twice, as emptying
 * the trash does, and only where the binary can remove a file (generation 20).
 */

/** When a meeting is written up (core/preferences.ts `WriteUp`), in the choice's order. */
const WRITE_UP_CHOICES: { value: WriteUp; label: string }[] = [
  { value: 'charging', label: 'When charging or above half' },
  { value: 'now', label: 'Straight away' },
];

/** How long the remove stays armed after its first tap. */
const ARMED_MS = 5000;

/** Which recordings are summarised on their own (core/preferences.ts `Summaries`), in the choice's order. */
const SUMMARY_CHOICES: { value: Summaries; label: string }[] = [
  { value: 'meetings', label: 'Meetings' },
  { value: 'long', label: 'Meetings and long voice notes' },
  { value: 'off', label: 'Off' },
];

export function RecordingPane() {
  const prefs = usePreferences();
  const meetings = useMeetingGeneration();
  return (
    <>
      <PaneSection title={isAndroid ? 'The side key' : 'While recording'}>
        <SettingRow
          label="Stop when I go quiet"
          hint="Saves the recording after four seconds of quiet, once you've started talking. You can still press the side key or tap Done."
          control={<Switch aria-label="Stop when I go quiet" checked={prefs.quietStop} onCheckedChange={(quietStop) => setPreferences({ quietStop })} />}
        />
        <SettingRow
          label="Commands start with “hey Ghost”"
          hint="Say “Hey Ghost, add call Sam to House TODOs” and the words go into that note as you say them. Not this note, Discard or Undo takes them back. Off, “Add a note to House TODOs…” at the very start of a recording works without it."
          control={
            <Switch aria-label="Commands start with hey Ghost" checked={prefs.commandWord} onCheckedChange={(commandWord) => setPreferences({ commandWord })} />
          }
        />
        <SettingRow
          label="Review after recording"
          hint="When you stop, a slower speech model listens again and the language model thinks the note through out loud, then shows what it would fix for you to keep or commit. For recordings under three minutes."
          control={<Switch aria-label="Review after recording" checked={prefs.review} onCheckedChange={(review) => setPreferences({ review })} />}
        />
      </PaneSection>
      {isAndroid ? <SideKeyPlace /> : null}
      <PaneSection title="After recording">
        <SettingRow
          label="Better words"
          hint="After you finish, a larger model goes over the recording and fixes the words. A few seconds of the phone per minute of speech."
          control={<Switch aria-label="Better words after recording" checked={prefs.refine} onCheckedChange={(refine) => setPreferences({ refine })} />}
        />
        <SettingRow
          label="Summaries"
          hint="The language model on the phone writes a summary under the title. What was said, what was decided, and your to-dos. A long voice note is one over three minutes. A few minutes of the phone for a long recording."
          layout="stacked"
          control={
            <SegmentedControl aria-label="Summaries" fullWidth size="sm" options={SUMMARY_CHOICES} value={prefs.summaries} onValueChange={(value) => setPreferences({ summaries: value as Summaries })} />
          }
        />
      </PaneSection>
      {isAndroid && meetings ? <Meetings writeUp={prefs.writeUp} /> : null}
      {isTauri() ? <Tapes canRemove={meetings} /> : null}
    </>
  );
}

/** Whether this binary has the meeting service and the recordings' commands (capture/meeting.ts). */
function useMeetingGeneration(): boolean {
  const [has, setHas] = useState(false);
  useEffect(() => {
    let live = true;
    void hasNativeGeneration(MEETING_GENERATION).then((answer) => {
      if (live) setHas(answer);
    });
    return () => {
      live = false;
    };
  }, []);
  return has;
}

/**
 * Meetings: when the phone writes one up with the app closed, and whether it may say when it has. The notification
 * is the meeting's own permission (never the update alerts'), read fresh as the page opens and again once the
 * prompt is answered, since the person can turn it off in the phone's settings while the app is closed.
 */
function Meetings({ writeUp }: { writeUp: WriteUp }) {
  const canNotify = useCanNotify();
  const [blocked, setBlocked] = useState(false);
  useEffect(() => void canNotifyNow(), []);
  const allow = () => {
    if (requestNotifications() === 'blocked') setBlocked(true);
    canNotifyNow();
  };
  return (
    <PaneSection title="Meetings">
      <SettingRow
        label="Write up"
        hint="A meeting is written up when the phone is charging or above half. Straight away uses more of the battery."
        layout="stacked"
        control={<SegmentedControl aria-label="Write up" fullWidth size="sm" options={WRITE_UP_CHOICES} value={writeUp} onValueChange={(value) => setPreferences({ writeUp: value as WriteUp })} />}
      />
      <SettingRow
        label="Tell me when a meeting is written up"
        hint={blocked && !canNotify ? 'Notifications are off for Ghost.md in the phone’s settings.' : 'A notification, with the first line of the summary once the phone is unlocked.'}
        value={canNotify ? 'On' : undefined}
        control={canNotify ? undefined : <RowAction onPress={allow}>Allow</RowAction>}
      />
    </PaneSection>
  );
}

/**
 * Tapes: the room the recordings take on this device, from their lengths, and the way to give back the room the old
 * ones take. The audio goes; the words and the phrases stay, so the note reads and the transcript plays as text.
 */
function Tapes({ canRemove }: { canRemove: boolean }) {
  const [notes, setNotes] = useState<Note[] | null>(null);
  const [armed, setArmed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  /** Tapes whose audio the `rec` scheme answered 404 for: a synced note whose audio stayed where it was made. */
  const [elsewhere, setElsewhere] = useState<ReadonlySet<string>>(() => new Set());
  useEffect(() => {
    let live = true;
    void listNotes()
      .then(async (all) => {
        if (!live) return;
        setNotes(all);
        // Asked of each tape only where a HEAD reads nothing (native generation 20, which `canRemove` is).
        if (!canRemove) return;
        const answers = await Promise.all(tapesHere(all, audioRemoved).map(async (note) => [note.id, await headStatus(note.id)] as const));
        if (live) setElsewhere(new Set(answers.filter(([, status]) => status === 404).map(([id]) => id)));
      })
      .catch(() => undefined);
    return () => {
      live = false;
    };
  }, [canRemove]);
  useEffect(() => {
    if (!armed) return undefined;
    const id = window.setTimeout(() => setArmed(false), ARMED_MS);
    return () => window.clearTimeout(id);
  }, [armed]);
  // Only the tapes whose audio is here: not one this row removed, nor one the `rec` scheme says is elsewhere.
  const taped = tapesHere(notes ?? [], (id) => audioRemoved(id) || elsewhere.has(id));
  const bytes = tapeBytes(taped);
  const old = oldTapes(taped, Date.now());
  const press = async () => {
    if (!armed) {
      setArmed(true);
      fireNativeHaptic('warning');
      return;
    }
    setBusy(true);
    setArmed(false);
    try {
      const done = await deleteRecordings(old.map((note) => note.id));
      setSaid(done.removed.length === 0 ? 'Nothing to remove.' : `Removed the audio of ${done.removed.length === 1 ? 'one tape' : `${done.removed.length} tapes`}. The words stay.`);
      setNotes((was) => (was ?? []).map((note) => (done.removed.includes(note.id) ? { ...note, recordingMs: 0 } : note)));
    } catch (failure) {
      setSaid(failureText(failure));
    } finally {
      setBusy(false);
    }
  };
  const size = notes === null ? 'Your tapes are being counted.' : taped.length === 0 ? 'No tapes on this device.' : `Your tapes take about ${tapeSize(bytes)} on this device.`;
  return (
    <PaneSection title="Tapes">
      <SettingRow
        label="Your tapes"
        hint={said ?? size}
        layout="stacked"
        control={
          canRemove ? (
            <RowAction onPress={() => void press()} disabled={busy || old.length === 0}>
              {busy ? 'Removing' : armed ? 'Tap again to remove the audio' : 'Remove audio older than a month'}
            </RowAction>
          ) : undefined
        }
      />
    </PaneSection>
  );
}

/**
 * Where the side key is, for the rings the recorder sends from it. Android
 * does not say where a phone's buttons are, so Glyph guesses from the model
 * and this lets the guess be moved: drag until the glow sits beside the key.
 */
function SideKeyPlace() {
  const [height, setHeight] = useState<number | null>(() => savedHeight());
  const [fallback, setFallback] = useState(0.4);
  useEffect(() => {
    let live = true;
    void defaultHeight().then((value) => {
      if (live) setFallback(value);
    });
    return () => {
      live = false;
    };
  }, []);
  const shown = height ?? fallback;
  const spot = useSideKeySpot(shown);
  return (
    <PaneSection
      title="Where the side key is"
      description="The recorder sends rings from the side key while you talk. If the glow isn't beside your key, slide it there."
    >
      {/* A phone's outline, upright, with the rings coming from its key. Inline so settings.css stays the kit's. */}
      <div
        style={{
          position: 'relative',
          inlineSize: '6.5rem',
          blockSize: '12rem',
          margin: 'var(--glacier-space-2) auto var(--glacier-space-3)',
          border: '2px solid var(--app-ink-3, var(--glacier-border-strong))',
          borderRadius: '1.1rem',
          overflow: 'hidden',
        }}
      >
        <SideKeyWaves spot={spot} contained />
      </div>
      <SettingRow
        label="Height"
        layout="stacked"
        control={
          <Slider
            aria-label="Side key height"
            min={0}
            max={100}
            step={1}
            value={Math.round(shown * 100)}
            onValueChange={(value) => {
              setHeight(value / 100);
              saveHeight(value / 100);
            }}
          />
        }
      />
      {height !== null ? (
        <SettingRow
          label="Use Ghost.md's guess"
          control={
            <RowAction
              onPress={() => {
                setHeight(null);
                saveHeight(null);
              }}
            >
              Reset
            </RowAction>
          }
        />
      ) : null}
    </PaneSection>
  );
}
