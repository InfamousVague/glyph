import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/library_folder.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/library_folder_pane.dart';

import 'stage9_support.dart';

/// Settings › Library folder (lib/settings/panes/library_folder_pane.dart): where the notes are, a folder chosen in
/// the system's own picker and said before anything moves, the move, the way home, and the page on a device that
/// cannot. A port of `src/app/settings/LibraryFolderPane.test.tsx`, case for case: the core's commands and the
/// activity's picker are stood in for, each answering as library_commands.rs and files/LibraryTree.kt do; the
/// activity's own words are read out of its Kotlin.
const home = {'kind': 'app', 'path': null, 'name': null, 'reachable': true, 'notes': 2, 'own': '/data/user/0/com.mattssoftware.glyph.flutter/Library'};
const vault = {'kind': 'tree', 'path': null, 'name': 'Vault', 'reachable': true, 'notes': 5, 'own': '/data/user/0/com.mattssoftware.glyph.flutter/Library'};
const tree = 'content://com.android.externalstorage.documents/tree/primary%3ANotes';

void main() {
  setUpAll(loadAppFonts);

  late FakeCore core;
  late int changed;
  late List<String> picked;

  /// The folder's calls over the fakes; the picker answers [answer].
  LibraryFolder folder({String? answer, TargetPlatform platform = TargetPlatform.android}) => LibraryFolder(
        invoke: core.invoke,
        platform: platform,
        onNotesChanged: () => changed += 1,
        pickTree: answer == null
            ? null
            : () async {
                picked.add('picker');
                return answer;
              },
      );

  Future<void> show(WidgetTester tester, LibraryFolder? given) => showPane(tester, 'Library folder', (context) => LibraryFolderPane(folder: given));

  setUp(() {
    core = FakeCore()..answers['library_root'] = home;
    changed = 0;
    picked = [];
  });

  group('Settings › Library folder, on Android', () {
    testWidgets('says where the notes are, and what a folder holds before anything moves into it', (tester) async {
      core.answers['library_inspect'] = {'kind': 'tree', 'path': null, 'name': 'Vault', 'markdown': 3, 'obsidian': true, 'notes': 2};
      core.answers['library_move'] = {'notes': 2, 'adopted': 3, 'renamed': 1, 'same': 0, 'removed': 2, 'status': vault};
      await show(tester, folder(answer: jsonEncode({'uri': tree, 'name': 'Vault'})));
      await letRun(tester);
      expect(rowLabels(tester, 'Where your notes are'), ['Ghost.md’s own folder', 'Choose a folder…', 'Open library from git…']);
      expect(hintOfRow(tester, 'Ghost.md’s own folder'), '2 notes. /data/user/0/com.mattssoftware.glyph.flutter/Library');
      expect(hintOfRow(tester, 'Choose a folder…'), 'In the phone’s folder picker.');
      expect(rowCalled('Use Ghost.md’s own folder'), findsNothing);

      await tapOn(tester, find.text('Choose a folder…'));
      await letRun(tester);
      expect(picked, ['picker']);
      expect(core.calls.firstWhere((call) => call.command == 'library_inspect').args, {'uri': tree});
      expect(cardCalled('Use Vault?'), findsOneWidget);
      final said = pageText(tester);
      expect(said, contains('Vault has 3 Markdown files, and Obsidian keeps it. Each becomes a note and stays where it is, as it is.'));
      expect(said, contains('Your 2 notes move in beside them'));
      expect(said, contains('Once they are in, they leave Ghost.md’s own folder.'));
      expect(core.commands, isNot(contains('library_move')));

      await tapOn(tester, actionSaying('Use it'));
      await letRun(tester);
      expect(find.text('Your notes are in Vault now. 2 notes moved in, 3 notes that were there already, 1 renamed with a number.'), findsOneWidget);
      expect(core.commands, ['library_root', 'library_inspect', 'library_move']);
      expect(changed, 1);
      expect(hintOfRow(tester, 'Vault'), '5 notes. Chosen on this phone.');
      expect(rowCalled('Use Ghost.md’s own folder'), findsOneWidget);
      expect(cardCalled('Use Vault?'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('an empty folder says so, with the phone’s own good-to-know', (tester) async {
      core.answers['library_inspect'] = {'kind': 'tree', 'path': null, 'name': 'Notes', 'markdown': 0, 'obsidian': false, 'notes': 2};
      await show(tester, folder(answer: jsonEncode({'uri': tree, 'name': 'Notes'})));
      await letRun(tester);
      expect(rowLabels(tester, 'Good to know'), ['A folder on the phone is the reliable one', 'iCloud Drive', 'Sync', 'What stays in Ghost.md']);
      await tapOn(tester, find.text('Choose a folder…'));
      await letRun(tester);
      expect(cardCalled('Use Notes?'), findsOneWidget);
      expect(pageText(tester), contains('Notes is empty of notes. Your 2 notes move in, in the same folders'));
      // Cancel leaves everything where it was.
      await tapOn(tester, actionSaying('Cancel'));
      expect(cardCalled('Use Notes?'), findsNothing);
      expect(core.commands, ['library_root', 'library_inspect']);
      await endSettings(tester);
    });

    testWidgets('does nothing when the picker is closed, and says what the app said when a folder cannot be the library', (tester) async {
      var answer = jsonEncode({'cancelled': true});
      final given = LibraryFolder(invoke: core.invoke, platform: TargetPlatform.android, pickTree: () async => answer);
      await show(tester, given);
      await letRun(tester);
      await tapOn(tester, find.text('Choose a folder…'));
      await letRun(tester);
      expect(actionSaying('Use it'), findsNothing);
      expect(core.commands, ['library_root']);

      answer = jsonEncode({'uri': tree, 'name': 'Notes'});
      core.answers['library_inspect'] = const CoreError('That folder could not be read: Ghost.md no longer has that folder. Choose it again.');
      await tapOn(tester, find.text('Choose a folder…'));
      await letRun(tester);
      expect(find.text('That folder could not be read: Ghost.md no longer has that folder. Choose it again.'), findsOneWidget);

      answer = jsonEncode({'error': 'Ghost.md can’t keep that folder. Choose another.'});
      await tapOn(tester, find.text('Choose a folder…'));
      await letRun(tester);
      expect(find.text('Ghost.md can’t keep that folder. Choose another.'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('goes home with a copy or with none, and says the folder keeps every file', (tester) async {
      core.answers['library_root'] = vault;
      core.answers['library_use_app_folder'] = (Map<String, Object?> args) => {'notes': args['copy'] == true ? 5 : 0, 'adopted': 0, 'renamed': 0, 'same': 0, 'removed': 0, 'status': {...home, 'notes': 5}};
      await show(tester, folder(answer: '{}'));
      await letRun(tester);
      await tapOn(tester, find.text('Use Ghost.md’s own folder'));
      expect(pageText(tester), contains('Vault keeps every file either way: Ghost.md never deletes anything in a folder of yours.'));
      expect(rowLabels(tester, 'Back to Ghost.md’s own folder?'), ['Bring a copy back', 'Start empty', 'Stay in the folder']);
      await tapOn(tester, actionSaying('Copy'));
      await letRun(tester);
      expect(find.text('Back in Ghost.md’s own folder. 5 notes moved in.'), findsOneWidget);
      expect(core.calls.last.command, 'library_use_app_folder');
      expect(core.calls.last.args, {'copy': true});
      expect(changed, 1);

      // And with none: the same call, and no count to say.
      core.answers['library_root'] = vault;
      await show(tester, folder(answer: '{}'));
      await letRun(tester);
      await tapOn(tester, find.text('Use Ghost.md’s own folder'));
      await tapOn(tester, actionSaying('Start'));
      await letRun(tester);
      expect(find.text('Back in Ghost.md’s own folder.'), findsOneWidget);
      expect(core.calls.last.args, {'copy': false});
      await endSettings(tester);
    });

    testWidgets('says so when the chosen folder cannot be reached, and that its notes are untouched', (tester) async {
      core.answers['library_root'] = {...vault, 'name': 'Backup', 'reachable': false};
      await show(tester, folder(answer: '{}'));
      await letRun(tester);
      final said = pageText(tester);
      expect(said, contains('Backup can’t be reached'));
      expect(said, contains('the notes in yours are untouched'));
      await endSettings(tester);
    });

    test('uses the activity’s own words for the channel and the answer', () {
      String kotlin(String path) => File('android/app/src/main/kotlin/com/mattssoftware/$path').readAsStringSync();
      final bridge = kotlin('ghost_md/FilesBridge.kt');
      expect(bridge, contains('const val CHANNEL = "${filesChannel.name}"'));
      expect(bridge, contains('"chooseLibraryFolder" ->'));
      final picker = kotlin('glyph/files/LibraryTree.kt');
      expect(picker, contains('put("uri", uri.toString())'));
      expect(picker, contains('put("cancelled", true)'));
      expect(picker, contains('private const val NO_PICKER = "This phone has no way to choose a folder."'));
    });
  });

  group('Settings › Library folder, where it cannot', () {
    testWidgets('needs the app’s next update with no picker or off the phone, and is not on an iPhone yet', (tester) async {
      await show(tester, null);
      await letRun(tester);
      expect(find.text('Needs the app’s next update'), findsOneWidget);
      expect(find.text('This version of Ghost.md keeps the notes in its own folder only. Update it to choose another.'), findsOneWidget);
      await show(tester, folder(platform: TargetPlatform.macOS));
      await letRun(tester);
      expect(find.text('Needs the app’s next update'), findsOneWidget);
      await show(tester, folder(platform: TargetPlatform.iOS));
      await letRun(tester);
      expect(find.text('Not on iPhone yet'), findsOneWidget);
      expect(find.text('Library folder'), findsWidgets, reason: 'the hero stays');
      expect(core.commands, isEmpty);
      await endSettings(tester);
    });

    test('where a folder can be chosen from', () async {
      expect(await folder(answer: '{}').way(), FolderWay.android);
      expect(await folder(platform: TargetPlatform.iOS).way(), FolderWay.none);
      expect(await folder(platform: TargetPlatform.macOS).way(), FolderWay.update);
      expect(folderGeneration, 25);
    });

    test('reads the picker’s answer, and says what an empty folder and a copy from another folder will do', () {
      expect(readFolderAnswer('{"uri":"content://x/tree/y","name":"y"}'), const FolderGranted('content://x/tree/y', 'y'));
      expect(readFolderAnswer('{"cancelled":true}'), const FolderCancelled());
      for (final odd in ['{"uri":"file:///sdcard"}', 'nonsense', '[]']) {
        expect(readFolderAnswer(odd), isA<FolderRefused>(), reason: odd);
      }
      const candidate = Candidate(kind: 'folder', path: '/x', name: 'Drive', markdown: 1, notes: 4);
      expect(
        candidateSaid(candidate, false),
        'Drive has 1 Markdown file. Each becomes a note and stays where it is, as it is. Your 4 notes are copied in beside them, in the same folders, and a note whose name is taken there gets “2” after it. The folder they are in now keeps its copy.',
      );
      expect(candidateSaid(const Candidate(kind: 'tree', name: 'Empty'), true), 'Empty is empty of notes. You have no notes to bring.');
      expect(whereSaid(const LibraryStatus(kind: 'folder', name: 'Vault', path: '/Users/matt/Obsidian/Vault', notes: 1)), ('Vault', '1 note. /Users/matt/Obsidian/Vault'));
      expect(whereSaid(const LibraryStatus(kind: 'tree', name: '', notes: 0)), ('A folder of yours', '0 notes. Chosen on this phone.'));
      expect(failureOf(const CoreError('Choose a folder first.')), 'Choose a folder first.');
      expect(failureOf(PlatformException(code: 'x')), 'That didn’t work.');
    });

    test('the phone’s picker with no phone half says there is no way to choose', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(readFolderAnswer(await pickTreeOnPhone()), const FolderRefused('This phone has no way to choose a folder.'));
    });
  });
}

/// The line under the row called [label].
String? hintOfRow(WidgetTester tester, String label) {
  final hint = tester.widget<SettingRow>(rowCalled(label)).hint;
  return hint is Text ? hint.data : null;
}
