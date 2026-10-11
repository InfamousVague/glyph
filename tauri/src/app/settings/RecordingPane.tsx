import { useEffect, useState } from 'react';
import { Switch } from '@glacier/react';
import { MEETING_GENERATION } from '../capture/meeting.ts';
import { canNotifyNow, useCanNotify } from '../capture/meetingLive.ts';
import { MEETING_SOUND_GENERATION, meetingSoundSupport, meetingSoundWords, type SoundSupport } from '../capture/systemSound.ts';
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
import { oldTapes, tapeBytes, tapeSize, tapesHere } from './tapes.ts';

/**
 * Recording: the microphone and what happens to a take. Listed on Android and on the Mac (SettingsSheet.tsx): the Mac
 * records through Speak, runs the better words and the summaries, and its rows had no home there before
 * (docs/DESIGN.md §127 section 2). The side key's card, Android's alone, went on 2026-10-02 with the rings it placed
 * (docs/DESIGN.md §173).
 *
 * Cards since docs/DESIGN.md §138 (Matt: "also see if you can clean up / streamline settings a bit"): While recording
 * (it was "The side key" on Android, a title over rows about quiet and the review), After recording, and the Summaries
 * as three picks with a hint each (a segmented control's middle label, "Meetings and long voice notes", did not fit at
 * 412). The model that writes a take up moved to its own AI section (settings/AiPane.tsx; Matt: "move the Model
 * sections into an AI setting section"); the summaries and the review still read as what it does with a take.
 *
 * Meetings (§127 section 4), on an Android phone with the service that records them (native generation 20): whether
 * the phone may say when a meeting is written up, and when it is written up with the app closed. And Tapes (§127
 * section 6), on Android and the Mac: how much room the recordings take, said from their lengths (an hour is about
 * 115 MB) in the card's footer, and the way to give the room back for the old ones, keeping every word and phrase.
 * That asks twice, as emptying the trash does, and only where the binary can remove a file (generation 20). Until the
 * binary has said which generation it is, the row offers nothing and says nothing, rather than a reason that is gone a
 * moment later.
 *
 * A meeting's own sound (capture/systemSound.ts, native generation 25): on Android the Meetings card's first row,
 * "Include sound from other apps", which says Android's limit under it (media and games, never calls); on the Mac a
 * Meetings card of its own with "Record the computer's sound too". A binary before generation 25 shows the row with
 * the update it needs, and a Mac older than 14.2 with why it cannot, rather than a switch that would do nothing.
 *
 * The page's words say where the work is done: "the phone" on Android, "this Mac" on the Mac, as the Model card does.
 *
 * What the search finds here is RecordingPane.findable.ts, in this page's order.
 */

/** How long the remove stays armed after its first tap. */
const ARMED_MS = 5000;

/**
 * Which recordings are summarised on their own (core/preferences.ts `Summaries`), in the choice's order, each with what
 * it means, and `device` the one doing the work ("the phone", "this Mac").
 */
function summaryChoices(device: string): { value: Summaries; label: string; hint?: string }[] {
  return [
    { value: 'meetings', label: 'Meetings', hint: 'Every meeting, once it is done.' },
    // The three minutes are LONG_NOTE_MS (core/preferences.ts): one line to change, and this sentence with it.
    { value: 'long', label: 'Meetings and long voice notes', hint: `A long voice note is one over three minutes. A few minutes of ${device} for each.` },
    { value: 'off', label: 'Off' },
  ];
}

export function RecordingPane() {
  const prefs = usePreferences();
  const meetings = useMeetingGeneration();
  // Where the model does its work: the page is listed on Android and on the Mac (SettingsSheet.tsx).
  const device = isAndroid ? 'the phone' : 'this Mac';
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
          hint={`A larger model goes over the recording and fixes the words. A few seconds of ${device} per minute of speech.`}
          control={<Switch aria-label="Better words after recording" checked={prefs.refine} onCheckedChange={(refine) => setPreferences({ refine })} />}
        />
      </PaneSection>
      <PaneSection title="Summaries" description={`The language model on ${device} writes a summary under the title. What was said, what was decided, and your to-dos.`}>
        {summaryChoices(device).map((choice) => (
          <SettingRow
            key={choice.value}
            label={choice.label}
            hint={choice.hint}
            control={<Pick checked={prefs.summaries === choice.value} label={choice.label} onPress={() => setPreferences({ summaries: choice.value })} />}
          />
        ))}
      </PaneSection>
      {isAndroid && meetings === true ? <Meetings /> : null}
      {isTauri() && !isAndroid ? (
        <PaneSection title="Meetings">
          <MeetingSound />
        </PaneSection>
      ) : null}
      {isTauri() ? <Tapes canRemove={meetings} /> : null}
    </>
  );
}

/**
 * Whether this binary has the meeting service and the recordings' commands (capture/meeting.ts): null until it has
 * answered, so nothing is said about it before it has.
 */
function useMeetingGeneration(): boolean | null {
  const [has, setHas] = useState<boolean | null>(null);
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
      <MeetingSound />
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
 * Whether this device's own sound can go into a meeting: 'old' on a binary before generation 25, null until asked,
 * and the device's answer after.
 */
function useMeetingSound(): SoundSupport | 'old' | null {
  const [state, setState] = useState<SoundSupport | 'old' | null>(null);
  useEffect(() => {
    let live = true;
    void (async () => {
      if (!(await hasNativeGeneration(MEETING_SOUND_GENERATION))) {
        if (live) setState('old');
        return;
      }
      const support = await meetingSoundSupport();
      if (live) setState(support ?? { supported: false, reason: null });
    })();
    return () => {
      live = false;
    };
  }, []);
  return state;
}

/** The switch for a meeting's own sound (`meetingSound`), with the honest limit under it. */
function MeetingSound() {
  const prefs = usePreferences();
  const support = useMeetingSound();
  const words = meetingSoundWords();
  const can = support !== null && support !== 'old' && support.supported;
  const why =
    support === 'old'
      ? isAndroid
        ? 'Update Ghost.md to include sound from other apps.'
        : "Update Ghost.md to record the computer's sound."
      : support && !support.supported
        ? (support.reason ?? undefined)
        : undefined;
  return (
    <SettingRow
      label={words.label}
      hint={words.hint}
      control={can ? <Switch aria-label={words.label} checked={prefs.meetingSound} onCheckedChange={(meetingSound) => setPreferences({ meetingSound })} /> : undefined}
      disabledReason={why}
    />
  );
}

/**
 * Tapes: the room the recordings take on this device, from their lengths, and the way to give back the room the old
 * ones take. The audio goes; the words and the phrases stay, so the note reads and the transcript plays as text. The
 * room is the card's footer, a readout under its group, and so is what a removal did.
 */
function Tapes({ canRemove }: { canRemove: boolean | null }) {
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
        // A binary before generation 20 cannot remove a file: the row says so rather than offering nothing. Not yet
        // known (null), it says nothing.
        disabledReason={canRemove === false ? 'Update Ghost.md to remove audio here.' : undefined}
      />
    </PaneSection>
  );
}
