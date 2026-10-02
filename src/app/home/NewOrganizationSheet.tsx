import { useState } from 'react';
import { createOrg } from '../core/orgs/orgs.ts';
import { failureText } from '../core/failure.ts';
import { SheetField, SheetGroup, SheetNote, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import { Sheet } from '../editor/Sheet.tsx';

/**
 * A new organization from the home page's filters (docs/TEAMS.md; the review's point that the place a person
 * already makes a space is the filters' "New workspace", not four taps under Account): a name, in the workspace
 * sheet's own look (notes/WorkspaceSheet.tsx), made on the service and opened at once. The maker owns it and can
 * invite people by handle from its screen; its workspace is made here as it is made.
 */
export function NewOrganizationSheet({ open, onClose, onMade }: { open: boolean; onClose: () => void; onMade: (orgId: string) => void }) {
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  if (!open) return null;
  const clean = name.trim();
  const submit = async () => {
    if (!clean || busy) return;
    setBusy(true);
    setProblem(null);
    try {
      const org = await createOrg(clean);
      setName('');
      onClose();
      onMade(org.id);
    } catch (failure) {
      setProblem(failureText(failure));
    } finally {
      setBusy(false);
    }
  };
  return (
    <Sheet label="New organization" onClose={onClose}>
      <SheetTitle>New organization</SheetTitle>
      <SheetNote>A team by name. You own it, can invite people by their handle, and each member gets its workspace.</SheetNote>
      <SheetGroup>
        <SheetField
          label="Name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          autoFocus
          autoCapitalize="words"
          maxLength={60}
          enterKeyHint="done"
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              void submit();
            }
          }}
        />
        <SheetRow label={busy ? 'One moment…' : 'Create'} hint={problem ?? undefined} onPress={() => void submit()} disabled={!clean || busy} />
      </SheetGroup>
    </Sheet>
  );
}
