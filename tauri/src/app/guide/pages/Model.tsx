import { gb, MODELS, modelName, modelSpec, useModels } from '../../core/ai.ts';
import { isIOS } from '../../core/platform.ts';
import { setPreferences, usePreferences } from '../../core/preferences.ts';
import { isTauri } from '../../core/tauri.ts';
import { Choice } from './parts.tsx';
import styles from '../Guide.module.css';

/**
 * Which model the AI runs, asked up front like the theme: the choice is a
 * row per model with its size, the chosen one printed in reverse. Choosing
 * only sets the preference; the bytes come from the word under the list, now,
 * or from Get in Settings › AI › Model later, so a phone on wifi tonight
 * is ready tomorrow. Asking the AI on a note with no model on the phone says it
 * needs one and fetches nothing (ai/available.ts), so the line says where to
 * get it rather than promising a download. Changeable any time on that card
 * (settings/ModelCard.tsx, which was the Formatting page until
 * docs/DESIGN.md §138, then Recording's, then AI's).
 *
 * The line under the rows reads the download only in the app, and not on an
 * iPhone: in a browser there is nothing to fetch, an iPhone runs no model
 * (ai/available.ts) and has no AI page to send anyone to, and a row
 * still sets the preference either way.
 */
export function Model() {
  const { formatModel } = usePreferences();
  const { models, download, problem, fetch } = useModels();
  const here = models.find((m) => m.id === formatModel)?.present ?? false;
  const chosen = modelSpec(formatModel);
  return (
    <>
      <h1 className={styles.title}>Choose your model</h1>
      <p className={styles.lead}>It rewrites your notes on the phone. Bigger is more careful, and slower. Nothing leaves the phone.</p>
      <div className={styles.choices} role="radiogroup" aria-label="Model">
        {MODELS.map((model) => (
          <Choice
            key={model.id}
            label={model.name}
            hint={model.about}
            on={formatModel === model.id}
            onPick={() => setPreferences({ formatModel: model.id })}
            swatch={gb(model.bytes)}
            swatchClass={styles.size}
          />
        ))}
      </div>
      {isTauri() && !isIOS && chosen ? (
        <p className={styles.fine}>
          {download?.id === formatModel
            ? `Getting ${modelName(formatModel)}, ${gb(download.received)} of ${gb(download.total)}. Keep Ghost.md open.`
            : here
              ? `${chosen.name} is on the phone.`
              : problem
                ? problem
                : `${chosen.name} is not on the phone yet. Get it later in Settings › Recording, or `}
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
