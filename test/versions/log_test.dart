import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/versions_file.dart';
import 'package:ghost_md/core/versions_log.dart';
import 'package:ghost_md/core/versions_record.dart';
import 'package:ghost_md/core/versions_store.dart';
import 'package:ghost_md/core/workspaces.dart';

/// The changes across many notes (lib/core/versions_log.dart), for an organization's audit log: each note's
/// versions as a line each, every note's together newest first, read a few at a time and read again as a note's
/// file changes. The web's `src/app/core/versions/log.test.tsx`, case for case, with [ChangesAcross] where the page
/// draws a component round its hook.
const day = 86400000;

void main() {
  late VersionsStore store;
  late VersionsRecord record;

  setUp(() {
    store = VersionsStore(null, kept: MemoryStored());
    record = VersionsRecord(store: store, preferences: PreferencesStore()..startWithoutStorage(), workspaces: WorkspaceStore());
  });
  tearDown(() => store.dispose());

  List<String> names(ChangesRead read) => [for (final c in read.changes) '${c.noteId}${c.n}'];

  /// Waits for [done] to hold of what [across] shows (`waitUntil`).
  Future<void> waitUntil(ChangesAcross across, bool Function(ChangesRead read) done) async {
    // By the clock, not by a count of turns: a read is as slow as the machine is busy.
    final waited = Stopwatch()..start();
    while (!done(across.value) && waited.elapsed < const Duration(seconds: 20)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(done(across.value), isTrue, reason: 'still ${names(across.value)}, read ${across.value.read} of ${across.value.total}');
  }

  group('a note’s changes', () {
    test('are its versions, each with its counts, the first line it changed, and whether it began the note', () {
      final file = writeFile('n1', const [
        VersionWords(at: 1000, by: 'matt', text: '# Plan\n- book the venue'),
        VersionWords(at: 2000, by: 'sam', text: '# Plan\n- book the venue (done)\n- send invites', label: 'Before the review'),
        VersionWords(at: 3000, by: 'sam', text: '# Plan\n- book the venue (done)\n- send invites', label: 'Named only'),
      ]);
      expect(changesIn('n1', readFile(file)!.versions), const [
        Change(noteId: 'n1', n: 1, at: 1000, by: 'matt', added: 2, removed: 0, peek: (kind: 'add', text: '# Plan'), first: true),
        Change(noteId: 'n1', n: 2, at: 2000, by: 'sam', label: 'Before the review', added: 2, removed: 1, peek: (kind: 'del', text: '- book the venue'), first: false),
        Change(noteId: 'n1', n: 3, at: 3000, by: 'sam', label: 'Named only', added: 0, removed: 0, peek: null, first: false),
      ]);
    });

    test('are read from the note’s file, with how many versions could not be', () async {
      await record.keepVersion('n2', 'Milk', now: 1000);
      await record.keepVersion('n2', 'Milk\nEggs', now: 2000);
      final read = await changesOf(record, 'n2');
      expect(read.damaged, 0);
      expect([for (final c in read.changes) (c.n, c.by, c.added, c.peek?.text)], [(1, 'me', 1, 'Milk'), (2, 'me', 1, 'Eggs')]);
      final nobody = await changesOf(record, 'nobody');
      expect(nobody.changes, isEmpty);
      expect(nobody.damaged, 0);
    });

    test('order newest first, and the same moment by note and then the later version', () {
      Change at(String noteId, int n, int when) => Change(noteId: noteId, n: n, at: when, by: 'me', added: 0, removed: 0, peek: null, first: n == 1);
      final sorted = [at('b', 1, 5), at('a', 2, 5), at('a', 1, 5), at('c', 1, 9), at('a', 3, 1)]..sort(newestFirst);
      expect([for (final c in sorted) '${c.noteId}${c.n}'], ['c1', 'a2', 'a1', 'b1', 'a3']);
    });
  });

  group('the changes across notes', () {
    test('come in as the files are read, every note’s together newest first, and a note that leaves the set goes with them', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await record.keepVersion('a', '# Roadmap', now: now - 2 * day);
      await record.keepVersion('a', '# Roadmap\n- ship', now: now - 60000);
      await record.keepVersion('b', '# Standup', now: now - day);
      final across = ChangesAcross(record, ['a', 'b', 'c']);
      addTearDown(across.dispose);
      // Nothing is read yet, and it says of how many.
      expect(across.value, const ChangesRead(total: 3));
      await waitUntil(across, (read) => read.read == 3);
      expect(across.value.total, 3);
      expect(across.value.damaged, 0);
      expect(names(across.value), ['a2', 'b1', 'a1']);
      // A note unfiled from the workspace: its changes go, and the count with them.
      across.watch(['b', 'c']);
      await waitUntil(across, (read) => names(read).join() == 'b1');
      expect(across.value.read, 2);
      expect(across.value.total, 2);
    });

    test('read a note again when its file changes here, and only that note', () async {
      await record.keepVersion('a', '# Roadmap', now: 1000);
      final across = ChangesAcross(record, ['a', 'b']);
      addTearDown(across.dispose);
      await waitUntil(across, (read) => read.read == 2);
      expect(across.value.changes, hasLength(1));
      await record.keepVersion('b', '# Standup', now: 2000);
      await waitUntil(across, (read) => names(read).join(' ') == 'b1 a1');
      // A file of someone else's changing is nothing to the log.
      var told = 0;
      across.addListener(() => told += 1);
      await store.writeVersionsFile('elsewhere', writeFile('elsewhere', const [VersionWords(at: 3000, by: 'me', text: 'x')]));
      await pumpEventQueue();
      expect(across.value.changes, hasLength(2));
      expect(told, 0);
    });

    test('is nothing for no notes, and does not wait', () {
      final across = ChangesAcross(record);
      addTearDown(across.dispose);
      expect(across.value, const ChangesRead());
    });

    test('reads many notes a few at a time, counts a file that cannot be read as a note with no changes, and adds up the damage', () async {
      // Not a case of the web's: its three notes never fill one batch.
      final ids = [for (var i = 0; i < 15; i += 1) 'n$i'];
      for (final id in ids) {
        await record.keepVersion(id, 'first of $id', now: 1000);
        await record.keepVersion(id, 'first of $id\nsecond', now: 2000);
      }
      final broken = (await store.readVersionsFile('n3'))!.replaceFirst('  +second', '  +tampered');
      await store.writeVersionsFile('n3', broken, owed: false);
      var reading = 0, most = 0;
      final slow = VersionsStore((command, [args = const {}]) async {
        if (command != 'versions_read') return false;
        reading += 1;
        most = reading > most ? reading : most;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        reading -= 1;
        if (args['id'] == 'n7') throw StateError('The library would not read.');
        return store.readVersionsFile(args['id'] as String);
      }, kept: MemoryStored());
      addTearDown(slow.dispose);
      final across = ChangesAcross(VersionsRecord(store: slow, preferences: PreferencesStore()..startWithoutStorage(), workspaces: WorkspaceStore()), ids);
      addTearDown(across.dispose);
      await waitUntil(across, (read) => read.read == 15);
      expect(most, 6);
      expect(across.value.damaged, 1);
      expect(across.value.changes, hasLength(13 * 2 + 1));
    });
  });
}
