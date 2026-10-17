import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/export/ghostex.dart';
import 'package:ghost_md/export/ghostex_calls.dart';
import 'package:ghost_md/export/ghostex_seal.dart';
import 'package:ghost_md/importer/ghostex.dart';
import 'package:ghost_md/importer/import_report.dart';
import 'package:ghost_md/settings/account_forms.dart' show FormSubmit;
import 'package:ghost_md/settings/kit/settings_icons.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/ghostex_cards.dart';
import 'package:ghost_md/settings/panes/import_pane.dart';
import 'package:glacier/glacier.dart';

import 'stage9_support.dart';

/// The .ghostex in Settings (lib/settings/panes/ghostex_cards.dart): Account › Export everything with its options, a
/// password typed twice, how far it has got and the file handed over; Import › A .ghostex file with its password,
/// the choice for the notes already here, and the report. The export and the read-back themselves are stood in for
/// (test/export/ and test/importer/ hold them).
class FakeGhostex extends Ghostex {
  FakeGhostex({this.offered = true, bool seals = true})
      : super(
          source: GhostexSource(library: SampleLibrary(const []), workspaces: WorkspaceStore(), picturePath: (_) async => null, filePath: (_) async => null, recordingPath: (_) async => null),
          target: () => throw StateError('not here'),
          temp: () async => '/nowhere',
          seal: seals ? _NoSeal() : null,
        );

  final bool offered;
  final List<GhostexOptions> exports = [];
  final List<GhostexMade> handed = [];
  final List<String?> passwords = [];
  final List<GhostexCollision> reads = [];
  Completer<GhostexMade> made = Completer<GhostexMade>();
  void Function(GhostexProgress)? tell;
  GhostexChosen? chosen = const GhostexChosen(path: '/cache/matt-2026-10-17.ghostex', name: 'matt-2026-10-17.ghostex');
  String password = 'correct horse';
  GhostexReport report = GhostexReport()
    ..notes = 3
    ..pictures = 2
    ..alreadyHere = 1;

  @override
  bool get exportOffered => offered;

  @override
  bool get importOffered => offered;

  @override
  Future<GhostexMade> export(GhostexOptions options, {void Function(GhostexProgress progress)? progress, DateTime? at}) {
    exports.add(options);
    tell = progress;
    return made.future;
  }

  @override
  Future<void> handOver(GhostexMade made) async => handed.add(made);

  @override
  Future<GhostexChosen?> choose() async => chosen;

  @override
  Future<GhostexOpened> open(GhostexChosen chosen, {String? password}) async {
    passwords.add(password);
    if (password == null) throw const GhostexNeedsPassword();
    if (password != this.password) throw const GhostexWrongPassword();
    return GhostexOpened(chosen: chosen, zip: '/cache/opened.zip', notes: 4, here: 1, temporary: true);
  }

  @override
  Future<GhostexReport> read(GhostexOpened opened, {required GhostexCollision collision, void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
    reads.add(collision);
    return report;
  }

  @override
  Future<void> close(GhostexOpened opened) async {}
}

class _NoSeal implements GhostexSeal {
  @override
  Future<void> open(String sealed, String out, String password) async {}

  @override
  Future<void> seal(String zip, String out, String password) async {}
}

GhostexMade madeOne() => const GhostexMade(name: 'matt-2026-10-17.ghostex', written: GhostexWritten(path: '/cache/ghostex/matt-2026-10-17.ghostex', notes: 312, pictures: 48, files: 3, recordings: 0, bytes: 1200000));

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => ghostexWaiting.value = null);

  GlacierSwitch switchOf(WidgetTester tester, String label) => tester.widget<GlacierSwitch>(find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == label));
  Finder input(String label) => find.descendant(of: find.byWidgetPredicate((w) => w is GlacierInput && w.ariaLabel == label), matching: find.byType(EditableText));

  group('Export everything', () {
    Future<void> open(WidgetTester tester, Ghostex? ghostex) async {
      await showPane(tester, 'Account', (context) => PaneBody(children: [GhostexExportCard(ghostex: ghostex)]), glyph: SettingsGlyph.circleUser);
      await letRun(tester);
    }

    testWidgets('waits for a device that can hand a file over', (tester) async {
      await open(tester, null);
      expect(tester.widget<SettingRow>(rowCalled('Export everything')).disabled, isTrue);
      await endSettings(tester);
      await open(tester, FakeGhostex(offered: false));
      expect(tester.widget<SettingRow>(rowCalled('Export everything')).disabled, isTrue);
      await endSettings(tester);
    });

    testWidgets('asks what goes in, the password twice, then says how far it has got and hands the file over', (tester) async {
      final ghostex = FakeGhostex();
      await open(tester, ghostex);
      await tapOn(tester, rowCalled('Export everything'));
      expect(rowLabels(tester), containsAllInOrder(['Include archived notes', 'Include organizations’ notes', 'Include recordings', 'Protect with a password']));
      switchOf(tester, 'Include archived notes').onCheckedChange!(true);
      switchOf(tester, 'Protect with a password').onCheckedChange!(true);
      await tester.pump();
      await tester.enterText(input('Password'), 'correct horse');
      await tester.enterText(input('The password again'), 'correct hose');
      await tester.pump();
      expect(find.text('The two passwords are not the same.'), findsOneWidget);
      await tapOn(tester, find.text('Export'));
      expect(ghostex.exports, isEmpty, reason: 'not with two passwords');
      await tester.enterText(input('The password again'), 'correct horse');
      await tester.pump();
      expect(find.text('The two passwords are not the same.'), findsNothing);
      await tapOn(tester, find.text('Export'));
      final options = ghostex.exports.single;
      expect((options.archived, options.organizations, options.recordings, options.password), (true, false, false, 'correct horse'));

      ghostex.tell!((done: 40, total: 360, step: 'Writing'));
      await tester.pump();
      expect(find.text('Writing the export, 40 of 360. Keep Ghost.md open.'), findsOneWidget);
      final bar = tester.widget<GlacierProgressBar>(find.byType(GlacierProgressBar));
      expect((bar.value, bar.max), (40, 360));

      ghostex.made.complete(madeOne());
      await letRun(tester);
      expect(find.text('Exported 312 notes, 48 pictures and 3 files as matt-2026-10-17.ghostex.'), findsOneWidget);
      expect(ghostex.handed.single.name, 'matt-2026-10-17.ghostex', reason: 'handed to the share sheet as soon as it is made');
      await tapOn(tester, rowCalled('Save or send it'));
      expect(ghostex.handed, hasLength(2));
      await tapOn(tester, actionSaying('Done'));
      expect(rowLabels(tester), ['Export everything']);
      await endSettings(tester);
    });

    testWidgets('offers no password where the build cannot seal, and says a failure in the app’s words', (tester) async {
      final ghostex = FakeGhostex(seals: false);
      await open(tester, ghostex);
      await tapOn(tester, rowCalled('Export everything'));
      expect(rowLabels(tester), isNot(contains('Protect with a password')));
      await tapOn(tester, find.text('Export'));
      expect(ghostex.exports.single.sealed, isFalse);
      ghostex.made.completeError(StateError('There is no room left on this phone.'));
      await letRun(tester);
      expect(find.text('There is no room left on this phone.'), findsOneWidget);
      await endSettings(tester);
    });
  });

  group('A .ghostex file', () {
    Future<void> open(WidgetTester tester, Ghostex? ghostex) async {
      await showPane(tester, 'Import', (context) => ImportPane(ghostex: ghostex), glyph: SettingsGlyph.folderInput);
      await letRun(tester);
    }

    testWidgets('is the last row, below the Todoist and Things ones, and waits for a picker', (tester) async {
      await open(tester, null);
      expect(rowLabels(tester), ['Obsidian vault', 'Evernote export (.enex)', 'Completed tasks too', 'Todoist CSV export (.csv)', 'Paste from Things', 'A .ghostex file']);
      expect(tester.widget<SettingRow>(rowCalled('A .ghostex file')).disabled, isTrue);
      await endSettings(tester);
    });

    testWidgets('asks the password of a protected one, says a wrong one, then the choice for the notes here', (tester) async {
      final ghostex = FakeGhostex();
      await open(tester, ghostex);
      await tapOn(tester, rowCalled('A .ghostex file'));
      expect(find.text('This export is protected with a password.'), findsOneWidget);
      await tester.enterText(input('The export’s password'), 'wrong');
      await tester.pump();
      await tapOn(tester, find.text('Open'));
      await letRun(tester);
      expect(find.text('That password does not open this export.'), findsOneWidget);
      await tester.enterText(input('The export’s password'), 'correct horse');
      await tester.pump();
      await tapOn(tester, find.text('Open'));
      await letRun(tester);
      expect(ghostex.passwords, [null, 'wrong', 'correct horse']);
      expect(find.text('4 notes, one of them here already.'), findsOneWidget);
      tester.widget<GlacierSegmentedControl>(find.byType(GlacierSegmentedControl)).onValueChange!('copy');
      await tester.pump();
      expect(find.text('Kept, and the export’s brought in beside them as copies.'), findsOneWidget);
      await tapOn(tester, find.descendant(of: find.byType(FormSubmit), matching: find.text('Import')));
      await letRun(tester);
      expect(ghostex.reads, [GhostexCollision.copy]);
      expect(find.text('Imported 3 notes and 2 pictures; one note was here already and was left as it is.'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('one opened from Files is taken up as the page opens', (tester) async {
      final ghostex = FakeGhostex()..password = '';
      ghostexWaiting.value = const GhostexChosen(path: '/cache/shared/1/old.ghostex', name: 'old.ghostex');
      await open(tester, ghostex);
      await letRun(tester);
      expect(ghostexWaiting.value, isNull);
      expect(find.text('This export is protected with a password.'), findsOneWidget, reason: 'the fake asks a password of every file');
      expect(find.byWidgetPredicate((w) => w is PaneSection && w.title == 'old.ghostex'), findsOneWidget);
      await tapOn(tester, actionSaying('Cancel'));
      expect(rowLabels(tester), ['Obsidian vault', 'Evernote export (.enex)', 'Completed tasks too', 'Todoist CSV export (.csv)', 'Paste from Things', 'A .ghostex file']);
      await endSettings(tester);
    });
  });
}
