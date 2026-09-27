import type { Placement } from './command.ts';
import type { Offer } from './offers.ts';
import type { TakeNote } from './takeTypes.ts';

/**
 * What a take (capture/take.ts) asks of whoever runs it, and what it tells them; and what the chip at the foot of the
 * recorder says, which the live reader (liveRoute.ts) tells it too.
 *
 * The take has no screen: its host shows and does. The recorder (CaptureScreen.tsx) runs one over the real notes, and
 * a test of the take passes one that does nothing until told (src/test/takeHost.ts). The chip and the card after Done
 * are the host's to draw from what arrives here; the notes are the host's to change when the card is tapped.
 */

/** What the chip at the foot of the recorder says. */
export type RouteView =
  /** A command held for its note's name: the name heard so far. */
  | { phase: 'hearing'; name: string }
  | { phase: 'done'; text: string }
  /** The keyword heard, and the words of the command after it so far. */
  | { phase: 'command'; words: string }
  | { phase: 'said'; text: string }
  /** A note named with nothing said for it yet: what is said next goes there. */
  | { phase: 'waiting'; title: string }
  /** Words landed in another note's list; `insert` is the live reader's one-shot, which its Not this note takes out again. */
  | { phase: 'added'; title: string; body: string; added: string[]; insert?: number }
  /** The words went to a note, and carry on there; `spot` says where in it ("under Electrical"). */
  | { phase: 'moved'; title: string; spot?: string | null }
  | { phase: 'missed'; title: string }
  /**
   * The last thing said, taken back (liveRoute.ts `takeBack`): what went, where it went instead or what it became, and
   * the take-back's id for its Undo; none when there is nothing to put back (a command cancelled).
   */
  | { phase: 'tookBack'; said: string; outcome: 'gone' | { sent: string } | { placed: string } | { changed: string }; undo?: number }
  | null;

export type Haptic = 'light' | 'selection' | 'success' | 'warning';

/** What the take asks of whoever runs it. */
export interface TakeHost<N extends TakeNote> {
  route(view: RouteView): void;
  offer(offer: Offer<N> | null): void;
  haptic(kind: Haptic): void;
  /** The take's words changed. */
  changed(): void;
  /** Add, tapped on a place offer: the words into that note. */
  addItems(note: N, spoken: string, placement: Placement): void;
}

/**
 * A host that is always the one `ref` holds now.
 *
 * The recorder makes its take once, but its host is new with every render, because each render's functions see that
 * render's state. So the take is given this instead, which looks each member up on the ref at the moment the take
 * uses it: a method is always the newest render's. A member the host gains is reached through it with nothing more to
 * write.
 */
export function hostThrough<N extends TakeNote>(ref: { readonly current: TakeHost<N> }): TakeHost<N> {
  return new Proxy({} as TakeHost<N>, {
    get: (_, member) => ref.current[member as keyof TakeHost<N>],
  });
}
