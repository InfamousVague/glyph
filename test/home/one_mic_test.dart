import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shell/dock_support.dart' show dockOrder;
import '../support/render.dart';
import 'support.dart';

/// One microphone on the home dock (GHST-104; Matt, 2026-10-18: "When Claude mode is enabled there should only be
/// one microphone icon still it should just use Claude instead of the local models"): where Talk to Claude is on the
/// dock, the ink-filled Speak is not; without it, Speak is the dock's microphone as before.
void main() {
  setUpAll(loadAppFonts);

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('with Talk to Claude on the dock, Speak is left off', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, speak: true, talk: true));
    await settle(tester);
    expect(find.byKey(const ValueKey('fake-talk')), findsOneWidget);
    expect(dockOrder(tester), isNot(contains('speak')));
    expect(find.bySemanticsLabel('Speak a voice note'), findsNothing);
    expect(dockOrder(tester), containsAll(['search', 'add']));
    await away(tester);
  });

  testWidgets('without it, Speak is the microphone, as it always was', (tester) async {
    final it = seeded();
    await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, speak: true));
    await settle(tester);
    expect(dockOrder(tester), contains('speak'));
    await tester.tap(find.bySemanticsLabel('Speak a voice note'));
    await settle(tester);
    expect(it.asked.said, contains('speak'));
    await away(tester);
  });
}
