import type { Choices } from './library.ts';
import type { Draft } from './note.ts';
import type { ClipMode, Extract, Peek } from './page.ts';
import type { LinkReason } from './pictures.ts';

/**
 * What the popup asks the clipper's background, and what it answers. The background holds the account (its keys
 * never reach the popup), reads pages, and saves; the popup only shows and asks. Every answer is `{ ok: true, ... }`
 * or `{ ok: false, error }` with words for the person.
 */
export type Ask =
  | { type: 'who' }
  | { type: 'signIn'; handle: string; password: string; stay: boolean }
  | { type: 'signOut' }
  | { type: 'choices' }
  | { type: 'peek'; tabId: number }
  | { type: 'read'; tabId: number; mode: ClipMode }
  | { type: 'save'; tabId: number; draft: Draft };

export interface SavedAnswer {
  id: string;
  title: string;
  stored: number;
  linked: { url: string; why: LinkReason }[];
}

export type Answer<T> = ({ ok: true } & T) | { ok: false; error: string; signedOut?: boolean };

export interface Answers {
  who: Answer<{ handle: string | null; stay: boolean }>;
  signIn: Answer<{ handle: string }>;
  signOut: Answer<object>;
  choices: Answer<{ choices: Choices }>;
  peek: Answer<{ page: Peek }>;
  read: Answer<{ extract: Extract }>;
  save: Answer<{ saved: SavedAnswer }>;
}
