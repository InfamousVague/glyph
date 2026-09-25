import { useEffect, useRef } from 'react';
import { useToast } from '@glacier/react';
import { startRefining } from '../capture/refine.ts';
import { installBack } from '../core/back.ts';
import { installTapHaptics } from '../core/haptics.ts';
import { settleBoot } from '../core/ota.ts';
import { applyPreferences } from '../core/preferences.ts';
import { sampleNoteSeeded, seedSampleNote } from '../core/seed.ts';
import { latestCommandMutation, NOTE_SAVED, undoCommandMutation, type Note } from '../core/store.ts';
import { sweepMemos } from '../core/sweepMemos.ts';
import { startSync } from '../core/sync/engine.ts';

/**
 * What the Shell keeps running for the life of the app and draws nothing for: the boot handshake, the page-wide
 * listeners, the work done in the background, and the few things done once to a library as it is first read.
 *
 * Each is an effect of its own, with the comment that says why it runs when it does. None of them reads or sets which
 * screen is up, which is why they are here and not in the Shell's body (App.tsx): that is the part of the app a person
 * can see.
 */

export interface HousekeepingOptions {
  notes: readonly Note[];
  loading: boolean;
  refresh: () => Promise<void>;
  /** Whether the window holds the sidebar beside the note (core/useWideScreen.ts `useSidebar`). */
  sidebar: boolean;
}

export function useHousekeeping({ notes, loading, refresh, sidebar }: HousekeepingOptions): void {
  const { toast } = useToast();

  useEffect(() => {
    // First, before anything that might reload: this frontend mounted, so the
    // build the loader staked on it is safe. See core/ota.ts.
    settleBoot();
    applyPreferences();
    // The phone's back gesture and Escape: each screen registers what
    // leaving it means (core/back.ts); this installs the answer once.
    const uninstallBack = installBack();
    const untap = installTapHaptics();
    return () => {
      uninstallBack();
      untap();
    };
  }, []);

  const undoRecoveryChecked = useRef(false);
  // A confirmed command and its undo record are persisted together. If the
  // process stopped before its success chip could be used, re-offer the same
  // guarded undo once; a later edit turns it into a conflict rather than data loss.
  // The one ask is never called off: StrictMode runs this effect, cleans it up and runs it again, and a cleanup that
  // cancelled the first ask left the second, stopped by the guard, nothing to offer.
  useEffect(() => {
    if (undoRecoveryChecked.current) return;
    undoRecoveryChecked.current = true;
    void latestCommandMutation()
      .then((pending) => {
        if (!pending) return;
        toast({
          message: pending.kind === 'create' ? 'Voice command created a note.' : 'Voice command changed a note.',
          duration: 10_000,
          action: {
            label: 'Undo',
            onPress: () => void undoCommandMutation(pending.mutationId).then(() => refresh()),
          },
        });
      })
      .catch(() => undefined);
  }, [refresh, toast]);

  // The better words after a recording, worked out in the background; the list
  // is refreshed when a note's words change.
  useEffect(() => startRefining(() => void refresh()), [refresh]);
  // Sync, for a device signed in to an account (docs/SYNC.md); nothing happens without one.
  useEffect(() => startSync(), []);

  // The list beside a note shows its title and order as it is written: read again a moment after each save.
  useEffect(() => {
    if (!sidebar) return undefined;
    let timer = 0;
    const saved = () => {
      window.clearTimeout(timer);
      timer = window.setTimeout(() => void refresh(), 300);
    };
    window.addEventListener(NOTE_SAVED, saved);
    return () => {
      window.clearTimeout(timer);
      window.removeEventListener(NOTE_SAVED, saved);
    };
  }, [sidebar, refresh]);

  // Memos were taken out of the app (Matt: "remove memo's entirely", and the ones written go too): the first read
  // of the notes after this build puts any left in the trash (core/sweepMemos.ts).
  useEffect(() => {
    if (loading) return;
    if (sweepMemos(notes)) void refresh();
  }, [loading, notes, refresh]);

  // A fresh library gets the sample note once (core/seed.ts): a few seconds
  // after the first read comes back empty, past the store's own re-asks, so a
  // slow first answer from the phone is never mistaken for an empty library.
  useEffect(() => {
    if (loading || sampleNoteSeeded()) return undefined;
    const timer = window.setTimeout(() => {
      void seedSampleNote(notes.length).then((made) => made && refresh());
    }, 4000);
    return () => window.clearTimeout(timer);
  }, [loading, notes.length, refresh]);
}
