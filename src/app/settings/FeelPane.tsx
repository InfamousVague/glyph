import { Switch } from '@glacier/react';
import { hapticsAvailable, setHapticsPref, useHapticsPref } from '../core/haptics.ts';
import { PaneSection, SettingRow } from './kit/settingsKit.tsx';

/** Feel: the haptics, the one switch about touch. Listed only where there is a motor to switch (SettingsSheet.tsx). */
export function FeelPane() {
  const haptics = useHapticsPref();
  return (
    <PaneSection title="Touch">
      <SettingRow
        label="Haptics"
        hint="A small tap when a style or a cue kicks in."
        control={<Switch aria-label="Haptics" checked={haptics} onCheckedChange={setHapticsPref} />}
        disabledReason={hapticsAvailable() ? undefined : 'This device has no motor.'}
      />
    </PaneSection>
  );
}
