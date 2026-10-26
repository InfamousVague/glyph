// The web build's library (lib/web/web_store.dart): the Rust library's rules, answered by the page over its own
// storage, held to what the phone's core answers for the same commands (tauri/src-tauri/src/library, the cases of
// its tests.rs and mutations.rs the app leans on). Over a shelf in memory, which is what IndexedDB is behind
// lib/web/idb_shelf.dart; reopened from the same shelf where a case is about what a reload keeps.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/web/shelf.dart';
import 'package:ghost_md/web/web_core.dart';
import 'package:ghost_md/web/web_store.dart';

import 'support.dart';

void main() {
  late MemoryShelf shelf;
  late int clock;

  Future<WebStore> open() => WebStore.open(shelf, browserCoreStandIn(), now: () => clock);

  setUp(() {
    shelf = MemoryShelf();
    clock = 1000;
  });

  Future<Map> ask(WebStore store, String command, [Map<String, Object?> args = const {}]) async => await store.call(command, args) as Map;

  test('a new note is named for its title in Inbox, kept across a reload, and the list is newest first', () async {
    final store = await open();
    final made = await ask(store, 'create_note', {'id': 'a', 'body': '# Weekend trip\n\nBook the cabin.', 'source': 'editor'});
    expect(made['path'], 'Inbox/Weekend trip.md');
    expect(made['revision'], 1);
    clock = 2000;
    await store.call('create_note', {'id': 'b', 'body': '# Weekend trip', 'source': 'capture'});
    final again = await open();
    final list = await again.call('list_notes', {}) as List;
    expect([for (final note in list) (note as Map)['id']], ['b', 'a']);
    expect((list.first as Map)['path'], 'Inbox/Weekend trip 2.md');
    expect((list.first as Map)['source'], 'capture');
    await expectLater(again.call('create_note', {'id': 'a', 'body': 'again', 'source': 'editor'}), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'the note id already exists')));
  });

  test('a blank note is a draft with no file, out of the list, until it has words', () async {
    final store = await open();
    final draft = await ask(store, 'create_note', {'id': 'd', 'body': '', 'source': 'editor'});
    expect(draft['path'], isNull);
    expect(await store.call('list_notes', {}), isEmpty);
    expect(await store.call('get_note', {'id': 'd'}), isNotNull);
    final saved = await ask(store, 'update_note', {'id': 'd', 'body': '# Now words', 'expectedRevision': 1});
    expect(saved['path'], 'Inbox/Now words.md');
    expect(saved['revision'], 2);
    // Its words all taken out again, with nothing else set on it: a draft again, and its row gone from the shelf.
    await store.call('update_note', {'id': 'd', 'body': '', 'expectedRevision': 2});
    expect(await store.call('list_notes', {}), isEmpty);
    expect(await shelf.texts(Shelves.notes), isEmpty);
  });

  test('a save from a revision that is not the note\'s is refused, and a deleted note is never written back', () async {
    final store = await open();
    await store.call('create_note', {'id': 'n', 'body': '# One', 'source': 'editor'});
    await store.call('update_note', {'id': 'n', 'body': '# One\n\nmore', 'expectedRevision': 1});
    await expectLater(store.call('update_note', {'id': 'n', 'body': 'stale', 'expectedRevision': 1}), throwsA(isA<CoreError>()));
    await store.call('delete_note', {'id': 'n'});
    await expectLater(store.call('update_note', {'id': 'n', 'body': 'back?', 'expectedRevision': 2}), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'the note was deleted or changed')));
    expect(await store.call('get_note', {'id': 'n'}), isNull);
  });

  test('a title that changes renames the file; the same words again are no write and keep the time', () async {
    final store = await open();
    await store.call('create_note', {'id': 'n', 'body': '# Old', 'source': 'editor'});
    clock = 5000;
    final renamed = await ask(store, 'update_note', {'id': 'n', 'body': '# New', 'expectedRevision': 1});
    expect(renamed['path'], 'Inbox/New.md');
    expect(renamed['updatedAt'], 5000);
    clock = 9000;
    final same = await ask(store, 'update_note', {'id': 'n', 'body': '# New', 'expectedRevision': 2});
    expect(same['updatedAt'], 5000);
    expect(same['revision'], 3);
  });

  test('a pin and an archive are not edits: the note keeps its time', () async {
    final store = await open();
    await store.call('create_note', {'id': 'n', 'body': '# Kept', 'source': 'editor'});
    clock = 7000;
    final pinned = await ask(store, 'set_note_starred', {'id': 'n', 'starred': true});
    expect(pinned['starred'], isTrue);
    expect(pinned['updatedAt'], 1000);
    final archived = await ask(store, 'set_note_archived', {'id': 'n', 'archived': true});
    expect(archived['archivedAt'], 7000);
    expect(archived['updatedAt'], 1000);
    expect(await store.call('set_note_starred', {'id': 'gone', 'starred': true}), isNull);
  });

  test('a note synced in keeps its own times, revision, pin and folder, and its phrases only when asked for by id', () async {
    final store = await open();
    final applied = await ask(store, 'store_apply', {
      'note': {
        'id': 't1', 'body': '# Plan', 'createdAt': 10, 'updatedAt': 20, 'source': 'capture', 'starred': true, 'archivedAt': null,
        'recordingMs': 1500, 'segments': [{'text': 'plan', 'startMs': 0, 'endMs': 900}], 'formatted': null, 'formattedFor': null,
        'formattedModel': null, 'path': 'orgs/Ghost/Clients/t1.md', 'revision': 7,
      },
    });
    expect(applied['path'], 'orgs/Ghost/Clients/t1.md');
    expect([applied['createdAt'], applied['updatedAt'], applied['revision'], applied['starred']], [10, 20, 7, true]);
    final listed = (await store.call('list_notes', {}) as List).single as Map;
    expect(listed['segments'], isNull);
    expect(listed['recordingMs'], 1500);
    expect(((await ask(store, 'get_note', {'id': 't1'}))['segments'] as List).single, {'text': 'plan', 'startMs': 0, 'endMs': 900});
    // A recording the phone would refuse is refused here too.
    await expectLater(
      store.call('store_apply', {'note': {'id': 'bad', 'body': 'x', 'recordingMs': 5, 'segments': [{'text': 'x', 'startMs': 9, 'endMs': 1}]}}),
      throwsA(isA<CoreError>().having((e) => e.message, 'message', 'segment 0 ends before it starts')),
    );
  });

  test('a command\'s write is undone only while the note is what the command left, and is offered again after a reload', () async {
    final store = await open();
    await store.call('create_note', {'id': 'n', 'body': '# List', 'source': 'editor'});
    final request = {'mutationId': 'm1', 'noteId': 'n', 'kind': 'append', 'beforeRevision': 1, 'beforeBody': '# List', 'afterBody': '# List\n- milk', 'source': 'editor'};
    final applied = await ask(store, 'apply_command_mutation', {'request': request});
    expect(applied['status'], 'applied');
    expect((applied['note'] as Map)['body'], '# List\n- milk');
    // The same preview again is a conflict: its base has moved on.
    expect((await ask(store, 'apply_command_mutation', {'request': {...request, 'mutationId': 'm2'}}))['status'], 'conflict');
    final again = await open();
    expect(await again.call('latest_command_mutation', {}), {'mutationId': 'm1', 'noteId': 'n', 'kind': 'append', 'createdAt': 1000});
    final undone = await ask(again, 'undo_command_mutation', {'mutationId': 'm1'});
    expect(undone['status'], 'undone');
    expect((undone['note'] as Map)['body'], '# List');
    expect((await ask(again, 'undo_command_mutation', {'mutationId': 'm1'}))['status'], 'already-undone');
    expect((await ask(again, 'undo_command_mutation', {'mutationId': 'nope'}))['status'], 'not-found');
    await expectLater(again.call('apply_command_mutation', {'request': {...request, 'mutationId': '../x'}}), throwsA(isA<CoreError>()));
  });

  test('pictures are kept by their names, a deleted note takes only the ones no other note shows, and digests are the phone\'s', () async {
    final store = await open();
    final png = base64.encode(Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]));
    await store.call('sync_put_file', {'kind': 'image', 'name': 'mine.png', 'base64': png});
    await store.call('sync_put_file', {'kind': 'image', 'name': 'shared.png', 'base64': png});
    await expectLater(store.call('sync_put_file', {'kind': 'image', 'name': '../x.png', 'base64': png}), throwsA(isA<CoreError>()));
    await store.call('create_note', {'id': 'n1', 'body': '# A\n![](image/mine.png)\n![](image/shared.png)', 'source': 'editor'});
    await store.call('create_note', {'id': 'n2', 'body': '# B\n![](image/shared.png)', 'source': 'editor'});
    expect(await store.call('file_digest', {'kind': 'image', 'name': 'mine.png'}), hasLength(32));
    expect(await store.call('file_path', {'kind': 'image', 'name': 'mine.png'}), isNull);
    await store.call('delete_note', {'id': 'n1'});
    expect(await store.call('file_exists', {'kind': 'image', 'name': 'mine.png'}), isFalse);
    expect(await store.call('read_file', {'kind': 'image', 'name': 'shared.png'}), png);
  });

  test('versions are kept beside a written note only, and a reset empties everything', () async {
    final store = await open();
    expect(await store.call('versions_write', {'id': 'none', 'text': 'v'}), isFalse);
    await store.call('create_note', {'id': 'n', 'body': '# V', 'source': 'editor'});
    expect(await store.call('versions_write', {'id': 'n', 'text': '{"v":1}'}), isTrue);
    expect(await store.call('versions_read', {'id': 'n'}), '{"v":1}');
    expect((await ask(store, 'library_root'))['notes'], 1);
    await store.call('reset_local_data', {'models': false});
    expect(await store.call('list_notes', {}), isEmpty);
    expect(await (await open()).call('list_notes', {}), isEmpty);
  });

  test('the old web app\'s notes are carried in once, with their own times, and a note deleted after does not come back', () async {
    final store = await open();
    final old = oldPageNotes([
      {'id': 'o1', 'body': '# From the old page', 'createdAt': 100, 'updatedAt': 200, 'source': 'editor', 'starred': true},
      {'id': 'o2', 'body': 'no title', 'createdAt': 100, 'updatedAt': 300, 'source': 'capture'},
      {'not': 'a note'},
    ]);
    expect(await carryOldPage(store, shelf, old), 2);
    final carried = await ask(store, 'get_note', {'id': 'o1'});
    expect([carried['updatedAt'], carried['starred'], carried['path']], [200, true, 'Inbox/From the old page.md']);
    await store.call('delete_note', {'id': 'o1'});
    expect(await carryOldPage(await open(), shelf, old), 0);
    expect(await store.call('get_note', {'id': 'o1'}), isNull);
  });

  test('the web core hands the library\'s commands to the store and every other to the worker', () async {
    final asked = <String>[];
    final core = WebCore(await open(), (command, [args = const {}]) async {
      asked.add(command);
      return 'from the worker';
    });
    await core.invoke('create_note', {'id': 'n', 'body': '# Here', 'source': 'editor'});
    expect(await core.invoke('seal', {'key': 1}), 'from the worker');
    expect(await core.invoke('crdt_open', {}), 'from the worker');
    expect(asked, ['seal', 'crdt_open']);
  });
}
