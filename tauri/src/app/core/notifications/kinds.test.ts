import { describe, expect, it } from 'vitest';
import { CATEGORIES, categoryOf, detailOf, isDetails, isKind, isSelfKind, KINDS, SELF_KINDS, sentenceOf, SERVER_KINDS, type Notification } from './kinds.ts';

/* The kinds table as words (kinds.ts): every sentence a row can read as, with "Someone" for an account that is gone. */

function row(n: Partial<Notification> & { kind: Notification['kind'] }): Notification {
  return { id: 'x', rev: 1, at: 1, readAt: null, hidden: false, ...n };
}

const ghost = { id: 'o1', name: 'Ghost' };

describe('the kinds', () => {
  it('are the service’s nine and the account’s seven, each in one category', () => {
    expect(KINDS).toHaveLength(16);
    expect(SERVER_KINDS).toHaveLength(9);
    expect(SELF_KINDS).toHaveLength(7);
    expect(CATEGORIES).toEqual(['team', 'claude', 'summaries', 'conflicts']);
    expect(categoryOf('invite')).toBe('invites');
    expect(SERVER_KINDS.filter((k) => k !== 'invite').every((k) => categoryOf(k) === 'team')).toBe(true);
    expect(['note-created', 'note-edited', 'note-appended', 'journal-entry', 'rule-added'].every((k) => categoryOf(k as never) === 'claude')).toBe(true);
    expect(categoryOf('summary-written')).toBe('summaries');
    expect(categoryOf('sync-conflict')).toBe('conflicts');
    expect(isKind('invite')).toBe(true);
    expect(isKind('poke')).toBe(false);
    expect(isSelfKind('note-edited')).toBe(true);
    expect(isSelfKind('invite')).toBe(false);
  });

  it('read a sealed payload only in the shape of a self kind', () => {
    expect(isDetails({ kind: 'summary-written', noteId: 'n', title: 'T' })).toBe(true);
    expect(isDetails({ kind: 'invite', noteId: 'n', title: 'T' })).toBe(false);
    expect(isDetails({ kind: 'note-edited', title: 'T' })).toBe(false);
    expect(isDetails(null)).toBe(false);
  });
});

describe('the sentences', () => {
  it('say what the service did about an organization, by whom', () => {
    expect(sentenceOf(row({ kind: 'invite', from: 'sam', org: ghost, body: { name: 'Ghost' }, state: 'pending' }))).toBe('sam invited you to Ghost');
    expect(sentenceOf(row({ kind: 'invite-accepted', from: 'sam', org: ghost }))).toBe('sam accepted your invitation to Ghost');
    expect(sentenceOf(row({ kind: 'invite-declined', from: 'sam', org: ghost }))).toBe('sam declined your invitation to Ghost');
    expect(sentenceOf(row({ kind: 'member-joined', from: 'sam', org: ghost }))).toBe('sam joined Ghost');
    expect(sentenceOf(row({ kind: 'member-left', from: 'sam', org: ghost, body: { name: 'Ghost' } }))).toBe('sam left Ghost');
    expect(sentenceOf(row({ kind: 'member-removed', from: 'sam', org: ghost, body: { handle: 'kim' } }))).toBe('sam removed kim from Ghost');
    expect(sentenceOf(row({ kind: 'member-removed', from: 'sam', body: { name: 'Ghost' } }))).toBe('sam removed you from Ghost');
    expect(sentenceOf(row({ kind: 'role-changed', from: 'sam', org: ghost, body: { role: 'admin' } }))).toBe('sam made you an admin of Ghost');
    expect(sentenceOf(row({ kind: 'role-changed', from: 'sam', org: ghost, body: { role: 'owner' } }))).toBe('sam made you the owner of Ghost');
    expect(sentenceOf(row({ kind: 'role-changed', from: 'sam', org: ghost, body: { role: 'member' } }))).toBe('sam made you a member of Ghost');
    expect(sentenceOf(row({ kind: 'org-renamed', from: 'sam', org: ghost, body: { name: 'Ghost', was: 'Boo' } }))).toBe('sam renamed Boo to Ghost');
    expect(sentenceOf(row({ kind: 'org-deleted', from: 'sam', body: { name: 'Ghost' } }))).toBe('sam deleted Ghost');
  });

  it('say "Someone" for an account that is gone, and fall back to the name the row remembers', () => {
    expect(sentenceOf(row({ kind: 'invite', from: null, body: { name: 'Ghost' } }))).toBe('Someone invited you to Ghost');
    expect(sentenceOf(row({ kind: 'member-joined', org: ghost }))).toBe('Someone joined Ghost');
    // The live name wins while the reader is a member; the body's when they are not; and then nothing.
    expect(sentenceOf(row({ kind: 'org-renamed', from: 'sam', org: { id: 'o1', name: 'Spectre' }, body: { name: 'Ghost', was: 'Boo' } }))).toBe('sam renamed Boo to Spectre');
    expect(sentenceOf(row({ kind: 'member-left', from: 'sam' }))).toBe('sam left an organization');
  });

  it('say what Claude did, with the note’s title once the seal is open and by kind before', () => {
    const about = { noteId: 'n1', title: 'Trip to Lisbon', by: 'Claude' };
    expect(sentenceOf(row({ kind: 'note-created' }), { kind: 'note-created', ...about })).toBe('Claude created Trip to Lisbon');
    expect(sentenceOf(row({ kind: 'note-created' }))).toBe('Claude created a note');
    expect(sentenceOf(row({ kind: 'note-edited' }), { kind: 'note-edited', ...about, added: 2, removed: 0, first: '- pack', at: 'l3' })).toBe('Claude edited Trip to Lisbon · 2 lines changed');
    expect(sentenceOf(row({ kind: 'note-edited' }), { kind: 'note-edited', ...about, added: 1, removed: 0, first: '', at: '' })).toBe('Claude edited Trip to Lisbon · 1 line changed');
    expect(sentenceOf(row({ kind: 'note-edited' }))).toBe('Claude edited a note');
    expect(sentenceOf(row({ kind: 'note-appended' }), { kind: 'note-appended', ...about, lines: 3, first: '- eggs' })).toBe('Claude added 3 lines to Trip to Lisbon');
    expect(sentenceOf(row({ kind: 'note-appended' }))).toBe('Claude added to a note');
    expect(sentenceOf(row({ kind: 'journal-entry' }), { kind: 'journal-entry', ...about, title: 'Journal', journal: 'Journal', first: 'A fine day' })).toBe('Claude wrote an entry in Journal');
    expect(sentenceOf(row({ kind: 'journal-entry' }))).toBe('Claude wrote a journal entry');
    expect(sentenceOf(row({ kind: 'rule-added' }), { kind: 'rule-added', ...about, title: 'Claude rules', first: 'Always be brief' })).toBe('Claude added a rule to Claude rules');
    expect(sentenceOf(row({ kind: 'rule-added' }))).toBe('Claude added a rule');
    // The hosted server's name rides in `by`.
    expect(sentenceOf(row({ kind: 'note-created' }), { kind: 'note-created', ...about, by: 'Claude (Mac)' })).toBe('Claude (Mac) created Trip to Lisbon');
  });

  it('say what the app did for itself', () => {
    expect(sentenceOf(row({ kind: 'summary-written' }), { kind: 'summary-written', noteId: 'n1', title: 'Standup' })).toBe('A meeting was written up: Standup');
    expect(sentenceOf(row({ kind: 'summary-written' }))).toBe('A meeting was written up');
    expect(sentenceOf(row({ kind: 'sync-conflict' }), { kind: 'sync-conflict', noteId: 'n1', title: 'Trip to Lisbon' })).toBe('Trip to Lisbon was kept twice: both devices had changed it');
    expect(sentenceOf(row({ kind: 'sync-conflict' }))).toBe('A note was kept twice');
  });

  it('carry the first changed line under the sentence, for the kinds that have one', () => {
    const about = { noteId: 'n1', title: 'T', by: 'Claude' };
    expect(detailOf({ kind: 'note-edited', ...about, added: 1, removed: 1, first: '- pack', at: 'l3' })).toBe('- pack');
    expect(detailOf({ kind: 'note-appended', ...about, lines: 1, first: '' })).toBeNull();
    expect(detailOf({ kind: 'summary-written', noteId: 'n1', title: 'T' })).toBeNull();
    expect(detailOf(null)).toBeNull();
  });
});
