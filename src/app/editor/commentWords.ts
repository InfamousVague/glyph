import { when } from '../notes/when.ts';

/**
 * The words a comment's card says about people and times (editor/CommentCard.tsx), in a file of their own so the
 * components' file exports components alone, as editor/versionWords.ts is for the version history.
 */

/** Who wears which colour (core/comments/colours.ts), and who "you" are, for the names. */
export interface CardPeople {
  colour: (handle: string) => string;
  /** This person's handle, written "You"; `me` is always you. */
  me: string;
}

/** A person as the card names them: "You" for this person. */
export function nameOf(by: string, people: CardPeople): string {
  return by === 'me' || by === people.me ? 'You' : by;
}

/** "2 hr ago" for a written time, or the time as written where it cannot be read. */
export function ago(at: string, now = Date.now()): string {
  const ms = Date.parse(at);
  return Number.isFinite(ms) ? when(ms, now) : at;
}
