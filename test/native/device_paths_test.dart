// Where the app keeps its files (lib/core/native/device_paths.dart): what the Android activity's channel says,
// read as MainActivity.kt answers it, and the folder used off Android.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/device_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(DevicePaths.channel, null));

  test('the activity\'s two directories are the app\'s', () async {
    final asked = <String>[];
    messenger.setMockMethodCallHandler(DevicePaths.channel, (call) async {
      asked.add(call.method);
      return {'dataDir': '/data/user/0/com.mattssoftware.glyph.flutter', 'cacheDir': '/data/user/0/com.mattssoftware.glyph.flutter/cache'};
    });
    final paths = await DevicePaths.fromActivity();
    expect(asked, ['dirs']);
    expect(paths.dataDir, '/data/user/0/com.mattssoftware.glyph.flutter');
    expect(paths.cacheDir, '/data/user/0/com.mattssoftware.glyph.flutter/cache');
  });

  test('an activity that says nothing is an error, not a library in the wrong place', () async {
    messenger.setMockMethodCallHandler(DevicePaths.channel, (call) async => {'dataDir': '/data/user/0/x'});
    await expectLater(DevicePaths.fromActivity(), throwsStateError);
  });

  test('on a phone the folder is the app\'s own by the system, even under the Tauri app\'s id; elsewhere that name is refused', () {
    const data = '/data/user/0/com.mattssoftware.glyph', cache = '/data/user/0/com.mattssoftware.glyph/cache';
    final told = DevicePaths.told(dataDir: data, cacheDir: cache, sandboxed: true);
    expect(told.dataDir, data);
    expect(told.cacheDir, cache);
    expect(() => DevicePaths.told(dataDir: data, cacheDir: cache, sandboxed: false), throwsStateError);
  });

  test('off Android it is a folder of its own under the temporary directory', () async {
    final paths = await DevicePaths.find();
    expect(paths.dataDir, '${Directory.systemTemp.path}/ghost_md/data');
    expect(paths.cacheDir, '${Directory.systemTemp.path}/ghost_md/cache');
  });

  test('the activity answers on the channel this file asks on, with the names it reads', () {
    final kotlin = File('android/app/src/main/kotlin/com/mattssoftware/ghost_md/MainActivity.kt').readAsStringSync();
    expect(kotlin, contains('"${DevicePaths.channel.name}"'));
    expect(kotlin, allOf(contains('"dirs" ->'), contains('"dataDir" to'), contains('"cacheDir" to')));
  });

  test('the backup rules leave the index out and the manifest names them', () {
    const main = 'android/app/src/main';
    final manifest = File('$main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:fullBackupContent="@xml/ghost_backup_rules"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/ghost_data_extraction_rules"'));
    for (final rules in ['ghost_backup_rules.xml', 'ghost_data_extraction_rules.xml']) {
      final xml = File('$main/res/xml/$rules').readAsStringSync();
      for (final file in ['index.sqlite', 'index.sqlite-wal', 'index.sqlite-shm']) {
        expect(xml, contains('<exclude domain="root" path="Library/.glyph/$file" />'), reason: rules);
      }
      expect(xml, isNot(contains('path="Library/"')), reason: 'the notes themselves are backed up');
    }
  });
}
