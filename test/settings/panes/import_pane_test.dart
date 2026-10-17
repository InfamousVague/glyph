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

/// Settings › Import (lib/settings/panes/import_pane.dart): its rows, an import under way with how far it has
/// got and Stop, what it brought, what it renamed and what it left out, taking it back, a picker closed, and a
/// failure; Todoist's token handed on and let go, its CSV, and Things on a Mac and pasted. The import itself is
/// stood in for (test/importer/ holds it).
class FakeImporter extends Importer {
  FakeImporter({bool mac = false}) : super(picker: ImportPicker(), workspaces: WorkspaceStore(), target: () => throw StateError('not here'), onMac: mac);

  int obsidians = 0, evernotes = 0, csvs = 0, macs = 0, pastes = 0;
  final List<(String, bool)> tokens = [];
  bool? logbook;
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
  Future<ImportReport?> todoist(String token, {bool done = false, void Function(ImportProgress progress)? progress, bool Function()? stopped}) {
    tokens.add((token, done));
    tell = progress;
    asked = stopped;
    return end.future;
  }

  @override
  Future<ImportReport?> todoistCsv({void Function(ImportProgress progress)? progress, bool Function()? stopped}) {
    csvs += 1;
    tell = progress;
    return end.future;
  }

  @override
  Future<ImportReport?> thingsOnMac({bool done = false, void Function(ImportProgress progress)? progress, bool Function()? stopped}) {
    macs += 1;
    logbook = done;
    tell = progress;
    return end.future;
  }

  @override
  Future<ImportReport?> thingsPaste() {
    pastes += 1;
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

  testWidgets('its rows, which wait for an importer', (tester) async {
    await open(tester, null);
    expect(rowLabels(tester), ['Obsidian vault', 'Evernote export (.enex)', 'Completed tasks too', 'Todoist CSV export (.csv)', 'Paste from Things']);
    expect(off(tester, 'Obsidian vault'), isTrue);
    expect(off(tester, 'Evernote export (.enex)'), isTrue);
    expect(off(tester, 'Todoist CSV export (.csv)'), isTrue);
    expect(off(tester, 'Paste from Things'), isTrue);
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

  testWidgets('Todoist with a token: the token handed on with the switch, and let go from the field', (tester) async {
    final importer = FakeImporter();
    await open(tester, importer);
    expect(tester.widget<SettingsWord>(find.byKey(const ValueKey('import-todoist'))).onPressed, isNull, reason: 'no token, nothing to press');
    await tester.enterText(find.byType(EditableText), ' 0123abcd ');
    await tester.pump();
    await tapOn(tester, inRow('Completed tasks too', find.byType(GlacierSwitch)));
    await tapOn(tester, find.byKey(const ValueKey('import-todoist')));
    expect(importer.tokens, [('0123abcd', true)]);
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty, reason: 'the token is not kept in the field');
    expect(find.text('Reading your Todoist account…'), findsOneWidget);
    importer.tell!((done: 1, total: 4, on: 'Inbox'));
    await tester.pump();
    expect(find.text('Importing from Todoist, 1 of 4. Keep Ghost.md open.'), findsOneWidget);
    importer.end.complete(ImportReport(from: 'Todoist')
      ..groupId = 'w-todoist'
      ..groupName = 'Imported from Todoist 2026-10-17'
      ..notes = 4
      ..tasks = 37
      ..notebooks = 1
      ..skipped.add('comments and attachments, which stay in Todoist'));
    await letRun(tester);
    expect(find.text('Imported 4 notes, 37 to-dos and 1 notebook, in the workspace Imported from Todoist 2026-10-17.'), findsOneWidget);
    expect(find.text('Left out: comments and attachments, which stay in Todoist.'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('a Todoist CSV export through the picker', (tester) async {
    final importer = FakeImporter();
    await open(tester, importer);
    await tapOn(tester, rowCalled('Todoist CSV export (.csv)'));
    expect(importer.csvs, 1);
    expect(find.text('Choose what to import.'), findsOneWidget);
    importer.end.complete(null);
    await letRun(tester);
    await endSettings(tester);
  });

  testWidgets('Things: on a Mac from its own data, the Logbook if asked; anywhere pasted', (tester) async {
    final importer = FakeImporter(mac: true);
    await open(tester, importer);
    expect(rowLabels(tester).sublist(4), ['From Things on this Mac', 'The Logbook too', 'Paste from Things']);
    await tapOn(tester, rowCalled('From Things on this Mac'));
    expect((importer.macs, importer.logbook), (1, false));
    expect(find.text('Reading Things…'), findsOneWidget);
    importer.end.complete(null);
    await letRun(tester);

    importer.end = Completer<ImportReport?>();
    await tapOn(tester, rowCalled('Paste from Things'));
    expect(importer.pastes, 1);
    importer.end.completeError(StateError('Nothing is copied. In Things, open a list, choose Share › Copy, and come back.'));
    await letRun(tester);
    expect(find.text('Nothing is copied. In Things, open a list, choose Share › Copy, and come back.'), findsOneWidget);
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
