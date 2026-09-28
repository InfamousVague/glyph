import { Download } from '@glacier/icons';
import { ProgressBar } from '@glacier/react';
import { gb, MODELS, modelSpec, useModels } from '../core/ai.ts';
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
 * old page chose one for them when the chosen one went).
 */
export function ModelCard() {
  const prefs = usePreferences();
  const { models, download, problem, fetch, remove } = useModels();
  const chosen = prefs.formatModel;
  const present = new Set(models.filter((m) => m.present).map((m) => m.id));
  const held = MODELS.filter((m) => present.has(m.id)).reduce((sum, m) => sum + m.bytes, 0);
  const downloading = download ? modelSpec(download.id) : null;
  // The Mac runs them too (§127 section 2), and a Mac is not a phone.
  const device = isAndroid ? 'the phone' : 'this Mac';

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
        description={`Writes the summaries and the review, and Format, Summarize and Enhance on a note. Bigger is more careful, and slower. It runs on ${device}. Nothing is sent anywhere.`}
        footer={held ? `${gb(held)} on ${device}.` : 'Nothing downloaded yet. Get one above, or tap the robot on a note and it will offer to.'}
      >
        {MODELS.map((model) => {
          const here = present.has(model.id);
          const inUse = here && chosen === model.id;
          return (
            <SettingRow
              key={model.id}
              label={model.name}
              hint={`${model.about} ${gb(model.bytes)}.`}
              value={
                inUse ? 'In use' : here ? (
                  <RowAction onPress={() => void remove(model.id)}>Remove</RowAction>
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
