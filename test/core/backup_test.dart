import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/backup.dart';
import 'package:ghost_md/core/library_folder.dart' show filesChannel;
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/native/events.dart';

/// A backup onto a removable drive (lib/core/backup.dart; docs/DESIGN.md §204 of tauri/): where one can go, the
/// drives as Android says them, Android's one-time allow, the backup's request and its words after. A port of
/// `src/app/core/backup.test.ts`: the core, its job and its events are stood in for; the activity's own words are
/// read out of its Kotlin.
const drive = BackupDrive(id: '/Volumes/KINGSTON', name: 'KINGSTON', free: 30000000000, total: 32000000000);

void main() {
  late List<({String command, Map<String, Object?> args})> commands;
  late Map<String, Object?> answers;
  late List<Map<String, Object?>> runs;

  Future<Object?> invoke(String command, [Map<String, Object?> args = const {}]) async {
    commands.add((command: command, args: args));
    final answer = answers[command];
    if (answer is CoreError) throw answer;
    return answer;
  }

  Backups backups({TargetPlatform platform = TargetPlatform.android, String? drives = '[]', Future<String> Function(String id)? chooseDrive, Backed backed = const Backed()}) => Backups(
        invoke: invoke,
        platform: platform,
        drives: drives == null ? null : () async => drives,
        chooseDrive: chooseDrive,
        run: (request, onProgress) async {
          runs.add(request);
          onProgress(const BackupProgress(done: 1, total: 2, files: 1, of: 2));
          return backed;
        },
      );

  setUp(() {
    commands = [];
    answers = {};
    runs = [];
  });

  group('where a backup can go', () {
    test('is Android’s drives, an app to update, or nowhere', () async {
      // An APK whose activity has no drives is one to update.
      expect(await backups(drives: null).way(), BackupWay.update);
      expect(await backups().way(), BackupWay.android);
      expect(await backups(platform: TargetPlatform.iOS).way(), BackupWay.none);
      // The Mac's and Windows' drives are stage 10's: until then, nowhere.
      expect(await backups(platform: TargetPlatform.macOS).way(), BackupWay.none);
      expect(await backups(platform: TargetPlatform.windows).way(), BackupWay.none);
      expect((backupGeneration, backupFilesGeneration), (26, 27));
    });
  });

  group('the drives', () {
    test('are the Mac’s as Rust lists them, with the last backup each holds', () async {
      answers['backup_drives'] = [
        {'id': '/Volumes/KINGSTON', 'name': 'KINGSTON', 'free': 30000000000, 'total': 32000000000, 'last': {'backedUpAt': '2026-10-05T18:52:00Z', 'notes': 312}},
        {'id': '/Volumes/SD', 'name': 'SD', 'free': null, 'total': null},
      ];
      expect(await backups().listDrives(BackupWay.mac), [
        drive.withLast(const LastBackup(backedUpAt: '2026-10-05T18:52:00Z', notes: 312)),
        const BackupDrive(id: '/Volumes/SD', name: 'SD'),
      ]);
    });

    test('are Android’s as the activity says them, and the last backup asked of each it may write', () async {
      answers['backup_last'] = {'backedUpAt': '2026-10-04T10:00:00Z', 'notes': 3};
      final said = backups(drives: '[{"id":"1A2B-3C4D","name":"SanDisk USB","tree":"content://tree/1A2B","free":5,"total":9},{"id":"SD-1","name":""},{"name":"no id"}]');
      expect(await said.listDrives(BackupWay.android), [
        const BackupDrive(id: '1A2B-3C4D', name: 'SanDisk USB', free: 5, total: 9, tree: 'content://tree/1A2B', last: LastBackup(backedUpAt: '2026-10-04T10:00:00Z', notes: 3)),
        const BackupDrive(id: 'SD-1', name: 'SD-1'),
      ]);
      // Only the drive it may write is asked of: the other has no tree to read.
      expect(commands.map((call) => (call.command, '${call.args}')), [('backup_last', '{tree: content://tree/1A2B}')]);
      // A drive whose last backup cannot be read is still a drive.
      answers['backup_last'] = const CoreError('The backup could not be written: gone');
      expect((await said.listDrives(BackupWay.android)).first.last, isNull);
      expect(await said.listDrives(BackupWay.none), isEmpty);
    });

    test('read nothing unreadable as no drives', () {
      expect(readAndroidDrives('not json'), isEmpty);
      expect(readAndroidDrives('{"id":"x"}'), isEmpty);
    });
  });

  group('Android’s allow, once a drive', () {
    test('waits for the picker’s answer and gives back the drive’s tree', () async {
      var asked = '';
      final said = backups(chooseDrive: (id) async {
        asked = id;
        return '{"id":"$id","tree":"content://tree/1A2B"}';
      });
      expect(await said.allowDrive('1A2B-3C4D'), const DriveAllowed('content://tree/1A2B'));
      expect(asked, '1A2B-3C4D');
    });

    test('says why where the picker would not open', () async {
      expect(await backups(chooseDrive: (id) async => '{"error":"That drive isn’t plugged in any more."}').allowDrive('gone'), const DriveRefused('That drive isn’t plugged in any more.'));
      expect(await backups().allowDrive('x'), const DriveRefused('This phone has no way to choose a drive.'));
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(readDriveAnswer(await chooseDriveOnPhone('x')), const DriveRefused('This phone has no way to choose a drive.'));
      expect(await drivesOnPhone(), '[]');
    });

    test('reads a cancel, a refusal and nonsense', () {
      expect(readDriveAnswer('{"cancelled":true}'), const DriveCancelled());
      expect(readDriveAnswer('{"error":"Choose the drive itself"}'), const DriveRefused('Choose the drive itself'));
      expect(readDriveAnswer('{}'), const DriveRefused('That drive can’t be written to.'));
      expect(readDriveAnswer('nonsense'), const DriveRefused('That drive can’t be written to.'));
    });

    test('is the words the activity says, so the two sides cannot drift', () {
      String kotlin(String path) => File('android/app/src/main/kotlin/com/mattssoftware/$path').readAsStringSync();
      final drives = kotlin('glyph/files/BackupDrives.kt');
      expect(drives, contains('put("tree", uri.toString())'));
      expect(drives, contains('put("cancelled", true)'));
      expect(drives, contains('private const val NO_PICKER = "This phone has no way to choose a drive."'));
      final bridge = kotlin('ghost_md/FilesBridge.kt');
      expect(bridge, contains('const val CHANNEL = "${filesChannel.name}"'));
      expect(bridge, contains('"backupDrives" ->'));
      expect(bridge, contains('"chooseBackupDrive" ->'));
      expect(bridge, contains('call.argument<String>("id")'));
    });
  });

  group('the backup', () {
    test('asks Rust to write the Mac’s drive, with the README, and tells how far it has got', () async {
      const backed = Backed(notes: 2, files: 3, written: 3, bytes: 9);
      final seen = <BackupProgress>[];
      final at = DateTime.utc(2026, 10, 5, 20);
      expect(await backups(backed: backed).runBackup(BackupWay.mac, drive, seen.add, at: at), backed);
      expect(runs, [
        {'drive': '/Volumes/KINGSTON', 'backedUpAt': '2026-10-05T20:00:00.000Z', 'readme': backupReadme(at)},
      ]);
      expect(seen.single.of, 2);
    });

    test('writes Android’s drive by its tree, and refuses one not yet allowed', () async {
      final said = backups();
      await said.runBackup(BackupWay.android, const BackupDrive(id: '1A2B', name: 'USB', tree: 'content://tree/1A2B'), (_) {});
      expect(runs.single['tree'], 'content://tree/1A2B');
      expect(runs.single.containsKey('drive'), isFalse);
      await expectLater(said.runBackup(BackupWay.android, const BackupDrive(id: '1A2B', name: 'USB'), (_) {}), throwsA(isA<StateError>().having((e) => e.message, 'message', 'Allow Ghost.md to use the drive first.')));
      await expectLater(said.runBackup(BackupWay.none, drive, (_) {}), throwsA(isA<StateError>().having((e) => e.message, 'message', 'Backing up isn’t on this device.')));
      await expectLater(said.runBackup(BackupWay.update, drive, (_) {}), throwsA(isA<StateError>().having((e) => e.message, 'message', 'Update Ghost.md to back up to a drive.')));
      expect(runs.length, 1);
    });

    test('is a job over the core: started, heard as it goes, and ended with what it did or the core’s sentence', () async {
      final events = StreamController<CoreEvent>.broadcast(sync: true);
      final ends = <Completer<Object?>>[];
      final started = <(String, Map<String, Object?>)>[];
      Future<CoreJob> startJob(String command, [Map<String, Object?> args = const {}]) async {
        started.add((command, args));
        ends.add(Completer<Object?>());
        return CoreJob('j${ends.length}', const Stream.empty(), ends.last.future, () async => true);
      }

      final run = coreBackupRun(startJob: startJob, events: events.stream);
      final seen = <BackupProgress>[];
      final done = run({'tree': 'content://tree/x'}, seen.add);
      await pumpEventQueue();
      expect(started.single.$1, 'backup_run');
      expect(started.single.$2, {'request': {'tree': 'content://tree/x'}});
      events.add(const CoreEvent('backup://progress', {'done': 10, 'total': 40, 'files': 1, 'of': 4}));
      events.add(const CoreEvent('export://progress', {'done': 99, 'total': 99, 'files': 9, 'of': 9}));
      expect(seen.map((p) => (p.done, p.total, p.files, p.of)), [(10, 40, 1, 4)]);
      ends.single.complete({'notes': 2, 'files': 4, 'written': 4, 'unchanged': 0, 'removed': 0, 'bytes': 40});
      expect(await done, const Backed(notes: 2, files: 4, written: 4, bytes: 40));
      // And lets go of the events once it has ended.
      expect(events.hasListener, isFalse);

      final failed = run({'tree': 'content://tree/x'}, seen.add);
      await pumpEventQueue();
      ends.last.completeError(const CoreError('The backup was stopped.'));
      await expectLater(failed, throwsA(isA<CoreError>().having((e) => e.message, 'message', 'The backup was stopped.')));
      expect(events.hasListener, isFalse);
      await events.close();
    });

    test('says what it did, and when a drive was last backed up', () {
      expect(backedSaid(const Backed(notes: 312, files: 340, written: 14, unchanged: 326, removed: 2, bytes: 10), 'KINGSTON'), 'Backed up 312 notes to KINGSTON: 14 files written, 326 already there, 2 taken off.');
      expect(backedSaid(const Backed(notes: 1, files: 1, written: 1, bytes: 1), 'SD'), 'Backed up one note to SD: one file written.');
      expect(lastSaid(null), 'No backup on it yet');
      final now = DateTime(2026, 10, 5, 21);
      expect(lastSaid(LastBackup(backedUpAt: isoInstant(DateTime(2026, 10, 5, 18, 52)), notes: 312), now: now), 'Last backed up today, 06:52 PM · 312 notes');
      expect(lastSaid(LastBackup(backedUpAt: isoInstant(DateTime(2026, 10, 4, 9, 5)), notes: 1), now: now), 'Last backed up Oct 4, 09:05 AM · one note');
      expect(lastSaid(LastBackup(backedUpAt: isoInstant(DateTime(2025, 12, 31, 0, 0)), notes: 2), now: now), 'Last backed up Dec 31, 2025, 12:00 AM · 2 notes');
      expect(lastSaid(const LastBackup(backedUpAt: 'when?', notes: 2)), 'Backed up before');
      expect((sizeSaid(999), sizeSaid(1000), sizeSaid(820000), sizeSaid(1400000000), sizeSaid(30000000000)), ('999 bytes', '1 KB', '820 KB', '1.4 GB', '30 GB'));
    });

    group('says when in the phone’s own words (core/locale_dates.dart)', () {
      tearDown(() => toldLocale = null);
      final now = DateTime(2026, 10, 5, 21);
      String last(DateTime at, int notes) => lastSaid(LastBackup(backedUpAt: isoInstant(at), notes: notes), now: now);

      test('an American phone has the month first and a 12-hour clock', () {
        toldLocale = DateLocale.enUS;
        expect(last(DateTime(2026, 10, 5, 18, 52), 312), 'Last backed up today, 06:52 PM · 312 notes');
        expect(last(DateTime(2026, 10, 4, 9, 5), 1), 'Last backed up Oct 4, 09:05 AM · one note');
        expect(last(DateTime(2025, 12, 31, 0, 0), 2), 'Last backed up Dec 31, 2025, 12:00 AM · 2 notes');
        expect(backupReadme(DateTime(2026, 10, 5, 20)).split('\n').first, 'Ghost.md, backed up 10/5/2026, 8:00:00 PM');
      });

      test('a British phone has the day first and a 24-hour clock', () {
        toldLocale = DateLocale.enGB;
        expect(last(DateTime(2026, 10, 5, 18, 52), 312), 'Last backed up today, 18:52 · 312 notes');
        expect(last(DateTime(2026, 10, 4, 9, 5), 1), 'Last backed up 4 Oct, 09:05 · one note');
        expect(last(DateTime(2025, 12, 31, 0, 0), 2), 'Last backed up 31 Dec 2025, 00:00 · 2 notes');
        expect(backupReadme(DateTime(2026, 10, 5, 20)).split('\n').first, 'Ghost.md, backed up 05/10/2026, 20:00:00');
      });
    });

    test('leaves a README that says what each folder is', () {
      final readme = backupReadme(DateTime(2026, 10, 5, 20));
      for (final folder in ['Inbox/', 'Workspaces/', 'Organizations/', 'Attachments/']) {
        expect(readme, contains(folder));
      }
      expect(readme.split('\n').first, 'Ghost.md, backed up 10/5/2026, 8:00:00 PM');
      expect(readme, endsWith('off at the next backup; nothing else in this folder is ever touched.\n'));
    });
  });

  group('the files a drive holds', () {
    test('asks Rust for a drive’s files by its path or its tree, and not at all of a drive not yet allowed', () async {
      answers['backup_files'] = [
        {'path': 'Inbox/A.md', 'size': 3},
        {'path': '', 'size': 1},
        'nonsense',
        {'path': 'README.txt'},
      ];
      final said = backups();
      expect(await said.listBackupFiles(BackupWay.mac, drive), const [HeldFile('Inbox/A.md', 3), HeldFile('README.txt', 0)]);
      expect((commands.last.command, '${commands.last.args}'), ('backup_files', '{drive: /Volumes/KINGSTON}'));
      await said.listBackupFiles(BackupWay.android, const BackupDrive(id: 'usb', name: 'USB', tree: 'content://tree/usb'));
      expect((commands.last.command, '${commands.last.args}'), ('backup_files', '{tree: content://tree/usb}'));
      final before = commands.length;
      expect(await said.listBackupFiles(BackupWay.android, const BackupDrive(id: 'usb', name: 'USB')), isNull);
      expect(await said.listBackupFiles(BackupWay.none, drive), isNull);
      expect(commands.length, before);
    });

    test('builds the folders the files are in, folders before files, each by name, counting what is under it', () {
      final tree = backupTree(const [
        HeldFile('Workspaces/Work/b.md', 20),
        HeldFile('Workspaces/Work/a.md', 10),
        HeldFile('Workspaces/Home/list.md', 5),
        HeldFile('README.txt', 7),
        HeldFile('Inbox/Note 10.md', 1),
        HeldFile('Inbox/Note 2.md', 1),
      ]);
      expect((tree.name, tree.path, tree.files, tree.size), ('Ghost.md', '', 6, 44));
      expect(tree.folders.map((f) => (f.name, f.files, f.size)), [('Inbox', 2, 2), ('Workspaces', 3, 35)]);
      expect(tree.leaves.map((l) => l.name), ['README.txt']);
      expect(tree.folders[0].leaves.map((l) => l.name), ['Note 2.md', 'Note 10.md']);
      final work = tree.folders[1].folders.firstWhere((f) => f.name == 'Work');
      expect(work.path, 'Workspaces/Work');
      expect(work.leaves.map((l) => (l.name, l.path, l.size)), [('a.md', 'Workspaces/Work/a.md', 10), ('b.md', 'Workspaces/Work/b.md', 20)]);
      expect(tree.folders[1].folders.map((f) => f.name), ['Home', 'Work']);
    });
  });
}
