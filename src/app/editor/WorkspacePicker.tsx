import { useEffect, useState } from 'react';
import { Workspace as WorkspaceIcon } from '../art/Icons.tsx';
import { addWorkspace, fileNote, isOrgWorkspace, useWorkspaces, workspaceOf } from '../core/workspaces.ts';
import { SheetField, SheetGroup, SheetNote, SheetRow, SheetTitle } from '../plugins/kit.tsx';

/**
 * Where a note is filed, on its More sheet: the workspaces to choose from with
 * the note's own ticked, a name for a new one that files the note there as it
 * is made, and a way out of the one it is in. The first workspace is made
 * here as often as on the list: a note is where the thought of sorting comes.
 *
 * A note filed in an organization's workspace is the team's (docs/SHARED.md, S1), so taking it out, or moving it
 * to another workspace, takes it from everyone in the organization: that press is asked twice, armed for a few
 * seconds in between, as leaving an organization is (settings/OrganizationSheet.tsx).
 */
export function WorkspacePicker({ noteId, onDone }: { noteId: string; onDone: () => void }) {
  const { list } = useWorkspaces();
  const filed = workspaceOf(noteId);
  const [name, setName] = useState('');
  /** The move out of the team armed: which destination, so a second press on the same row goes through. */
  const [armed, setArmed] = useState<string | null>(null);
  useEffect(() => {
    if (armed === null) return undefined;
    const id = window.setTimeout(() => setArmed(null), 4000);
    return () => window.clearTimeout(id);
  }, [armed]);
  const team = filed !== null && isOrgWorkspace(filed);
  const choose = (id: string | null) => {
    const key = id ?? 'none';
    if (team && id !== filed.id && armed !== key) {
      setArmed(key);
      return;
    }
    fileNote(noteId, id);
    onDone();
  };
  const make = () => {
    const made = addWorkspace(name);
    if (made) choose(made.id);
  };
  return (
    <>
      <SheetTitle>Workspace</SheetTitle>
      <SheetNote>
        {armed !== null
          ? `This takes the note away from everyone in ${filed?.name ?? 'the organization'}. Press again to go on.`
          : team
            ? `Filed in ${filed?.name ?? 'an organization'}, this note is the team’s: everyone in it reads and edits it.`
            : list.length
              ? 'Notes in a workspace show together on the list. Filed in an organization’s, a note is the team’s.'
              : 'A name to file notes under. The list can then show one workspace at a time.'}
      </SheetNote>
      {list.length ? (
        <SheetGroup>
          {list.map((workspace) => (
            <SheetRow key={workspace.id} icon={WorkspaceIcon} label={workspace.name} chosen={filed?.id === workspace.id} onPress={() => choose(workspace.id)} />
          ))}
        </SheetGroup>
      ) : null}
      <SheetGroup>
        <SheetField
          label="New workspace"
          value={name}
          onChange={(e) => setName(e.target.value)}
          autoCapitalize="words"
          enterKeyHint="done"
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              make();
            }
          }}
        />
        <SheetRow label="Add it and file this note there" onPress={make} disabled={!name.trim()} />
      </SheetGroup>
      {filed ? (
        <SheetGroup>
          <SheetRow label={armed === 'none' ? 'Press again to take it from the team' : `Take this note out of ${filed.name}`} onPress={() => choose(null)} />
        </SheetGroup>
      ) : null}
    </>
  );
}
