import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart' show chaptersOf, isBookBody;
import 'package:ghost_md/core/front_matter.dart' show frontMatterValue;
import 'package:ghost_md/importer/import_report.dart';
import 'package:ghost_md/importer/notion/notion_import.dart';
import 'package:ghost_md/importer/notion/notion_source.dart';

import '../support.dart';
import 'fake_notion.dart';

const String home = 'aaaa0000000000000000000000000001';
const String plans = 'aaaa0000000000000000000000000002';
const String q1 = 'aaaa0000000000000000000000000003';
const String tasks = 'aaaa0000000000000000000000000004';
const String rowA = 'aaaa0000000000000000000000000005';
const String rowB = 'aaaa0000000000000000000000000006';
const String notes = 'aaaa0000000000000000000000000007';
const String twin = 'aaaa0000000000000000000000000008';
const String inColumn = 'aaaa0000000000000000000000000009';

const String coverUrl = 'https://prod-files-secure.s3.us-west-2.amazonaws.com/x/cover.png';

/// A small workspace: Home with Plans under it (Plans with Q1 under it, and Q1 inside a column), a Tasks database in
/// Home with two rows, a Notes page at the top, and a second page called Plans at the top.
FakeNotion workspace() {
  final notion = FakeNotion();
  notion.files[coverUrl] = pngBytes;
  notion.add(page(home, 'Home', icon: {'type': 'emoji', 'emoji': '🏠'}, cover: {'type': 'file', 'file': {'url': coverUrl}}), children: [
    block('paragraph', rich: 'Welcome.'),
    {'object': 'block', 'id': dashed(plans), 'type': 'child_page', 'has_children': true, 'child_page': {'title': 'Plans'}},
    {'object': 'block', 'id': dashed(tasks), 'type': 'child_database', 'has_children': false, 'child_database': {'title': 'Tasks'}},
  ]);
  notion.add(page(plans, 'Plans', parent: home), children: [
    {
      'type': 'paragraph',
      'object': 'block',
      'id': dashed('cc000000000000000000000000000001'),
      'has_children': false,
      'paragraph': {
        'rich_text': [text('See '), mentionPage(notes, 'Notes'), text(' and '), mentionPage(rowA, 'Write the doc')],
      },
    },
    block('column_list', children: [
      block('column', children: [
        {'object': 'block', 'id': dashed(inColumn), 'type': 'child_page', 'has_children': false, 'child_page': {'title': 'Q1'}},
      ]),
    ]),
  ]);
  notion.add(page(inColumn, 'Q1', parent: 'cc000000000000000000000000000099', parentKind: 'block_id'), children: [block('paragraph', rich: 'Quarter one.')]);
  notion.add(database(tasks, 'Tasks', parent: home, schema: {
    'Status': {'id': 's', 'name': 'Status', 'type': 'status', 'status': {}},
    'Due Date': {'id': 'd', 'name': 'Due Date', 'type': 'date', 'date': {}},
    'Tags': {'id': 't', 'name': 'Tags', 'type': 'multi_select', 'multi_select': {}},
    'Owner': {'id': 'o', 'name': 'Owner', 'type': 'people', 'people': {}},
    'Points': {'id': 'p', 'name': 'Points', 'type': 'number', 'number': {}},
    'Blocked by': {'id': 'r', 'name': 'Blocked by', 'type': 'relation', 'relation': {}},
    'Created': {'id': 'c', 'name': 'Created', 'type': 'created_time', 'created_time': {}},
  }));
  notion.addRow(tasks, page(rowA, 'Write the doc', parent: tasks, parentKind: 'database_id', titleProperty: 'Name', properties: {
    'Status': {'type': 'status', 'status': {'name': 'In progress'}},
    'Due Date': {'type': 'date', 'date': {'start': '2026-11-10', 'end': '2026-11-12'}},
    'Tags': {'type': 'multi_select', 'multi_select': [{'name': 'Big launch'}, {'name': 'docs'}]},
    'Owner': {'type': 'people', 'people': [{'object': 'user', 'id': 'u', 'name': 'Sam Ortiz'}]},
    'Points': {'type': 'number', 'number': 3},
    'Blocked by': {'type': 'relation', 'relation': [{'id': dashed(rowB)}]},
    'Created': {'type': 'created_time', 'created_time': '2026-10-01T10:00:00.000Z'},
  }), children: [block('paragraph', rich: 'Draft it.')]);
  notion.addRow(tasks, page(rowB, 'Review: final', parent: tasks, parentKind: 'database_id', titleProperty: 'Name', properties: {
    'Status': {'type': 'status', 'status': {'name': 'Done'}},
    'Points': {'type': 'number', 'number': null},
  }));
  notion.add(page(notes, 'Notes', created: '2026-09-01T10:00:00.000Z'), children: [block('to_do', rich: 'Buy milk')]);
  notion.add(page(twin, 'Plans', created: '2026-10-20T10:00:00.000Z'), children: [block('paragraph', rich: 'The other one.')]);
  return notion;
}

void main() {
  const root = 'workspaces/Notion';

  group('a whole workspace', () {
    late ImportHarness it;
    late FakeNotion notion;
    late ImportReport report;
    setUp(() async {
      it = ImportHarness();
      notion = workspace();
      report = await importNotion(notion.reader(), it.target());
    });
    tearDown(() => it.dispose());

    test('comes in as the tree it was: a page with sub-pages a folder and its index.md, in a workspace called Notion', () {
      expect({for (final note in it.library.value) note.path}, {
        '$root/Home/index.md',
        '$root/Home/Plans/index.md',
        '$root/Home/Plans/Q1.md',
        '$root/Home/Tasks/index.md',
        '$root/Home/Tasks/Write the doc.md',
        '$root/Home/Tasks/Review final.md',
        '$root/Notes.md',
        '$root/Plans 2.md',
      });
      expect(report.groupName, 'Notion');
      expect(report.madeGroup, isTrue);
      expect(it.workspaces.value.list.map((w) => w.name), contains('Notion'));
      expect((report.notes, report.notebooks, report.pictures), (7, 1, 1));
    });

    test('a page says where it came from, its icon, its cover as a banner, its sub-pages’ order, and its blocks', () {
      final body = it.at('$root/Home/index.md')!.body;
      expect(body, startsWith('---\ntitle: "Home"\nicon: 🏠\nbanner: "![](image/p1.png)"\norder: [Plans, Tasks]\nnotion-id: ${dashed(home)}\n'));
      expect(frontMatterValue(body, 'notion-edited'), '2026-11-01T10:00:00.000Z');
      expect(body, endsWith('---\n# Home\n\nWelcome.\n\n[[Plans]]\n\n[[Tasks]]\n'));
      expect(it.pictures.keys, ['p1.png']);
      expect(it.at('$root/Home/index.md')!.createdAt, DateTime.parse('2026-10-01T10:00:00.000Z').millisecondsSinceEpoch);
    });

    test('links between pages are wiki links by unique titles; a twin title is told apart', () {
      expect(it.at('$root/Home/Plans/index.md')!.body, contains('See [[Notes]] and [[Write the doc]]\n\n[[Q1]]'));
      expect(it.at('$root/Plans 2.md')!.body, contains('title: "Plans 2"'));
      expect(it.at('$root/Plans 2.md')!.body, contains('# Plans 2'));
    });

    test('a database is a notebook of its rows, with a live table and a board by its status', () {
      final index = it.at('$root/Home/Tasks/index.md')!.body;
      expect(isBookBody(index), isTrue);
      expect([for (final c in chaptersOf(index)) c.title], ['Write the doc', 'Review: final']);
      expect(index, contains('```query\nfrom: [[Tasks]]\nshow: table\ncolumns: title, status, due-date, tags, owner, points, blocked-by\nsort: title\n```'));
      expect(index, contains('```query\nfrom: [[Tasks]]\nshow: board\ngroup: status\n```'));
    });

    test('a row’s properties are its front matter, in the keys the queries read', () {
      final row = it.at('$root/Home/Tasks/Write the doc.md')!.body;
      expect(row, contains('status: In progress\ndue-date: 2026-11-10\ndue-date-end: 2026-11-12\ntags: [Big-launch, docs]\nowner: [Sam Ortiz]\npoints: 3\nblocked-by: ["[[Review: final]]"]\n'));
      expect(row, isNot(contains('created:')));
      expect(row, endsWith('# Write the doc\n\nDraft it.\n'));
      final other = it.at('$root/Home/Tasks/Review final.md')!.body;
      expect(other, contains('status: Done\n'));
      expect(other, isNot(contains('points:')));
    });

    test('everything is filed in the workspace, and the report says what stays in Notion', () {
      final filed = it.workspaces.value.of;
      for (final id in report.noteIds) {
        expect(filed[id], report.groupId);
      }
      expect(importSkippedSaid(report), contains('comments, which stay in Notion'));
    });

    test('every list was read a page at a time, and a sub-page’s blocks are never read as its parent’s', () {
      expect(notion.asked.where((a) => a == 'POST search').length, 4);
      expect(notion.asked.where((a) => a.startsWith('GET blocks/${dashed(home)}/children')).length, 2);
      expect(notion.asked.where((a) => a.contains('start_cursor=2')), isNotEmpty);
    });
  });

  group('again', () {
    test('a second run updates what changed in place, leaves the rest unread, and makes what is new', () async {
      final it = ImportHarness();
      addTearDown(it.dispose);
      final notion = workspace();
      final first = await importNotion(notion.reader(), it.target());
      final ids = {for (final note in it.library.value) note.path: note.id};
      final into = it.workspaces.value.list.firstWhere((w) => w.id == first.groupId);

      notion.add(page(notes, 'Notes', created: '2026-09-01T10:00:00.000Z', edited: '2026-11-03T10:00:00.000Z'), children: [block('to_do', rich: 'Buy oat milk')]);
      notion.add(page(idOf(99), 'Fresh'), children: [block('paragraph', rich: 'New.')]);
      notion.asked.clear();
      final second = await importNotion(notion.reader(), it.target(), into: into);

      expect(it.library.value.length, 9);
      expect(second.groupId, first.groupId);
      expect(second.madeGroup, isFalse);
      expect((second.notes, second.updated), (1, 1));
      expect(it.at('$root/Notes.md')!.id, ids['$root/Notes.md']);
      expect(it.at('$root/Notes.md')!.body, contains('- [ ] Buy oat milk'));
      expect(it.at('$root/Fresh.md'), isNotNull);
      // Unchanged pages were not asked for their blocks.
      expect(notion.asked.where((a) => a.startsWith('GET blocks/${dashed(home)}')), isEmpty);
      expect(notion.asked.where((a) => a.startsWith('GET blocks/${dashed(notes)}')), isNotEmpty);
      expect(importDoneSaid(second), contains('1 note updated'));
    });

    test('a note moved since keeps its place; a page that gains a sub-page becomes a folder', () async {
      final it = ImportHarness();
      addTearDown(it.dispose);
      final notion = workspace();
      final first = await importNotion(notion.reader(), it.target());
      final into = it.workspaces.value.list.firstWhere((w) => w.id == first.groupId);
      final notesNote = it.at('$root/Notes.md')!;
      await it.library.apply(notesNote.copyWith(path: () => 'Inbox/Notes.md'));

      notion.add(page(twin, 'Plans', created: '2026-10-20T10:00:00.000Z', edited: '2026-11-03T10:00:00.000Z'), children: [block('paragraph', rich: 'The other one.')]);
      notion.add(page(idOf(98), 'Under twin', parent: twin), children: const []);
      notion.add(page(notes, 'Notes', created: '2026-09-01T10:00:00.000Z', edited: '2026-11-03T11:00:00.000Z'), children: const []);
      await importNotion(notion.reader(), it.target(), into: into);

      expect(it.at('Inbox/Notes.md')!.id, notesNote.id);
      expect(it.at('$root/Plans 2.md'), isNull);
      expect(it.at('$root/Plans 2/index.md'), isNotNull);
      expect(it.at('$root/Plans 2/Under twin.md'), isNotNull);
    });
  });

  group('the reader', () {
    test('waits out a 429 for as long as Retry-After says, and a 503 doubling, then goes on', () async {
      final notion = FakeNotion(pageSize: 100)..add(page(notes, 'Notes'));
      notion.script.addAll([
        (status: 429, body: {'message': 'slow down'}, headers: {'retry-after': '7'}),
        (status: 503, body: null, headers: const <String, String>{}),
      ]);
      final waits = <Duration>[];
      final reader = notion.reader(waits: waits);
      final found = await reader.search();
      expect(found.length, 1);
      expect(waits.where((w) => w >= const Duration(seconds: 1)), [const Duration(seconds: 7), const Duration(seconds: 2)]);
      expect(reader.limited, 1);
    });

    test('paces its requests a third of a second apart at least', () async {
      final notion = FakeNotion(pageSize: 1);
      for (var n = 1; n <= 3; n += 1) {
        notion.add(page(idOf(n), 'Page $n'));
      }
      final waits = <Duration>[];
      var now = DateTime(2026, 11, 4);
      final reader = NotionReader(notion.call, sleep: (wait) async {
        waits.add(wait);
        now = now.add(wait);
      }, clock: () => now);
      expect((await reader.search()).length, 3);
      expect(reader.requests, 3);
      expect(waits, [notionGap, notionGap]);
    });

    test('says a refusal in words, and a sign-out as one', () async {
      final notion = FakeNotion()..script.add((status: 401, body: {'message': 'API token is invalid.'}, headers: const <String, String>{}));
      await expectLater(notion.reader().search(), throwsA(isA<NotionImportFailure>().having((f) => f.status, 'status', 401).having((f) => f.message, 'message', contains('Sign in again'))));
    });

    test('counts what is shared', () async {
      expect(await notionShared(workspace().reader()), (pages: 7, databases: 1));
    });

    test('reads an id from a link into Notion and no other', () {
      expect(notionLinkId('https://www.notion.so/team/Plans-$idA?pvs=4'), idA);
      expect(notionLinkId('/${dashed(idA)}'), idA);
      expect(notionLinkId('https://example.com/$idA'), isNull);
    });
  });
}
