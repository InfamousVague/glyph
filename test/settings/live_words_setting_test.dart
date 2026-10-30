// Settings › Recording › Live transcript during meetings (lib/settings/panes/recording_pane.dart,
// lib/capture/meeting_live_words.dart; Matt, 2026-10-30: "If possible add real time transcriptions for meetings"): this
// device's own choice. On a phone Off, While charging (its start) or On, beside the meeting service's own rows; on the
// Mac a switch, on; each kept on the device and read by the meeting's live words.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/meeting_live_words.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/settings/panes/recording_pane.dart';
import 'package:ghost_md/settings/panes/settings_host.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => useStored(MemoryStored()));

  Widget page(Widget child) => SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child));

  testWidgets('on a phone with the meeting service: Off, While charging and On, While charging at first, kept on the phone', (tester) async {
    final setting = LiveWordsSetting(phone: true);
    await pumpSettings(tester, page(RecordingPane(android: true, features: const SettingsFeatures(meetings: true), liveWords: setting)));
    expect(find.text('Live transcript during meetings'), findsOneWidget);
    final control = find.byWidgetPredicate((w) => w is GlacierSegmentedControl && w.ariaLabel == 'Live transcript during meetings');
    expect(control, findsOneWidget);
    expect(tester.widget<GlacierSegmentedControl>(control).value, 'charging');
    await tester.ensureVisible(control);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.descendant(of: control, matching: find.text('On')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(setting.value, LiveWordsChoice.on);
    expect(stored.read<Object?>(liveWordsKey, null, (raw) => raw), 'on');
    await tester.tap(find.descendant(of: control, matching: find.text('Off')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(LiveWordsSetting(phone: true).value, LiveWordsChoice.off, reason: 'read back as kept');
    await endSettings(tester);
  });

  testWidgets('on the Mac: a switch, on at first', (tester) async {
    final setting = LiveWordsSetting(phone: false);
    await pumpSettings(tester, page(RecordingPane(android: false, liveWords: setting)));
    final toggle = find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == 'Live transcript during meetings');
    expect(toggle, findsOneWidget);
    expect(tester.widget<GlacierSwitch>(toggle).checked, isTrue);
    await tester.ensureVisible(toggle);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 300));
    expect(setting.value, LiveWordsChoice.off);
    expect(tester.widget<GlacierSwitch>(toggle).checked, isFalse);
    await endSettings(tester);
  });

  test('found by searching Settings', () {
    expect(recordingFindable(android: true).map((f) => f.name), contains('Live transcript during meetings'));
    expect(recordingFindable(android: false).map((f) => f.name), contains('Live transcript during meetings'));
  });
}
