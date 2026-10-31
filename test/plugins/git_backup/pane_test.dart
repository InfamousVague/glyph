// The git backup's page in Settings (lib/plugins/git_backup/git_backup_pane.dart; Matt, 2026-10-31): without the core's
// service it says so and still shows the setup; with one, over a fixture library and the real core, the repository's
// rows (remote, last commit and push, who pushes, the sizes), the switches behind More in Simple, a conflict copy with
// Open, Back up now, Open library from git, and Remove asking twice. The pictures (build/feature-shots/git-backup/)
// are drawn with --update-goldens only.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/library_folder.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/files/attachment_places.dart';
import 'package:ghost_md/plugins/git_backup/git_backup.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/onboarding/setup_card.dart';
import 'package:ghost_md/plugins/onboarding/setup_sheet.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:glacier/glacier.dart';

import '../../settings/support.dart' show endSettings, pumpSettings;
import '../github/support.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);
  final shots = autoUpdateGoldenFiles;

  Future<void> snap(WidgetTester tester, String name) async {
    if (!shots) return;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    var target = tester.renderObject(find.byType(GhostApp));
    while (!target.isRepaintBoundary) {
      target = target.parent!;
    }
    final boundary = target;
    final bytes = await tester.runAsync(() async {
      final layer = boundary.debugLayer! as OffsetLayer;
      final image = await layer.toImage(boundary.paintBounds, pixelRatio: boundary is RenderView ? 1 : tester.view.devicePixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    File('build/feature-shots/git-backup/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
  }

  tearDown(() {
    GitBackupService.current = null;
    usePluginGround(PluginGround());
    preferences.update((p) => p.copyWith(experience: 'advanced'));
  });

  testWidgets('without the core’s service the page says so, with the setup at its head and nothing to press', (tester) async {
    gitGround();
    await pumpPane(tester, const GitBackupPane());
    expect(find.textContaining('isn’t available in this build'), findsOneWidget);
    expect(find.byType(PluginSetupCard), findsOneWidget);
    expect(find.text('No repository yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('git-backup-remove')), findsNothing, reason: 'nothing set up, nothing to remove');
    await away(tester);
  });

  group('over a library and the core', () {
    final skip = coreSkip != null;
    late Directory root;
    late String library;
    late String appData;
    late String remote;
    late GitBackupService service;

    setUp(() async {
      root = tempFolder('pane');
      final fixture = fixtureLibrary(root);
      library = fixture.library;
      appData = fixture.appData;
      remote = await bareRemote(realPath(root));
      final on = gitGround(remote: remote);
      final core = await gitCore();
      var prefs = const Preferences();
      service = GitBackupService(
        invoke: core.invoke,
        libraryFolder: LibraryFolder(invoke: (command, [args = const {}]) async => command == 'library_root' ? {'kind': 'folder', 'path': library, 'name': 'Library'} : core.invoke(command, args)),
        appData: appData,
        library: null,
        changes: null,
        handle: () => 'matt',
        preferences: () => prefs,
        setPreferences: (change) => prefs = change(prefs),
        syncNow: () async {},
      );
      // The old places for the attachments, as the engine test has them.
      service.backup = GitBackup(invoke: core.invoke, place: service.place, handle: () => 'matt', holdsPusher: service.claims.holds, pusherElsewhere: service.claims.elsewhere, auth: () async => GitAuth.none, appData: appData, places: () async => AttachmentPlaces.legacy(appData), activity: on.record, publishBundle: () async => null, warn: (_) {});
      GitBackupService.current = service;
    });

    tearDown(() => root.deleteSync(recursive: true));

    testWidgets('the rows: the remote, the last commit and push, this device pushes, the sizes; Back up now backs up and the page says so', skip: skip, (tester) async {
      await service.backup.backUpNow();
      await pumpPane(tester, GitBackupPane(now: () => DateTime.now()));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(find.text(remoteShort(remote)), findsOneWidget);
      expect(find.textContaining('branch main'), findsOneWidget);
      expect(find.textContaining('Last commit just now'), findsOneWidget);
      expect(find.textContaining('Last push just now'), findsOneWidget);
      expect(find.text('This device pushes'), findsOneWidget);
      expect(find.textContaining('backed up'), findsWidgets);
      expect(find.textContaining('recordings'), findsWidgets);
      expect(find.byKey(const ValueKey('git-backup-recordings')), findsOneWidget, reason: 'Advanced: the switches are on the page');
      await snap(tester, 'page-light');
      // Back up now, with a change waiting.
      write(library, 'Inbox/Plan.md', '# Plan\n\nchanged\n');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('git-backup-now')), matching: find.byType(RowAction)));
      await tester.runAsync(() => until(() => !service.backup.running && service.backup.last?.pushed == true));
      await tester.pump();
      expect(find.text('Backed up.'), findsOneWidget);
      await away(tester);
    });

    testWidgets('in Simple the switches wait behind More; a conflict copy has Open; Remove asks twice and leaves the files', skip: skip, (tester) async {
      preferences.update((p) => p.copyWith(experience: 'simple'));
      await service.backup.backUpNow();
      updateGitBackupSettings((s) => s.copyWith(conflicts: ['Inbox/Plan (conflict from git).md']));
      await pumpPane(tester, const GitBackupPane());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(find.byKey(const ValueKey('git-backup-recordings')), findsNothing);
      expect(find.byKey(const ValueKey('git-backup-more')), findsOneWidget);
      expect(find.text('1 conflict copy'), findsOneWidget);
      expect(find.text('Plan (conflict from git)'), findsOneWidget);
      await snap(tester, 'conflict-simple');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('git-backup-more')), matching: find.byType(RowAction)));
      await tester.pump();
      expect(find.byKey(const ValueKey('git-backup-recordings')), findsOneWidget);
      expect(find.byKey(const ValueKey('git-backup-org-Acme')), findsOneWidget);
      expect(tester.widget<GlacierSwitch>(find.descendant(of: find.byKey(const ValueKey('git-backup-org-Acme')), matching: find.byType(GlacierSwitch))).checked, isFalse, reason: 'a team’s notes are the team’s');
      // Open clears the row.
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('git-backup-conflicts')), matching: find.byType(RowAction)));
      await tester.pump();
      expect(find.byKey(const ValueKey('git-backup-conflicts')), findsNothing);
      // Remove: twice.
      await tester.ensureVisible(find.byKey(const ValueKey('git-backup-remove')));
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('git-backup-remove')), matching: find.byType(RowAction)));
      await tester.pump();
      expect(find.text('Tap again'), findsOneWidget);
      expect(exists(library, '.git'), isTrue);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('git-backup-remove')), matching: find.byType(RowAction)));
      await tester.runAsync(() => until(() => !exists(library, '.git')));
      await tester.pump();
      expect(exists(library, 'Inbox/Plan.md'), isTrue, reason: 'the files stay');
      expect(gitBackupSettings().configured, isFalse);
      await away(tester);
    });

    testWidgets('Open library from git shows its fields; the setup sheet and a failed row are pictured', skip: skip, (tester) async {
      await pumpPane(tester, const GitBackupPane());
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('git-backup-restore')));
      await tester.tap(find.byKey(const ValueKey('git-backup-restore')));
      await tester.pump();
      expect(find.byKey(const ValueKey('git-backup-restore-url')), findsOneWidget);
      expect(find.byKey(const ValueKey('git-backup-import')), findsOneWidget, reason: 'a Mac can import a clone made by hand');
      await snap(tester, 'restore');
      await away(tester);
      // The setup's first step.
      await pumpSettings(tester, PluginSetupSheet(key: UniqueKey(), setup: gitBackupSetup(hooks: GitBackupSetupHooks(adopt: ({required remote, authUser}) async => null)), onClose: () {}));
      expect(find.text('Your notes, in a repository you own'), findsOneWidget);
      await snap(tester, 'setup-intro');
      await endSettings(tester);
    });

    testWidgets('a failed backup is a red row with Retry, pictured on the page as the last failure', skip: skip, (tester) async {
      setGitBackupSettings(const GitBackupSettings(remote: 'https://127.0.0.1:9/nobody/nothing.git'));
      await service.backup.backUpNow(personStarted: true);
      final job = activity[backupJobId]!;
      expect((job.state, job.fix?.kind), (JobState.failed, JobFixKind.retry));
      await pumpPane(tester, const GitBackupPane());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(find.textContaining('The last backup failed: The git host couldn’t be reached.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await snap(tester, 'failed-row');
      await away(tester);
    });
  });
}
