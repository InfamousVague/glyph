import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/net/forward_secrecy.dart' show MemoryFsStore;
import 'package:ghost_messaging/net/kept_files.dart';
import 'package:ghost_messaging/net/net.dart';

/// Where the ledger is kept (lib/net/kept_files.dart; the review, 2026-11-23, D6): files of its own, out of any backup,
/// and never the app's choices, which Android's backup copies.
void main() {
  test('the folder is one no backup takes, on each kind of device', () {
    expect(keptPathFor('ledger', os: 'android', data: '/data/user/0/app'), '/data/user/0/app/no_backup/ledger', reason: 'Android never backs up no_backup');
    expect(keptPathFor('ledger', os: 'macos', data: '/x', env: {'HOME': '/Users/maya'}), '/Users/maya/Library/Caches/Ghost Messaging/ledger');
    expect(keptPathFor('ledger', os: 'ios', data: '/var/mobile/Containers/Data/Application/A'), '/var/mobile/Containers/Data/Application/A/Library/Caches/Ghost Messaging/ledger', reason: 'an iPhone gives the app no HOME: its container');
    expect(keptPathFor('ledger', os: 'windows', data: '', env: {'LOCALAPPDATA': r'C:\Users\maya\AppData\Local'}), r'C:\Users\maya\AppData\Local\Ghost Messaging\ledger');
    expect(keptPathFor('ledger', os: 'linux', data: '', env: {'HOME': '/home/maya'}), '/home/maya/.cache/ghost-messaging/ledger');
    expect(keptPathFor('ledger', os: 'linux', data: '', env: {'XDG_CACHE_HOME': '/tmp/c', 'HOME': '/home/maya'}), '/tmp/c/ghost-messaging/ledger');
    expect([keptPathFor('ledger', os: 'windows', data: ''), keptPathFor('ledger', os: 'fuchsia', data: '/x')], [isNull, isNull]);
  });

  test('a file for each name, written whole (one cut short leaves the one before), gone when written empty', () async {
    final folder = Directory.systemTemp.createTempSync('kept');
    addTearDown(() => folder.deleteSync(recursive: true));
    final store = FilesFsStore(Directory('${folder.path}/ledger'));
    expect(await store.read('ldg'), isNull);
    await store.write('ldg', '{"d":"x"}');
    await store.write('ldg.0123', 'a book');
    await store.write('ldg.0123', 'the book again');
    expect([await store.read('ldg'), await store.read('ldg.0123')], ['{"d":"x"}', 'the book again']);
    expect(Directory('${folder.path}/ledger').listSync().map((f) => f.uri.pathSegments.last).toSet(), {'ldg', 'ldg.0123'}, reason: 'nothing half written left beside them');
    await store.write('../escape', 'x');
    expect(File('${folder.path}/escape').existsSync(), isFalse, reason: 'a name is never a path out of the folder');
    await store.write('ldg.0123', '');
    expect([await store.read('ldg.0123'), File('${folder.path}/ledger/ldg.0123').existsSync()], [null, false]);
  });

  test('the app keeps its ledger there; under a test, in memory, so nothing is written where this computer\'s own app keeps its files', () {
    expect(Net.defaultLedgerStore(), isA<MemoryFsStore>());
    expect(ledgerFiles(), isA<FilesFsStore>());
    expect((ledgerFiles()! as FilesFsStore).dir.path, endsWith(Platform.isMacOS ? 'Library/Caches/Ghost Messaging/ledger' : 'ledger'));
  });
}
