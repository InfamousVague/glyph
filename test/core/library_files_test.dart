import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/library_files.dart';
import 'package:ghost_md/core/library_folder.dart' show filesChannel;

/// The notes' folder shown where the device shows folders (lib/core/library_files.dart): the Files app through the
/// activity on a phone, a desktop's own way where it is given one, and nothing anywhere else. A port of
/// `src/app/core/libraryFiles.test.ts`, case for case: the activity is stood in for on its channel, where the page's
/// was an object on its window; and its own words, the provider's and the manifest's are read out of their sources.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Every call the activity was asked, in order.
  late List<String> asked;

  /// The activity as FilesBridge.kt answers; one from before the button knows neither call.
  void phone({bool before = false}) => messenger.setMockMethodCallHandler(filesChannel, (call) async {
        asked.add(call.method);
        if (before) throw MissingPluginException();
        return switch (call.method) { 'canBrowseFiles' => true, 'browseFiles' => null, _ => throw MissingPluginException() };
      });

  setUp(() => asked = []);
  tearDown(() => messenger.setMockMethodCallHandler(filesChannel, null));

  group('the notes’ folder', () {
    test('is not offered where there is no folder to show', () async {
      // The page's browser. Here: a desktop this build has no way to show a folder on.
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]) {
        final files = LibraryFiles(platform: platform);
        expect(await files.canBrowse(), isFalse, reason: '$platform');
        await expectLater(files.browse(), throwsStateError);
      }
      expect(asked, isEmpty);
    });

    test('is drawn on an iPhone as the page draws it there, and its press opens nothing', () async {
      // The real iPhone app's binary is new enough for the page to offer the tool, and has nothing to open the
      // folder with: the press fails and nothing is said (NoteTree.tsx). No phone half is asked.
      final files = LibraryFiles(platform: TargetPlatform.iOS);
      expect(await files.canBrowse(), isTrue);
      await expectLater(files.browse(), throwsStateError);
      expect(asked, isEmpty);
    });

    test('is offered on a phone whose activity can open it, and opened there', () async {
      phone();
      var revealed = 0;
      final files = LibraryFiles(platform: TargetPlatform.android, reveal: () async => revealed += 1);
      expect(await files.canBrowse(), isTrue);
      await files.browse();
      expect(asked, ['canBrowseFiles', 'browseFiles']);
      expect(revealed, 0);
    });

    test('is not offered on a phone whose activity is from before it', () async {
      phone(before: true);
      expect(await LibraryFiles(platform: TargetPlatform.android).canBrowse(), isFalse);
      // Nor with no phone half behind the channel at all, which every other test of the app is.
      messenger.setMockMethodCallHandler(filesChannel, null);
      expect(await LibraryFiles(platform: TargetPlatform.android).canBrowse(), isFalse);
    });

    test('is offered on a Mac that is given a way to show it, and shown that way', () async {
      // The page's Mac from generation 18 asked Rust (`library_reveal`); this core has none, so the way is handed in.
      final invoked = <String>[];
      final files = LibraryFiles(platform: TargetPlatform.macOS, reveal: () async => invoked.add('library_reveal'));
      expect(await files.canBrowse(), isTrue);
      await files.browse();
      expect(invoked, ['library_reveal']);
      expect(asked, isEmpty);
    });
  });

  group('the sidebar’s Browse files', () {
    test('is nothing until the phone has said it can, asks once, and then is the press', () async {
      phone();
      final files = LibraryFiles(platform: TargetPlatform.android);
      var known = 0;
      expect(files.offered(() => known += 1), isNull);
      expect(files.offered(() => known += 1), isNull);
      await pumpEventQueue();
      expect(known, 1);
      expect(asked, ['canBrowseFiles']);
      final press = files.offered(() => known += 1);
      expect(press, isNotNull);
      press!();
      await pumpEventQueue();
      expect(known, 1);
      expect(asked, ['canBrowseFiles', 'browseFiles']);
    });

    test('stays nothing where the device cannot, and a press that fails is only written down', () async {
      var known = 0;
      final none = LibraryFiles(platform: TargetPlatform.android);
      expect(none.offered(() => known += 1), isNull);
      await pumpEventQueue();
      expect(none.offered(() => known += 1), isNull);
      expect(known, 0);

      final said = <String?>[];
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) => said.add(message);
      addTearDown(() => debugPrint = print);
      final mac = LibraryFiles(platform: TargetPlatform.macOS, reveal: () async => throw StateError('Finder is not there'));
      expect(mac.offered(() => known += 1), isNull);
      await pumpEventQueue();
      mac.offered(() {})!();
      await pumpEventQueue();
      expect(known, 1);
      expect(said.single, startsWith('[ghost] could not show the notes folder:'));
    });
  });

  group('the phone’s half', () {
    String kotlin(String path) => File('android/app/src/main/kotlin/com/mattssoftware/$path').readAsStringSync();

    test('answers on the channel this file asks on, by the names it asks', () {
      final bridge = kotlin('ghost_md/FilesBridge.kt');
      expect(bridge, contains('const val CHANNEL = "${filesChannel.name}"'));
      expect(bridge, contains('"canBrowseFiles" -> result.success(true)'));
      expect(bridge, contains('"browseFiles" -> {\n          LibraryFiles.browse(activity)'));
      // The place it opens is the provider's, by the provider's own names.
      final browse = kotlin('ghost_md/LibraryFiles.kt');
      expect(browse, contains('LibraryDocuments.authority(activity.packageName)'));
      expect(browse, contains('DocumentsContract.buildRootUri(authority, LibraryDocuments.ROOT_ID)'));
      // And a library in a folder of the person's is shown where it is, not at the app's emptied place.
      expect(browse, contains('LibraryRoot.chosenTree(activity.applicationContext)'));
    });

    test('lists this app’s own folder, as a place of this app’s own', () {
      final provider = kotlin('glyph/files/LibraryDocuments.kt');
      // The folder the core keeps the notes in: ../glyph's paths.rs holds its Kotlin twin the same way.
      final library = RegExp(r'pub const LIBRARY: &str = "([^"]+)";').firstMatch(File('native/src/paths.rs').readAsStringSync())!.group(1)!;
      expect(provider, contains('private fun library(): File = File(context!!.dataDir, "$library")'));
      expect(provider, contains('paths.rs'));
      // The authority is made from the id this app is installed by, which is never the real app's.
      expect(provider, contains(r'fun authority(packageName: String) = "$packageName.library"'));
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final declared = RegExp(r'<provider\s+android:name="com\.mattssoftware\.glyph\.files\.LibraryDocuments"[^>]*>').firstMatch(manifest)?.group(0) ?? '';
      expect(declared, contains(r'android:authorities="${applicationId}.library"'));
      expect(manifest, isNot(contains('"com.mattssoftware.glyph.library"')));
      expect(File('android/app/build.gradle.kts').readAsStringSync(), contains('applicationId = "com.mattssoftware.glyph.flutter"'));
      // Reached only by the system's Files app, and read-only there.
      expect(declared, allOf(contains('android:exported="true"'), contains('android:permission="android.permission.MANAGE_DOCUMENTS"')));
      expect(manifest, contains('<action android:name="android.content.action.DOCUMENTS_PROVIDER" />'));
      expect(provider, contains('add(Document.COLUMN_FLAGS, 0)'));
      expect(provider, contains("if (mode.contains('w') || mode.contains('t')) throw FileNotFoundException("));
    });

    test('is the Tauri app’s provider line for line, but for the app’s name and its R', () {
      final original = File('../glyph/src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/files/LibraryDocuments.kt');
      if (!original.existsSync()) {
        markTestSkipped('../glyph is not beside the repository');
        return;
      }
      /// A file's lines of code: nothing of its comments, which say whose button opens it.
      List<String> code(String source) => [
            for (final line in source.split('\n').map((line) => line.trim()))
              if (line.isNotEmpty && !line.startsWith('//') && !line.startsWith('/*') && !line.startsWith('*')) line,
          ];
      final theirs = code(original.readAsStringSync());
      final ours = code(kotlin('glyph/files/LibraryDocuments.kt'));
      // What the port's header says differs: this app's R, and the place named as the app is named on the phone.
      const differs = {
        'import com.mattssoftware.glyph.R': 'import com.mattssoftware.ghost_md.R',
        'add(Document.COLUMN_DISPLAY_NAME, if (file.canonicalFile == library().canonicalFile) "Ghost.md" else file.name)':
            'add(Document.COLUMN_DISPLAY_NAME, if (file.canonicalFile == library().canonicalFile) name() else file.name)',
        'add(Root.COLUMN_TITLE, "Ghost.md")': 'add(Root.COLUMN_TITLE, name())',
      };
      expect(theirs.where(differs.containsKey), hasLength(differs.length), reason: 'the original no longer has a line this test names');
      const added = ['private fun name(): String = context!!.applicationInfo.loadLabel(context!!.packageManager).toString()'];
      expect([for (final line in ours) if (!added.contains(line)) line], [for (final line in theirs) differs[line] ?? line]);
    });
  });
}
