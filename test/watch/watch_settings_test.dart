import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/settings/panes/watch_section.dart';
import 'package:ghost_md/watch/watch_link.dart';

import '../settings/panes/support.dart';
import 'fakes.dart';

/// Settings › Recording › Watch (docs/WATCH.md): there only where a watch has Ghost.md, saying which and what came last.
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => watchLink = null);

  testWidgets('a phone with a watch shows it, and the last voice note it sent', (tester) async {
    final host = FakeHost()
      ..said = WatchStatus(
        watches: const [(name: 'Galaxy Watch9', nearby: true)],
        lastAt: DateTime.now().millisecondsSinceEpoch,
        lastWatch: 'Galaxy Watch9',
        lastMs: 42000,
        waiting: 1,
      );
    watchLink = WatchLink(host);
    await openPane(tester, 'recording', size: const Size(390, 1800));
    await tester.pump();
    await settleSettings(tester);
    expect(cardTitles(tester).last, 'Watch');
    expect(rowLabels(tester, 'Watch'), ['Galaxy Watch9', watchClaudeLabel]);
    // No key on this device in a test: the line says how Claude is shown, with no switch to turn.
    expect(find.textContaining('then your Anthropic API key', skipOffstage: false), findsOneWidget);
    expect(find.text('Connected', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Last voice note from Galaxy Watch9 at ', skipOffstage: false), findsOneWidget);
    expect(find.textContaining(', 0:42. One is waiting to be made a note.', skipOffstage: false), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('a phone that never had a watch shows nothing new', (tester) async {
    watchLink = WatchLink(FakeHost());
    await openPane(tester, 'recording', size: const Size(390, 1800));
    await tester.pump();
    await settleSettings(tester);
    expect(cardTitles(tester), isNot(contains('Watch')));
    await endSettings(tester);
  });

  test('the footer says when, from which watch and how long', () {
    final now = DateTime(2026, 10, 20, 18, 30);
    expect(watchWhen(DateTime(2026, 10, 20, 9, 5).millisecondsSinceEpoch, now: now), '09:05');
    expect(watchWhen(DateTime(2026, 10, 18, 14, 0).millisecondsSinceEpoch, now: now), endsWith(', 14:00'));
    expect(watchLength(725000), '12:05');
    expect(watchFooter(const WatchStatus(), now: now), isNull);
    expect(watchFooter(const WatchStatus(waiting: 3), now: now), '3 are waiting to be made notes.');
    expect(watchFooter(WatchStatus(lastAt: DateTime(2026, 10, 20, 9, 5).millisecondsSinceEpoch), now: now), 'Last voice note at 09:05.');
  });
}
