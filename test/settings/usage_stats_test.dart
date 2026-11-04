import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/metrics.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/guide/pages.dart';
import 'package:ghost_md/guide/pages/about.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/privacy_card.dart';
import 'package:ghost_md/settings/usage_stats.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// The anonymous usage stats' switch (lib/settings/usage_stats.dart): on by default, in Settings › Privacy and on the
/// walkthrough's privacy page, one switch in both places, and off deletes the install ID.
void main() {
  setUp(() {
    usageStatsPref.set(true);
    useMetrics(Metrics(key: 'phc_test', keep: const DeviceMetricsKeep(), send: (_, _) async => true, sendEvery: const Duration(hours: 1)));
  });
  tearDown(() {
    usageStatsPref.set(true);
    useMetrics(Metrics.off());
  });

  Finder privacySwitch() => find.descendant(of: find.widgetWithText(SettingRow, usageStatsLabel), matching: find.byType(GlacierSwitch));
  Finder guideSwitch() => find.descendant(of: find.byType(GuideUsageStats), matching: find.byType(GlacierSwitch));

  testWidgets('Settings › Privacy has it, on by default, and says it truly', (tester) async {
    await pumpSettings(tester, const SingleChildScrollView(child: PrivacyCard()));
    expect(privacySwitch(), findsOneWidget);
    expect(tester.widget<GlacierSwitch>(privacySwitch()).checked, isTrue);
    expect(find.textContaining('No ads, no analytics'), findsNothing);
    expect(find.textContaining('Anonymous usage stats help us improve the app'), findsOneWidget);
    expect(find.textContaining('Never your notes'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('the walkthrough\'s privacy page has it, on by default', (tester) async {
    await pumpSettings(tester, const SingleChildScrollView(child: GuideAbout(page: GuidePage.sync)));
    expect(guideSwitch(), findsOneWidget);
    expect(tester.widget<GlacierSwitch>(guideSwitch()).checked, isTrue);
    expect(find.textContaining('Settings › Privacy'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('only the privacy page of the walkthrough has it', (tester) async {
    await pumpSettings(tester, const SingleChildScrollView(child: GuideAbout(page: GuidePage.market)));
    expect(find.byType(GuideUsageStats), findsNothing);
    await endSettings(tester);
  });

  testWidgets('off in the walkthrough is off in Settings, and deletes the install ID', (tester) async {
    track(MetricEvent.noteOpened);
    expect(const DeviceMetricsKeep().installId, isNotEmpty);
    await pumpSettings(tester, const SingleChildScrollView(child: Column(children: [GuideAbout(page: GuidePage.sync), PrivacyCard()])));
    await tester.tap(guideSwitch());
    await tester.pump();
    expect(usageStatsPref.value, isFalse);
    expect(tester.widget<GlacierSwitch>(privacySwitch()).checked, isFalse);
    expect(tester.widget<GlacierSwitch>(guideSwitch()).checked, isFalse);
    expect(const DeviceMetricsKeep().installId, isEmpty);
    expect(metrics.queued, isEmpty);
    // And back on from Settings: on in the walkthrough too.
    await tester.ensureVisible(privacySwitch());
    await tester.pump();
    await tester.tap(privacySwitch());
    await tester.pump();
    expect(tester.widget<GlacierSwitch>(guideSwitch()).checked, isTrue);
    await endSettings(tester);
  });

  testWidgets('reads Simple for its words', (tester) async {
    final store = PreferencesStore()..startWithoutStorage();
    store.value = const Preferences(experience: 'simple', experienceChosen: true);
    await pumpSettings(tester, SingleChildScrollView(child: GuideUsageStats(store: store)));
    expect(find.textContaining(usageStatsHint(simple: true)), findsOneWidget);
    store.value = const Preferences(experience: 'advanced', experienceChosen: true);
    await tester.pump();
    expect(find.textContaining(usageStatsHint(simple: false)), findsOneWidget);
    await endSettings(tester);
  });
}
