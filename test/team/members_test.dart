// A member's page (lib/team/members.dart, lib/orgs/ui/member_page.dart; docs/TEAMSPACES.md, "Members"; Matt,
// 2026-10-31: "A member's page is drawn, not stored: their tickets, the docs they own (`owner:` or verified `by:`),
// their recent edits (from versions), their colour"): what it says of someone from the organization's notes, their
// versions and the room, and the page drawing each section, a row opening its note.
import 'package:flutter/rendering.dart' show debugDisableShadows;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/versions_log.dart';
import 'package:ghost_md/home/home_organizations.dart' show OrgPresence;
import 'package:ghost_md/orgs/ui/member_page.dart';
import 'package:ghost_md/team/members.dart';

import '../support/render.dart';

Note note(String id, String body, {int? archivedAt}) => Note(id: id, body: body, createdAt: 0, updatedAt: 0, archivedAt: archivedAt);

Change change(String note, int n, {required String by, required int at}) => Change(noteId: note, n: n, at: at, by: by, added: 1, removed: 0, peek: null, first: false);

final List<Note> notes = [
  note('t1', '---\ntype: ticket\nid: GHO-1\nstatus: In progress\nassignee: sam\ndue: 2026-11-04\n---\n# Fix login\n'),
  note('t2', '---\ntype: ticket\nid: GHO-2\nstatus: To do\nassignee: "@Sam"\n---\n# Write docs\n'),
  note('t3', '---\ntype: ticket\nid: GHO-3\nstatus: Done\nassignee: sam\n---\n# Old one\n'),
  note('t4', '---\ntype: ticket\nid: GHO-4\nstatus: To do\nassignee: ana\n---\n# Not theirs\n'),
  note('t5', '---\ntype: ticket\nid: GHO-5\nstatus: To do\nassignee: sam\ndue: 2026-11-01\n---\n# Sooner\n'),
  note('d1', '---\nowner: "@sam"\n---\n# Roadmap\n'),
  note('d2', '---\nverified: {by: "@sam", until: 2026-12-01}\n---\n# Onboarding\n'),
  note('d3', '---\nowner: ana\n---\n# Pricing\n'),
  note('d4', '---\nowner: sam\n---\n# Archived plan\n', archivedAt: 5),
];

void main() {
  setUpAll(loadAppFonts);

  test('their open tickets, soonest due first; the pages they own or vouch for; their newest edit to each page', () {
    final facts = memberFacts(
      handle: 'sam',
      notes: notes,
      changes: [change('d1', 1, by: 'sam', at: 100), change('d1', 2, by: 'sam', at: 300), change('d3', 4, by: 'Sam', at: 200), change('d3', 5, by: 'ana', at: 400), change('gone', 1, by: 'sam', at: 900)],
      seen: const [OrgPresence(client: '1', handle: 'Sam', editingNote: 'd1', editingTitle: 'Roadmap'), OrgPresence(client: '2', handle: 'sam', ai: true)],
    );
    expect([for (final t in facts.tickets) t.ticket.id], ['GHO-5', 'GHO-1', 'GHO-2'], reason: 'done and someone else’s left out; the soonest due first, no day last');
    expect([for (final n in facts.owned) n.id], ['d2', 'd1'], reason: 'by title, Onboarding before Roadmap; the archived left out');
    expect([for (final e in facts.edits) '${e.change.noteId}:${e.change.n}'], ['d1:2', 'd3:4'], reason: 'one line a page, newest first; a page not here left out');
    expect(facts.online, isTrue);
    expect(facts.editing, 'Roadmap');
    final away = memberFacts(handle: 'ana', notes: notes, seen: const [OrgPresence(client: '2', handle: 'ana', ai: true)]);
    expect(away.online, isFalse, reason: 'an AI under their name is not them');
    expect([for (final n in away.owned) n.id], ['d3']);
  });

  testWidgets('the page draws their name, whether they are here, and each section; a row opens its note', (tester) async {
    final opened = <String>[];
    var back = 0;
    await pumpApp(
      tester,
      home: MemberPage(
        services: null,
        orgId: 'o1',
        handle: 'sam',
        notes: notes,
        seen: const [OrgPresence(client: '1', handle: 'sam', editingNote: 'd1', editingTitle: 'Roadmap')],
        onBack: () => back += 1,
        onOpenNote: opened.add,
        wisp: false,
      ),
    );
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const ValueKey('member-page-name'))).data, 'sam');
    expect(find.text('Here now, editing Roadmap'), findsOneWidget);
    for (final key in [MemberPage.ticketsKey, MemberPage.ownedKey, MemberPage.editsKey]) {
      expect(find.byKey(key), findsOneWidget);
    }
    // With no services the organization's workspace is unknown, so nothing is the organization's: the sections say so.
    expect(find.byKey(MemberPage.rowKey('ticket', 't1')), findsNothing);
    await tester.tap(find.byKey(MemberPage.statusKey));
    expect(opened, ['d1'], reason: 'the page they are editing, from where they are');
    await tester.tap(find.byKey(MemberPage.backKey));
    expect(back, 1);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
