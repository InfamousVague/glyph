import { useState } from 'react';
import { failureText } from '../core/failure.ts';
import { setAccountColour, useOrgs } from '../core/orgs/orgs.ts';
import type { WorkspaceHue } from '../core/workspaces.ts';
import { WorkspaceSwatch } from '../notes/WorkspaceSwatch.tsx';
import { PaneSection, SettingsFootnote } from './kit/settingsKit.tsx';
import styles from './OrganizationsPane.module.css';

/**
 * Your colour (docs/SHARED.md, S7; Matt: "add the ability for users to pick and change their color"): one of the
 * app's seven hues, worn in every organization - your cursor and your selections while you edit a team note, your
 * comments, and your row in the members - unless an organization gives you another there (OrganizationSheet.tsx).
 * Ink, the app's own, is no colour. Kept on the service in the clear, as an organization's hue is.
 */
export function ColourCard() {
  const { colour } = useOrgs();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const choose = async (hue: WorkspaceHue) => {
    setBusy(true);
    setProblem(null);
    try {
      await setAccountColour(hue === 'ink' ? null : hue);
    } catch (failure) {
      setProblem(failureText(failure));
    } finally {
      setBusy(false);
    }
  };
  return (
    <PaneSection title="Your colour" footer="Worn by your cursor and your selections while you edit a team note, by your comments, and by your row in an organization's members. An organization can give you another colour there.">
      <div className={styles.swatch} aria-busy={busy || undefined}>
        <WorkspaceSwatch hue={(colour as WorkspaceHue | null) ?? 'ink'} onHue={(hue) => void choose(hue)} />
      </div>
      {problem ? <SettingsFootnote>{problem}</SettingsFootnote> : null}
    </PaneSection>
  );
}
