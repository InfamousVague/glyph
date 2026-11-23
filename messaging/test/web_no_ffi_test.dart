import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/files/apple_sha.dart';
import 'package:ghost_messaging/files/apple_sha_web.dart' as web_sha;
import 'package:ghost_messaging/inbox/inbox.dart';
import 'package:ghost_messaging/inbox/td_json_web.dart' as web_td;
import 'package:ghost_messaging/inbox/telegram.dart';

/// What reaches C through `dart:ffi` is in two halves each (Matt: "the full web client"): a build for a browser can't
/// so much as name `dart:ffi`, so the browser's half says "not here" the way a build without the library always has.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (call) async => null);
  });

  test('TDLib in a browser: no library, so Telegram says it isn\'t in this build', () async {
    expect(await web_td.TdJson.start(), isNull);
    final tg = Telegram(apiId: 12345, apiHash: 'hash', folder: '/tmp/tg', transport: web_td.TdJson.start);
    await tg.start(AppState());
    expect(tg.state, InboxState.signedOut);
    await tg.begin();
    expect(tg.state, InboxState.unavailable);
    expect(tg.error, 'Telegram isn\'t in this build of the app.');
  });

  test('CommonCrypto in a browser: none, so a file is read by the plain Dart reader', () {
    expect(web_sha.AppleSha.open(), isNull);
  });

  test('CommonCrypto on a Mac, moved to its own file, hashes as it did', () {
    final sha = AppleSha.open();
    expect(sha, isNotNull);
    final bytes = Uint8List.fromList(utf8.encode('abc' * 100000));
    // In two pieces, the second from the buffer's start as shaOfFile hands them on.
    sha!.add(bytes, 100000);
    sha.add(Uint8List.sublistView(bytes, 100000), bytes.length - 100000);
    expect(sha.end(), crypto.sha256.convert(bytes).bytes);
    sha.close();
  }, skip: Platform.isMacOS ? false : 'CommonCrypto is a Mac\'s and an iPhone\'s');

  test('dart:ffi is named only by the halves a browser\'s build leaves out', () {
    // Each is the `_io` half of a pair chosen by a conditional export; its `_web` half is what a browser gets.
    const allowed = {
      'lib/inbox/td_json_io.dart': 'TDLib (lib/inbox/td_json.dart)',
      'lib/files/apple_sha_io.dart': 'CommonCrypto\'s SHA-256 (lib/files/apple_sha.dart)',
      'lib/net/p2p/node_ffi_io.dart': 'the direct network\'s core (lib/net/p2p/node_ffi.dart)',
    };
    final named = RegExp(r'''^\s*(?:import|export)\s+['"](?:dart:ffi|package:ffi/)''');
    final roots = [Directory('lib'), for (final p in Directory('packages').listSync().whereType<Directory>()) Directory('${p.path}/lib')];
    final found = <String>[];
    var files = 0;
    for (final root in roots) {
      for (final file in root.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final path = file.path.replaceAll('\\', '/');
        files++;
        final lines = file.readAsLinesSync();
        final here = [for (var i = 0; i < lines.length; i++) if (named.hasMatch(lines[i])) '$path:${i + 1}: ${lines[i].trim()}'];
        if (allowed.containsKey(path)) {
          expect(here, isNotEmpty, reason: '$path is allowed dart:ffi and no longer names it: take it off the list.');
          // And the pair is there: the file that chooses, and the half without dart:ffi.
          final pair = path.replaceFirst('_io.dart', '.dart'), web = path.replaceFirst('_io.dart', '_web.dart');
          expect(File(pair).readAsStringSync(), contains("export '${path.split('/').last}' if (dart.library.js_interop) '${web.split('/').last}';"));
          expect(File(web).existsSync(), isTrue);
        } else {
          found.addAll(here);
        }
      }
    }
    expect(files, greaterThan(300));
    expect(found, isEmpty, reason: 'A build for a browser stops at dart:ffi wherever it is imported from: split the file as lib/files/apple_sha.dart is.\n${found.join('\n')}');
  });
}
