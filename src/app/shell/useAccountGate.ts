import { useState } from 'react';
import { accountState } from '../core/account/account.ts';
import { preferences } from '../core/preferences.ts';
import { storedFlag } from '../core/stored.ts';

/**
 * Whether the way into an account is the first thing on screen (shell/AccountGate.tsx; Matt: "move the login / signup
 * flow to the first thing that happens when you open the app"). It comes up by itself, before the walkthrough, on an
 * open that is signed out - once: signing in, making an account or choosing to use the app without one marks it seen,
 * and after that the way in is Settings › Account, as before.
 *
 * Not for a person already signed in, nor one who chose Local only (nothing would sync, so asking would only be in the
 * way), nor an open by the side key, who is already mid-sentence: the recording comes first, as it does for the guide.
 */

/** No storage: asking on every open would be worse than never asking. */
const seenFlag = storedFlag('glyph-account-gate-seen', { value: '1', unreadable: true });

export interface AccountGateState {
  open: boolean;
  /** Closed and seen: signed in, or going on without an account. */
  close: () => void;
}

/** `launchedByKey`: the side key launched this run of the app (core/host.ts `takeCaptureLaunch`). */
export function useAccountGate(launchedByKey: boolean): AccountGateState {
  const [open, setOpen] = useState(() => !seenFlag.is() && !launchedByKey && !accountState().session && !preferences().localOnly);
  return {
    open,
    close: () => {
      seenFlag.mark();
      setOpen(false);
    },
  };
}
