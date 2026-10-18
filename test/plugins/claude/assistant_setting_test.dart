// Phone assistant on the Claude plugin's page (lib/plugins/claude/claude_in_app.dart). Matt, 2026-10-17: "add the
// setting back in to be able to bind ghost as the agent on the phone". Its switch is the Developer page's (one flag,
// lib/core/wip.dart); on, Android's Default digital assistant app screen is opened, since the app cannot pick itself.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/plugins/claude/claude.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';

import '../../settings/support.dart';

void main() {
  late ValueNotifier<bool> on;
  late List<bool> switched;
  late int chooses;
  late bool chosen;

  setUp(() {
    on = ValueNotifier<bool>(false);
    switched = [];
    chooses = 0;
    chosen = false;
  });
  tearDown(() => on.dispose());

  PhoneAssistantSeam seam() => PhoneAssistantSeam(
        on: on,
        set: (next) async {
          switched.add(next);
          on.value = next;
        },
        choose: () async {
          chooses += 1;
          return true;
        },
        chosen: () async => chosen,
      );

  Future<void> page(WidgetTester tester, {required bool phone}) => pumpSettings(
        tester,
        SingleChildScrollView(child: ClaudeInApp(settings: ClaudeSettings(MemorySecureStore()), assistant: seam(), phone: phone)),
        size: const Size(390, 3000),
      );

  GlacierSwitch assistantSwitch(WidgetTester tester) =>
      tester.widget<GlacierSwitch>(find.descendant(of: find.byKey(const ValueKey('claude-assistant')), matching: find.byType(GlacierSwitch)));

  testWidgets('is a card of its own on a phone, and nowhere else', (tester) async {
    await page(tester, phone: false);
    expect(find.byWidgetPredicate((w) => w is PaneSection && w.title == 'Phone assistant'), findsNothing);
    await endSettings(tester);

    await page(tester, phone: true);
    expect(find.byWidgetPredicate((w) => w is PaneSection && w.title == 'Phone assistant'), findsOneWidget);
    expect(find.text('Ghost.md as the phone’s assistant'), findsOneWidget);
    expect(find.textContaining('cannot make itself the assistant'), findsOneWidget);
    expect(assistantSwitch(tester).checked, isFalse);
    // Off, there is nothing to choose yet.
    expect(find.byKey(const ValueKey('claude-assistant-choose')), findsNothing);
    await endSettings(tester);
  });

  testWidgets('switched on, offers Ghost.md as the assistant and opens Android’s screen to pick it, then says whether it was', (tester) async {
    await page(tester, phone: true);
    assistantSwitch(tester).onCheckedChange!(true);
    await tester.pump();
    await tester.pump();
    expect(switched, [true]);
    expect(chooses, 1);
    expect(find.byKey(const ValueKey('claude-assistant-choose')), findsOneWidget);
    expect(find.text('Not chosen yet. Pick Ghost.md on Android’s screen.'), findsOneWidget);
    // The row opens the screen again.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('claude-assistant-choose')), matching: find.text('Choose')));
    await tester.pump();
    expect(chooses, 2);
    await endSettings(tester);

    // Picked there: the page says so, and switching it on again asks for no screen.
    chosen = true;
    await page(tester, phone: true);
    await tester.pump();
    expect(find.text('Ghost.md is your phone’s assistant.'), findsOneWidget);
    assistantSwitch(tester).onCheckedChange!(false);
    await tester.pump();
    expect(switched, [true, false]);
    expect(find.byKey(const ValueKey('claude-assistant-choose')), findsNothing);
    await endSettings(tester);
  });
}
