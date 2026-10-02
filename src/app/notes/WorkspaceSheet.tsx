import { useEffect, useState } from 'react';
import { addWorkspace, chooseWorkspace, deleteWorkspace, notesInWorkspace, renameWorkspace, setWorkspaceHue, type Workspace, type WorkspaceHue } from '../core/workspaces.ts';
import { SheetField, SheetGroup, SheetHeading, SheetNote, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import { WorkspaceSwatch } from './WorkspaceSwatch.tsx';
import { Sheet } from '../editor/Sheet.tsx';
import { OrgMark } from './OrgMark.tsx';

/**
 * A workspace's sheet, from the row on the list or Settings › Workspaces: a
 * name to add, or the name of one to change, a colour for its pill, and Delete
 * under it, which asks what becomes of its notes - kept and unfiled, or put in
 * the Trash with it (Matt: "I need a way to delete workspaces"). In the note's
 * settings' own look. A new one is chosen as it is made, so the list lands in
 * it with nothing in it yet and the + at the foot writes the first note there.
 *
 * The colour of one that exists is set as it is tapped, since it is a thing to
 * look at rather than a thing to fill in: the pill behind the sheet changes
 * under your finger. A new one carries its colour into the making.
 *
 * An organization's workspace (docs/TEAMS.md, D5) is named and coloured after the organization, on every member's
 * device, and goes when they leave it: no name, no swatch and no Remove here, only the way to the organization's own
 * screen, where those are set by whoever may.
 */
export function WorkspaceSheet({ which, onClose, onOrganization }: { which: Workspace | 'new' | null; onClose: () => void; onOrganization?: (orgId: string) => void }) {
  const editing = which && which !== 'new' ? which : null;
  const [name, setName] = useState('');
  const [hue, setHue] = useState<WorkspaceHue>('ink');
  // Delete pressed: the sheet asks what becomes of the notes before anything goes.
  const [deleting, setDeleting] = useState(false);
  useEffect(() => {
    setName(editing?.name ?? '');
    setHue(editing?.hue ?? 'ink');
    setDeleting(false);
  }, [editing, which]);
  if (!which) return null;

  if (editing?.org) {
    const org = editing.org;
    return (
      <Sheet label={editing.name} onClose={onClose}>
        <SheetTitle>
          <OrgMark />
          {editing.name}
        </SheetTitle>
        <SheetNote>An organization’s workspace: its name and colour follow the organization, and it is on every member’s device. Notes filed here stay yours for now.</SheetNote>
        <SheetGroup>
          <SheetRow
            label="Organization settings"
            hint="Members, invitations, its name and colour."
            onPress={() => {
              onClose();
              onOrganization?.(org);
            }}
            disabled={!onOrganization}
          />
        </SheetGroup>
      </Sheet>
    );
  }

  if (editing && deleting) {
    const notes = notesInWorkspace(editing.id);
    const count = notes.length === 1 ? 'its 1 note' : `its ${notes.length} notes`;
    const done = (trashNotes: boolean) => {
      deleteWorkspace(editing.id, { trashNotes });
      onClose();
    };
    return (
      <Sheet label={`Delete ${editing.name}`} onClose={onClose}>
        <SheetTitle>Delete {editing.name}?</SheetTitle>
        <SheetNote>{notes.length ? `What happens to ${count}?` : 'There are no notes in it.'}</SheetNote>
        <SheetGroup>
          {notes.length ? (
            <>
              <SheetRow label="Delete, keep the notes" hint="They stay, just not filed in a workspace." onPress={() => done(false)} />
              <SheetRow label="Delete, and move the notes to Trash" hint="They can be restored from the Trash until it is emptied." danger onPress={() => done(true)} />
            </>
          ) : (
            <SheetRow label="Delete workspace" danger onPress={() => done(false)} />
          )}
          <SheetRow label="Cancel" onPress={() => setDeleting(false)} />
        </SheetGroup>
      </Sheet>
    );
  }

  const clean = name.trim();
  const submit = () => {
    if (!clean) return;
    if (editing) {
      renameWorkspace(editing.id, name);
    } else {
      const made = addWorkspace(name, hue);
      if (made) chooseWorkspace(made.id);
    }
    onClose();
  };
  return (
    <Sheet label={editing ? editing.name : 'New workspace'} onClose={onClose}>
      <SheetTitle>{editing ? editing.name : 'New workspace'}</SheetTitle>
      {editing ? null : <SheetNote>Notes filed in a workspace show together. A note made while one is chosen goes there.</SheetNote>}
      <SheetGroup>
        <SheetField
          label="Name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          autoFocus
          autoCapitalize="words"
          enterKeyHint="done"
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              submit();
            }
          }}
        />
        <SheetRow label={editing ? 'Rename' : 'Add'} onPress={submit} disabled={!clean || clean === editing?.name} />
      </SheetGroup>
      <SheetHeading>Colour</SheetHeading>
      <SheetGroup>
        <WorkspaceSwatch
          hue={hue}
          onHue={(picked) => {
            setHue(picked);
            // One that exists changes as it is tapped; a new one wears it when it is made.
            if (editing) setWorkspaceHue(editing.id, picked);
          }}
        />
      </SheetGroup>
      {editing ? (
        <SheetGroup>
          <SheetRow label="Delete workspace" hint="Asks what happens to its notes first." danger onPress={() => setDeleting(true)} />
        </SheetGroup>
      ) : null}
    </Sheet>
  );
}
