import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/export_all.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/settings/kit/settings_icons.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/export_pane.dart';
import 'package:glacier/glacier.dart';

import 'stage9_support.dart';

/// Settings › Export (lib/settings/panes/export_pane.dart; `ExportCard.tsx`): the one row, the export under way
/// with how far it has got and Stop, what it wrote, a picker closed, and a failure in the app's own words. The
/// export itself is stood in for.
class FakeExport extends ExportAll {
  FakeExport({this.found = ExportWay.android})
      : super(invoke: (command, [args = const {}]) async => null, run: (args, onProgress) async => const Exported(name: ''), platform: TargetPlatform.android);

  final ExportWay found;
  int started = 0, cancelled = 0;
  Completer<Exported?> end = Completer<Exported?>();
  void Function(ExportProgress)? tell;

  @override
  Future<ExportWay> way() async => found;

  @override
  void cancel() => cancelled += 1;

  @override
  Future<Exported?> exportEverything(void Function(ExportProgress progress) onProgress, {DateTime? at}) {
    started += 1;
    tell = onProgress;
    return end.future;
  }
}

void main() {
  setUpAll(loadAppFonts);

  Future<void> open(WidgetTester tester, ExportAll? export) async {
    await showPane(tester, 'Export', (context) => ExportPane(export: export), glyph: SettingsGlyph.hardDriveDownload);
    await letRun(tester);
  }

  String? hint(WidgetTester tester) => (tester.widget<SettingRow>(rowCalled('Export everything')).hint as Text?)?.data;
  bool off(WidgetTester tester) => tester.widget<SettingRow>(rowCalled('Export everything')).disabled;

  testWidgets('exports from its row, says how far it has got with a word to stop it, and then what it wrote', (tester) async {
    final export = FakeExport();
    await open(tester, export);
    expect(hint(tester), 'Every note, picture, film and recording, as one zip. Plug in a USB drive and choose it, or any folder.');
    expect(off(tester), isFalse);
    await tapOn(tester, rowCalled('Export everything'));
    expect(export.started, 1);
    expect(find.text('Choose where the export goes.'), findsOneWidget);
    expect(off(tester), isTrue, reason: 'one export at a time');
    expect(find.byType(GlacierProgressBar), findsNothing);

    export.tell!(const ExportProgress(done: 820000, total: 1400000000, files: 3, of: 40));
    await tester.pump();
    expect(find.text('Exporting, 820 KB of 1.4 GB. Keep Ghost.md open, and the drive plugged in.'), findsOneWidget);
    final bar = tester.widget<GlacierProgressBar>(find.byType(GlacierProgressBar));
    expect((bar.value, bar.max, bar.ariaLabel), (820000, 1400000000, 'Exporting everything'));
    await tapOn(tester, actionSaying('Stop'));
    expect(export.cancelled, 1);

    export.end.complete(const Exported(name: 'ghostmarkdown_2026-10-01_21-42-05.zip', notes: 12, files: 40, bytes: 9000000, written: 8100000));
    await letRun(tester);
    expect(find.text('Exported 12 notes and 28 other files, 8.1 MB, as ghostmarkdown_2026-10-01_21-42-05.zip.'), findsOneWidget);
    expect(off(tester), isFalse);
    expect(find.byType(GlacierProgressBar), findsNothing);
    await endSettings(tester);
  });

  testWidgets('says nothing when the picker was closed, and why when the export failed', (tester) async {
    final export = FakeExport();
    await open(tester, export);
    await tapOn(tester, rowCalled('Export everything'));
    export.end.complete(null);
    await letRun(tester);
    expect(find.byType(SettingsCallout), findsNothing);
    expect(off(tester), isFalse);

    export.end = Completer<Exported?>();
    await tapOn(tester, rowCalled('Export everything'));
    export.end.completeError(const CoreError('The export was stopped.'));
    await letRun(tester);
    expect(find.text('The export was stopped.'), findsOneWidget);
    expect(export.started, 2);
    await endSettings(tester);
  });

  testWidgets('the row says why where an export cannot go, and cannot be pressed', (tester) async {
    await open(tester, FakeExport(found: ExportWay.update));
    expect(hint(tester), 'Update Ghost.md to export everything.');
    expect(off(tester), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await open(tester, FakeExport(found: ExportWay.none));
    expect(hint(tester), 'Exporting isn’t on iPhone yet.');
    await tester.pumpWidget(const SizedBox.shrink());
    await open(tester, null);
    expect(hint(tester), ExportPane.hint(TargetPlatform.android));
    expect(off(tester), isTrue);
    expect(ExportPane.hint(TargetPlatform.macOS), 'Every note, picture, film and recording, as one zip. Choose a USB drive or any folder.');
    await endSettings(tester);
  });
}
