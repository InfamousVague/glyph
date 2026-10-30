// The bell's Mentions filter (lib/notes/notifications_drawer.dart; Matt, 2026-10-30: "add all 12"): there once someone
// has mentioned you, showing only those rows when it is on; a mention's row says who and where, and opens the note at
// the line that names you. With pictures, on a phone and a desktop, light and dark, into
// build/feature-shots/mentions-verified/ under --update-goldens.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/notes/notifications_drawer.dart';

import '../support/feature_shot.dart';
import '../support/render.dart';
import 'support.dart';

const NotificationOrg ghost = (id: 'o1', name: 'Ghost');
const int now = 1790000000000;

final List<FeedNotification> rows = [
  const FeedNotification(id: 'm1', rev: 9, kind: 'mention', at: now - 4 * 60000, from: 'sam', org: ghost, body: {'name': 'Ghost', 'generation': 1}, blob: 'sealed'),
  const FeedNotification(id: 'j1', rev: 8, kind: 'member-joined', at: now - 3600000, from: 'ana', org: ghost, body: {'name': 'Ghost'}),
  const FeedNotification(id: 'e1', rev: 7, kind: 'note-edited', at: now - 7200000, blob: 'sealed'),
  const FeedNotification(id: 'x1', rev: 6, kind: 'page-expired', at: now - 9000000, blob: 'sealed'),
];

NotificationDetails? opened(FeedNotification n) => switch (n.id) {
      'm1' => NotificationDetails.fromJson({'kind': 'mention', 'noteId': 'n1', 'title': 'Launch plan', 'by': 'sam', 'first': 'Ask @matt to check the copy by @2026-11-06', 'at': 'line:3'}),
      'e1' => NotificationDetails.fromJson({'kind': 'note-edited', 'noteId': 'n2', 'title': 'Pricing', 'by': 'Claude', 'added': 2, 'removed': 0, 'first': '- Annual plan', 'at': 'l4'}),
      'x1' => NotificationDetails.fromJson({'kind': 'page-expired', 'noteId': 'n3', 'title': 'Onboarding guide'}),
      _ => null,
    };

void main() {
  setUpAll(loadAppFonts);

  Future<List<String>> show(WidgetTester tester, List<FeedNotification> list, {Size size = const Size(390, 844), String theme = 'light'}) async {
    final said = <String>[];
    await pumpPage(
      tester,
      PageUnder(
        children: [
          NotificationsDrawer(
            notifications: list,
            memberOf: const {'o1'},
            detailsOf: opened,
            now: now,
            onClose: () => said.add('close'),
            onOpenNote: (id, at) => said.add('note $id${at == null ? '' : ' at $at'}'),
            onOpenOrganization: (id) => said.add('org $id'),
            onAccount: () {},
            onMarkRead: (id) => said.add('read $id'),
          ),
        ],
      ),
      size: size,
      theme: theme,
    );
    await tester.pump(const Duration(milliseconds: 400));
    return said;
  }

  Finder rowOf(String id) => find.byKey(ValueKey('notification-$id'));

  testWidgets('a mention reads who and where; the filter shows only mentions; the row opens the note at its line', (tester) async {
    final said = await show(tester, rows);
    expect(find.text('sam mentioned you in Launch plan'), findsOneWidget);
    expect(find.text('Ask @matt to check the copy by @2026-11-06'), findsOneWidget);
    expect(find.text('Onboarding guide needs review: its verification ran out'), findsOneWidget);
    for (final id in ['m1', 'j1', 'e1', 'x1']) {
      expect(rowOf(id), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('filter-mentions')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(rowOf('m1'), findsOneWidget);
    for (final id in ['j1', 'e1', 'x1']) {
      expect(rowOf(id), findsNothing);
    }
    await tester.tap(find.byKey(const ValueKey('filter-all')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(rowOf('j1'), findsOneWidget);
    await tester.tap(rowOf('m1'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(said, containsAllInOrder(['read m1', 'close', 'note n1 at line:3']));
    await away(tester);
  });

  testWidgets('no filter while nobody has mentioned you', (tester) async {
    await show(tester, rows.where((n) => n.kind != 'mention').toList());
    expect(find.byKey(const ValueKey('filter-mentions')), findsNothing);
    await away(tester);
  });

  for (final theme in ['light', 'dark']) {
    for (final (size, where) in [(const Size(390, 844), 'phone'), (const Size(1280, 800), 'desktop')]) {
      testWidgets('the bell with a mention, its filter on, $where, $theme', (tester) async {
        await show(tester, rows, size: size, theme: theme);
        await featureShot(tester, 'mentions-verified', 'bell-all-$where-$theme');
        await tester.tap(find.byKey(const ValueKey('filter-mentions')));
        await tester.pump(const Duration(milliseconds: 300));
        await featureShot(tester, 'mentions-verified', 'bell-mentions-$where-$theme');
        expect(rowOf('j1'), findsNothing);
        await away(tester);
      });
    }
  }
}
