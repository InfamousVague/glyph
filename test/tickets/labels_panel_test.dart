import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/properties.dart' show defaultStatuses;
import 'package:ghost_md/editor/tickets/ticket_panel.dart' show TicketOptions;
import 'package:ghost_md/tickets/ui/label_chips.dart';

import '../editor/tickets/support.dart' as panel;
import '../support/render.dart';

/// A ticket's labels in its panel (lib/editor/tickets/ticket_panel.dart): chips in their notebook's colours, the
/// label picker that makes one as it is typed and keeps a colour in the notebook, and its component's own row.
const String doc = '---\ntype: ticket\nid: WAIT-1\nstatus: To do\nlabels: [bug, email]\ncomponent: Waitlist\n---\n# Invite emails bounce\n\nThe welcome mail is refused.\n';

void main() {
  setUpAll(loadAppFonts);

  TicketOptions options({List<(String, String?)>? coloured}) => TicketOptions(
    statuses: () => defaultStatuses,
    people: () => const ['Matt', 'Sam'],
    choices: () => const <TicketChoice>[],
    find: (_) => null,
    open: (_) {},
    labels: () => const ['bug', 'ui', 'email', 'signup'],
    labelColours: () => const {'bug': 'amber'},
    setLabelColour: coloured == null ? null : (label, hue) => coloured.add((label, hue)),
  );

  testWidgets('draws its labels as chips in the notebook’s colours, and its component as a row', (tester) async {
    await panel.pumpTickets(tester, doc, options: options());
    final bug = tester.widget<LabelChip>(find.byWidgetPredicate((widget) => widget is LabelChip && widget.label == 'bug'));
    expect(bug.hue, 'amber');
    final email = tester.widget<LabelChip>(find.byWidgetPredicate((widget) => widget is LabelChip && widget.label == 'email'));
    expect(email.hue, isNot('amber'));
    expect(find.text('Component'), findsOneWidget);
    expect(find.text('Waitlist'), findsOneWidget);
  });

  testWidgets('its picker gives a label, makes a new one as it is typed, and keeps a colour in the notebook', (tester) async {
    final coloured = <(String, String?)>[];
    final view = await panel.pumpTickets(tester, doc, options: options(coloured: coloured));
    await tester.tap(panel.said('Change labels'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('label:ui')));
    await tester.pumpAndSettle();
    expect(view.state.doc.toString(), contains('labels: [bug, email, ui]'));
    await tester.enterText(find.byType(EditableText).first, 'Needs design');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('label-make')));
    await tester.pumpAndSettle();
    expect(view.state.doc.toString(), contains('labels: [bug, email, ui, Needs design]'));
    await tester.tap(find.byKey(const ValueKey('label-colours')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('label-colour:email')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('label-hue:teal')));
    await tester.pumpAndSettle();
    expect(coloured, [('email', 'teal')]);
  });
}
