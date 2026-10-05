import { useEffect, useState } from 'react';
import { useAccount } from '../core/account/account.ts';
import { failureText } from '../core/failure.ts';
import { dropHeldJoin, heldJoin, holdJoin } from '../core/orgs/joinLinks.ts';
import { joinByLink, previewJoin } from '../core/orgs/orgs.ts';
import type { JoinPreview } from '../core/orgs/types.ts';
import { Sheet } from '../editor/Sheet.tsx';
import { SheetGroup, SheetNote, SheetRow, SheetTitle } from '../plugins/kit.tsx';
import { memberWords } from '../settings/orgWords.ts';
import { OrgMark } from './OrgMark.tsx';

/**
 * "Join it?" for an invite link that opened the app (docs/TEAMS.md, "Invite by link"; core/orgs/joinLinks.ts): the
 * organization's name, who made the link and how many are in it, then Join or Not now. Nothing is joined until Join
 * is pressed. Matt: "add the ability to invite people to a team by link".
 *
 * Signed out, the sheet says to sign in and the code waits on this device; once an account is signed in the sheet
 * asks again (`JoinInvites`). Not now, signed in, lets the code go; a link that has stopped working says so in the
 * service's words, and lets it go too.
 */
export function JoinSheet({ code, onClose, onOpen, onAccount }: {
  code: string;
  /** Closed: `keep` when the code should wait for an account. */
  onClose: (keep?: boolean) => void;
  /** The organization's dashboard, once joined or already in. */
  onOpen: (orgId: string) => void;
  /** Settings › Account, to sign in or sign up. */
  onAccount: () => void;
}) {
  const { session } = useAccount();
  const signedIn = Boolean(session);
  const [preview, setPreview] = useState<JoinPreview | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!signedIn) return undefined;
    let live = true;
    setPreview(null);
    setProblem(null);
    previewJoin(code)
      .then((read) => {
        if (live) setPreview(read);
      })
      .catch((failure: unknown) => {
        if (live) setProblem(failureText(failure));
      });
    return () => {
      live = false;
    };
  }, [code, signedIn]);

  const join = async () => {
    setBusy(true);
    setProblem(null);
    try {
      const org = await joinByLink(code);
      onClose();
      onOpen(org.id);
    } catch (failure) {
      setProblem(failureText(failure));
      setBusy(false);
    }
  };

  if (!signedIn) {
    return (
      <Sheet label="Join a team" onClose={() => onClose(true)}>
        <SheetTitle>
          <OrgMark />
          Join a team
        </SheetTitle>
        <SheetNote>You opened an invite link. Sign in, or sign up, to see which organization it is for and join it. The link waits on this device until you do.</SheetNote>
        <SheetGroup>
          <SheetRow
            label="Sign in or sign up"
            onPress={() => {
              onClose(true);
              onAccount();
            }}
          />
          <SheetRow label="Not now" onPress={() => onClose(true)} />
        </SheetGroup>
      </Sheet>
    );
  }

  if (!preview) {
    return (
      <Sheet label="Invite link" onClose={() => onClose()}>
        <SheetTitle>
          <OrgMark />
          {problem ? 'This invite link doesn’t work' : 'Reading the invite link…'}
        </SheetTitle>
        {problem ? <SheetNote>{problem}</SheetNote> : null}
        <SheetGroup>
          <SheetRow label="Close" onPress={() => onClose()} />
        </SheetGroup>
      </Sheet>
    );
  }

  const { org } = preview;
  if (preview.member) {
    return (
      <Sheet label={org.name} onClose={() => onClose()}>
        <SheetTitle>
          <OrgMark />
          You’re in {org.name}
        </SheetTitle>
        <SheetNote>You’re already a member, so the link has nothing to add.</SheetNote>
        <SheetGroup>
          <SheetRow
            label={`Open ${org.name}`}
            onPress={() => {
              onClose();
              onOpen(org.id);
            }}
          />
          <SheetRow label="Close" onPress={() => onClose()} />
        </SheetGroup>
      </Sheet>
    );
  }

  return (
    <Sheet label={`Join ${org.name}`} onClose={() => onClose()}>
      <SheetTitle>
        <OrgMark />
        Join {org.name}?
      </SheetTitle>
      <SheetNote>
        {preview.by ? `${preview.by} shared this invite link. ` : ''}
        {memberWords(org.members)} so far. You join as a member, and its workspace is made on each of your devices. Notes filed there are the team’s: everyone in it reads and edits them.
      </SheetNote>
      {problem ? <SheetNote>{problem}</SheetNote> : null}
      <SheetGroup>
        <SheetRow label={busy ? 'Joining…' : `Join ${org.name}`} disabled={busy} onPress={() => void join()} />
        <SheetRow label="Not now" disabled={busy} onPress={() => onClose()} />
      </SheetGroup>
    </Sheet>
  );
}

/**
 * Where an invite link lands in the app (App.tsx): each one that arrives (`request`, from shell/useAppLinks.ts) is held
 * on this device and asked about, and a code held from before - followed signed out - is asked about as soon as an
 * account is signed in. `hold` keeps it back while the way into an account is up at launch (shell/AccountGate.tsx).
 */
export function JoinInvites({ request, hold, onOpen, onAccount }: { request: { code: string; nonce: number } | null; hold: boolean; onOpen: (orgId: string) => void; onAccount: () => void }) {
  const { session } = useAccount();
  const [code, setCode] = useState<string | null>(null);

  useEffect(() => {
    if (!request) return;
    holdJoin(request.code);
    setCode(request.code);
  }, [request]);

  const accountId = session?.accountId ?? null;
  useEffect(() => {
    if (accountId === null) return;
    const held = heldJoin();
    if (held) setCode(held);
  }, [accountId]);

  if (!code || hold) return null;
  return (
    <JoinSheet
      code={code}
      onClose={(keep) => {
        if (!keep) dropHeldJoin();
        setCode(null);
      }}
      onOpen={onOpen}
      onAccount={onAccount}
    />
  );
}
