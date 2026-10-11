import { useState } from 'react';
import { Folder, Plus } from '@glacier/icons';
import { useTrash } from '../core/trash.ts';
import { notesInWorkspace, useWorkspaces, type Workspace } from '../core/workspaces.ts';
import { WorkspaceSheet } from '../notes/WorkspaceSheet.tsx';
import { HueMark } from './OrganizationsPane.tsx';
import { PaneSection, SettingRow, SettingsFootnote } from './kit/settingsKit.tsx';

/**
 * Workspaces, a page of Settings (Matt: "I need a way to delete workspaces"): every workspace in one list, each a row
 * that opens its sheet (notes/WorkspaceSheet.tsx) to rename it, colour it, or delete it - which asks what becomes of
 * its notes. Before this, the way to a workspace's Delete was three taps deep in Home's filters, or a sidebar only the
 * desktop has.
 *
 * An organization's workspace is listed apart: its name and colour are the organization's, and it goes when the person
 * leaves the organization, so its row opens the organization's own screen instead. What the search finds here is
 * WorkspacesPane.findable.ts.
 */
export function WorkspacesPane({ onOrganization }: { onOrganization?: (orgId: string) => void }) {
  const { list } = useWorkspaces();
  // The counts leave out notes in the trash, so they change as the trash does.
  useTrash();
  const [manage, setManage] = useState<Workspace | 'new' | null>(null);
  const personal = list.filter((space) => !space.org);
  const teams = list.filter((space) => space.org);
  const notes = (space: Workspace) => {
    const count = notesInWorkspace(space.id).length;
    return count === 1 ? '1 note' : `${count} notes`;
  };
  return (
    <>
      <PaneSection title="Your workspaces" description="Notes filed in a workspace show together. A note made while one is chosen goes there.">
        {personal.length ? (
          personal.map((space) => <SettingRow key={space.id} icon={<HueMark hue={space.hue ?? null} />} label={space.name} hint={notes(space)} onPress={() => setManage(space)} />)
        ) : (
          <SettingRow icon={<Folder size={20} />} label="None yet" hint="Make one below." />
        )}
        <SettingRow icon={<Plus size={20} />} label="New workspace" onPress={() => setManage('new')} />
      </PaneSection>
      {teams.length ? (
        <PaneSection title="Organizations’ workspaces" description="Named and coloured after the organization. One goes when you leave its organization.">
          {teams.map((space) => (
            <SettingRow key={space.id} icon={<HueMark hue={space.hue ?? null} />} label={space.name} hint={notes(space)} onPress={onOrganization && space.org ? () => onOrganization(space.org!) : undefined} />
          ))}
        </PaneSection>
      ) : null}
      <SettingsFootnote>Deleting a workspace asks first whether its notes stay, unfiled, or go to the Trash with it. Nothing is deleted for good until the Trash is emptied.</SettingsFootnote>
      <WorkspaceSheet which={manage} onClose={() => setManage(null)} onOrganization={onOrganization} />
    </>
  );
}
