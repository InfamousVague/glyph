// Settings › Test results in the app put together (lib/root): the root reads the test report the build carries
// and hands it to Settings (docs/PARITY.md, section 33; lib/diag/built_report.dart, tool/test_report.mjs). It
// handed none, so the page said "No test report in this build." in every build.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/settings/panes/test_results_pane.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import '../support/render.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  const report = <String, Object?>{
    'schemaVersion': 1,
    'generatedAt': '2026-10-11T12:00:00.000Z',
    'version': '0.1.0',
    'commit': 'bb83267',
    'dirty': false,
    'sourceHash': '8d33d8c3cef6d6a0',
    'host': {'os': 'darwin arm64', 'node': 'v25.9.0'},
    'tools': {'flutter': 'Flutter 3.41.0'},
    'suites': [
      {
        'id': 'flutter:app',
        'title': 'App (Flutter)',
        'status': 'passed',
        'counts': {'total': 2, 'passed': 2, 'failed': 0, 'skipped': 0, 'todo': 0},
        'tests': [
          {'file': 'test/root/root_test.dart', 'line': 3, 'name': 'opens on home', 'status': 'passed', 'ms': 12, 'failure': null},
          {'file': 'test/root/root_test.dart', 'line': 9, 'name': 'opens a note', 'status': 'passed', 'ms': 30, 'failure': null},
        ],
      },
    ],
  };

  Future<void> settle(WidgetTester tester, [int beats = 4]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  SettingsFeatures features(WidgetTester tester) => tester.widget<SettingsSheet>(find.byType(SettingsSheet, skipOffstage: false)).features;

  testWidgets('the report the build carries reaches Settings once Developer mode is on, read once and never before', (tester) async {
    var reads = 0;
    addTearDown(() => developerMode.set(false));
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: SampleLibrary.seeded(),
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: MemoryStored(),
        testReport: () async {
          reads += 1;
          return report;
        },
      ),
    );
    await settle(tester);
    // The pages nobody has unlocked are not read for.
    expect(reads, 0);
    expect(features(tester).testReport, isNull);

    developerMode.set(true);
    await settle(tester);
    expect(reads, 1);
    final handed = features(tester).testReport;
    expect(identical(handed, report), isTrue, reason: 'Settings is built again with the report when it has come');
    // What the row in Settings' list says of it, and the page's verdict: this app's own suite.
    expect(reportSummary(TestReport.of(handed!), buildSource: features(tester).testBuildSource), '2 passed');
    expect(features(tester).testBuildSource, isNull, reason: 'a test is a development build: no GHOST_SOURCE');
    expect(identical(TestReport.of(handed), TestReport.of(handed)), isTrue, reason: 'read into its tests once, however often Settings is built');

    // Off and on again: it has it, and does not read it again.
    developerMode.set(false);
    await settle(tester, 1);
    developerMode.set(true);
    await settle(tester, 2);
    expect(reads, 1);
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a build with no report to read hands Settings none, and the page says so', (tester) async {
    addTearDown(() => developerMode.set(false));
    developerMode.set(true);
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        library: SampleLibrary.seeded(),
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        stored: MemoryStored(),
        testReport: () async => null,
      ),
    );
    await settle(tester);
    expect(features(tester).testReport, isNull);
    expect(reportSummary(null), 'No report yet');
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
