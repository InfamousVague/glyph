/**
 * The words a version's timeline is read by (VersionHistory.tsx, notes/OrganizationLog.tsx): the day's name over a
 * day's versions, the clock beside each, and who kept it. In a file of their own so the components' file exports
 * components alone, which is what keeps its edits hot.
 */

/** "Today", "Yesterday", or the date: a day's heading on the timeline. */
export function dayOf(at: number, now = Date.now()): string {
  const day = (ms: number) => new Date(ms).setHours(0, 0, 0, 0);
  const days = Math.round((day(now) - day(at)) / 86_400_000);
  if (days === 0) return 'Today';
  if (days === 1) return 'Yesterday';
  return new Date(at).toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short', ...(new Date(at).getFullYear() !== new Date(now).getFullYear() ? { year: 'numeric' } : {}) });
}

/** The time of day a version was kept, beside it on the timeline. */
export const clock = (at: number): string => new Date(at).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });

/** A version's author in words: "You" for one kept here without an account. */
export const authorName = (by: string): string => (by === 'me' ? 'You' : by);
