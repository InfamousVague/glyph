// Settings › Notifications › Reminders (lib/settings/panes/reminders_section.dart): drawn first where the phone
// reminds, signed in or not; its switch, its time on the phone's own clock and the day before kept on this device;
// and what Android is keeping from them, with the way to allow it. Against a stand-in for the phone.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/reminders/reminder_settings.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/notifications_pane.dart';
import 'package:glacier/glacier.dart';

import '../../support/fake_reminders.dart';
import '../support.dart';

List<String> titles(WidgetTester tester) => [for (final section in tester.widgetList<PaneSection>(find.byType(PaneSection, skipOffstage: false))) section.title ?? ''];

String? hintOf(WidgetTester tester, String label) {
  final hint = tester.widget<SettingRow>(find.byWidgetPredicate((w) => w is SettingRow && w.label == label, skipOffstage: false)).hint;
  return hint is Text ? hint.data : null;
}

GlacierSwitch switchOf(WidgetTester tester, String label) => tester.widget<GlacierSwitch>(find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == label, skipOffstage: false));

void main() {
  setUpAll(loadAppFonts);

  late FakeReminders host;
  late MemoryStored kept;

  setUp(() {
    host = FakeReminders();
    kept = MemoryStored();
    useStored(kept);
    forgetReminderSettings();
  });

  tearDown(forgetReminderSettings);

  Future<void> open(WidgetTester tester, {Preferences prefs = const Preferences(theme: 'light'), Size? size}) async {
    await pumpSettings(tester, SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: NotificationsPane(reminders: host))), prefs: prefs, size: size ?? phone);
  }

  testWidgets('is not drawn where the phone does not remind', (tester) async {
    await pumpSettings(tester, const SingleChildScrollView(child: Padding(padding: EdgeInsets.all(16), child: NotificationsPane(signedIn: true))));
    expect(titles(tester), ['What reaches you']);
    expect(find.text('Remind me'), findsNothing);
    await endSettings(tester);
  });

  testWidgets('is drawn first, signed in or not, in its own words', (tester) async {
    await open(tester);
    expect(titles(tester), ['Reminders', 'What reaches you']);
    expect(hintOf(tester, 'Remind me'), 'To-dos and tickets with a due date, and any line with a time set.');
    expect(find.text('9:00'), findsOneWidget);
    expect(find.text('A to-do with a due date reminds you at 9:00 on the day. Hold a to-do and choose Remind me for a time of its own.'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('the switch, the time and the day before are this device’s, and kept', (tester) async {
    await open(tester);
    switchOf(tester, 'The day before').onCheckedChange!(true);
    await tester.pump();
    host.picks = (hour: 7, minute: 30);
    await tester.tap(find.text('9:00'));
    await tester.pump();
    await tester.pump();
    expect(host.pickedFrom, [(9, 0)]);
    expect(find.text('7:30'), findsOneWidget);
    expect(hintOf(tester, 'The day before'), 'Also at 7:30 the day before it is due.');
    switchOf(tester, 'Remind me').onCheckedChange!(false);
    await tester.pump();
    expect(ReminderSettingsStore(kept).value, const ReminderSettings(on: false, hour: 7, minute: 30, dayBefore: true));
    expect(switchOf(tester, 'The day before').disabled, isTrue);
    await endSettings(tester);
  });

  testWidgets('says what Android keeps from them, and offers the way to allow it', (tester) async {
    host.ability = (notify: true, exact: false);
    await open(tester);
    expect(hintOf(tester, 'Remind me'), 'Android may send a reminder a few minutes late. Allow exact times below to have it on the minute.');
    host.ability = (notify: true, exact: true);
    await tester.tap(find.text('Allow exact times'));
    await tester.pump();
    await tester.pump();
    expect(host.exactAsked, 1);
    expect(find.text('Allow exact times'), findsNothing);
    await endSettings(tester);
    host.ability = (notify: false, exact: true);
    await open(tester);
    expect(hintOf(tester, 'Remind me'), 'It’s on, but Android is not showing notifications from Ghost.md. Allow them below.');
    expect(find.text('Allow notifications'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('a picture of it, dark, on a phone', (tester) async {
    host.ability = (notify: true, exact: false);
    await open(tester, prefs: const Preferences(theme: 'dark'), size: const Size(430, 932));
    await shot(tester, '../../../../build/feature-shots/reminders/settings-reminders-dark');
  }, skip: !autoUpdateGoldenFiles);
}
