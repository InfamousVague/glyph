import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/notion/notion.dart';
import 'package:ghost_md/plugins/notion/notion_import_job.dart';
import 'package:ghost_md/plugins/notion/notion_import_section.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';

import '../../importer/notion/fake_notion.dart';
import '../../importer/support.dart';
import '../../settings/support.dart';
import 'support.dart' show Phone;

/// Import from Notion on the plugin's page (notion_import_section.dart): what Notion shares, Import everything, its
/// progress and its end, Sync again after, where it goes behind More in Simple; and the job on the app's record.
void main() {
  setUpAll(loadAppFonts);
  late ImportHarness it;
  late FakeNotion notion;
  late NotionImportJob job;

  setUp(() {
    Phone().use();
    useActivity(Activity());
    it = ImportHarness();
    notion = FakeNotion(pageSize: 100)
      ..add(page(idOf(1), 'Home'), children: [block('paragraph', rich: 'Hello.')])
      ..add(page(idOf(2), 'Recipes'), children: const [])
      ..add(database(idOf(3), 'Tasks'));
    job = NotionImportJob(call: notion.call, download: notion.download, background: const NoBackgroundJobs(), gap: Duration.zero, sleep: (_) async {});
  });
  tearDown(() {
    it.dispose();
    resetNotionClient();
    usePluginGround(PluginGround());
  });

  Future<void> section(WidgetTester tester, {bool simple = false}) =>
      pumpSettings(tester, SingleChildScrollView(child: NotionImportSection(job: job, target: it.target, workspaces: it.workspaces, simple: simple)));

  testWidgets('says what Notion shares, imports everything into a new workspace, and offers Sync again after', (tester) async {
    await section(tester);
    expect(find.text('2 pages and 1 database shared'), findsOneWidget);
    expect(find.text('Choose more pages'), findsOneWidget);
    expect(find.text('Import everything'), findsOneWidget);
    // A new organization by default (Matt, 2026-11-04); this test has no Ghost.md sign-in, and picks a workspace.
    expect(find.text('Into a new organization named for your Notion workspace (sign in to Ghost.md first). Running it again later brings only what changed.'), findsOneWidget);
    expect(find.text('A new organization'), findsOneWidget);
    await tester.tap(find.text('A new workspace on this account'));
    await settleSettings(tester);
    expect(find.text('Into a new workspace, Notion. Running it again later brings only what changed.'), findsOneWidget);

    await tester.tap(find.text('Import'));
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && job.running; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await settleSettings(tester);
    expect(job.value, isA<NotionImportDone>());
    expect(find.byKey(const ValueKey('notion-import-done')), findsOneWidget);
    expect(find.textContaining('Imported 2 notes and 1 notebook, in the workspace Notion.'), findsOneWidget);
    expect(it.library.value.length, 3);
    // The record: the job ended well, counted, and the place kept for Sync again.
    expect(activity.lastEnded?.id, notionImportJobId);
    expect(job.last?.name, 'Notion');
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Keep in sync'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('in Simple the import stays and where it goes waits behind More', (tester) async {
    it.workspaces.addWorkspace('Work');
    await section(tester, simple: true);
    expect(find.text('Import everything'), findsOneWidget);
    expect(find.text('WHERE IT GOES'), findsNothing);
    await tester.tap(find.text('Show'));
    await settleSettings(tester);
    expect(find.text('WHERE IT GOES'), findsOneWidget);
    expect(find.text('A new organization'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await settleSettings(tester);
    expect(find.text('Into Work. Running it again later brings only what changed.'), findsOneWidget);
    expect(find.byType(SettingRow), findsWidgets);
    await endSettings(tester);
  });

  Future<void> imported(WidgetTester tester) async {
    await tester.runAsync(() => job.start(it.target()));
    expect(job.value, isA<NotionImportDone>());
  }

  testWidgets('Keep in sync is on once an import ran, says when it last checked, and switches off', (tester) async {
    await imported(tester);
    expect(job.last!.live, isTrue);
    expect(job.last!.mark, '2026-11-01T10:00:00.000Z');
    await section(tester);
    expect(find.text('Keep in sync'), findsOneWidget);
    expect(find.textContaining('Synced just now.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Keep in sync').last);
    await settleSettings(tester);
    expect(job.last!.live, isFalse);
    expect(find.text('Off. Sync now brings what changed when you ask.'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('a sync with nothing changed is one search and quiet; a few changes are quiet too; a failure is said', (tester) async {
    await imported(tester);
    notion.asked.clear();
    await tester.runAsync(() => job.sync(target: it.target(), workspaces: it.workspaces));
    expect(notion.asked, ['POST search']);
    expect(job.lastSync, isNull);

    final started = <JobEvent>[];
    final heard = activity.events.where((e) => e.kind == JobEventKind.started).listen(started.add);
    addTearDown(heard.cancel);
    notion.add(page(idOf(1), 'Home', edited: '2026-11-04T10:00:00.000Z'), children: [block('paragraph', rich: 'Hello again.')]);
    await tester.runAsync(() => job.sync(target: it.target(), workspaces: it.workspaces));
    expect(job.lastSync!.updated, 1);
    expect(job.last!.mark, '2026-11-04T10:00:00.000Z');
    // Quiet: one page changed, so nothing was begun on the record.
    expect(started, isEmpty);
    expect(it.library.value.where((n) => n.body.contains('Hello again.')), hasLength(1));

    notion.script.add((status: 401, body: {'message': 'API token is invalid.'}, headers: const <String, String>{}));
    await tester.runAsync(() => job.sync(target: it.target(), workspaces: it.workspaces));
    expect(job.last!.error, contains('Sign in again'));
  });

  testWidgets('A new organization without a sign-in says so in words and imports nothing', (tester) async {
    await section(tester);
    await tester.tap(find.text('Import'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await settleSettings(tester);
    expect(find.textContaining('A new organization needs your Ghost.md account.'), findsOneWidget);
    expect(it.library.value, isEmpty);
    await endSettings(tester);
  });

  testWidgets('Remove what was imported asks twice, then says how many went to the trash', (tester) async {
    await imported(tester);
    await section(tester);
    expect(find.text('Moves the notes that came from Notion to the trash; they can be put back from there.'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await settleSettings(tester);
    expect(it.workspaces.trash!.value, isEmpty);
    await tester.tap(find.text('Tap again'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await settleSettings(tester);
    expect(find.text('3 notes moved to the trash.'), findsOneWidget);
    expect(it.workspaces.trash!.value.length, 3);
    expect(job.last!.live, isFalse);
    await endSettings(tester);
  });
}
