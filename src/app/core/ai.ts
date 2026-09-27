import { useCallback, useEffect, useRef, useState } from 'react';
import { MEETING_GENERATION } from '../capture/meeting.ts';
import { listenTo } from './events.ts';
import { failureText } from './failure.ts';
import { hasNativeGeneration } from './nativeGeneration.ts';
import { preferences } from './preferences.ts';
import { invoke, isTauri } from './tauri.ts';

/**
 * The formatting model on the phone: which ones there are, which are here,
 * getting one, and running it.
 *
 * Everything runs on the device (Matt: "the idea is that everything on here
 * will be on device"). The catalogue's bytes and hashes live in Rust
 * (`src-tauri/src/llm/model.rs`); the names and the words a person reads live
 * here, keyed by the same ids. A browser has no engine: `useModels` answers an
 * empty catalogue there, and the Formatted view says so.
 *
 * The events (`ai://model-progress`, `ai://progress`) carry the page's own
 * ids, so two runs or two downloads in flight cannot be confused.
 */

export interface ModelChoice {
  id: string;
  name: string;
  /** One line under the name in Settings. */
  about: string;
  /** The download, in bytes, from the catalogue. */
  bytes: number;
}

/** In the order Settings shows them. Ids match `llm::model::CATALOGUE`. */
export const MODELS: readonly ModelChoice[] = [
  { id: 'qwen3.5-2b', name: 'Qwen3.5 2B', about: 'Quick. Good for short notes; it can shorten long ones.', bytes: 1_280_835_840 },
  { id: 'qwen3.5-4b', name: 'Qwen3.5 4B', about: 'The balance. Careful with facts, fits most phones.', bytes: 2_740_937_888 },
  { id: 'qwen3.5-9b', name: 'Qwen3.5 9B', about: 'The most careful, and the slowest. Wants 12 GB of memory.', bytes: 5_680_522_464 },
  { id: 'gemma-4-e4b', name: 'Gemma 4 E4B', about: 'A different voice. Runs like a 4B; the file is bigger.', bytes: 4_977_171_584 },
];

export const DEFAULT_MODEL = 'qwen3.5-4b';

/** A model in the catalogue by its id, or undefined for one this build does not offer. */
export function modelSpec(id: string): ModelChoice | undefined {
  return MODELS.find((m) => m.id === id);
}

export function modelName(id: string): string {
  return modelSpec(id)?.name ?? id;
}

/** Bytes as a person reads them: "2.7 GB". */
export function gb(bytes: number): string {
  return `${(bytes / 1e9).toFixed(1)} GB`;
}

/** A download's size as its line says it: whole megabytes, as a phone's own download lines count them. */
export function megabytes(bytes: number): number {
  return Math.round(bytes / 1e6);
}

// ---- what is on the phone ---------------------------------------------------------------

/** One catalogue entry with whether this phone has it. Mirrors Rust's ModelInfo. */
export interface ModelInfo {
  id: string;
  file: string;
  bytes: number;
  present: boolean;
  path: string;
}

export interface Download {
  id: string;
  received: number;
  total: number;
}

/** The catalogue with what is on this phone; an empty list in a browser. */
export async function listModels(): Promise<ModelInfo[]> {
  if (!isTauri()) return [];
  return invoke<ModelInfo[]>('ai_models');
}

/**
 * The catalogue with its state on this phone, refreshed after every change
 * and whenever the app comes back to the front (a download killed by the
 * phone locking is retried by a person tapping Get again, not by itself:
 * gigabytes are not fetched behind anyone's back).
 */
export function useModels(): {
  models: ModelInfo[];
  download: Download | null;
  problem: string | null;
  fetch: (id: string) => Promise<void>;
  remove: (id: string) => Promise<void>;
  refresh: () => Promise<void>;
} {
  const [models, setModels] = useState<ModelInfo[]>([]);
  const [download, setDownload] = useState<Download | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  const busy = useRef(false);

  const refresh = useCallback(async () => {
    try {
      setModels(await listModels());
    } catch (failure) {
      console.warn('[glyph] models:', failure);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const onVisible = () => {
      if (document.visibilityState === 'visible') void refresh();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [refresh]);

  const fetch = useCallback(
    async (id: string) => {
      if (busy.current || !isTauri()) return;
      if (preferences().localOnly) {
        setProblem('Local only is on, so nothing is downloaded. Turn it off in Settings to get a model.');
        return;
      }
      busy.current = true;
      setProblem(null);
      const unlisten = await listenTo<{ id: string; receivedBytes: number; totalBytes: number }>('ai://model-progress', (progress) => {
        if (progress.id === id) setDownload({ id, received: progress.receivedBytes, total: progress.totalBytes });
      });
      setDownload({ id, received: 0, total: modelSpec(id)?.bytes ?? 0 });
      try {
        await invoke<ModelInfo>('ai_fetch_model', { id });
      } catch (failure) {
        setProblem(failureText(failure));
      } finally {
        unlisten();
        setDownload(null);
        busy.current = false;
        await refresh();
      }
    },
    [refresh],
  );

  const remove = useCallback(
    async (id: string) => {
      if (!isTauri()) return;
      setProblem(null);
      try {
        await invoke<ModelInfo>('ai_delete_model', { id });
      } catch (failure) {
        setProblem(failureText(failure));
      }
      await refresh();
    },
    [refresh],
  );

  return { models, download, problem, fetch, remove, refresh };
}

// ---- a run ---------------------------------------------------------------------------------

export type Phase = 'loading' | 'prefill' | 'generating' | 'done' | 'error' | 'cancelled';

/**
 * What the phone is doing for the model, sampled with each progress report
 * by the engine (native generation 14): its own memory and what the phone has
 * free, its share of the cores over the last tick, the threads it runs on,
 * and the hottest thermal zone where Android lets it be read.
 */
export interface Hardware {
  rssBytes: number;
  freeBytes: number;
  totalBytes: number;
  /** 0 to 100 per core: 640 is six and a half cores busy. */
  cpuPercent: number;
  threads: number;
  cores: number;
  tempC?: number | null;
}

const share = (value: number) => Math.min(1, Math.max(0, value));

/** The heat as a share of a bar: 20 °C is its foot and 60 °C its top (the AI card's meter, and the scene's rings). */
export function heatShare(tempC: number): number {
  return share((tempC - 20) / 40);
}

/** The busy figure as a share of every core: 640% of eight is four fifths. */
export function cpuShare(cpuPercent: number, cores: number): number {
  return cores > 0 ? share(cpuPercent / (100 * cores)) : 0;
}

/** Mirrors Rust's Progress. */
export interface Progress {
  id: string;
  phase: Phase;
  promptTokens: number;
  promptTokensDone: number;
  outputTokens: number;
  tokensPerSecond: number;
  elapsedMs: number;
  partial: string;
  /** `partial` starts with the model's reasoning, up to `</think>` (native generation 13, `think` asked for). */
  thinking?: boolean;
  message?: string;
  /** From native generation 14; absent before. */
  hardware?: Hardware | null;
}

/** Mirrors Rust's Output. */
export interface Output {
  text: string;
  promptTokens: number;
  outputTokens: number;
  ms: number;
  cachedTokens: number;
  prefillMs: number;
  loadMs: number;
  tokensPerSecond: number;
  truncated: boolean;
  /** The text starts with reasoning, up to `</think>` (ai/runs.ts `splitThinking` parts the two). */
  thinking?: boolean;
}

export interface RunOptions {
  model: string;
  system: string;
  context?: string;
  prompt: string;
  maxTokens: number;
  temperature: number;
  /**
   * Let a reasoning model think before it answers, the thinking streamed ahead
   * of the answer, up to `</think>` (ai/runs.ts `splitThinking` parts the two).
   * Needs native generation 13; an older binary ignores it and answers
   * straight away. Off for every formatting pass.
   */
  think?: boolean;
  /** With `think`: tokens of thinking before it is closed for the model and the answer starts (native 13). */
  thinkBudget?: number;
  onProgress: (progress: Progress) => void;
}

export interface Run {
  /** Resolves with the whole output; rejects with the engine's sentence, "cancelled" included. */
  done: Promise<Output>;
  cancel: () => void;
}

let runs = 0;

/**
 * Starts a generation and streams its progress. The listener is attached
 * before the command is sent, so no report is missed, and detached when the
 * run ends however it ends.
 */
export function generate(options: RunOptions): Run {
  const id = `run-${Date.now().toString(36)}-${(runs += 1)}`;
  let unlisten: (() => void) | null = null;
  const done = (async () => {
    if (!isTauri()) throw new Error('Formatting runs on the phone. Install Ghost.md to use it.');
    unlisten = await listenTo<Progress>('ai://progress', (progress) => {
      if (progress.id === id) options.onProgress(progress);
    });
    try {
      return await invoke<Output>('ai_generate', {
        request: {
          id,
          model: options.model,
          system: options.system,
          context: options.context ?? null,
          prompt: options.prompt,
          maxTokens: options.maxTokens,
          temperature: options.temperature,
          think: options.think ?? false,
          thinkBudget: options.thinkBudget ?? 0,
        },
      });
    } finally {
      unlisten?.();
      unlisten = null;
    }
  })();
  return {
    done,
    cancel: () => {
      if (isTauri()) void invoke<boolean>('ai_cancel', { id }).catch(() => undefined);
    },
  };
}

// ---- the write-up with the app closed (native generation 20) ---------------------------------

/**
 * What the phone's own write-up reads when the app is not there to ask (src-tauri/src/jobs.rs `JobConfig`): which
 * model, the prompts as the page has them, the piece rule, and the two preferences it obeys. Written at launch and on
 * every change (shell/useHousekeeping.ts), so a write-up runs by the same words and the same budget the page would use.
 */
export interface JobConfig {
  model: string;
  prompts: { summary: string; notes: string; piece: string; parts: string };
  onePassChars: number;
  pieceChars: number;
  temperature: number;
  writeUp: 'charging' | 'now';
  summaries: 'meetings' | 'long' | 'off';
}

/** Hand the write-up its configuration; nothing on a binary without a write-up. */
export async function keepJobConfig(config: JobConfig): Promise<void> {
  if (!isTauri() || !(await hasNativeGeneration(MEETING_GENERATION))) return;
  await invoke<void>('ai_keep_job_config', { config });
}

/**
 * Let the engine drop its model and context: after a long summary, whose context is the largest the page asks for.
 * The engine idles it out after five minutes anyway; this is sooner. Nothing on an older binary.
 */
export async function unloadModel(): Promise<void> {
  if (!isTauri() || !(await hasNativeGeneration(MEETING_GENERATION))) return;
  await invoke<void>('ai_unload').catch(() => undefined);
}

