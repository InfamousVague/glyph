// The pictures of a ticket's team parts (Matt, 2026-10-31), into build/feature-shots/tickets-team/: a ticket's panel
// with its watchers, its history and its possible duplicates; Show all; simple mode's More; the Merge into… sheet; a
// closed duplicate; and Add sub-ticket's hints. On a phone and on a Mac's width, light and dark. Written only under
// --update-goldens.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/book/ticket_history.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/editor/queries/query_look.dart';
import 'package:ghost_md/editor/tickets/tickets.dart';
import 'package:glacier/glacier.dart';

import '../../support/feature_shot.dart';
import '../../support/render.dart';
import 'support.dart';

const TicketChoice loop = TicketChoice(key: 'GHO-1', title: 'Login loops after signing in', status: 'In progress', category: StatusCategory.doing);
const TicketChoice old = TicketChoice(key: 'GHO-4', title: 'Login loops forever', status: 'Done', category: StatusCategory.done);
const TicketChoice docs = TicketChoice(key: 'GHO-14', title: 'Write the docs', status: 'To do', category: StatusCategory.todo);

const int hour = 3600000;
const int now = 100 * hour;

const List<TicketChange> changes = [
  TicketChange(at: 30 * hour, by: 'matt', key: 'type', from: null, to: 'ticket'),
  TicketChange(at: 31 * hour, by: 'matt', key: 'assignee', from: null, to: 'sam'),
  TicketChange(at: 80 * hour, by: 'sam', key: 'status', from: 'To do', to: 'In progress'),
  TicketChange(at: 97 * hour, by: 'sam', key: 'due', from: null, to: '2026-11-06'),
  TicketChange(at: 98 * hour, by: 'sam', key: 'status', from: 'In progress', to: 'In review'),
  TicketChange(at: 99 * hour + 30 * 60000, by: 'ana', key: 'labels', from: 'auth', to: 'auth, safari'),
];

TicketOptions options({bool simple = false, bool closed = false}) => TicketOptions(
  statuses: () => defaultStatuses,
  people: () => const ['sam'],
  choices: () => const [loop, old, docs],
  find: (target) => const [loop, old, docs].where((choice) => choice.key == target.toUpperCase()).firstOrNull,
  open: (_) {},
  addSubTicket: (_) {},
  follow: TicketFollow(
    me: () => 'matt',
    history: () async => changes,
    duplicates: () => closed ? const [] : const [(ticket: loop, shared: ['login', 'loop']), (ticket: old, shared: ['login', 'loop'])],
    similar: (title) => const [(ticket: loop, shared: ['login'])],
    merge: (_) {},
    undoMerge: () => closed ? () {} : null,
    simple: () => simple,
    now: () => now,
  ),
);

const String front = '---\ntype: ticket\nid: GHO-12\nstatus: In review\nassignee: sam\npriority: high\ndue: 2026-11-06\nlabels: [auth, safari]\nwatchers: ["@matt", "@sam", "@ana"]\n---';

Future<void> draw(WidgetTester tester, {required Size size, required String shade, required double width, String front = front, TicketOptions? given}) => pumpApp(
  tester,
  size: size,
  prefs: AppPreferences(theme: shade),
  home: Builder(
    builder: (context) => BackScope(
      child: ColoredBox(
        color: context.tokens.color('glacier-bg'),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 40),
              child: TicketPanel(look: QueryLook.of(context, null), front: front, options: given ?? options(), editable: true, today: '2026-10-31', locale: 'en-GB', write: (_, _) {}, openLines: () {}),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadAppFonts);

  for (final shade in ['light', 'dark']) {
    for (final (where, size) in [('phone', const Size(390, 900)), ('mac', const Size(1280, 900))]) {
      final width = where == 'phone' ? 390.0 : 720.0;

      testWidgets('a ticket’s watchers, history and possible duplicates, $where, $shade', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        await draw(tester, size: size, shade: shade, width: width);
        await settle(tester);
        await featureShot(tester, 'tickets-team', 'panel-$where-$shade');
        await tester.tap(find.byKey(const ValueKey('ticket-history-all')));
        await settle(tester);
        await featureShot(tester, 'tickets-team', 'history-all-$where-$shade');
        await tester.tap(find.byKey(const ValueKey('ticket-merge-into')));
        await settle(tester);
        await featureShot(tester, 'tickets-team', 'merge-into-$where-$shade');
        debugDisableShadows = true;
      });

      testWidgets('simple mode’s More, a closed duplicate, and Add sub-ticket’s hints, $where, $shade', (tester) async {
        if (!autoUpdateGoldenFiles) return;
        await draw(tester, size: size, shade: shade, width: width, given: options(simple: true));
        await settle(tester);
        await featureShot(tester, 'tickets-team', 'simple-$where-$shade');
        await draw(tester, size: size, shade: shade, width: width, front: '---\ntype: ticket\nid: GHO-12\nstatus: Duplicate\nduplicate-of: "[[GHO-1]]"\nwatchers: ["@matt"]\n---', given: options(closed: true));
        await settle(tester);
        await featureShot(tester, 'tickets-team', 'closed-duplicate-$where-$shade');
        await draw(tester, size: size, shade: shade, width: width);
        await settle(tester);
        await tester.tap(said('Add sub-ticket'));
        await settle(tester);
        await tester.enterText(find.byType(EditableText).last, 'Login breaks on Safari');
        await settle(tester);
        await featureShot(tester, 'tickets-team', 'sub-ticket-hints-$where-$shade');
        debugDisableShadows = true;
      });
    }
  }
}
