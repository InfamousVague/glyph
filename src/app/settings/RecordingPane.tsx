import { useEffect, useState } from 'react';
import { Slider, Switch } from '@glacier/react';
import { MEETING_GENERATION } from '../capture/meeting.ts';
import { canNotifyNow, useCanNotify } from '../capture/meetingLive.ts';
import { defaultHeight, saveHeight, savedHeight, useSideKeySpot } from '../capture/sideKey.ts';
import { SideKeyWaves } from '../capture/SideKeyWaves.tsx';
import { failureText } from '../core/failure.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { requestNotifications } from '../core/host.ts';
import { hasNativeGeneration } from '../core/nativeGeneration.ts';
import { isAndroid } from '../core/platform.ts';
import { setPreferences, usePreferences, type Summaries } from '../core/preferences.ts';
import { audioRemoved, deleteRecordings } from '../core/recordings.ts';
import { listNotes, type Note } from '../core/store.ts';
import { isTauri } from '../core/tauri.ts';
import { headStatus } from '../tapes/useTape.ts';
import { PaneSection, Pick, RowAction, SettingRow } from './kit/settingsKit.tsx';
import { ModelCard } from './ModelCard.tsx';
import { oldTapes, tapeBytes, tapeSize, tapesHere } from './tapes.ts';

/**
 * Recording: the microphone, what happens to a take, the model that writes it up, and the side key. Listed on Android
 * and on the Mac (SettingsSheet.tsx): the Mac records through Speak, runs the better words and the summaries, and its
 * rows had no home there before (docs/DESIGN.md §127 section 2). The side key's card is Android's alone, and last,
 * since it is set once.
 *
 * Cards since docs/DESIGN.md §138 (Matt: "also see if you can clean up / streamline settings a bit"): While recording
 * (it was "The side key" on Android, a title over rows about quiet and the review), After recording, the Summaries as
 * three picks with a hint each (a segmented control's middle label, "Meetings and long voice notes", did not fit at
 * 412), and the Model (ModelCard.tsx), which was the Formatting page: it writes the summaries and the review, so it
 * sits beside them. In the app only, where there are models to fetch.
 *
 * Meetings (§127 section 4), on an Android phone with the service that records them (native generation 20): whether
 * the phone may say when a meeting is written up, and when it is written up with the app closed. And Tapes (§127
 * section 6), on Android and the Mac: how much room the recordings take, said from their lengths (an hour is about
 * 115 MB) in the card's footer, and the way to give the room back for the old ones, keeping every word and phrase.
 * That asks twice, as emptying the trash does, and only where the binary can remove a file (generation 20).
 *
 * What the search finds here is RecordingPane.findable.ts, in this page's order.
 */

/** How long the remove stays armed after its first tap. */
const ARMED_MS = 5000;

/** Which recordings are summarised on their own (core/preferences.ts `Summaries`), in the choice's order, each with what it means. */
const SUMMARY_CHOICES: { value: Summaries; label: string; hint?: string }[] = [
  { value: 'meetings', label: 'Meetings', hint: 'Every meeting, once it is done.' },
  // The three minutes are LONG_NOTE_MS (core/preferences.ts): one line to change, and this sentence with it.
  { value: 'long', label: 'Meetings and long voice notes', hint: 'A long voice note is one over three minutes. A few minutes of the phone for each.' },
  { value: 'off', label: 'Off' },
];

export function RecordingPane() {
  const prefs = usePreferences();
  const meetings = useMeetingGeneration();
  return (
    <>
      <PaneSection title="While recording">
        <SettingRow
          label="Stop when I go quiet"
          hint={
            isAndroid
              ? "Saves after four seconds of quiet, once you've started talking. The side key and Done still work."
              : "Saves after four seconds of quiet, once you've started talking. Done still works."
          }
          control={<Switch aria-label="Stop when I go quiet" checked={prefs.quietStop} onCheckedChange={(quietStop) => setPreferences({ quietStop })} />}
        />
        <SettingRow
          label="Review after recording"
          hint="After you stop, a slower listen and a read-through, with what it would fix for you to keep. For recordings under three minutes."
          control={<Switch aria-label="Review after recording" checked={prefs.review} onCheckedChange={(review) => setPreferences({ review })} />}
        />
      </PaneSection>
      <PaneSection title="After recording">
        <SettingRow
          label="Better words"
          hint="A larger model goes over the recording and fixes the words. A few seconds of the phone per minute of speech."
          control={<Switch aria-label="Better words after recording" checked={prefs.refine} onCheckedChange={(refine) => setPreferences({ refine })} />}
        />
      </PaneSection>
      <PaneSection title="Summaries" description="The language model on the phone writes a summary under the title. What was said, what was decided, and your to-dos.">
        {SUMMARY_CHOICES.map((choice) => (
          <SettingRow
            key={choice.value}
            label={choice.label}
            hint={choice.hint}
            control={<Pick checked={prefs.summaries === choice.value} label={choice.label} onPress={() => setPreferences({ summaries: choice.value })} />}
          />
        ))}
      </PaneSection>
      {isTauri() ? <ModelCard /> : null}
      {isAndroid && meetings ? <Meetings /> : null}
      {isTauri() ? <Tapes canRemove={meetings} /> : null}
      {isAndroid ? <SideKeyPlace /> : null}
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
 * Meetings: whether the phone may say when one is written up, and when it writes one up with the app closed. The
 * notification is the meeting's own permission (never the update alerts'), read fresh as the page opens and again
 * once the prompt is answered, since the person can turn it off in the phone's settings while the app is closed.
 *
 * Write up is a switch over the two-way preference (`writeUp`, core/preferences.ts) since §138: off is "charging",
 * its default, and on is "now". The values kept, and synced, are the same two, so nothing was migrated.
 */
function Meetings() {
  const prefs = usePreferences();
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
        label="Tell me when a meeting is written up"
        hint={blocked && !canNotify ? 'Notifications are off for Ghost.md in the phone’s settings.' : 'A notification, with the first line of the summary once the phone is unlocked.'}
        value={canNotify ? 'On' : undefined}
        control={canNotify ? undefined : <RowAction onPress={allow}>Allow</RowAction>}
      />
      <SettingRow
        label="Write up straight away"
        hint="Off, a meeting is written up when the phone is charging or above half. On, straight away, which uses more of the battery."
        control={
          <Switch aria-label="Write up straight away" checked={prefs.writeUp === 'now'} onCheckedChange={(now) => setPreferences({ writeUp: now ? 'now' : 'charging' })} />
        }
      />
    </PaneSection>
  );
}

/**
 * Tapes: the room the recordings take on this device, from their lengths, and the way to give back the room the old
 * ones take. The audio goes; the words and the phrases stay, so the note reads and the transcript plays as text. The
 * room is the card's footer, a readout under its group, and so is what a removal did.
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
    <PaneSection title="Tapes" footer={said ?? size}>
      <SettingRow
        label="Remove audio older than a month"
        hint="Every word and phrase stays. Only the audio goes."
        control={
          canRemove ? (
            <RowAction onPress={() => void press()} disabled={busy || old.length === 0}>
              {busy ? 'Removing' : armed ? 'Tap again' : 'Remove'}
            </RowAction>
          ) : undefined
        }
        // A binary before generation 20 cannot remove a file: the row says so rather than offering nothing.
        disabledReason={canRemove ? undefined : 'Update Ghost.md to remove audio here.'}
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
    <PaneSection title="The side key" description="The recorder sends rings from the side key while you talk. If the glow isn't beside your key, slide it there.">
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
