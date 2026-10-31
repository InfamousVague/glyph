import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/properties.dart' show StatusCategory, ticketOf;
import 'package:ghost_md/core/query/query.dart';
import 'package:ghost_md/tickets/labels.dart';
import 'package:ghost_md/tickets/ui/tickets_screen.dart';

import '../support/render.dart';
import 'support.dart';

/// A library a test's tickets page writes into: each note's words as they are now, and what was opened.
class Desk {
  Desk([List<QueryNote>? from]) : bodies = {for (final each in from ?? notes) each.id: each.body}, _created = {for (final each in from ?? notes) each.id: each.createdAt};

  final Map<String, String> bodies;
  final Map<String, int> _created;
  final List<String> opened = [];
  final List<String> writes = [];

  QueryLibrary get library => libraryOf([for (final MapEntry(:key, :value) in bodies.entries) QueryNote(id: key, body: value, createdAt: _created[key]!, updatedAt: noon('2026-10-20'))]);

  Future<void> write(String id, String? Function(String body) change) async {
    final now = bodies[id];
    if (now == null) return;
    final next = change(now);
    if (next == null || next == now) return;
    bodies[id] = next;
    writes.add(id);
  }

  List<TicketChoice> choices() => [
    for (final MapEntry(:key, :value) in bodies.entries)
      if (ticketOf(value) case final ticket?) TicketChoice(key: ticket.id, title: value.split('\n').firstWhere((line) => line.startsWith('# '), orElse: () => '# $key').substring(2), status: ticket.status, category: ticket.category),
  ];
}

/// The tickets page on its own over the app's theme, at [size], drawn again after every write as the root's is.
Future<void> pumpTickets(WidgetTester tester, Desk desk, {TicketsPage page = TicketsPage.mine, Size size = const Size(390, 844), String theme = 'light', bool simple = false, bool shadows = false}) async {
  var shown = page;
  await pumpApp(
    tester,
    size: size,
    prefs: AppPreferences(theme: theme),
    home: BackScope(
      child: StatefulBuilder(
        builder: (context, setState) => TicketsScreen(
          page: shown,
          library: desk.library,
          today: today,
          onPage: (next) => setState(() => shown = next),
          onBack: () {},
          onOpen: desk.opened.add,
          write: (id, change) async {
            await desk.write(id, change);
            setState(() {});
          },
          teamOf: teamOf,
          coloursOf: (id) => labelColoursOf(id.startsWith('wait') ? desk.bodies['waitlist'] : null),
          people: () => const ['Matt', 'Sam', 'Alex'],
          labels: () => labelsIn(desk.bodies.values),
          choices: desk.choices,
          simple: simple,
        ),
      ),
    ),
  );
  // Shadows drawn only for a picture, which puts the binding's switch back itself.
  if (!shadows) debugDisableShadows = true;
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Whether a ticket's words say it is done.
bool isDone(String body) => ticketOf(body)?.category == StatusCategory.done;
