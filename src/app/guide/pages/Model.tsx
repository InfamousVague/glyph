import { gb, MODELS, modelName, useModels } from '../../core/ai.ts';
import { setPreferences, usePreferences } from '../../core/preferences.ts';
import { isTauri } from '../../core/tauri.ts';
import styles from '../Guide.module.css';

/**
 * Which model the AI runs, asked up front like the theme: the choice is a
 * row per model with its size, the chosen one printed in reverse. Choosing
 * only sets the preference; the bytes come the first time the AI is asked
 * for on a note, or now, from the word under the list, so a phone on wifi
 * tonight is ready tomorrow. Changeable any time in Settings > Formatting;
 * the Developer page's "Choose your model" row opens the guide on this page
 * alone (guide/pages.ts `GUIDE_MODEL_PAGE`).
 *
 * The line under the rows reads the download only in the app: in a browser
 * there is nothing to fetch, and a row still sets the preference.
 */
export function Model() {
  const { formatModel } = usePreferences();
  const { models, download, problem, fetch } = useModels();
  const here = models.find((m) => m.id === formatModel)?.present ?? false;
  const chosen = MODELS.find((m) => m.id === formatModel);
  return (
    <>
      <h1 className={styles.title}>Choose your model</h1>
      <p className={styles.lead}>It rewrites your notes on the phone. Bigger is more careful, and slower. Nothing leaves the phone.</p>
      <div className={styles.choices} role="radiogroup" aria-label="Model">
        {MODELS.map((model) => (
          <button
            key={model.id}
            type="button"
            role="radio"
            aria-checked={formatModel === model.id}
            className={`${styles.choice} ${formatModel === model.id ? 'app-inverse' : ''}`}
            data-selected={formatModel === model.id ? '' : undefined}
            onClick={() => setPreferences({ formatModel: model.id })}
          >
            <span className={`${styles.swatch} ${styles.size}`} aria-hidden="true">
              {gb(model.bytes)}
            </span>
            <span className={styles.choiceText}>
              <span className={styles.stepTitle}>{model.name}</span>
              <span className={styles.note}>{model.about}</span>
            </span>
          </button>
        ))}
      </div>
      {isTauri() && chosen ? (
        <p className={styles.fine}>
          {download?.id === formatModel
            ? `Getting ${modelName(formatModel)}, ${gb(download.received)} of ${gb(download.total)}. Keep Ghost.md open.`
            : here
              ? `${chosen.name} is on the phone.`
              : problem
                ? problem
                : `${chosen.name} downloads the first time you ask the robot on a note, or `}
          {!here && download === null ? (
            <button type="button" className={`app-word ${styles.action}`} onClick={() => void fetch(formatModel)}>
              get it now
            </button>
          ) : null}
        </p>
      ) : null}
    </>
  );
}
