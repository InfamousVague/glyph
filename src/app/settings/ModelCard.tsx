import { useEffect, useState } from 'react';
import { Download } from '@glacier/icons';
import { ProgressBar } from '@glacier/react';
import { modelFor } from '../ai/available.ts';
import { gb, MODEL_LIMITS, MODELS, modelSpec, useModels } from '../core/ai.ts';
import { fireNativeHaptic } from '../core/haptics.ts';
import { isAndroid } from '../core/platform.ts';
import { setPreferences, usePreferences } from '../core/preferences.ts';
import { PaneSection, Pick, RowAction, SettingRow, SettingsCallout } from './kit/settingsKit.tsx';

/**
 * The model: which language model writes the summaries and the review, and Format, Summarize and Enhance on a note,
 * and which of them are here. A card on Recording (settings/RecordingPane.tsx), where what it writes is; it was the
 * Formatting page until docs/DESIGN.md §138, which also listed every downloaded model a second time in a card of its
 * own with Remove, under the same title as the Local only switch (now Account's Privacy card).
 *
 * One row a model, once. Not here: Get, which downloads it in the open with the bytes arriving in a callout above.
 * Here: a radio to choose it, and Remove beside it, so the gigabytes are never invisible; the footer adds them up.
 * The one in use has no Remove: another is picked first, so nothing switches the model behind a person's back (the
 * old page chose one for them when the chosen one went). In use is the one that runs (ai/available.ts `modelFor`):
 * the chosen one when it is here, else the one standing in for it. When it is the only one here there is nothing to
 * pick first, so it has Remove too, or its gigabytes could not be given back.
 *
 * Remove asks twice, Remove and then Tap again, as the Tapes card's does: it gives back gigabytes that take minutes to
 * get again, and it sits a thumb's width from the radio that picks the same model.
 */

/** How long a Remove stays armed after its first tap, as the Tapes card's does. */
const ARMED_MS = 5000;

export function ModelCard() {
  const prefs = usePreferences();
  const { models, download, problem, fetch, remove } = useModels();
  const present = new Set(models.filter((m) => m.present).map((m) => m.id));
  const running = modelFor([...present], prefs.formatModel);
  const held = MODELS.filter((m) => present.has(m.id)).reduce((sum, m) => sum + m.bytes, 0);
  const downloading = download ? modelSpec(download.id) : null;
  // The Mac runs them too (§127 section 2), and a Mac is not a phone.
  const device = isAndroid ? 'the phone' : 'this Mac';

  // The model whose Remove has had its first tap, for a few seconds.
  const [armed, setArmed] = useState<string | null>(null);
  useEffect(() => {
    if (!armed) return undefined;
    const id = window.setTimeout(() => setArmed(null), ARMED_MS);
    return () => window.clearTimeout(id);
  }, [armed]);
  const removeTapped = (id: string) => {
    if (armed !== id) {
      setArmed(id);
      fireNativeHaptic('warning');
      return;
    }
    setArmed(null);
    void remove(id);
  };

  return (
    <>
      {downloading && download ? (
        <SettingsCallout icon={<Download size={20} />}>
          <span>
            Getting {downloading.name}, {gb(download.received)} of {gb(download.total)}. Keep Ghost.md open.
          </span>
          <ProgressBar aria-label={`Downloading ${downloading.name}`} value={download.received} max={Math.max(download.total, 1)} size="sm" />
        </SettingsCallout>
      ) : null}
      {problem ? <SettingsCallout>{problem}</SettingsCallout> : null}

      <PaneSection
        title="Model"
        description={`Writes the summaries and the review, runs the AI in a note's More sheet, and fills its blanks. Bigger writes better, and is slower. It runs on ${device}. Nothing is sent anywhere. ${MODEL_LIMITS}`}
        footer={held ? `${gb(held)} on ${device}.` : 'Nothing downloaded yet. Get one above, or tap the robot on a note and it will offer to.'}
      >
        {MODELS.map((model) => {
          const here = present.has(model.id);
          const inUse = model.id === running;
          const removable = here && (!inUse || present.size === 1);
          return (
            <SettingRow
              key={model.id}
              label={model.name}
              hint={`${model.about} ${gb(model.bytes)}.`}
              value={
                removable ? (
                  <RowAction onPress={() => removeTapped(model.id)}>{armed === model.id ? 'Tap again' : 'Remove'}</RowAction>
                ) : inUse ? (
                  'In use'
                ) : download?.id === model.id ? (
                  'Downloading'
                ) : undefined
              }
              control={
                here ? (
                  <Pick checked={inUse} label={`Use ${model.name}`} onPress={() => setPreferences({ formatModel: model.id })} />
                ) : (
                  <RowAction onPress={() => void fetch(model.id)} disabled={download !== null}>
                    Get
                  </RowAction>
                )
              }
            />
          );
        })}
      </PaneSection>
    </>
  );
}
