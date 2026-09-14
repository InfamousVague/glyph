import { useState } from 'react';
import { GitBranch } from '@glacier/icons';
import { PaneSection, RowAction, SettingRow, SettingsEmpty, SettingsFootnote } from '../../settings/kit/settingsKit.tsx';
import { githubToken, projects, removeProject, setGithubToken, type Project } from './projects.ts';

/**
 * The Projects plugin's page in Settings: the repos read on this phone, each
 * with what wrote its briefing and a way to forget it, and the GitHub token
 * kept for private repos. Linking a project to a note is on the note, from its
 * cog.
 */
export function ProjectsPane() {
  const [known, setKnown] = useState<Project[]>(() => projects());
  const [hasToken, setHasToken] = useState(() => githubToken() !== '');

  return (
    <>
      <PaneSection title="Projects" description="Repos the model on your phone has read. A note linked to one is formatted knowing its names and terms.">
        {known.length ? (
          known.map((p) => (
            <SettingRow
              key={p.id}
              icon={<GitBranch size={16} />}
              label={`${p.owner}/${p.repo}`}
              hint={`${p.packModel ? `Read by ${p.packModel}` : 'Kept from its README'}, ${new Date(p.packedAt).toLocaleDateString(undefined, { month: 'long', day: 'numeric' })}.`}
              control={
                <RowAction
                  onPress={() => {
                    removeProject(p.id);
                    setKnown(projects());
                  }}
                >
                  Forget
                </RowAction>
              }
            />
          ))
        ) : (
          <SettingsEmpty icon={<GitBranch size={22} />} title="No projects yet." body="Open a note, tap its cog, and choose Project to read a GitHub repo." />
        )}
      </PaneSection>

      <PaneSection title="GitHub">
        <SettingRow
          label={hasToken ? 'A token is kept for private repos' : 'No token'}
          hint={hasToken ? 'It stays on this phone.' : 'Public repos need none. Add one on a note when you link a private repo.'}
          control={
            hasToken ? (
              <RowAction
                onPress={() => {
                  setGithubToken('');
                  setHasToken(false);
                }}
              >
                Forget
              </RowAction>
            ) : undefined
          }
        />
      </PaneSection>

      <SettingsFootnote>Only the repo goes to the model, and the model runs on your phone.</SettingsFootnote>
    </>
  );
}
