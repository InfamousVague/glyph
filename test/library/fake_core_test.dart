import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/core.dart';

import 'fake_core.dart';

/// What the fake core holds to (test/library/fake_core.dart), each case one the Rust's own tests or its code state
/// (src-tauri/src/library/mod.rs, commands.rs): so a test that passes over the fake is a claim about the real one
/// that can be checked there, case by case.
void main() {
  late FakeCore core;
  setUp(() => core = FakeCore());

  Future<Map<String, Object?>?> ask(String command, [Map<String, Object?> args = const {}]) async => (await core.invoke(command, args)) as Map<String, Object?>?;
  Future<List<Object?>> list() async => (await core.invoke('list_notes')) as List<Object?>;

  test('a blank new note is a draft: it answers by id, has no path, and is not in the list', () async {
    final draft = (await ask('create_note', {'id': 'd1', 'body': '', 'source': 'capture'}))!;
    expect(draft.containsKey('path'), isFalse);
    expect((draft['revision'], draft['source']), (1, 'capture'));
    expect(await list(), isEmpty);
    expect((await ask('get_note', {'id': 'd1'}))!['id'], 'd1');
    expect(core.files, isEmpty);
    // Its id is taken all the same.
    await expectLater(core.invoke('create_note', {'id': 'd1', 'body': 'x', 'source': 'editor'}), throwsA(isA<CoreError>()));
  });

  test('a draft’s first words write Inbox/<Title>.md, keeping when it was made and where it came from', () async {
    await ask('create_note', {'id': 'd1', 'body': '', 'source': 'capture'});
    core.now = 4000;
    final written = (await ask('update_note', {'id': 'd1', 'body': '# Groceries', 'expectedRevision': 1}))!;
    expect((written['path'], written['createdAt'], written['updatedAt'], written['source'], written['revision']), ('Inbox/Groceries.md', 1000, 4000, 'capture', 2));
    expect(await list(), hasLength(1));
  });

  test('a draft pinned becomes a file even without words', () async {
    await ask('create_note', {'id': 'd1', 'body': '', 'source': 'editor'});
    final pinned = (await ask('set_note_starred', {'id': 'd1', 'starred': true}))!;
    expect((pinned['path'], pinned['starred']), ('Inbox/Untitled.md', true));
    // And it is no longer one to take back to a draft.
    final still = (await ask('update_note', {'id': 'd1', 'body': '', 'expectedRevision': 1}))!;
    expect(still['path'], 'Inbox/Untitled.md');
  });

  test('a title change renames the file in its folder, and a second note of the same title is numbered', () async {
    await ask('create_note', {'id': 'a', 'body': '# Plan', 'source': 'editor'});
    final b = (await ask('create_note', {'id': 'b', 'body': '# Plan', 'source': 'editor'}))!;
    expect(b['path'], 'Inbox/Plan 2.md');
    final renamed = (await ask('update_note', {'id': 'a', 'body': '# Launch: the *plan*?', 'expectedRevision': 1}))!;
    expect(renamed['path'], 'Inbox/Launch the plan.md');
    // A note already named for its title, with a number, keeps its name.
    final same = (await ask('update_note', {'id': 'b', 'body': '# Plan\n\nmore', 'expectedRevision': 1}))!;
    expect(same['path'], 'Inbox/Plan 2.md');
  });

  test('the list is newest modified first, ties by id, and carries no phrases', () async {
    core
      ..seed('b', '# B', at: 10)
      ..seed('a', '# A', at: 10)
      ..seed('c', '# C', at: 30);
    await ask('set_note_recording', {
      'id': 'c',
      'recordingMs': 400,
      'segments': [
        {'text': 'hello', 'startMs': 0, 'endMs': 400},
      ],
    });
    final notes = await list();
    expect([for (final n in notes) (n as Map)['id']], ['c', 'a', 'b']);
    expect((notes.first as Map)['segments'], isNull);
    expect((notes.first as Map)['recordingMs'], 400);
    expect((await ask('get_note', {'id': 'c'}))!['segments'], hasLength(1));
  });

  test('a save that changes nothing keeps the modified time, and still counts the revision', () async {
    await ask('create_note', {'id': 'a', 'body': 'words', 'source': 'editor'});
    core.now = 5000;
    final again = (await ask('update_note', {'id': 'a', 'body': 'words', 'expectedRevision': 1}))!;
    expect((again['updatedAt'], again['revision']), (1000, 2));
  });

  test('store_apply moves a note to a free library path, and to nowhere it should not go', () async {
    core.seed('a', '# A', at: 10);
    Future<Object?> to(String path) async {
      final note = (await ask('get_note', {'id': 'a'}))!;
      return (await ask('store_apply', {'note': {...note, 'path': path}}))!['path'];
    }

    expect(await to('workspaces/Home/A.md'), 'workspaces/Home/A.md');
    // library/mod.rs `library_path`: relative, `.md`, no dot folders or `..`.
    expect(await to('../A.md'), 'workspaces/Home/A.md');
    expect(await to('.glyph/A.md'), 'workspaces/Home/A.md');
    expect(await to('workspaces/Home/A.txt'), 'workspaces/Home/A.md');
    expect((await ask('get_note', {'id': 'a'}))!['updatedAt'], 10);
  });

  test('a note that is gone answers null to a pin, false to a second delete, and refuses a save', () async {
    expect(await ask('set_note_starred', {'id': 'gone', 'starred': true}), isNull);
    expect(await core.invoke('delete_note', {'id': 'gone'}), isFalse);
    await expectLater(core.invoke('update_note', {'id': 'gone', 'body': 'x', 'expectedRevision': 1}), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'the note was deleted or changed')));
  });
}
