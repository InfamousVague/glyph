// The Rust core through its real C functions, on the Mac: lib/core/native/ghost_core.dart and ghost_worker.dart
// over native/target/debug/libghost_core.dylib (tool/build-native.sh host). What the commands themselves do is
// Rust's to test (native/src/dispatch.rs, and the library's own tests that came with it); this holds the crossing:
// the worker isolate, the JSON either way, errors and panics as CoreError, and that what lands on disk is what
// the Tauri app writes.
//
// One process has one core (dispatch.rs `CORE`), so every test here shares one data directory, opened once.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/native/ghost_core.dart';

const _library = 'native/target/debug/libghost_core.dylib';

Future<CoreError> _refused(Future<Object?> asked) async {
  try {
    await asked;
  } on CoreError catch (e) {
    return e;
  }
  fail('the core answered where it should have refused');
}

void main() {
  final built = File(_library).existsSync();
  final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $_library)';

  late Directory root;
  late String data, cache;
  late GhostCore core;

  File inData(String path) => File('$data/$path');
  Map<String, Object?> note(Object? answer) => (answer as Map).cast<String, Object?>();

  setUpAll(() async {
    if (!built) return;
    // Resolved, as the phone's directory is: /var is a link on a Mac, and the core answers paths as it was told.
    root = Directory(Directory.systemTemp.createTempSync('ghost-core-test-').resolveSymbolicLinksSync());
    data = '${root.path}/data';
    cache = '${root.path}/cache';
    core = await GhostCore.open(libraryPath: File(_library).absolute.path);
    await core.init(dataDir: data, cacheDir: cache);
  });

  tearDownAll(() async {
    if (!built) return;
    await core.close();
    root.deleteSync(recursive: true);
  });

  test('a library that is not there is a CoreError, not a crash', () async {
    await expectLater(
      GhostCore.open(libraryPath: '/nowhere/libghost_core.dylib'),
      throwsA(isA<CoreError>().having((e) => e.message, 'message', startsWith('Ghost.md\'s core could not be loaded:'))),
    );
  });

  test('init makes the library the Tauri app would, and may be asked twice', () async {
    expect(inData('Library/.glyph/index.sqlite').existsSync(), isTrue);
    expect(Directory('$data/Library/.glyph/notes').existsSync(), isTrue);
    final manifest = jsonDecode(inData('Library/.glyph/library.json').readAsStringSync()) as Map;
    expect(manifest['version'], 1);
    expect(manifest['created'], matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$')));

    await core.init(dataDir: data, cacheDir: cache);
    final other = await _refused(core.invoke('init', {'dataDir': '$data-2', 'cacheDir': cache}));
    expect(other.message, startsWith('Ghost.md\'s core is already open on $data'));
    expect(Directory('$data-2').existsSync(), isFalse);

    final where = note(await core.invoke('library_root'));
    expect(where, {'kind': 'app', 'path': null, 'name': null, 'reachable': true, 'notes': isA<int>(), 'own': '$data/Library'});
  }, skip: skip);

  test('a note is created, listed, read, and updated only at the revision it was read at', () async {
    final id = await core.newId();
    expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));

    final made = note(await core.invoke('create_note', {'id': id, 'body': '# Weekend trip\n\nBook the cabin.\n', 'source': 'capture'}));
    expect(made['id'], id);
    expect(made['revision'], 1);
    expect(made['path'], 'Inbox/Weekend trip.md');
    expect(made['source'], 'capture');
    expect(made['starred'], false);
    expect(made['archivedAt'], isNull);

    // The file: the library's front matter (a source only when it is not the editor's), then the words as given.
    final text = inData('Library/Inbox/Weekend trip.md').readAsStringSync();
    expect(text, startsWith('---\nsource: capture\nid: $id\ncreated: '));
    expect(text, endsWith('Z\n---\n# Weekend trip\n\nBook the cabin.\n'));
    expect(inData('Library/.glyph/notes/$id.json').existsSync(), isFalse, reason: 'no recording, no sidecar');

    final again = await _refused(core.invoke('create_note', {'id': id, 'body': 'x', 'source': 'editor'}));
    expect(again.message, 'the note id already exists');

    final listed = (await core.invoke('list_notes') as List).map(note).singleWhere((n) => n['id'] == id);
    expect(listed['body'], '# Weekend trip\n\nBook the cabin.\n');
    expect(listed['segments'], isNull);

    final changed = note(await core.invoke('update_note', {'id': id, 'body': '# Weekend away\n\nBook the cabin.\n', 'expectedRevision': 1}));
    expect(changed['revision'], 2);
    expect(changed['path'], 'Inbox/Weekend away.md', reason: 'a title change renames the file');
    expect(inData('Library/Inbox/Weekend trip.md').existsSync(), isFalse);
    expect(inData('Library/Inbox/Weekend away.md').readAsStringSync(), startsWith('---\nsource: capture\nid: $id\ncreated: '));

    final stale = await _refused(core.invoke('update_note', {'id': id, 'body': 'late', 'expectedRevision': 1}));
    expect(stale.message, 'the note was deleted or changed');
    expect(note(await core.invoke('get_note', {'id': id}))['body'], '# Weekend away\n\nBook the cabin.\n');
    expect(await core.invoke('get_note', {'id': 'nobody'}), isNull);
  }, skip: skip);

  test('a pin and an archive are front matter, and neither is an edit', () async {
    final id = await core.newId();
    final made = note(await core.invoke('create_note', {'id': id, 'body': '# Pinned\n', 'source': 'editor'}));
    final file = inData('Library/Inbox/Pinned.md');
    expect(file.readAsStringSync(), startsWith('---\nid: $id\ncreated: '), reason: 'the editor is no source');
    expect(file.readAsStringSync(), isNot(contains('source:')));

    final pinned = note(await core.invoke('set_note_starred', {'id': id, 'starred': true}));
    expect(pinned['starred'], true);
    expect(pinned['updatedAt'], made['updatedAt']);
    expect(pinned['revision'], made['revision']);
    expect(file.readAsStringSync(), contains('\npinned: true\n'));

    final archived = note(await core.invoke('set_note_archived', {'id': id, 'archived': true}));
    expect(archived['archivedAt'], isA<int>());
    expect(file.readAsStringSync(), contains(RegExp(r'\narchived: \d{4}-\d\d-\d\dT[\d:.]+Z\n')));

    await core.invoke('set_note_starred', {'id': id, 'starred': false});
    final back = note(await core.invoke('set_note_archived', {'id': id, 'archived': false}));
    expect(back['archivedAt'], isNull);
    expect(file.readAsStringSync(), allOf(isNot(contains('pinned')), isNot(contains('archived'))));
    expect(await core.invoke('set_note_starred', {'id': 'nobody', 'starred': true}), isNull);
  }, skip: skip);

  test('store_apply moves a note to its folder and keeps the sidecar it was read with', () async {
    final id = await core.newId();
    await core.invoke('create_note', {'id': id, 'body': '# Standup\n\nSpoken.\n', 'source': 'capture'});
    final phrases = [
      {'text': 'Spoken.', 'startMs': 0, 'endMs': 900},
    ];
    await core.invoke('set_note_recording', {'id': id, 'recordingMs': 900, 'segments': phrases});
    final sidecar = inData('Library/.glyph/notes/$id.json');
    expect(jsonDecode(sidecar.readAsStringSync()), {'recordingMs': 900, 'segments': phrases});

    // The trap docs/STAGE3.md names: apply what get_note answered (it carries the sidecar), never a list's row.
    final whole = note(await core.invoke('get_note', {'id': id}));
    expect(whole['segments'], phrases);
    final moved = note(await core.invoke('store_apply', {'note': {...whole, 'path': 'Work/Standup.md', 'starred': true}}));
    expect(moved['path'], 'Work/Standup.md');
    expect(moved['starred'], true);
    expect(moved['createdAt'], whole['createdAt']);
    expect(inData('Library/Inbox/Standup.md').existsSync(), isFalse);
    expect(inData('Library/Work/Standup.md').readAsStringSync(), contains('\npinned: true\n'));
    expect(jsonDecode(sidecar.readAsStringSync()), {'recordingMs': 900, 'segments': phrases});
    expect(note(await core.invoke('get_note', {'id': id}))['segments'], phrases);

    final bad = await _refused(core.invoke('store_apply', {'note': {...whole, 'segments': [{'text': 'x', 'startMs': 9, 'endMs': 1}]}}));
    expect(bad.message, 'segment 0 ends before it starts');
  }, skip: skip);

  test('a versions file is kept beside its note, and both go with a delete', () async {
    final id = await core.newId();
    await core.invoke('create_note', {'id': id, 'body': '# Drafted\n', 'source': 'editor'});
    expect(await core.invoke('versions_read', {'id': id}), isNull);
    const versions = '{"v":1,"versions":[{"at":1,"body":"# Draft\\n"}]}';
    expect(await core.invoke('versions_write', {'id': id, 'text': versions}), true);
    expect(await core.invoke('versions_read', {'id': id}), versions);
    expect(inData('Library/Inbox/Drafted.versions').readAsStringSync(), versions);
    expect(await core.invoke('versions_write', {'id': 'nobody', 'text': versions}), false);

    // What a delete takes besides: the note's recording and write-up files, by its id.
    for (final kept in ['recordings/$id.wav', 'jobs/$id.progress', 'jobs/$id.json']) {
      inData(kept)
        ..createSync(recursive: true)
        ..writeAsStringSync('bytes');
    }
    expect(await core.invoke('delete_note', {'id': id}), true);
    expect(inData('Library/Inbox/Drafted.md').existsSync(), isFalse);
    expect(inData('Library/Inbox/Drafted.versions').existsSync(), isFalse);
    expect(inData('recordings/$id.wav').existsSync() || inData('jobs/$id.progress').existsSync() || inData('jobs/$id.json').existsSync(), isFalse);
    expect(await core.invoke('get_note', {'id': id}), isNull);
    expect(await core.invoke('delete_note', {'id': id}), false, reason: 'already gone is not an error');
  }, skip: skip);

  test('what the core refuses is a CoreError with its sentence', () async {
    expect((await _refused(core.invoke('open_the_pod_bay_doors'))).message, 'Ghost.md\'s core has no command named open_the_pod_bay_doors.');
    expect((await _refused(core.invoke('get_note'))).message, startsWith('invalid args for command `get_note`: missing field `id`'));
    expect((await _refused(core.invoke('update_note', {'id': 'n', 'body': 'x', 'expectedRevision': 'one'}))).message, startsWith('invalid args for command `update_note`:'));
    // Arguments that are not JSON never reach Rust.
    expect((await _refused(core.invoke('get_note', {'id': double.nan}))).message, startsWith('Ghost.md\'s core could not be asked get_note:'));
    expect((await _refused(core.invoke('get_note', {'id': Object()}))).message, startsWith('Ghost.md\'s core could not be asked get_note:'));
    expect('${const CoreError('a sentence')}', 'a sentence');
  }, skip: skip);

  test('a panic in Rust is a CoreError, and the library answers afterwards', () async {
    final id = await core.newId();
    await core.invoke('create_note', {'id': id, 'body': '# Survives\n', 'source': 'editor'});
    // `test_panic` (dispatch.rs, the `test-hooks` feature) panics holding the library's lock.
    final died = await _refused(core.invoke('test_panic'));
    if (died.message.contains('no command named')) {
      markTestSkipped('this library was built without --features test-hooks (tool/build-native.sh host turns it on)');
      return;
    }
    expect(died.message, 'Ghost.md\'s core stopped in the middle of that: a command dies with the lock');
    expect(note(await core.invoke('get_note', {'id': id}))['body'], '# Survives\n');
    expect(note(await core.invoke('update_note', {'id': id, 'body': '# Survives\n\nStill.\n', 'expectedRevision': 1}))['revision'], 2);
  }, skip: skip);

  test('200 commands asked at once are each answered with their own answer', () async {
    final ids = [for (var i = 0; i < 100; i++) await core.newId()];
    // A create and a read of each, all in flight together; the queue keeps each read behind its create.
    final asked = <Future<Object?>>[
      for (final (i, id) in ids.indexed) ...[
        core.invoke('create_note', {'id': id, 'body': '# Many $i\n\nNote $i of a hundred.\n', 'source': 'editor'}),
        core.invoke('get_note', {'id': id}),
      ],
    ];
    expect(asked, hasLength(200));
    final answers = await Future.wait(asked);
    for (final (i, id) in ids.indexed) {
      final made = note(answers[2 * i]), read = note(answers[2 * i + 1]);
      expect(made['id'], id);
      expect(read['id'], id);
      expect(read['body'], '# Many $i\n\nNote $i of a hundred.\n');
      expect(read['path'], 'Inbox/Many $i.md');
    }
    final listed = (await core.invoke('list_notes') as List).map((n) => note(n)['id']).toSet();
    expect(listed.containsAll(ids), isTrue);
    expect(Directory('$data/Library/Inbox').listSync().where((f) => f.path.contains('/Many ')).length, 100);
  }, skip: skip);

  test('a second core in the process finds the library as the first left it, and a closed one refuses', () async {
    final id = await core.newId();
    await core.invoke('create_note', {'id': id, 'body': '# Shared\n', 'source': 'editor'});
    final second = await GhostCore.open(libraryPath: File(_library).absolute.path);
    await second.init(dataDir: data, cacheDir: cache);
    expect(note(await second.invoke('get_note', {'id': id}))['body'], '# Shared\n');
    // Asked before the close, answered before the worker ends.
    final last = second.invoke('get_note', {'id': id});
    await second.close();
    expect(note(await last)['id'], id);
    expect((await _refused(second.invoke('list_notes'))).message, 'Ghost.md\'s core is closed, so it cannot answer list_notes.');
    await second.close();
    expect(note(await core.invoke('get_note', {'id': id}))['id'], id, reason: 'the first is untouched');
  }, skip: skip);
}
