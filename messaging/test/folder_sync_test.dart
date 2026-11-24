// A folder on a computer kept in step with My files (GMFB-38: "Sync a folder on your computer with a drive"): one
// pass's rules against a real temporary folder and a drive of the test's own. Nothing is ever deleted on either side,
// and a local file is replaced only where its content is one the sync recorded.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/files/folder_sync.dart';

/// A drive in memory: files by id, each with its bytes. Like the real one it never replaces: the same path added again
/// is a newer file beside the older.
class FakeDrive implements SyncDrive {
  FakeDrive(this.dir);
  final Directory dir;
  final Map<String, (DriveFile, List<int>)> files = {};
  int _n = 0, uploads = 0, fetches = 0;
  bool reachable = true;

  @override
  String get id => 'drive-1';
  @override
  int maxFile = 0;
  @override
  int? free;

  DriveFile put(String path, String text) {
    final bytes = utf8.encode(text);
    final f = DriveFile(id: 'f${++_n}', path: path, size: bytes.length, sha: crypto.sha256.convert(bytes).toString(), at: _n);
    files[f.id] = (f, bytes);
    return f;
  }

  void remove(String path) => files.removeWhere((_, v) => v.$1.path == path);
  List<String> get paths => [for (final v in files.values) v.$1.path]..sort();
  String newest(String path) => utf8.decode((files.values.where((v) => v.$1.path == path).toList()..sort((a, b) => b.$1.at.compareTo(a.$1.at))).first.$2);

  @override
  Future<List<DriveFile>?> list() async => reachable ? [for (final v in files.values) v.$1] : null;

  @override
  Future<DriveFile?> upload(String local, String? folder, String name) async {
    uploads++;
    return put(folder == null ? name : '$folder/$name', File(local).readAsStringSync());
  }

  @override
  Future<String> fetch(DriveFile f) async {
    fetches++;
    final at = File('${dir.path}/cache/${f.id}')..parent.createSync(recursive: true);
    at.writeAsBytesSync(files[f.id]!.$2);
    return at.path;
  }
}

void main() {
  late Directory tmp;
  late String root;
  late FakeDrive drive;
  // The clock a pass reads: an hour on from the real one, so files the test has just written are not "still being
  // written" unless the test says so.
  var ahead = const Duration(hours: 1);
  DateTime now() => DateTime.now().add(ahead);

  File local(String path) => File('$root/$path');
  void write(String path, String text) => local(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);
  List<String> localPaths() => [
        for (final e in Directory(root).listSync(recursive: true, followLinks: false))
          if (e is File) e.path.substring(root.length + 1),
      ]..sort();

  FolderSyncEngine engine({int most = 2000}) => FolderSyncEngine(root: root, drive: drive, state: SyncState(File('${tmp.path}/app/state.json')), now: now, most: most);
  Future<SyncReport> pass({int most = 2000}) => engine(most: most).run();

  setUp(() {
    tmp = Directory(Directory.systemTemp.createTempSync('ghost-folder-sync').resolveSymbolicLinksSync());
    root = FolderSyncEngine.resolve((Directory('${tmp.path}/Synced')..createSync()).path)!;
    drive = FakeDrive(tmp);
    ahead = const Duration(hours: 1);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a file new in the folder goes up under the same path, its folders with it', () async {
    write('notes.txt', 'one');
    write('Trip/Day 2/plan.md', 'two');
    final r = await pass();
    expect(r.stopped, isNull);
    expect(r.up, 2);
    expect(drive.paths, ['Trip/Day 2/plan.md', 'notes.txt']);
    expect(drive.newest('Trip/Day 2/plan.md'), 'two');
    expect(r.line, 'In step.');
  });

  test('a file new in the drive comes down, under a temporary name until it is whole', () async {
    drive.put('Papers/lease.pdf', 'lease');
    drive.put('top.txt', 'top');
    final r = await pass();
    expect(r.down, 2);
    expect(local('Papers/lease.pdf').readAsStringSync(), 'lease');
    expect(local('top.txt').readAsStringSync(), 'top');
    expect(localPaths(), ['Papers/lease.pdf', 'top.txt'], reason: 'no temporary file is left');
    expect(drive.uploads, 0);
  });

  test('a pass after nothing changed moves nothing', () async {
    write('a.txt', 'a');
    drive.put('b.txt', 'b');
    await pass();
    final ups = drive.uploads, downs = drive.fetches;
    final r = await pass();
    expect(r.moved, 0);
    expect(r.line, 'In step.');
    expect(drive.uploads, ups);
    expect(drive.fetches, downs);
    expect(drive.files.length, 2);
  });

  test('changed here goes up as the newest; changed there comes down over the copy the sync recorded', () async {
    write('a.txt', 'a1');
    write('b.txt', 'b1');
    await pass();
    write('a.txt', 'a2 longer');
    drive.put('b.txt', 'b2 from the drive');
    final r = await pass();
    expect(r.up, 1);
    expect(r.down, 1);
    expect(r.both, 0);
    expect(drive.newest('a.txt'), 'a2 longer');
    expect(local('b.txt').readAsStringSync(), 'b2 from the drive');
    expect(localPaths(), ['a.txt', 'b.txt']);
    // The older a.txt is still in the drive: nothing is removed there.
    expect(drive.files.values.where((v) => v.$1.path == 'a.txt').length, 2);
  });

  test('both changed keeps both: the drive\'s beside it with a suffix, the local one untouched and sent up', () async {
    write('doc.txt', 'first');
    await pass();
    write('doc.txt', 'mine, changed here');
    drive.put('doc.txt', 'theirs, changed there');
    final r = await pass();
    expect(r.both, 1);
    expect(local('doc.txt').readAsStringSync(), 'mine, changed here');
    expect(local('doc (from My files).txt').readAsStringSync(), 'theirs, changed there');
    expect(drive.newest('doc.txt'), 'mine, changed here');
    // Next pass the copy beside it is a file like any other, and nothing is copied twice.
    final again = await pass();
    expect(again.both, 0);
    expect(localPaths(), ['doc (from My files).txt', 'doc.txt']);
    expect((await pass()).moved, 0);
  });

  test('a file on both sides the sync has no record of is never replaced: same content is in step, different keeps both', () async {
    write('same.txt', 'equal');
    drive.put('same.txt', 'equal');
    write('diff.txt', 'local words');
    drive.put('diff.txt', 'drive words');
    final r = await pass();
    expect(local('diff.txt').readAsStringSync(), 'local words');
    expect(local('diff (from My files).txt').readAsStringSync(), 'drive words');
    expect(r.both, 1);
    expect(drive.files.values.where((v) => v.$1.path == 'same.txt').length, 1, reason: 'not sent again');
  });

  test('a local file changed without its size or time showing it is still not replaced (its content is checked)', () async {
    write('a.txt', 'aaaa');
    await pass();
    final when = local('a.txt').lastModifiedSync();
    write('a.txt', 'bbbb');
    local('a.txt').setLastModifiedSync(when);
    drive.put('a.txt', 'from the drive');
    final r = await pass();
    expect(local('a.txt').readAsStringSync(), 'bbbb');
    expect(local('a (from My files).txt').readAsStringSync(), 'from the drive');
    expect(r.both, 1);
  });

  test('a local delete does not delete from the drive, and a drive delete does not delete locally: each comes back', () async {
    write('here.txt', 'here');
    write('there.txt', 'there');
    await pass();
    local('here.txt').deleteSync();
    drive.remove('there.txt');
    final r = await pass();
    expect(r.stopped, isNull);
    expect(drive.paths, ['here.txt', 'there.txt']);
    expect(localPaths(), ['here.txt', 'there.txt']);
    expect(local('here.txt').readAsStringSync(), 'here');
    expect(drive.newest('there.txt'), 'there');
  });

  test('hidden files and folders and links are left out, and a link is never followed or written through', () async {
    final outside = Directory('${tmp.path}/Outside')..createSync();
    File('${outside.path}/secret.txt').writeAsStringSync('secret');
    write('.env', 'hidden');
    write('.git/config', 'hidden');
    write('Thumbs.db', 'x');
    write('desktop.ini', 'x');
    write('.DS_Store', 'x');
    write('ok.txt', 'ok');
    Link('$root/way-out').createSync(outside.path);
    Link('$root/linked.txt').createSync('${outside.path}/secret.txt');
    // The drive has a path that would go through the link, and names that climb out.
    drive.put('way-out/planted.txt', 'planted');
    drive.put('../climbed.txt', 'no');
    drive.put('.hidden/x.txt', 'no');
    final r = await pass();
    expect(drive.paths.where((p) => !p.startsWith('.') && !p.startsWith('way-out')), ['ok.txt']);
    expect(File('${outside.path}/planted.txt').existsSync(), isFalse);
    expect(File('${tmp.path}/climbed.txt').existsSync(), isFalse);
    expect(outside.listSync().length, 1);
    expect(Directory('$root/.hidden').existsSync(), isFalse);
    expect(r.skipped.keys, contains('a link'));
    expect(r.line, startsWith('In step, but for'));
  });

  test('a file still being written is left this pass and taken the next', () async {
    ahead = Duration.zero;
    write('draft.txt', 'half');
    final r = await pass();
    expect(drive.paths, isEmpty);
    expect(r.skipped['still being written'], 1);
    ahead = const Duration(hours: 1);
    expect((await pass()).up, 1);
    expect(drive.newest('draft.txt'), 'half');
  });

  test('too big, no room, and names another system can\'t hold are left out with the reason, and the rest go', () async {
    drive.maxFile = 10;
    write('big.bin', 'x' * 50);
    write('small.txt', 'ok');
    write('what?.txt', 'windows can\'t hold this');
    final r = await pass();
    expect(drive.paths, ['small.txt']);
    expect(r.skipped.keys.any((k) => k.startsWith('too big')), isTrue);
    expect(r.skipped['with a name My files can\'t hold'], 1);
    drive.maxFile = 0;
    drive.free = 5;
    final r2 = await pass();
    expect(r2.skipped['with no room left in My files'], 1);
    expect(r2.line, contains('left out'));
    expect(local('big.bin').existsSync(), isTrue);
  });

  test('one pass moves no more than its cap, says so, and the next goes on', () async {
    for (var i = 0; i < 5; i++) {
      write('f$i.txt', '$i');
    }
    final r = await pass(most: 3);
    expect(r.up, 3);
    expect(r.capped, isTrue);
    expect(r.line, contains('More next time'));
    final r2 = await pass(most: 3);
    expect(r2.up, 2);
    expect(r2.capped, isFalse);
  });

  test('the state survives a restart: a new engine on the same state file knows what was in step', () async {
    write('a.txt', 'a1');
    await pass();
    expect(File('${tmp.path}/app/state.json').existsSync(), isTrue);
    expect(Directory(root).listSync().length, 1, reason: 'the state is not kept in the synced folder');
    // "Restarted": only the drive changed since. With the state it is a plain change that comes down; without it,
    // it would be two files that differ.
    drive.put('a.txt', 'a2 from another device');
    final r = await pass();
    expect(r.both, 0);
    expect(local('a.txt').readAsStringSync(), 'a2 from another device');
    expect(localPaths(), ['a.txt']);
  });

  test('the home folder, anything above it, a disk\'s top, and the app\'s own folders are refused', () {
    final home = '${tmp.path}/home/me';
    final app = '$home/Library/Application Support/Ghost Messaging';
    Directory('$app/folder-sync').createSync(recursive: true);
    Directory('$home/Documents').createSync();
    String? why(String p) => FolderSyncEngine.whyNot(FolderSyncEngine.resolve(p) ?? p, home: home, own: [app]);
    expect(why(home), contains('home folder'));
    expect(why('${tmp.path}/home'), contains('home folder'));
    expect(why('/'), contains('whole disk'));
    expect(FolderSyncEngine.whyNot(r'C:\', home: r'C:\Users\me'), contains('whole disk'));
    expect(FolderSyncEngine.whyNot('C:', home: r'C:\Users\me'), contains('whole disk'));
    expect(FolderSyncEngine.whyNot('/Volumes/Backup', home: '/Users/me'), contains('whole disk'));
    expect(why(app), contains('its own files'));
    expect(why('$app/folder-sync'), contains('its own files'));
    expect(why('$home/Library'), contains('its own files'), reason: 'it holds the app\'s folder');
    expect(why('$home/Documents'), isNull);
  });

  group('this computer\'s choice', () {
    FolderSync sync({SyncDrive? Function()? d}) => FolderSync(
          data: () => Directory('${tmp.path}/app/folder-sync'),
          drive: () async => d == null ? drive : d(),
          home: () => '${tmp.path}/home',
          own: () => ['${tmp.path}/app'],
          quiet: Duration.zero,
        );

    test('choosing runs a pass and is remembered on this device; stopping forgets it and removes nothing', () async {
      Directory('${tmp.path}/home').createSync();
      write('a.txt', 'a');
      final s = sync();
      expect(s.choose('${tmp.path}/home'), contains('home folder'));
      expect(s.choose('${tmp.path}/app'), isNotNull);
      expect(s.root, isNull);
      expect(s.choose(root), isNull);
      while (s.running) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(s.line, 'In step.');
      expect(drive.paths, ['a.txt']);
      // A new run of the app reads the same choice.
      final next = sync()..load();
      expect(next.root, root);
      next.stop();
      expect((sync()..load()).root, isNull);
      expect(local('a.txt').existsSync(), isTrue);
      expect(drive.paths, ['a.txt']);
    });

    test('signed out, out of reach, or the folder gone: it stops quietly and says why', () async {
      final s = sync(d: () => null);
      expect(s.choose(root), isNull);
      await s.pass();
      while (s.running) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(s.line, 'Stopped: sign in to your Ghost account on this computer.');
      final t = sync();
      drive.reachable = false;
      expect(t.choose(root), isNull);
      while (t.running) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(t.line, 'Stopped: My files can\'t be reached right now.');
      Directory(root).deleteSync(recursive: true);
      await t.pass();
      expect(t.line, 'Stopped: the folder isn\'t there any more.');
    });
  });
}
