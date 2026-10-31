import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/ticket_merge.dart';
import 'package:ghost_md/book/ticket_watchers.dart';
import 'package:ghost_md/book/tickets.dart';
import 'package:ghost_md/comments/format.dart';
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/core/link_index.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/core/stored.dart';

import '../core/make_note.dart';

/// "Merge into…" (lib/book/ticket_merge.dart; Matt, 2026-10-31): everything moved - comments, watchers, labels, links,
/// words - every link rewritten across the library, the duplicate closed with `duplicate-of`, and one Undo.
const String notebook = '---\ntitle: "Ghost"\nbook: true\nkey: GHO\nstatuses: [To do, In progress, Done, Duplicate]\n---\n# Ghost\n\n- [[Login loops forever]]\n- [[Fix the login loop]]\n';

const String target = '---\ntype: ticket\nid: GHO-1\nstatus: In progress\nwatchers: ["@matt"]\nlabels: [auth]\n---\n# Fix the login loop\n\nThe cookie is dropped.[^c1]\n\n```comments\nc1 matt 2026-10-30T09:00:00Z\nSafari only?\n```\n';

const String duplicate = '---\ntype: ticket\nid: GHO-4\nstatus: To do\nwatchers: ["@sam", "@matt"]\nlabels: [bug, auth]\nblocked-by: ["[[GHO-9]]", "[[GHO-1]]"]\n---\n# Login loops forever\n\nSteps: sign in, then it loops.[^c1] See [[GHO-9]].\n\n```comments\nc1 sam 2026-10-31T08:00:00Z\nOn Android too.\n  ana 2026-10-31T08:10:00Z\n  And on the Fold.\n```\n';

const String blocker = '---\ntype: ticket\nid: GHO-9\nstatus: To do\n---\n# Cookies\n';

final Map<String, String> bodies = {
  'book': notebook,
  'target': target,
  'dup': duplicate,
  'blocker': blocker,
  'plan': '# Launch plan\n\n- waits on [[GHO-4]] and [[Login loops forever#Steps|the steps]]\n- ![[GHO-4]]\n- not this: `[[GHO-4]]`\n',
  'team': '# Team standup\n\nSam took [[GHO-4]].\n',
  'other': '# Other\n\nNothing here links [[GHO-9]].\n',
};

({List<TicketEntry> entries, LinkIndex index, Map<String, ({String title, String body})> notes}) world(Map<String, String> now) {
  final notes = [for (final MapEntry(:key, :value) in now.entries) makeNote(key, body: value)];
  return (
    entries: ticketsIn(notes),
    index: LinkIndex.build([for (final note in notes) (id: note.id, body: note.body, path: null, updatedAt: 0)]),
    notes: {for (final note in notes) note.id: (title: note.body.split('\n').firstWhere((l) => l.startsWith('# '), orElse: () => '# ').substring(2), body: note.body)},
  );
}

MergePlan plan(Map<String, String> now, {bool Function(String id)? editable}) {
  final w = world(now);
  TicketEntry entry(String id) => w.entries.firstWhere((e) => e.note.id == id);
  return planMerge(duplicate: entry('dup'), target: entry('target'), notes: w.notes, index: w.index, editable: editable);
}

void main() {
  test('the target takes its words under “Merged from”, its comments under fresh ids, its watchers, labels and links', () {
    final made = plan(bodies);
    final after = made.writes.firstWhere((w) => w.id == 'target').after;
    expect(after, contains('## Merged from GHO-4\n\nSteps: sign in, then it loops.'));
    expect(after, isNot(contains('# Login loops forever')), reason: 'its title heading is left out');
    expect(watchersOf(after), ['matt', 'sam']);
    expect(propertyList(frontMatterValue(after, 'labels')), ['auth', 'bug']);
    expect(frontMatterValue(after, 'blocked-by'), '[[GHO-9]]', reason: 'its blockers, less the two tickets themselves');
    final comments = readComments(after);
    expect(comments.threads, hasLength(2));
    expect(comments.threads.first.id, 'c1');
    final moved = comments.threads.last;
    expect(moved.id, isNot('c1'), reason: 'the target has a c1 already');
    expect((moved.head.by, moved.head.words, moved.replies.single.by), ('sam', 'On Android too.', 'ana'));
    expect(comments.anchors.map((a) => a.id), ['c1', moved.id], reason: 'its anchor came with its words, renamed');
    expect(after.indexOf('## Merged from'), lessThan(after.indexOf('```comments')), reason: 'its words before the comments');
    expect(made.comments, 1);
  });

  test('the duplicate is closed in its workflow’s Duplicate, points at the target, and its comments are gone', () {
    final after = plan(bodies).writes.firstWhere((w) => w.id == 'dup').after;
    expect(ticketOf(after)?.status, 'Duplicate');
    expect(frontMatterValue(after, 'duplicate-of'), '[[GHO-1]]');
    expect(after, isNot(contains('```comments')));
    expect(after, isNot(contains('[^c1]')));
    expect(after, contains('Steps: sign in, then it loops. See [[GHO-9]].'));
    expect(duplicateStatus(defaultStatuses), 'Done');
  });

  test('every link to it is rewritten, heading, words and embed kept, none in code; a note that cannot be changed is said', () {
    final made = plan(bodies, editable: (id) => id != 'team');
    final linked = made.writes.firstWhere((w) => w.id == 'plan').after;
    expect(linked, '# Launch plan\n\n- waits on [[GHO-1]] and [[GHO-1#Steps|the steps]]\n- ![[GHO-1]]\n- not this: `[[GHO-4]]`\n');
    expect((made.links, made.linkNotes), (3, 1));
    expect(made.writes.map((w) => w.id), isNot(contains('team')));
    expect(made.skipped, ['Team standup']);
    expect(made.warnings.join(' '), contains('cannot be changed here'));
    expect(made.writes.map((w) => w.id), isNot(contains('other')), reason: 'a note that does not link to it is left alone');
    expect(made.summary, contains('3 links in 1 note change to GHO-1'));
    final all = plan(bodies);
    expect(all.writes.firstWhere((w) => w.id == 'team').after, '# Team standup\n\nSam took [[GHO-1]].\n');
  });

  test('one Undo puts every note back, and leaves one changed since', () async {
    final now = {...bodies};
    final versions = <(String, String, String)>[];
    final unconditional = <String>{};
    final world = MergeWorld(
      body: (id) async => now[id],
      write: (id, body) async => now[id] = body,
      keepVersion: (id, text, label, {bool always = false}) async {
        versions.add((id, label, text));
        if (always) unconditional.add(id);
      },
      kept: MemoryStored(),
      clock: () => 5,
    );
    final made = plan(now);
    final record = await applyMerge(made, world);
    expect(now['plan'], contains('[[GHO-1]]'));
    expect(ticketOf(now['dup']!)?.status, 'Duplicate');
    expect(versions.map((v) => v.$2).toSet(), {'Before merging GHO-4 into GHO-1'});
    expect(versions.map((v) => v.$1), containsAll(['target', 'dup', 'plan', 'team']));
    // The target and the duplicate keep theirs whatever their switch says (MARKDOWN_FIRST §11, decision 21); a note
    // whose links were rewritten only where it keeps versions.
    expect(unconditional, {'target', 'dup'});
    expect(mergeOf(world.kept, 'dup')?.targetId, 'target');
    // The Undo: everything back as one step.
    expect(await undoMerge(record, world), isEmpty);
    expect(now, bodies);
    expect(mergeOf(world.kept, 'dup'), isNull);
    // Merged again, and a note changed since: the rest put back, it left and named.
    final again = await applyMerge(plan(now), world);
    now['plan'] = '${now['plan']}\nA line typed after the merge.\n';
    expect(await undoMerge(again, world), ['Launch plan']);
    expect(now['target'], bodies['target']);
    expect(now['plan'], contains('A line typed after the merge.'));
  });

  test('a note changed while the merge was planned stops it whole', () async {
    final now = {...bodies};
    final made = plan(now);
    now['plan'] = '# Launch plan\n\nRewritten.\n';
    final world = MergeWorld(body: (id) async => now[id], write: (id, body) async => now[id] = body, kept: MemoryStored());
    await expectLater(applyMerge(made, world), throwsA(isA<StateError>()));
    expect(now['target'], bodies['target'], reason: 'nothing was written');
  });
}
