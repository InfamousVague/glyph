import { Ghost } from '../art/Ghost.tsx';
import { useEffect, useState, type FormEvent } from 'react';
import { KeyRound, LogOut, RefreshCw, ShieldCheck, Trash2 } from '@glacier/icons';
import { Input, SegmentedControl, Switch } from '@glacier/react';
import { changePassword, handleProblem, newRecoveryCodes, passwordProblem, recover, signIn, signUp, useAccount } from '../core/account/account.ts';
import { failureText } from '../core/failure.ts';
import { setLiveEnabled, useLiveEnabled } from '../core/live/enabled.ts';
import { setPreferences, usePreferences } from '../core/preferences.ts';
import { listNotes } from '../core/store.ts';
import { deleteAccountHere, signOutHere, syncNow, syncedWhen, unsentLine, useSyncStatus } from '../core/sync/engine.ts';
import { stayedHere } from '../core/sync/notes.ts';
import { ExportCard } from './ExportCard.tsx';
import { LocationCard } from './LocationCard.tsx';
import { PrivacyCard } from './PrivacyCard.tsx';
import type { SettingsTarget } from './SettingsScreen.tsx';
import { SharedLinks } from './SharedLinks.tsx';
import { GoWord, PaneHero, PaneSection, RowAction, SettingRow, SettingsCallout, SettingsFootnote } from './kit/settingsKit.tsx';

/**
 * Account: a Glyph account keeps notes, their recordings and pictures, and settings the same on every device
 * (docs/SYNC.md). Everything is sealed on the device before it is sent, so the page says so plainly, and says the one
 * consequence that follows: a password and every recovery code lost is an account nobody can open, us included.
 *
 * Two things a sync leaves on this device are said here as well (docs/DESIGN.md §127 section 6): a meeting's audio,
 * which stays where it was made unless "Sync meeting recordings" is on, and a recording too big for the service,
 * counted under Sync as "3 recordings stayed on this phone". And the notes the last sync could not send, with why,
 * since one bad note no longer stops the rest.
 *
 * Who you are, and what leaves the phone (docs/DESIGN.md §138): the Privacy card (PrivacyCard.tsx: Local only, Link
 * previews, the policy) and the Location card (LocationCard.tsx, which was a page) are here, beside sync and shared
 * links, signed in or out, and after the account's own cards either way. Signed out that is after the ways in. The
 * design had Privacy first there, but measured it put Sign in on the second screen at 412 × 915 (its title at 948 px)
 * and off the Fold's opened screen too, with the ghost between the two privacy cards; someone who opens Account signed
 * out has come to sign in. While Local only holds the sync off, a callout says so, signed in or out, and its "Local
 * only" is a word that brings the card into view: a plain word while a form has the card off the page.
 *
 * Organizations are not here: they are a row of their own under Account in Settings' list (OrganizationsPane.tsx;
 * Matt: "make an organizations tab under account in the sidebar instead of nesting it inside the account page").
 *
 * What the search finds here is AccountPane.findable.ts.
 */

type Mode = 'in' | 'up' | 'recover';

function Codes({ codes, onDone }: { codes: string[]; onDone: () => void }) {
  return (
    <PaneSection
      title="Recovery codes"
      description="Keep these somewhere safe, away from this device. Each opens your account once if the password is lost. They are shown this once and never again."
      footer={<RowAction onPress={onDone}>I've kept them</RowAction>}
    >
      <div className="setk-codes" data-testid="recovery-codes">
        {codes.map((code) => (
          <code key={code}>{code}</code>
        ))}
      </div>
      <SettingRow label="Copy all" onPress={() => void navigator.clipboard?.writeText(codes.join('\n'))} />
    </PaneSection>
  );
}

/** The callout while Local only holds the sync off; its words bring the Privacy card into view, where there is one. */
function LocalOnlyCallout({ onOpen }: { onOpen?: () => void }) {
  return (
    <SettingsCallout>
      <span>
        <GoWord onPress={onOpen}>Local only</GoWord> is on, so nothing syncs until it is off.
      </span>
    </SettingsCallout>
  );
}

/**
 * The way in on its own, as one plain card: sign in or make an account, and keep a new account's recovery codes - or
 * recover one. The first screen on open draws it (shell/AccountGate.tsx; Matt: "a simple login card that asks you to
 * login or signup"), told by `onIn` once the person is in - straight after a sign-in, and after the codes are put away
 * for a new or recovered account, so the codes are never skipped. Settings' Account page has the long form of the
 * same thing (`SignedOut`), with the privacy cards after it.
 */
export function SignInFlow({ onIn }: { onIn: () => void }) {
  const [codes, setCodes] = useState<string[] | null>(null);
  const form = useWayIn(setCodes, onIn);
  if (codes)
    return (
      <section className="setk-signIn" aria-label="Recovery codes">
        <Codes codes={codes} onDone={onIn} />
      </section>
    );
  const { mode, setMode } = form;
  return (
    <section className="setk-signIn" aria-label={mode === 'up' ? 'Create an account' : mode === 'recover' ? 'Recover an account' : 'Sign in'}>
      <h1 className="setk-signIn__title">{mode === 'up' ? 'Create an account' : mode === 'recover' ? 'Recover an account' : 'Sign in to Ghost.md'}</h1>
      <p className="setk-signIn__line">{mode === 'recover' ? 'A recovery code and a new password open it again.' : 'Your notes, the same on every device, encrypted before they leave this one.'}</p>
      {mode !== 'recover' ? (
        <SegmentedControl
          aria-label="Sign in or sign up"
          fullWidth
          size="sm"
          options={[
            { value: 'in', label: 'Sign in' },
            { value: 'up', label: 'Sign up' },
          ]}
          value={mode}
          onValueChange={(value) => setMode(value as Mode)}
        />
      ) : null}
      <WayInForm form={form} />
      <button type="button" className="app-word setk-signIn__other" onClick={() => setMode(mode === 'recover' ? 'in' : 'recover')}>
        {mode === 'recover' ? 'Back to sign in' : 'Lost the password?'}
      </button>
    </section>
  );
}

/** The way-in form's state and its submit, for the long form (`SignedOut`) and the card (`SignInFlow`) alike. */
function useWayIn(onCodes: (codes: string[]) => void, onIn?: () => void) {
  const [mode, setModeNow] = useState<Mode>('in');
  const [handle, setHandle] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);

  const setMode = (next: Mode) => {
    setModeNow(next);
    setProblem(null);
  };

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const early = handleProblem(handle) ?? (mode !== 'in' ? passwordProblem(password) : null);
    if (early) return setProblem(early);
    setBusy(true);
    setProblem(null);
    try {
      if (mode === 'up') onCodes((await signUp(handle, password)).codes);
      else if (mode === 'recover') onCodes((await recover(handle, code, password)).codes);
      else {
        await signIn(handle, password);
        onIn?.();
      }
      void syncNow();
    } catch (failure) {
      setProblem(failureText(failure));
    } finally {
      setBusy(false);
    }
  };

  return { mode, setMode, handle, setHandle, password, setPassword, code, setCode, busy, problem, submit };
}

function WayInForm({ form }: { form: ReturnType<typeof useWayIn> }) {
  const { mode, handle, setHandle, password, setPassword, code, setCode, busy, problem, submit } = form;
  const verb = mode === 'up' ? 'Create account' : mode === 'recover' ? 'Recover and set password' : 'Sign in';
  return (
    <form className="setk-form" onSubmit={(e) => void submit(e)}>
      <Input aria-label="Handle" placeholder="Handle" autoComplete="username" autoCapitalize="none" spellCheck={false} value={handle} onChange={(e) => setHandle(e.target.value)} />
      {mode === 'recover' ? (
        <Input aria-label="Recovery code" placeholder="Recovery code" autoCapitalize="characters" spellCheck={false} value={code} onChange={(e) => setCode(e.target.value)} />
      ) : null}
      <Input
        aria-label={mode === 'recover' ? 'New password' : 'Password'}
        placeholder={mode === 'recover' ? 'New password' : 'Password'}
        type="password"
        autoComplete={mode === 'in' ? 'current-password' : 'new-password'}
        value={password}
        onChange={(e) => setPassword(e.target.value)}
      />
      {problem ? (
        <p className="setk-form__problem" role="alert">
          {problem}
        </p>
      ) : null}
      <button type="submit" className="app-word setk-form__submit" disabled={busy || !handle || !password || (mode === 'recover' && !code)}>
        {busy ? 'One moment…' : verb}
      </button>
    </form>
  );
}

function SignedOut({
  onCodes,
  said,
  onOpen,
}: {
  onCodes: (codes: string[]) => void;
  said?: string | null;
  onOpen?: (target: SettingsTarget) => void;
}) {
  const prefs = usePreferences();
  const form = useWayIn(onCodes);
  const { mode, setMode } = form;
  return (
    <>
      {said ? <SettingsCallout>{said}</SettingsCallout> : null}
      {prefs.localOnly ? <LocalOnlyCallout onOpen={onOpen ? () => onOpen({ id: 'account', setting: 'Privacy' }) : undefined} /> : null}
      <Ghost scene="signed-out" align="center" />
      <PaneSection
        title={mode === 'up' ? 'New account' : mode === 'recover' ? 'Recover' : 'Sign in'}
        description="Keep your notes, recordings and settings the same on your phone and computer. They are encrypted on the device first. The service stores only what it cannot read."
      >
        <WayInForm form={form} />
      </PaneSection>
      <PaneSection>
        {mode !== 'in' ? <SettingRow label="I have an account" onPress={() => setMode('in')} /> : null}
        {mode !== 'up' ? <SettingRow label="Create an account" onPress={() => setMode('up')} /> : null}
        {mode !== 'recover' ? <SettingRow label="Lost the password" hint="Use one of your recovery codes." onPress={() => setMode('recover')} /> : null}
      </PaneSection>
      <SettingsFootnote>
        Your password never leaves this device, and nobody can reset it for you. Without it or a recovery code, the notes in an account can't be opened by anyone. Notes on this device stay here either way.
      </SettingsFootnote>
      <PrivacyCard />
      <LocationCard />
      <ExportCard />
    </>
  );
}

function PasswordForm({ onCodes, onDone }: { onCodes: (codes: string[]) => void; onDone: () => void }) {
  const [what, setWhat] = useState<'password' | 'codes'>('password');
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setProblem(null);
    try {
      if (what === 'password') {
        await changePassword(current, next);
        onDone();
      } else {
        onCodes((await newRecoveryCodes(current)).codes);
      }
    } catch (failure) {
      setProblem(failureText(failure));
    } finally {
      setBusy(false);
    }
  };

  return (
    <PaneSection title={what === 'password' ? 'Change password' : 'New recovery codes'} footer={<RowAction onPress={onDone}>Cancel</RowAction>}>
      <form className="setk-form" onSubmit={(e) => void submit(e)}>
        <Input aria-label="Current password" placeholder="Current password" type="password" autoComplete="current-password" value={current} onChange={(e) => setCurrent(e.target.value)} />
        {what === 'password' ? (
          <Input aria-label="New password" placeholder="New password" type="password" autoComplete="new-password" value={next} onChange={(e) => setNext(e.target.value)} />
        ) : null}
        {problem ? (
          <p className="setk-form__problem" role="alert">
            {problem}
          </p>
        ) : null}
        <button type="submit" className="app-word setk-form__submit" disabled={busy || !current || (what === 'password' && !next)}>
          {busy ? 'One moment…' : what === 'password' ? 'Change password' : 'Make new codes'}
        </button>
        <button type="button" className="app-word" onClick={() => setWhat(what === 'password' ? 'codes' : 'password')}>
          {what === 'password' ? 'Make new recovery codes instead' : 'Change the password instead'}
        </button>
      </form>
    </PaneSection>
  );
}

/**
 * Deleting the account (App Store 5.1.1(v) and Google Play both ask for it in the app): what goes and what stays said
 * first, then the password asked for, as a phone left unlocked shouldn't be able to lose its owner's account.
 * Everything the account keeps on the service goes at once and for good; the notes on this device stay.
 */
function DeleteAccountForm({ onDeleted, onDone }: { onDeleted: () => void; onDone: () => void }) {
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setProblem(null);
    try {
      await deleteAccountHere(password);
      onDeleted();
    } catch (failure) {
      setProblem(failureText(failure));
      setBusy(false);
    }
  };

  return (
    <PaneSection
      title="Delete account"
      description="This deletes your account and everything it keeps on the sync service, for good: your synced notes, their recordings and pictures, your settings, and every link you've shared, which will stop opening. Your other devices are signed out. The notes on this device stay here."
      footer={<RowAction onPress={onDone}>Cancel</RowAction>}
    >
      <form className="setk-form" onSubmit={(e) => void submit(e)}>
        <Input aria-label="Password" placeholder="Password" type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} />
        {problem ? (
          <p className="setk-form__problem" role="alert">
            {problem}
          </p>
        ) : null}
        <button type="submit" className="app-word setk-form__submit" disabled={busy || !password}>
          {busy ? 'Deleting…' : 'Delete my account'}
        </button>
      </form>
    </PaneSection>
  );
}

export function AccountPane({ onOpen }: { onOpen?: (target: SettingsTarget) => void }) {
  const account = useAccount();
  const status = useSyncStatus();
  const live = useLiveEnabled();
  const prefs = usePreferences();
  // How many recordings stayed on this phone, by the notes as they are and the two rules: counted as the page opens.
  const [stayed, setStayed] = useState(0);
  useEffect(() => {
    let alive = true;
    void listNotes()
      .then((notes) => {
        if (alive) setStayed(stayedHere(notes, prefs));
      })
      .catch(() => undefined);
    return () => {
      alive = false;
    };
  }, [prefs]);
  const [codes, setCodes] = useState<string[] | null>(null);
  const [editing, setEditing] = useState(false);
  const [deleting, setDeleting] = useState(false);
  // Said on the signed-out page that follows a deletion, so it is clear the account went and the notes didn't.
  const [deleted, setDeleted] = useState(false);

  if (codes) return <Codes codes={codes} onDone={() => setCodes(null)} />;
  if (!account.session) return <SignedOut onCodes={setCodes} onOpen={onOpen} said={deleted ? 'Your account is deleted. The notes on this device are still here.' : null} />;

  const statusText =
    status.phase === 'syncing'
      ? 'Syncing'
      : status.phase === 'error'
        ? (status.message ?? 'Not synced')
        : status.lastAt
          ? `Synced ${syncedWhen(status.lastAt)}`
          : account.unlocked
            ? 'Waiting to sync'
            : 'Sign in again to sync';
  return (
    <>
      <PaneSection>
        <PaneHero glyph={<ShieldCheck size={22} />} title={account.session.handle} meta="End-to-end encrypted" status={{ text: statusText, pulse: status.phase === 'syncing' }} />
      </PaneSection>
      {status.conflicts ? (
        <SettingsCallout>
          {status.conflicts === 1 ? 'A note was' : `${status.conflicts} notes were`} changed on two devices at once. Both versions are kept as separate notes.
        </SettingsCallout>
      ) : null}
      {status.unsent ? (
        <SettingsCallout>
          {unsentLine(status.unsent)}. {status.unsentReason ?? 'They are sent again next time.'}
        </SettingsCallout>
      ) : null}
      {/* The password and delete forms take the Privacy card off the page: the word has nowhere to go while one is open. */}
      {prefs.localOnly ? <LocalOnlyCallout onOpen={onOpen && !editing && !deleting ? () => onOpen({ id: 'account', setting: 'Privacy' }) : undefined} /> : null}
      {deleting ? (
        <DeleteAccountForm
          onDeleted={() => {
            setDeleting(false);
            setDeleted(true);
          }}
          onDone={() => setDeleting(false)}
        />
      ) : editing ? (
        <PasswordForm
          onCodes={(next) => {
            setEditing(false);
            setCodes(next);
          }}
          onDone={() => setEditing(false)}
        />
      ) : (
        <PaneSection
          title="Sync"
          footer={`Notes, their recordings and pictures, and your settings. The model you downloaded and Developer settings stay on each device.${stayed ? ` ${stayed === 1 ? '1 recording' : `${stayed} recordings`} stayed on this phone.` : ''}`}
        >
          <SettingRow icon={<RefreshCw size={20} />} label="Sync now" onPress={() => void syncNow()} disabled={status.phase === 'syncing'} />
          <SettingRow
            label="Sync meeting recordings"
            hint="A meeting is other people's voices. Off, the words sync and the audio stays on the device it was made on."
            control={<Switch aria-label="Sync meeting recordings" checked={prefs.syncMeetingRecordings} onCheckedChange={(syncMeetingRecordings) => setPreferences({ syncMeetingRecordings })} />}
          />
          {/* Live sync (docs/LIVE.md), on by hand while it is being tried: off, nothing of it is loaded at all. */}
          <SettingRow
            label="Live typing (trial)"
            hint="A note open on two of your devices shows what is typed on either as it is typed, end to end encrypted like everything else. Starts with the next note you open."
            control={<Switch aria-label="Live typing" checked={live} onCheckedChange={setLiveEnabled} />}
          />
          <SettingRow icon={<KeyRound size={20} />} label="Password and recovery codes" onPress={() => setEditing(true)} />
          <SettingRow icon={<LogOut size={20} />} label="Sign out" hint="Your notes stay on this device." onPress={() => void signOutHere()} />
        </PaneSection>
      )}
      {editing || deleting ? null : (
        <>
          <SharedLinks />
          <PrivacyCard />
          <LocationCard />
          <ExportCard />
          <PaneSection>
            <SettingRow icon={<Trash2 size={20} />} label="Delete account" hint="Your account and everything synced to it. The notes on this device stay." onPress={() => setDeleting(true)} />
          </PaneSection>
        </>
      )}
    </>
  );
}
