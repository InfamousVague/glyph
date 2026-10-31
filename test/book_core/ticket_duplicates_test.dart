import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/ticket_duplicates.dart';
import 'package:ghost_md/book/tickets.dart';
import 'package:ghost_md/core/link_index.dart';

import '../core/make_note.dart';

/// A ticket's likely duplicates (lib/book/ticket_duplicates.dart; Matt, 2026-10-31): titles weighed by the words they
/// share, rarer words counting more, narrowed by the link index's words; done ones a little lower, closed duplicates
/// never, the ticket itself never.
String ticket(String id, String title, {String status = 'To do', String more = '', String words = ''}) => '---\ntype: ticket\nid: $id\nstatus: $status\n$more---\n# $title\n\n$words';

final Map<String, String> bodies = {
  'loop': ticket('GHO-1', 'Login page loops after signing in', words: 'The session cookie is dropped on Safari.'),
  'oauth': ticket('GHO-2', 'Google sign in fails on Android'),
  'docs': ticket('GHO-3', 'Write the onboarding docs'),
  'login-old': ticket('GHO-4', 'Login loops forever', status: 'Done'),
  'closed': ticket('GHO-5', 'Login loop on the Mac', status: 'Duplicate', more: 'duplicate-of: "[[GHO-1]]"\n'),
  'export': ticket('GHO-6', 'Export a notebook as PDF'),
  'note': '# Login loops, a note that is no ticket\n',
};

List<TicketEntry> library() => ticketsIn([for (final MapEntry(:key, :value) in bodies.entries) makeNote(key, body: value)]);

LinkIndex index() => LinkIndex.build([for (final MapEntry(:key, :value) in bodies.entries) (id: key, body: value, path: null, updatedAt: 0)]);

void main() {
  test('a title’s words, less the small ones, a plural’s s off', () {
    expect(titleTerms('The login page loops when I sign in'), ['login', 'page', 'loop', 'sign']);
    expect(titleTerms('Fix #42: crash'), ['fix', '42', 'crash']);
  });

  test('a new ticket’s likely duplicates, most alike first, with the words they share', () {
    final hits = likelyDuplicates(title: 'Login loops after sign in', entries: library(), index: index());
    expect([for (final hit in hits) hit.entry.ticket.id], ['GHO-1', 'GHO-4']);
    expect(hits.first.shared, ['login', 'loop', 'after'], reason: '“signing” is not “sign”: words, not stems');
    expect(hits.first.score, greaterThan(hits.last.score));
    expect(hits.any((hit) => hit.entry.note.id == 'closed'), isFalse, reason: 'a closed duplicate is never offered');
  });

  test('without the index every ticket is weighed, to the same answer', () {
    final withIndex = likelyDuplicates(title: 'Login loops after sign in', entries: library(), index: index());
    final without = likelyDuplicates(title: 'Login loops after sign in', entries: library());
    expect([for (final hit in without) hit.entry.note.id], [for (final hit in withIndex) hit.entry.note.id]);
  });

  test('nothing for a title like no other, for the ticket itself, or for one of small words alone', () {
    expect(likelyDuplicates(title: 'Dark mode for the calendar', entries: library(), index: index()), isEmpty);
    expect(likelyDuplicates(title: 'Write the onboarding docs', entries: library(), index: index(), selfId: 'docs'), isEmpty);
    expect(likelyDuplicates(title: 'the and to', entries: library(), index: index()), isEmpty);
  });

  test('a new ticket’s own words count a little towards a ticket that says them', () {
    final bare = likelyDuplicates(title: 'Login fails', entries: library(), index: index(), floor: 0);
    final worded = likelyDuplicates(title: 'Login fails', words: 'Safari drops the session cookie.', entries: library(), index: index(), floor: 0);
    double scoreOf(List<DuplicateHit> hits, String id) => hits.firstWhere((hit) => hit.entry.note.id == id).score;
    expect(scoreOf(worded, 'loop'), greaterThan(scoreOf(bare, 'loop')));
    expect(worded.first.entry.note.id, 'loop');
  });
}
