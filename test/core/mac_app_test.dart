import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/capture/device_mic.dart';
import 'package:ghost_md/core/backup.dart';
import 'package:ghost_md/core/export_all.dart';
import 'package:ghost_md/core/library_folder.dart';
import 'package:ghost_md/core/mac_app.dart';
import 'package:ghost_md/core/native/device_paths.dart';
import 'package:ghost_md/core/native/ghost_worker.dart';

/// The Mac app's own halves are asked for only inside the built app: never in a test on a Mac, where no channel
/// answers and nothing of the app's (its data directory, the Keychain, the microphone) may be touched.
void main() {
  const inApp = '/Applications/Ghost Flutter.app/Contents/MacOS/Ghost Flutter';

  test('the Mac app is a Mac, an executable in an app bundle, and not a test', () {
    expect(inMacAppFor(executable: inApp, macOS: true, test: false), isTrue);
    expect(inMacAppFor(executable: inApp, macOS: true, test: true), isFalse);
    expect(inMacAppFor(executable: inApp, macOS: false, test: false), isFalse);
    expect(inMacAppFor(executable: '/opt/flutter/bin/cache/artifacts/engine/darwin-x64/flutter_tester', macOS: true, test: false), isFalse);
    // This run is a test.
    expect(runsAsMacApp, isFalse);
  });

  test('the core is the copy in the app’s own Frameworks, by its whole path', () {
    expect(bundledCoreIn(inApp), '/Applications/Ghost Flutter.app/Contents/Frameworks/libghost_core.dylib');
    // A test opens the library it is given a path to; the name alone is what is left.
    expect(defaultLibraryName, isNot(contains('/')));
  });

  test('the app’s files are never the Tauri app’s: its folder, or anything in it, is refused before the core is opened', () {
    const home = '/Users/someone/Library';
    // The Mac app's own two, beside the Tauri app's and not in it.
    final own = DevicePaths.own(dataDir: '$home/Application Support/com.mattssoftware.glyph.flutter', cacheDir: '$home/Caches/com.mattssoftware.glyph.flutter');
    expect(own.dataDir, '$home/Application Support/com.mattssoftware.glyph.flutter');
    expect(isRealAppPath(own.dataDir), isFalse);
    expect(isRealAppPath(own.cacheDir), isFalse);
    expect(isRealAppPath('/data/user/0/com.mattssoftware.glyph.flutter'), isFalse);
    // The Tauri app's folder, a place inside it, and the ways a path could be made to mean one.
    for (final theirs in [
      '$home/Application Support/com.mattssoftware.glyph',
      '$home/Application Support/com.mattssoftware.glyph/',
      '$home/Application Support/com.mattssoftware.glyph/Library',
      '$home/Application Support/com.mattssoftware.glyph/models/x.bin',
      '$home/Caches/com.mattssoftware.glyph',
      '$home/Application Support/com.mattssoftware.glyph.flutter/../com.mattssoftware.glyph',
      '$home/Application Support/./com.mattssoftware.glyph/Library',
      '$home/Application Support/Com.MattsSoftware.Glyph',
    ]) {
      expect(isRealAppPath(theirs), isTrue, reason: theirs);
      expect(() => DevicePaths.own(dataDir: theirs, cacheDir: own.cacheDir), throwsStateError, reason: theirs);
      expect(() => DevicePaths.own(dataDir: own.dataDir, cacheDir: theirs), throwsStateError, reason: theirs);
    }
    // A folder that only begins with the Tauri app's name is another folder.
    expect(isRealAppPath('$home/Application Support/com.mattssoftware.glyph.staging'), isFalse);
    expect(realAppId, 'com.mattssoftware.glyph');
  });

  test('what the Mac app is told its directories are is asked the same before anything is opened', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Map<String, String> said = {'dataDir': '/Users/someone/Library/Application Support/com.mattssoftware.glyph', 'cacheDir': '/Users/someone/Library/Caches/com.mattssoftware.glyph.flutter'};
    messenger.setMockMethodCallHandler(DevicePaths.channel, (call) async => said);
    addTearDown(() => messenger.setMockMethodCallHandler(DevicePaths.channel, null));
    await expectLater(DevicePaths.fromActivity(), throwsStateError);
    said = {'dataDir': '/Users/someone/Library/Application Support/com.mattssoftware.glyph.flutter', 'cacheDir': '/Users/someone/Library/Caches/com.mattssoftware.glyph.flutter'};
    expect((await DevicePaths.fromActivity()).dataDir, endsWith('/com.mattssoftware.glyph.flutter'));
  });

  test('a test on a Mac keeps to its temporary folder, memory for secrets, and no microphone', () async {
    final paths = await DevicePaths.find();
    expect(paths.dataDir, DevicePaths.fallback().dataDir);
    expect(paths.dataDir, isNot(contains('com.mattssoftware.glyph')));
    expect(deviceSecureStore(), isA<MemorySecureStore>());
    expect(DeviceMic.supported, isFalse);
  });

  group('on a Mac', () {
    Future<Object?> invoke(String command, [Map<String, Object?> args = const {}]) async => switch (command) {
          'library_inspect' => {'kind': 'folder', 'path': args['path'], 'name': 'Vault', 'markdown': 3, 'obsidian': true, 'notes': 2},
          'backup_last' => {'backedUpAt': '2026-10-05T18:52:00Z', 'notes': 312},
          'backup_files' => [
              {'path': 'Inbox/A.md', 'size': 3},
            ],
          _ => null,
        };

    test('the library’s folder is chosen in the Mac’s panel and looked into by its path', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final folder = LibraryFolder(
        invoke: (command, [args = const {}]) {
          calls.add((command, args));
          return invoke(command, args);
        },
        platform: TargetPlatform.macOS,
        pickTree: () async => '{"path":"/Users/someone/Vault","name":"Vault"}',
      );
      expect(await folder.way(), FolderWay.mac);
      final candidate = await folder.choose();
      expect((candidate?.name, candidate?.markdown, candidate?.obsidian), ('Vault', 3, true));
      expect(calls.single.$1, 'library_inspect');
      expect(calls.single.$2, {'path': '/Users/someone/Vault'});
      // Outside the Mac app there is no panel behind the channel: nothing is offered.
      expect(await LibraryFolder(invoke: invoke, platform: TargetPlatform.macOS, macApp: false).way(), FolderWay.update);
      expect(readFolderAnswer('{"path":"relative"}'), const FolderRefused('That folder can’t be used.'));
      expect(readFolderAnswer('{"path":"/"}'), const FolderRefused('That folder can’t be used.'));
      expect(readFolderAnswer('{"cancelled":true}'), const FolderCancelled());
    });

    test('the drives are the core’s, as the Tauri app’s: listed, backed up to by path with nothing to allow, ejected', () async {
      final asked = <String>[];
      final runs = <Map<String, Object?>>[];
      final backups = Backups(
        invoke: (command, [args = const {}]) async {
          asked.add('$command ${args['drive'] ?? ''}'.trim());
          if (command == 'backup_drives') {
            return [
              {'id': '/Volumes/KINGSTON', 'name': 'KINGSTON', 'free': 30000000000, 'total': 32000000000, 'last': {'backedUpAt': '2026-10-05T18:52:00Z', 'notes': 312}},
            ];
          }
          return invoke(command, args);
        },
        platform: TargetPlatform.macOS,
        macApp: true,
        run: (request, onProgress) async {
          runs.add(request);
          return const Backed();
        },
      );
      expect(await backups.way(), BackupWay.mac);
      final drive = (await backups.listDrives(BackupWay.mac)).single;
      expect(drive.last, const LastBackup(backedUpAt: '2026-10-05T18:52:00Z', notes: 312));
      // No panel and no grant on a Mac: the drive is written by its path.
      expect(backups.needsAllowing(BackupWay.mac, drive), isFalse);
      expect(drive.tree, isNull);
      expect(await backups.listBackupFiles(BackupWay.mac, drive), const [HeldFile('Inbox/A.md', 3)]);
      await backups.runBackup(BackupWay.mac, drive, (_) {}, at: DateTime(2026, 10, 9, 12));
      expect(runs.single['drive'], '/Volumes/KINGSTON');
      expect(runs.single.containsKey('tree'), isFalse);
      await backups.ejectDrive(drive);
      expect(asked, ['backup_drives', 'backup_files /Volumes/KINGSTON', 'backup_eject /Volumes/KINGSTON']);
    });

    test('a Mac outside the Mac app (a test, a desktop run) offers no backup', () async {
      final backups = Backups(invoke: invoke, platform: TargetPlatform.macOS, macApp: false, run: (request, onProgress) async => const Backed());
      expect(await backups.way(), BackupWay.none);
      // And asked from a test on a Mac with nothing said, it is not the Mac app.
      expect(await Backups(invoke: invoke, platform: TargetPlatform.macOS, run: (request, onProgress) async => const Backed()).way(), BackupWay.none);
    });

    test('an export is saved through the Mac’s panel by the descriptor it hands over, as Android’s is', () async {
      final calls = <String>[];
      final runs = <Map<String, Object?>>[];
      final export = ExportAll(
        invoke: invoke,
        platform: TargetPlatform.macOS,
        picker: ExportPicker(
          choose: (name) async {
            calls.add('choose $name');
            return '{"fd":41,"name":"mine.zip"}';
          },
          done: () => calls.add('done'),
          discard: () => calls.add('discard'),
        ),
        run: (args, onProgress) async {
          runs.add(args);
          return const Exported(name: 'ghostmarkdown_2026-10-01_21-42-05.zip', notes: 1, files: 1, bytes: 10, written: 10);
        },
      );
      expect(await export.way(), ExportWay.mac);
      final done = await export.exportEverything((_) {}, at: DateTime(2026, 10, 1, 21, 42, 5));
      expect(done?.name, 'mine.zip');
      expect(runs.single['fd'], 41);
      expect(calls, ['choose ghostmarkdown_2026-10-01_21-42-05.zip', 'done']);
    });
  });
}
