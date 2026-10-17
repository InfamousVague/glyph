import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/importer/import_report.dart';
import 'package:ghost_md/importer/import_sources.dart';
import 'package:ghost_md/importer/importer.dart';
import 'package:ghost_md/settings/kit/settings_icons.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/import_pane.dart';
import 'package:glacier/glacier.dart';

import 'stage9_support.dart';

/// Settings › Import (lib/settings/panes/import_pane.dart): its two rows, an import under way with how far it has
/// got and Stop, what it brought, what it renamed and what it left out, taking it back, a picker closed, and a
/// failure. The import itself is stood in for (test/importer/ holds it).
class FakeImporter extends Importer {
  FakeImporter() : super(picker: ImportPicker(), workspaces: WorkspaceStore(), target: () => throw StateError('not here'));

  int obsidians = 0, evernotes = 0;
  final List<ImportReport> removed = [];
  Completer<ImportReport?> end = Completer<ImportReport?>();
  void Function(ImportProgress)? tell;
  bool Function()? asked;

  @override
  Future<ImportReport?> obsidian({void Function(ImportProgress progress)? progress, bool Function()? stopped}) {
    obsidians += 1;
    tell = progress;
    asked = stopped;
    return end.future;
  }

  @override
  Future<ImportReport?> evernote({void Function(ImportProgress progress)? progress, bool Function()? stopped}) {
    evernotes += 1;
    tell = progress;
    asked = stopped;
    return end.future;
  }

  @override
  void remove(ImportReport report) => removed.add(report);
}

/// What the vault in test/importer/fixtures brings, as its report says it.
ImportReport vaultReport() => ImportReport(from: 'Obsidian')
  ..groupId = 'w-import'
  ..groupName = 'Imported from Obsidian 2026-10-16'
  ..notes = 7
  ..canvases = 1
  ..pictures = 2
  ..files = 4
  ..missing = 1
  ..skipped.addAll(['.obsidian/, Obsidian’s settings', '.trash/, Obsidian’s trash'])
  ..renamed.add((from: 'Welcome.md', to: 'Welcome 2.md'));

void main() {
  setUpAll(loadAppFonts);

  Future<void> open(WidgetTester tester, Importer? importer, {Size size = phone, String theme = 'light'}) async {
    await showPane(tester, 'Import', (context) => ImportPane(importer: importer), glyph: SettingsGlyph.folderInput, size: size);
    if (theme != 'light') preferences.update((now) => now.copyWith(theme: theme));
    await letRun(tester);
  }

  bool off(WidgetTester tester, String row) => tester.widget<SettingRow>(rowCalled(row)).disabled;

  testWidgets('two rows, which wait for an importer, and A .ghostex file below them', (tester) async {
    await open(tester, null);
    expect(rowLabels(tester), ['Obsidian vault', 'Evernote export (.enex)', 'A .ghostex file']);
    expect(off(tester, 'Obsidian vault'), isTrue);
    expect(off(tester, 'Evernote export (.enex)'), isTrue);
    expect(find.textContaining('a workspace of their own, named for the day'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('imports a vault, says how far it has got with a word to stop it, then what it did, and takes it back', (tester) async {
    final importer = FakeImporter();
    await open(tester, importer);
    await tapOn(tester, rowCalled('Obsidian vault'));
    expect(importer.obsidians, 1);
    expect(find.text('Choose what to import.'), findsOneWidget);
    expect(off(tester, 'Evernote export (.enex)'), isTrue, reason: 'one import at a time');

    importer.tell!((done: 3, total: 12, on: 'Projects/Alpha.md'));
    await tester.pump();
    expect(find.text('Importing from Obsidian, 3 of 12. Keep Ghost.md open.'), findsOneWidget);
    final bar = tester.widget<GlacierProgressBar>(find.byType(GlacierProgressBar));
    expect((bar.value, bar.max), (3, 12));
    expect(importer.asked!(), isFalse);
    await tapOn(tester, actionSaying('Stop'));
    expect(importer.asked!(), isTrue, reason: 'Stop is asked between files');

    importer.end.complete(vaultReport());
    await letRun(tester);
    expect(find.text('Imported 7 notes, 1 canvas, 2 pictures and 4 files, in the workspace Imported from Obsidian 2026-10-16.'), findsOneWidget);
    expect(find.text('A name was taken, so one note has another: Welcome.md is now Welcome 2.md.'), findsOneWidget);
    expect(find.text('Left out: .obsidian/, Obsidian’s settings; .trash/, Obsidian’s trash; 1 link to a missing file.'), findsOneWidget);
    expect(off(tester, 'Obsidian vault'), isFalse);

    await tapOn(tester, rowCalled('Remove this import'));
    expect(importer.removed.single.groupId, 'w-import');
    expect(find.textContaining('The import is in the trash'), findsOneWidget);
    expect(find.text('Remove this import'), findsNothing);
    await endSettings(tester);
  });

  testWidgets('an export’s import counts its notes as they come, with no total to count to', (tester) async {
    final importer = FakeImporter();
    await open(tester, importer);
    await tapOn(tester, rowCalled('Evernote export (.enex)'));
    expect(importer.evernotes, 1);
    importer.tell!((done: 41, total: 0, on: 'Pancakes'));
    await tester.pump();
    expect(find.text('Importing from Evernote, 41 notes so far. Keep Ghost.md open.'), findsOneWidget);
    expect(find.byType(GlacierProgressBar), findsNothing);
    importer.end.complete(null);
    await letRun(tester);
    expect(find.textContaining('Importing'), findsNothing, reason: 'a picker closed is nothing to say');
    await endSettings(tester);
  });

  testWidgets('a failure in the app’s words', (tester) async {
    final importer = FakeImporter();
    await open(tester, importer);
    await tapOn(tester, rowCalled('Obsidian vault'));
    importer.end.completeError(StateError('That folder could not be read.'));
    await letRun(tester);
    expect(find.text('That folder could not be read.'), findsOneWidget);
    await endSettings(tester);
  });

  // Pictures to look at, not held: `FEATURE_SHOTS=1 flutter test --update-goldens test/settings/panes/import_pane_test.dart`
  // writes them under build/feature-shots/share-import/.
  final shots = Platform.environment.containsKey('FEATURE_SHOTS');
  for (final (name, size) in [('phone', const Size(430, 932)), ('fold', const Size(900, 1000))]) {
    testWidgets('a picture: the page, and an import done, on the $name', (tester) async {
      final importer = FakeImporter();
      await open(tester, importer, size: size, theme: 'dark');
      await expectLater(find.byType(GhostApp), matchesGoldenFile('../../../build/feature-shots/share-import/import-idle-$name-dark.png'));
      await tapOn(tester, rowCalled('Obsidian vault'));
      importer.end.complete(vaultReport());
      await letRun(tester);
      await expectLater(find.byType(GhostApp), matchesGoldenFile('../../../build/feature-shots/share-import/import-done-$name-dark.png'));
      await endSettings(tester);
    }, skip: !shots);
  }
}
