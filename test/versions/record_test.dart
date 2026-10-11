import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/versions_record.dart';
import 'package:ghost_md/core/versions_store.dart';
import 'package:ghost_md/core/workspaces.dart';

/// Which notes keep a version history, and keeping one (lib/core/versions_record.dart): the web's
/// `src/app/core/versions/record.test.ts`, case for case, with the device's own keeping of the file (no core), and
/// the stream that stands for the page's `useVersions`.
void main() {
  late PreferencesStore preferences;
  late WorkspaceStore workspaces;
  late VersionsStore store;
  late VersionsRecord record;
  String? handle;

  setUp(() {
    preferences = PreferencesStore()..startWithoutStorage();
    workspaces = WorkspaceStore();
    store = VersionsStore(null, kept: MemoryStored());
    handle = null;
    record = VersionsRecord(store: store, preferences: preferences, workspaces: workspaces, keeper: () => handle);
  });
  tearDown(() => store.dispose());

  group('which notes keep a version history', () {
    test('is every note in an organization, unless switched off, and a note of one’s own once switched on', () {
      final team = workspaces.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'Ghost', hue: 'sea'));
      final home = workspaces.addWorkspace('Home')!;
      workspaces.fileNote('team-note', team.id);
      workspaces.fileNote('home-note', home.id);
      expect(record.keepsVersions('team-note'), isTrue);
      expect(record.keepsVersions('home-note'), isFalse);
      expect(record.keepsVersions('loose'), isFalse);
      expect(record.versionsByDefault('team-note'), isTrue);
      expect(record.versionsByDefault('home-note'), isFalse);

      var told = 0;
      record.keeping.addListener(() => told += 1);
      record.setKeepsVersions('home-note', true);
      record.setKeepsVersions('team-note', false);
      expect(told, 2);
      expect(record.keepsVersions('home-note'), isTrue);
      expect(record.keepsVersions('team-note'), isFalse);
      expect(preferences.value.versions, {'home-note': true, 'team-note': false});

      // A choice that is what the note would do anyway is not kept.
      record.setKeepsVersions('team-note', true);
      record.setKeepsVersions('home-note', false);
      expect(preferences.value.versions, isEmpty);
    });
  });

  group('keeping versions', () {
    test('keeps each change once, names one by hand, and owes the file to the account', () async {
      expect(await record.keepVersion('n1', '# Plan', now: 1000), isTrue);
      expect(await record.keepVersion('n1', '# Plan', now: 2000), isFalse);
      expect(await record.keepVersion('n1', '# Plan\n- venue', now: 3000), isTrue);
      expect(await record.keepVersion('n1', '# Plan\n- venue', now: 4000, label: 'Sent to Sam'), isTrue);
      final (:versions, :damaged) = await record.versionsOf('n1');
      expect(damaged, 0);
      expect([for (final v in versions) (v.text, v.label, v.by)], [('# Plan', null, 'me'), ('# Plan\n- venue', 'Sent to Sam', 'me')]);
      expect(store.unsentVersions(), ['n1']);
    });

    test('keeps two versions asked for at once in the order they were asked, neither lost', () async {
      await Future.wait([record.keepVersion('n2', 'one', now: 1), record.keepVersion('n2', 'one\ntwo', now: 2), record.keepVersion('n2', 'one\ntwo\nthree', now: 3)]);
      expect([for (final v in (await record.versionsOf('n2')).versions) v.text], ['one', 'one\ntwo', 'one\ntwo\nthree']);
    });

    test('is kept by the account’s handle once there is one, and goes on after a write that failed', () async {
      // Not cases of the web's file: the keeper is the page's account module there, and its queue is tried by none.
      handle = 'matt';
      await record.keepVersion('n3', 'signed in', now: 1);
      expect((await record.versionsOf('n3')).versions.single.by, 'matt');
      var fail = true;
      final flaky = VersionsStore((command, [args = const {}]) async {
        if (command == 'versions_read') return null;
        if (fail) throw StateError('The library would not write.');
        return false;
      }, kept: MemoryStored());
      final other = VersionsRecord(store: flaky, preferences: preferences, workspaces: workspaces);
      final first = other.keepVersion('n4', 'lost', now: 1);
      final second = first.then((_) => true, onError: (Object _) {
        fail = false;
        return other.keepVersion('n4', 'kept', now: 2);
      });
      await expectLater(first, throwsStateError);
      expect(await second, isTrue);
      expect([for (final v in (await other.versionsOf('n4')).versions) v.text], ['kept']);
      flaky.dispose();
    });

    test('are read again for whoever is watching when the note’s file changes here, and only that note’s', () async {
      final seen = <List<String>>[];
      final watching = record.watch('n5').listen((read) => seen.add([for (final v in read.versions) v.text]));
      await pumpEventQueue();
      expect(seen, [<String>[]]);
      await record.keepVersion('n5', 'one', now: 1);
      await record.keepVersion('elsewhere', 'x', now: 1);
      await pumpEventQueue();
      expect(seen, [
        <String>[],
        ['one'],
      ]);
      await watching.cancel();
      await record.keepVersion('n5', 'two', now: 2);
      await pumpEventQueue();
      expect(seen, hasLength(2));
    });
  });
}
