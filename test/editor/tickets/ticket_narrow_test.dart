// A ticket's panel in less room than its words want (lib/editor/tickets/ticket_panel.dart): on the page the panel is
// as narrow as its narrowest content and no narrower, and a pane narrower than that cuts it. Its rows give way as
// the page's do: a value's words are cut with an ellipsis, a day's cross keeps its size, and nothing is drawn over
// an edge.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/editor/queries/query_look.dart';
import 'package:ghost_md/editor/tickets/tickets.dart';
import 'package:glacier/glacier.dart';

import '../../support/render.dart';
import 'support.dart';

/// The names of the rows, in order.
List<String> names(WidgetTester tester) => <String>[for (var index = 0; index < parts('name').evaluate().length; index += 1) wordsOf(tester, parts('name').at(index)).trim()];

const TicketChoice loop = TicketChoice(key: 'EX-2', title: 'Fix the sign-in loop', status: 'In progress', category: StatusCategory.doing);

/// The example project's third ticket, as the app writes it, with every property it can have.
const String every = '---\ntype: ticket\nid: EX-3\nstatus: To do\nassignee: Priya Shah\npriority: medium\ndue: 2026-10-16\nstart: 2026-10-12\nestimate: 3\nblocked-by: "[[EX-2]]"\nparent: "[[EX-2]]"\nlabels: [words, welcome]\n---';
const String third = '---\ntype: ticket\nid: EX-3\nstatus: To do\npriority: medium\ndue: 2026-10-16\nblocked-by: "[[EX-2]]"\n---';

Future<List<String>> draw(WidgetTester tester, String front, double width, {double ratio = 2.625, bool more = true}) async {
  final errors = <String>[];
  final was = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.toString().split('\n').take(12).join('\n'));
  await pumpApp(
    tester,
    size: const Size(704, 933),
    ratio: ratio,
    home: Builder(
      builder: (context) => BackScope(
        child: ColoredBox(
          color: context.tokens.color('glacier-bg'),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: TicketPanel(
                look: QueryLook.of(context, null),
                front: front,
                options: optionsWith(const <TicketChoice>[loop]),
                editable: true,
                today: '2026-10-09',
                locale: 'en-US',
                write: (key, value) {},
                openLines: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  debugDisableShadows = true;
  await tester.pump();
  if (more && parts('more').evaluate().isNotEmpty) {
    await tester.tap(parts('more'), warnIfMissed: false);
    await tester.pump();
  }
  await tester.pump();
  FlutterError.onError = was;
  return errors;
}

void main() {
  setUpAll(loadAppFonts);

  const first = '---\ntype: ticket\nid: EX-1\nstatus: Done\nassignee: Alex\npriority: high\n---';
  const second = '---\ntype: ticket\nid: EX-2\nstatus: In progress\nassignee: Sam\npriority: highest\ndue: 2026-10-11\n---';
  const long = '---\ntype: ticket\nid: EX-3\nstatus: Waiting for the review\nassignee: Bartholomew Montgomery-Smythe\npriority: highest\ndue: 2026-12-30\nstart: 2026-11-25\nestimate: 13.5\nblocked-by: [EX-2, "[[A ticket with a long title of its own]]", EX-2]\nparent: "[[A ticket with a long title of its own]]"\nlabels: [words, welcome, onboarding, design, copy]\nsprint: 12\nteam: growth\n---';
  for (final (name, front) in const [('first', first), ('second', second), ('third', third), ('long', long)]) {
    for (final width in const <double>[300.0, 280, 260]) {
      for (final more in const [false, true]) {
        testWidgets('the $name ticket in $width px${more ? ', every row shown' : ''}', (tester) async {
          final errors = await draw(tester, front, width, more: more);
          expect(errors, isEmpty);
        });
      }
    }
  }

  testWidgets('in the Fold’s narrowest pane the panel is as wide as the page’s, cut by the pane, and its rows give way as the page’s do', (tester) async {
    // The page, in the Tauri app on an emulator at the Fold's unfolded size (a window of 704 x 933 at 2.625), the
    // sidebar and the aside docked and the note 164px between them, the Example project's third ticket with its
    // every row shown, 2026-10-09: `getBoundingClientRect`, less the pane's left edge (300).
    final errors = await draw(tester, third, 164);
    expect(errors, isEmpty);
    Rect of(String part, [int index = 0]) => tester.getRect(parts(part).at(index));
    void near(double here, double page, String what, [double within = 0.6]) => expect(here, closeTo(page, within), reason: '$what: page $page, here ${here.toStringAsFixed(2)}');
    final panel = of('panel');
    near(panel.left, 23.73, 'the panel’s left');
    near(panel.width, 196.15, 'the panel’s width');
    // What it waits on holds it that wide: the key at a letter, the title whole.
    near(of('waiting').width, 156.65, 'the waiting box');
    near(of('waiting').height, 71.64, 'the waiting box’s height', 1.2);
    near(of('waitOn').width, 137.67, 'the ticket it waits on');
    near(of('waitOn').height, 38.27, 'its two lines, EX- over 2', 1.2);
    // The names' column, and what is left for the values.
    near(of('name').width, 75.18, 'the names’ column');
    near(of('value').left, 132.90, 'the values’ column');
    near(of('value').width, 67.23, 'the values’ width');
    near(of('value').height, 30.76, 'a row');
    // A day gives way to its cross, which keeps its size at the column's end.
    final due = names(tester).indexOf('Due');
    final day = find.descendant(of: parts('value').at(due), matching: parts('chip'));
    final cross = find.descendant(of: parts('value').at(due), matching: parts('clear'));
    near(tester.getRect(day).left, 123.41, 'the day’s chip, stepped out');
    near(tester.getRect(day).width, 50.49, 'the day’s chip');
    near(tester.getRect(cross).left, 178.60, 'the cross');
    near(tester.getRect(cross).width, 21.49, 'the cross’s size');
    // A ticket it is blocked by keeps three ems beside it for its pencil; the pencil and Add keep their sizes.
    near(of('link').width, 26.22, 'the link');
    near(of('edit').width, 31.99, 'the pencil');
    near(of('edit', 1).width, 62.90, 'Add');
    // And the pane cuts it: nothing of the panel is laid out narrower than the page lays it.
    expect(tester.getSize(find.byType(TicketPanel)).width, 164);
  });

  for (final width in const <double>[390, 300, 243.62, 164, 120]) {
    testWidgets('a ticket with every field is drawn in $width px with nothing over an edge', (tester) async {
      final errors = await draw(tester, every, width);
      expect(errors, isEmpty);
      for (final name in const ['Status', 'Assignee', 'Priority', 'Due', 'Start', 'Estimate', 'Blocked by', 'Parent', 'Labels']) {
        expect(find.text(name), findsOneWidget);
      }
    });
  }
}
