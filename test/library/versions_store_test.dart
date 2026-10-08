import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/versions_store.dart';

import 'support.dart';

/// Where a note's versions file is kept ([VersionsStore]). The web's `core/versions/store.ts` has no test file of
/// its own; these are the rules its header and its two functions state, and the Rust's own cases for the file
/// beside the note (src-tauri/src/library/versions.rs).
const String file = '# Ghost.md versions 1\n';

void main() {
  late FakeCore core;
  late MemoryStored device;
  late VersionsStore versions;

  setUp(() async {
    core = FakeCore();
    device = MemoryStored();
    versions = VersionsStore(core.invoke, kept: device);
    addTearDown(versions.dispose);
    await core.invoke('create_note', {'id': 'n1', 'body': '# Plan\nwords', 'source': 'editor'});
  });

  group('a note’s versions file, with a library', () {
    test('is kept beside the note, not on the device, and read back from there', () async {
      expect(await versions.readVersionsFile('n1'), isNull);
      await versions.writeVersionsFile('n1', file);
      expect(core.versionsFiles, {'Inbox/Plan.versions': file});
      expect(device.getItem('glyph-versions-n1'), isNull);
      expect(await versions.readVersionsFile('n1'), file);
    });

    test('goes where its note goes, and with it', () async {
      // versions.rs `the_versions_file_sits_beside_its_note_and_goes_where_it_goes`.
      await versions.writeVersionsFile('n1', file);
      await core.invoke('update_note', {'id': 'n1', 'body': '# Launch plan\nwords', 'expectedRevision': 1});
      expect(core.versionsFiles.keys, ['Inbox/Launch plan.versions']);
      expect(await versions.readVersionsFile('n1'), file);
      await core.invoke('delete_note', {'id': 'n1'});
      expect(core.versionsFiles, isEmpty);
      expect(await versions.readVersionsFile('n1'), isNull);
    });

    test('is kept on the device for a note the library has no file to keep it beside', () async {
      await versions.writeVersionsFile('nobody', file);
      expect(core.versionsFiles, isEmpty);
      expect(device.getItem('glyph-versions-nobody'), file);
      // Read from the device while the library has none.
      expect(await versions.readVersionsFile('nobody'), file);
      expect(device.getItem('glyph-versions-nobody'), file);
    });

    test('moves beside its note the first time it is read with a library that can keep it there', () async {
      // Kept by the app before there was a library: a history begun without one is not lost.
      device.setItem('glyph-versions-n1', file);
      expect(await versions.readVersionsFile('n1'), file);
      expect(core.versionsFiles, {'Inbox/Plan.versions': file});
      expect(device.getItem('glyph-versions-n1'), isNull);
      // The library's own wins from then on.
      await core.invoke('versions_write', {'id': 'n1', 'text': '$file+ one more\n'});
      device.setItem('glyph-versions-n1', 'stale');
      expect(await versions.readVersionsFile('n1'), '$file+ one more\n');
    });

    test('writes a draft as a file to keep its versions', () async {
      // versions.rs `a_draft_is_written_as_a_file_to_keep_its_versions_and_a_missing_note_keeps_none`.
      await core.invoke('create_note', {'id': 'd1', 'body': '', 'source': 'editor'});
      await versions.writeVersionsFile('d1', file);
      expect(core.versionsFiles, {'Inbox/Untitled.versions': file});
      expect(device.getItem('glyph-versions-d1'), isNull);
    });
  });

  group('a note’s versions file, with no library', () {
    test('is kept on the device, under the note’s own key', () async {
      final local = VersionsStore(null, kept: device);
      addTearDown(local.dispose);
      expect(await local.readVersionsFile('n1'), isNull);
      await local.writeVersionsFile('n1', file);
      expect(device.getItem('glyph-versions-n1'), file);
      expect(await local.readVersionsFile('n1'), file);
      expect(versionsKey('n1'), 'glyph-versions-n1');
    });
  });

  group('what sync owes the account', () {
    test('is every note whose versions file changed here, once each, until it is sent', () async {
      expect(versions.unsentVersions(), isEmpty);
      await versions.writeVersionsFile('n1', file);
      await versions.writeVersionsFile('n1', '$file+\n');
      await versions.writeVersionsFile('nobody', file);
      expect(versions.unsentVersions(), ['n1', 'nobody']);
      expect(device.getItem('glyph-versions-unsent'), '["n1","nobody"]');
      versions.sentVersions('n1');
      versions.sentVersions('n1');
      expect(versions.unsentVersions(), ['nobody']);
    });

    test('is not a file that sync itself wrote', () async {
      await versions.writeVersionsFile('n1', file, owed: false);
      expect(versions.unsentVersions(), isEmpty);
      expect(core.versionsFiles, {'Inbox/Plan.versions': file});
    });

    test('reads rubbish under its key as nothing owed', () {
      device.setItem('glyph-versions-unsent', '{"not":"a list"}');
      expect(versions.unsentVersions(), isEmpty);
      device.setItem('glyph-versions-unsent', '["n1", 7, null, "n2"]');
      expect(versions.unsentVersions(), ['n1', 'n2']);
    });
  });

  group('a change to a versions file', () {
    test('is heard with the note’s id, whoever wrote it', () async {
      final heard = <String>[];
      final listening = versions.changed.listen(heard.add);
      addTearDown(listening.cancel);
      await versions.writeVersionsFile('n1', file);
      await versions.writeVersionsFile('nobody', file, owed: false);
      expect(heard, ['n1', 'nobody']);
    });
  });
}
