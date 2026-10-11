import { MEETING_GENERATION } from '../capture/meeting.ts';
import { hasNativeGeneration } from './nativeGeneration.ts';
import { readStored, writeStored } from './stored.ts';
import { invoke, isTauri } from './tauri.ts';

/**
 * The recordings' commands that came with the meeting service (native generation 20; docs/DESIGN.md §127 sections
 * 4 and 6): the result of a write-up done with the app closed, the state of every write-up, a tape's digest for
 * sync, and removing tapes' audio. Each is asked only of a binary that has it (core/nativeGeneration.ts) and answers
 * nothing on an older one, so a page that arrived over the air runs on a generation-19 APK as it did.
 *
 * The last answer to `recordingJobState` is kept here, so the queues can ask whether a write-up is running without
 * a trip to Rust (`writeUpRunningNow`): the refine queue holds while one is, since both want the same speech model.
 */

/** What a write-up left for the page (src-tauri/src/jobs.rs `JobResult`): the model's answer, raw, or null with summaries off. */
export interface RecordingResult {
  summary: string | null;
  model: string;
  transcriptChars: number;
  finishedAt: number;
}

export type RecordingJobPhase = 'queued' | 'listening' | 'summarizing' | 'waiting' | 'needsModel' | 'failed' | 'done' | 'cancelled';

/** One write-up as its progress file says it (src-tauri/src/jobs.rs `Progress`, the fields the page reads). */
export interface RecordingJobState {
  id: string;
  title: string;
  phase: RecordingJobPhase;
  /** What a `waiting` job waits for: the battery, the heat, a dictation, or a retry after an error. */
  waitingFor: string | null;
  percent: number;
  error: string | null;
  updatedAt: number;
}

/** Whether this binary has the commands, asked once per page load. */
function available(): Promise<boolean> {
  if (!isTauri()) return Promise.resolve(false);
  return hasNativeGeneration(MEETING_GENERATION);
}

/** The write-up's result for `id`, taken once (the job's files go with it), or null: none yet, or an older binary. */
export async function takeRecordingResult(id: string): Promise<RecordingResult | null> {
  if (!(await available())) return null;
  return invoke<RecordingResult | null>('recording_result_take', { id });
}

let known: RecordingJobState[] = [];

/** Every write-up's state, as the phone has it; an empty list on an older binary. */
export async function recordingJobState(): Promise<RecordingJobState[]> {
  if (!(await available())) return [];
  known = await invoke<RecordingJobState[]>('recording_job_state');
  return known;
}

/** The states as last read, for callers outside React and for tests. */
export function jobStatesNow(): readonly RecordingJobState[] {
  return known;
}

/** Whether a write-up is listening or summarizing now, by the last read: both want the cores the refine wants. */
export function writeUpRunningNow(): boolean {
  return known.some((job) => job.phase === 'listening' || job.phase === 'summarizing');
}

/** A tape's SHA-256 as hex and its size, hashed on the phone rather than read into the page; null with no tape, or an older binary. */
export async function recordingDigest(id: string): Promise<{ sha256: string; bytes: number } | null> {
  if (!(await available())) return null;
  return invoke<{ sha256: string; bytes: number } | null>('recording_digest', { id });
}

/** Remove the audio of these notes' tapes, keeping their words and phrases: which went, and how many bytes came back. */
export async function deleteRecordings(ids: readonly string[]): Promise<{ removed: string[]; freedBytes: number }> {
  if (!ids.length || !(await available())) return { removed: [], freedBytes: 0 };
  const done = await invoke<{ removed: string[]; freedBytes: number }>('recording_delete', { ids: [...ids] });
  markAudioRemoved(done.removed);
  return done;
}

// ---- audio removed on this device ------------------------------------------------------------

/** The notes whose audio was removed from this device by the Tapes row, so the tape can say so rather than that it will not play. */
const REMOVED_KEY = 'glyph-audio-removed';

function removedIds(): string[] {
  return readStored<string[]>(REMOVED_KEY, [], (raw) => (Array.isArray(raw) ? raw.filter((id): id is string => typeof id === 'string') : []));
}

/** Remember that these notes' audio is gone from this device. */
export function markAudioRemoved(ids: readonly string[]): void {
  if (!ids.length) return;
  writeStored(REMOVED_KEY, [...new Set([...removedIds(), ...ids])]);
}

/** Whether `id`'s audio was removed from this device. */
export function audioRemoved(id: string): boolean {
  return removedIds().includes(id);
}
