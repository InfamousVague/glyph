import { gb, modelName, MODELS, type Hardware, type Phase } from '../core/ai.ts';
import { clock, pace } from '../ai/words.ts';
import { useDeviceFacts } from './deviceFacts.ts';
import { Thinking } from './Thinking.tsx';
import styles from './AiCard.module.css';

/**
 * The AI card: one face for the model at work, wherever it works.
 *
 * Matt: "highlight the local AI part of this, making sure the app can be run
 * totally without a server; a better, consistent AI card that renders when
 * it's thinking, and it should render things like real phone hardware
 * usage". So one card, opened from the strip under a note's header while a
 * run is on (ai/AiStrip.tsx): the model and its size on disk, what it is
 * doing and how fast, the little reader while nothing has arrived yet, and
 * the phone underneath it - the cores it runs on, the memory it holds, the
 * battery it draws on, and, from native generation 14, the engine's own
 * readings every tick: its memory, its share of the cores, the heat. "On
 * this phone" is the point, and the card says so.
 *
 * Three sources, by what is there. The engine's readings come with each
 * progress report (`hardware`); the page reads cores, memory class and the
 * battery itself (`useDeviceFacts`), so an older binary still shows the
 * phone; and what neither knows is left out rather than guessed.
 */

export interface AiCardProps {
  model: string;
  phase: Phase;
  /** "Formatting", "Summarizing": the verb for what the model is doing. */
  doing: string;
  promptTokens: number;
  promptTokensDone: number;
  outputTokens: number;
  tokensPerSecond: number;
  elapsedMs: number;
  hardware?: Hardware | null;
}

export function AiCard({ model, phase, doing, promptTokens, promptTokensDone, outputTokens, tokensPerSecond, elapsedMs, hardware }: AiCardProps) {
  const facts = useDeviceFacts();
  const spec = MODELS.find((m) => m.id === model);
  const cores = hardware?.cores ?? facts.cores;
  const threads = hardware?.threads ?? null;
  const cpuShare = hardware && cores ? Math.min(1, hardware.cpuPercent / (100 * cores)) : null;
  const memoryTotal = hardware?.totalBytes ?? (facts.memoryGb ? facts.memoryGb * 1e9 : null);
  const memoryUsed = hardware?.rssBytes ?? null;

  let line: string;
  if (phase === 'loading') line = `Loading ${modelName(model)}.`;
  else if (phase === 'prefill') line = promptTokens ? `Reading the note, ${promptTokensDone} of ${promptTokens}.` : 'Reading the note.';
  else if (phase === 'generating') line = `${doing}, ${pace(tokensPerSecond)}, ${clock(elapsedMs)}.`;
  else line = `${doing}.`;

  return (
    <section className={styles.card} aria-label="The model at work" data-phase={phase}>
      <div className={styles.reader}>
        <Thinking phase={phase} />
      </div>
      <div className={styles.body}>
        <p className={styles.title}>
          <span className={styles.model}>{spec?.name ?? modelName(model)}</span>
          {spec ? <span className={styles.size}>{gb(spec.bytes)}</span> : null}
          <span className={styles.local}>On this phone</span>
        </p>
        <p className={styles.line} role="status">
          {line}
        </p>
        <dl className={styles.meters}>
          {cores ? (
            <Meter label="Cores" value={threads ? `${threads} of ${cores}` : `${cores}`} share={threads ? threads / cores : null} />
          ) : null}
          {/* Loading is one report with no tick behind it, so its CPU figure would be stale: not shown until the model reads. */}
          {cpuShare !== null && hardware && phase !== 'loading' ? <Meter label="CPU" value={`${Math.round(hardware.cpuPercent)}%`} share={cpuShare} /> : null}
          {memoryTotal ? (
            <Meter
              label="Memory"
              value={memoryUsed ? `${gb(memoryUsed)} of ${gb(memoryTotal)}` : `${gb(memoryTotal)}`}
              share={memoryUsed ? Math.min(1, memoryUsed / memoryTotal) : null}
            />
          ) : null}
          {hardware?.tempC != null ? <Meter label="Heat" value={`${Math.round(hardware.tempC)} °C`} share={Math.min(1, Math.max(0, (hardware.tempC - 20) / 40))} /> : null}
          {facts.battery ? (
            <Meter label="Battery" value={`${Math.round(facts.battery.level * 100)}%${facts.battery.charging ? ', charging' : ''}`} share={facts.battery.level} />
          ) : null}
          {phase === 'generating' && outputTokens ? <Meter label="Written" value={`${outputTokens} tokens`} share={null} /> : null}
        </dl>
        <p className={styles.foot}>
          <span>Nothing leaves the phone.</span>
        </p>
      </div>
    </section>
  );
}

/** One reading: a label, a value, and a thin bar when the value is a share of something. */
function Meter({ label, value, share }: { label: string; value: string; share: number | null }) {
  return (
    <div className={styles.meter}>
      <dt className={styles.meterLabel}>{label}</dt>
      <dd className={styles.meterValue}>{value}</dd>
      {share !== null ? (
        <dd className={styles.bar} aria-hidden="true">
          <span style={{ inlineSize: `${Math.round(share * 100)}%` }} />
        </dd>
      ) : null}
    </div>
  );
}
