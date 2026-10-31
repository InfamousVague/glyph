// A ticket's work in its panel (lib/editor/tickets/ticket_work.dart; Matt, 2026-10-31): its time with Start, Stop and
// Add time…, a long timer's question, and its pull requests as chips with their state and checks. On a phone and a
// desktop, light and dark, with pictures into build/feature-shots/tickets-automation/ under --update-goldens.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/summary_handoff.dart' show SummaryDevice;
import 'package:ghost_md/book/timers.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;
import 'package:ghost_md/editor/tickets/ticket_work.dart';
import 'package:ghost_md/editor/tickets/tickets.dart';
import 'package:ghost_md/plugins/github/pull_links.dart';

import '../../support/feature_shot.dart';
import '../../support/render.dart' show loadAppFonts;
import 'support.dart';

const String doc = '---\ntype: ticket\nid: HT-12\nstatus: In progress\nassignee: Sam\nspent: 3h 20m\n---\n# Fix the login\n\nThe form forgets the email.\n';
const int t0 = 1790000000000;

final List<LinkedPull> pulls = [
  const LinkedPull(pull: PullRecord(repo: 'ghost/app', number: 41, title: 'HT-12: keep the email', state: PullState.merged, url: 'https://github.com/ghost/app/pull/41'), via: PullVia.title),
  const LinkedPull(pull: PullRecord(repo: 'ghost/app', number: 43, title: 'Login copy', state: PullState.open, url: 'https://github.com/ghost/app/pull/43'), via: PullVia.branch, checks: PullChecks.failing),
  const LinkedPull(pull: PullRecord(repo: 'ghost/app', number: 42, title: 'Tidy the form', state: PullState.draft), via: PullVia.body, checks: PullChecks.pending),
];

void main() {
  setUpAll(loadAppFonts);

  late ValueNotifier<Preferences> prefs;
  late List<int> clock;
  late Map<String, String> written;
  late TicketTimers timers;
  late List<String> opened;

  setUp(() {
    final kept = MemoryStored();
    useActivity(Activity(clock: () => DateTime.fromMillisecondsSinceEpoch(clock[0]), store: () => kept));
    prefs = ValueNotifier<Preferences>(const Preferences());
    clock = [t0];
    written = {'n12': doc};
    opened = [];
    timers = TicketTimers(
      device: () => const SummaryDevice(id: 'mac', name: 'Mac'),
      preferences: () => prefs.value,
      setPreferences: (change) => prefs.value = change(prefs.value),
      prefsChanged: prefs,
      write: (noteId, change) async => written[noteId] = change(written[noteId]!),
      who: () => 'Matt',
      clock: () => clock[0],
    );
    addTearDown(timers.dispose);
  });

  TicketOptions options({bool withPulls = true}) {
    final base = optionsWith(const []);
    return TicketOptions(
      statuses: base.statuses,
      people: base.people,
      choices: base.choices,
      find: base.find,
      open: base.open,
      work: TicketWorkOptions(noteId: 'n12', title: 'Fix the login', ticketKey: 'HT-12', timers: timers, pulls: withPulls ? () => pulls : null, openUrl: opened.add, today: () => '2026-10-31'),
    );
  }

  testWidgets('time spent, Start, the time so far with Stop, and the line logged', (tester) async {
    await pumpTickets(tester, doc, options: options(withPulls: false));
    expect(find.text('3h 20m'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ticket-timer-start')));
    await tester.pump();
    expect(timers.mine!.named, 'HT-12');
    clock[0] = t0 + 25 * 60000;
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('25m'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ticket-timer-stop')));
    await tester.pump();
    await tester.pump();
    expect(timers.mine, isNull);
    expect(written['n12'], contains('spent: 3h 45m'));
    expect(written['n12'], endsWith('- 2026-09-21 · 25m · Matt\n'));
    await away(tester);
  });

  testWidgets('a timer running on another device says so, and Stop there logs it', (tester) async {
    prefs.value = prefs.value.copyWith(more: {ticketTimersKey: {'phone': {'note': 'n12', 'title': 'Fix the login', 'key': 'HT-12', 'start': t0 - 10 * 60000, 'who': 'Matt', 'name': 'phone'}}});
    await pumpTickets(tester, doc, options: options(withPulls: false));
    expect(find.text('10m on your phone'), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-timer-start')), findsNothing, reason: 'one runs on it already');
    await tester.tap(find.byKey(const ValueKey('ticket-timer-stop')));
    await tester.pump();
    expect(timers.all, isEmpty);
    expect(written['n12'], contains('spent: 3h 30m'));
    await away(tester);
  });

  testWidgets('Add time… logs what is typed, on the day typed', (tester) async {
    await pumpTickets(tester, doc, options: options(withPulls: false));
    await tester.tap(find.byKey(const ValueKey('ticket-add-time')));
    await settle(tester);
    expect(find.text('Add time to HT-12'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('add-time-time')), matching: find.byType(EditableText)), '1h 30m');
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('add-time-day')), matching: find.byType(EditableText)), '2026-10-29');
    await tester.pump();
    expect(find.text('Logs 1h 30m under Time, and adds it to the ticket’s spent.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-time-add')));
    await settle(tester);
    expect(written['n12'], contains('spent: 4h 50m'));
    expect(written['n12'], endsWith('- 2026-10-29 · 1h 30m · Matt\n'));
    await away(tester);
  });

  testWidgets('a timer of more than ten hours asks before it is logged', (tester) async {
    await pumpTickets(tester, doc, options: options(withPulls: false));
    await tester.tap(find.byKey(const ValueKey('ticket-timer-start')));
    await tester.pump();
    clock[0] = t0 + 11 * 3600000;
    await tester.pump(const Duration(seconds: 31));
    await tester.tap(find.byKey(const ValueKey('ticket-timer-stop')));
    await settle(tester);
    expect(find.text('The timer on HT-12 ran 11h'), findsOneWidget);
    await featureShot(tester, 'tickets-automation', 'long-timer-phone-light');
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('long-timer-some')), matching: find.byType(EditableText)), '2h');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('long-timer-typed')));
    await settle(tester);
    expect(written['n12'], contains('spent: 5h 20m'));
    await away(tester);
  });

  testWidgets('the pull requests: each its number, state and checks, opening its page', (tester) async {
    await pumpTickets(tester, doc, options: options());
    expect(find.text('PRs'), findsOneWidget);
    expect(find.text('#41 Merged'), findsOneWidget);
    expect(find.text('#43 Open'), findsOneWidget);
    expect(find.text('#42 Draft'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('pull request 43, Open, Checks failed')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ticket-pull-41')));
    expect(opened, ['https://github.com/ghost/app/pull/41']);
    await tester.tap(find.byKey(const ValueKey('ticket-pull-42')));
    expect(opened, hasLength(1), reason: 'no address to open');
    await away(tester);
  });

  testWidgets('read only: the time is read, nothing started or added', (tester) async {
    await pumpTickets(tester, doc, options: options(), readOnly: true);
    expect(find.text('3h 20m'), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-timer-start')), findsNothing);
    expect(find.byKey(const ValueKey('ticket-add-time')), findsNothing);
    await away(tester);
  });

  for (final theme in ['light', 'dark']) {
    for (final (screen, where) in [(390.0, 'phone'), (1024.0, 'desktop')]) {
      testWidgets('the panel with its time running and its pull requests, $where, $theme', (tester) async {
        await timers.start('n12', title: 'Fix the login', key: 'HT-12');
        clock[0] = t0 + 72 * 60000;
        await pumpTickets(tester, doc, options: options(), theme: theme, screen: screen);
        await tester.pump(const Duration(seconds: 31));
        expect(find.text('1h 12m'), findsOneWidget);
        await featureShot(tester, 'tickets-automation', 'panel-$where-$theme');
        await tester.tap(find.byKey(const ValueKey('ticket-add-time')));
        await settle(tester);
        await featureShot(tester, 'tickets-automation', 'add-time-$where-$theme');
        // The timer let go, so nothing is left ticking.
        prefs.value = const Preferences();
        await away(tester);
      });
    }
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
