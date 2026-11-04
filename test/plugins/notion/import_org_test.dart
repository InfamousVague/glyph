import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/front_matter.dart' show frontMatterValue;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/notion/notion.dart';
import 'package:ghost_md/plugins/notion/notion_import_job.dart';

import '../../feed/signed.dart';
import '../../importer/notion/fake_notion.dart';
import '../../importer/support.dart';
import '../../support/fake_service.dart';
import 'support.dart' show Phone;

/// Import from Notion into a new organization, made by the app's own createOrg over a fake service (Matt,
/// 2026-11-04: "I want the import to start a new org"), and Remove what was imported, into the trash and back
/// ("also delete the notes from my most recent notion import").
void main() {
  late ImportHarness it;
  late FakeNotion notion;
  late NotionImportJob job;

  setUp(() {
    Phone().use();
    useActivity(Activity());
    it = ImportHarness();
    notion = FakeNotion(pageSize: 100)
      ..add(page(idOf(1), 'Home'), children: [block('paragraph', rich: 'Hello.'), {'object': 'block', 'id': dashed(idOf(2)), 'type': 'child_page', 'has_children': false, 'child_page': {'title': 'Plans'}}])
      ..add(page(idOf(2), 'Plans', parent: idOf(1)), children: [block('paragraph', rich: 'Q1.')])
      ..add(page(idOf(3), 'Recipes'), children: const []);
    job = NotionImportJob(call: notion.call, download: notion.download, background: const NoBackgroundJobs(), gap: Duration.zero, sleep: (_) async {});
  });
  tearDown(() {
    it.dispose();
    resetNotionClient();
    usePluginGround(PluginGround());
  });

  group('a new organization', () {
    late FakeService service;
    late Orgs orgs;
    setUp(() async {
      service = await FakeService.start(seed: testAccount);
      orgs = Orgs(account: SignedAccount(session: testSession), api: apiOf(service), workspaces: it.workspaces);
    });

    test('is made by createOrg, named for the Notion workspace, and the import lands in its workspace', () async {
      final ctx = CallContext(token: service.signedIn());
      await job.startInNewOrg(it.target(), makeOrg: (name) => orgs.createOrg(name, ctx: ctx), workspaces: it.workspaces);
      expect(job.value, isA<NotionImportDone>());
      final made = (await orgs.listOrgs(ctx: ctx)).rows;
      expect(made.map((row) => row.name), ['Acme HQ']);
      final ws = it.workspaces.value.list.firstWhere((w) => w.id == orgWorkspaceId(made.single.id));
      expect(ws.name, 'Acme HQ');
      expect({for (final note in it.library.value) note.path}, {'orgs/Acme HQ/Home/index.md', 'orgs/Acme HQ/Home/Plans.md', 'orgs/Acme HQ/Recipes.md'});
      for (final note in it.library.value) {
        expect(it.workspaces.value.of[note.id], ws.id);
      }
      // Sync now and Keep in sync go there after.
      expect(job.last!.workspaceId, ws.id);
      expect(job.last!.made, isTrue);
      expect(job.lastIn(it.workspaces)?.id, ws.id);
    });

    test('without a Ghost.md sign-in says so, and imports nothing anywhere else', () async {
      await job.startInNewOrg(it.target(), makeOrg: null, workspaces: it.workspaces);
      expect((job.value as NotionImportFailed).why, contains('needs your Ghost.md account'));
      expect(it.library.value, isEmpty);
      expect(it.workspaces.value.list, isEmpty);
    });

    test('an organization the service refuses is said, and nothing is imported', () async {
      await job.startInNewOrg(it.target(), makeOrg: (name) async => throw StateError('Too many organizations.'), workspaces: it.workspaces);
      expect((job.value as NotionImportFailed).why, allOf(contains('couldn’t make the organization “Acme HQ”'), contains('Nothing was imported.')));
      expect(it.library.value, isEmpty);
    });
  });

  group('Remove what was imported', () {
    test('moves the import’s notes to the trash, leaves the person’s own beside them, and each can be put back', () async {
      await job.start(it.target());
      final ws = job.lastIn(it.workspaces)!;
      final mine = Note(id: 'mine', body: '# My own\n\nNot from Notion.\n', createdAt: 1, updatedAt: 1, path: 'workspaces/Notion/Home/Mine.md');
      await it.library.apply(mine);
      it.workspaces.fileNotes(['mine'], ws.id);
      final moved = await job.removeImported(library: it.library, workspaces: it.workspaces);
      expect(moved, 3);
      final trash = it.workspaces.trash!;
      for (final note in it.library.value) {
        expect(trash.isTrashed(note.id), note.id != 'mine', reason: note.path);
      }
      // Its own note is still in it, so the workspace stays; Keep in sync is off.
      expect(it.workspaces.value.list.any((w) => w.id == ws.id), isTrue);
      expect(job.last!.live, isFalse);
      final back = it.library.value.firstWhere((note) => note.path == 'workspaces/Notion/Recipes.md');
      trash.restoreNote(back.id);
      expect(trash.isTrashed(back.id), isFalse);
      expect(it.library.value.where((note) => note.id == back.id), hasLength(1));
    });

    test('works on an import from before (no notion-hash, no made mark): the notes go, and the empty workspace with them', () async {
      await job.start(it.target());
      final ws = job.lastIn(it.workspaces)!;
      // As 2.4.13 wrote them: no hash in the notes, nothing in the place but where and when.
      for (final note in [...it.library.value]) {
        await it.library.apply(note.copyWith(body: note.body.replaceAll(RegExp(r'notion-hash: .*\n'), '')));
      }
      notionHost.storage.set('glyph-notion-import', {'workspace': ws.id, 'name': ws.name, 'at': 1});
      expect(it.library.value.every((note) => frontMatterValue(note.body, 'notion-hash') == null), isTrue);
      expect(await job.removeImported(library: it.library, workspaces: it.workspaces), 3);
      expect(it.workspaces.value.list.any((w) => w.id == ws.id), isFalse);
      expect(it.library.value.every((note) => it.workspaces.trash!.isTrashed(note.id)), isTrue);
    });

    test('never touches a note without notion-id, nor one outside the import’s workspace', () async {
      await job.start(it.target());
      final elsewhere = Note(id: 'elsewhere', body: '---\nnotion-id: ${dashed(idOf(9))}\n---\n# Kept\n', createdAt: 1, updatedAt: 1, path: 'Inbox/Kept.md');
      await it.library.apply(elsewhere);
      await job.removeImported(library: it.library, workspaces: it.workspaces);
      expect(it.workspaces.trash!.isTrashed('elsewhere'), isFalse);
    });
  });
}
