// Pictures of the Lovart plugin's steps for the website's page, ghostmarkdown.com/lovart.html (Matt, 2026-10-26:
// "update the website with more imagery by generating some prompts and showing screenshots of the different steps
// too"): the whole app on a phone, 390 by 844 at 2x as landing/shots/ are, light and dark, over the app put together
// (lib/root/ghost_root.dart) with the plugin on and keys held. Written only by `flutter test --update-goldens
// test/site/lovart_site_shots_test.dart`, into build/feature-shots/lovart-site/<name>-<theme>.png (not committed);
// scripts/lovart-site-shots.sh runs it and makes the dark ones into landing/shots/lovart-<name>.webp.
//
// - `cue`: Matt's test note open, each `{image: …}` with its wash and Lovart's mark after it.
// - `making`: Return at the end of the reading nook's line, its stand-in under it and the mark turning. Lovart is a
//   client that never answers, so it stays there.
// - `menu`: the note's More sheet at its Lovart rows, Make images and Inspiration images.
// - `settings`: Settings › Plugins › Lovart with keys kept.
// - `done` and `inspiration`: the cues made into pictures, and a moodboard of four under `## Inspiration`. Their
//   pictures are Lovart's own from Matt's account, read from the folder `LOVART_SHOT_IMAGES` names (its .png, .jpg
//   and .webp in name order: the first two the cues', the last four the moodboard's); without it they are skipped.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/plugins/built_in.dart' show builtIn;
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:ghost_md/plugins/registry.dart' show MemorySwitches, createRegistry, usePlugins;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../plugins/support.dart';
import '../support/render.dart';

const String noteId = 'lovart-examples';

/// Matt's test note, cut to what a phone shows above the page's dock: its title, its first words, a cue on its own
/// line and one inside a sentence, prompts as he wrote them.
const String body = '# Lovart examples\n'
    '\n'
    'A note to try the Lovart plugin on. Add your keys in Settings › Plugins › Lovart first; each image uses your Lovart credits.\n'
    '\n'
    '{image: a cozy reading nook by a rainy window, warm lamp light, soft film photo}\n'
    '\n'
    'The landing page opens on {image: a wide banner of misty pine hills at dawn, pale gold light, minimal} with the headline over it.\n';

const String nook = '{image: a cozy reading nook by a rainy window, warm lamp light, soft film photo}';

/// Lovart, asked and never answering: the cue stays being made.
class Waiting extends LovartClient {
  Waiting() : super(accessKey: 'ak', secretKey: 'sk');

  @override
  Future<List<Uint8List>> generate(String prompt, {Duration timeout = lovartTimeout}) => Completer<List<Uint8List>>().future;
}

/// The pictures Lovart made on Matt's account, for `done` and `inspiration`: the folder's in name order.
List<File> shotImages() {
  final dir = Platform.environment['LOVART_SHOT_IMAGES'];
  if (dir == null || dir.isEmpty || !Directory(dir).existsSync()) return const [];
  final files = Directory(dir).listSync().whereType<File>().where((f) => RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(f.path)).toList()
    ..sort((a, b) => a.path.split('/').last.compareTo(b.path.split('/').last));
  return files;
}

/// The device's pictures as the core keeps them: files in [dir], found by name (lib/core/native/files.dart).
Future<Object?> Function(String command, [Map<String, Object?> args]) coreOver(Directory dir) => (command, [args = const <String, Object?>{}]) async {
      final name = args['name'];
      if (args['kind'] != 'image' || name is! String) return null;
      final file = File('${dir.path}/$name');
      switch (command) {
        case 'file_path':
          return file.existsSync() ? {'path': file.path, 'bytes': file.lengthSync()} : null;
        case 'read_file':
          return file.existsSync() ? base64.encode(file.readAsBytesSync()) : null;
        case 'file_exists':
          return file.existsSync();
        case 'sync_put_file':
          file.writeAsBytesSync(base64.decode(args['base64']! as String));
          return null;
      }
      return null;
    };

void main() {
  setUpAll(loadAppFonts);

  late Directory store;

  setUp(() async {
    store = Directory.systemTemp.createTempSync('lovart-site-');
    usePluginGround(TestGround().ground);
    final registry = createRegistry(builtIn, store: MemorySwitches());
    registry.setEnabled('lovart', true);
    usePlugins(registry);
    await lovart.host.secrets.write(accessKeySecret, 'ak-3f9c2e7a51d04b86');
    await lovart.host.secrets.write(secretKeySecret, 'sk-8d14b0c6e29f7a35');
    setDesignMeetings(true);
    lovartClient = () => Waiting();
  });

  tearDown(() {
    lovartMaking.value = const {};
    lovartClient = () => LovartClient.kept();
    usePluginGround(PluginGround());
    usePlugins(createRegistry(const []));
    store.deleteSync(recursive: true);
  });

  /// Time for the pictures to be read from their files and drawn: the machine's clock, then the test's.
  Future<void> settle(WidgetTester tester, [int beats = 8]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The app over the sample library with [text] as the note [noteId], opened.
  Future<NoteScreenState> open(WidgetTester tester, String theme, String text) async {
    final library = SampleLibrary.seeded();
    await tester.runAsync(() => library.apply(Note(id: noteId, body: text, createdAt: seedNow - 600000, updatedAt: seedNow - 600000)));
    await pumpApp(
      tester,
      prefs: Preferences(theme: theme),
      home: GhostRoot(
        launch: false,
        core: coreOver(store),
        library: library,
        stored: MemoryStored(),
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
      ),
    );
    // The site's shots have no phone's status bar over them, only a step above the app's bar.
    tester.view.padding = const FakeViewPadding(top: 20);
    tester.view.viewPadding = const FakeViewPadding(top: 20);
    await tester.pump(const Duration(milliseconds: 300));
    tester.state<AppShellState>(find.byType(AppShell)).openNote(noteId);
    await settle(tester);
    return tester.state<NoteScreenState>(find.byType(NoteScreen));
  }

  Future<void> snap(WidgetTester tester, String name, String theme) async {
    Directory('build/feature-shots/lovart-site').createSync(recursive: true);
    await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/lovart-site/$name-$theme.png'));
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  /// The note's page scrolled until the line at [pos] is [top] from the window's top, its pictures read on the way.
  Future<void> bringUp(WidgetTester tester, NoteScreenState screen, int pos, {double top = 110}) async {
    final page = tester.stateList<ScrollableState>(find.byType(Scrollable)).firstWhere((s) => s.position.axis == Axis.vertical && s.position.maxScrollExtent > 0 && s.context.findAncestorStateOfType<NoteScreenState>() == screen);
    for (var at = 0.0; at <= page.position.maxScrollExtent + 300; at += 300) {
      page.position.jumpTo(math.min(at, page.position.maxScrollExtent));
      await settle(tester, 3);
      final rect = screen.view!.coordsAtPos(pos);
      if (rect == null || rect.top < 0 || rect.top > 844) continue;
      page.position.jumpTo((page.position.pixels + rect.top - top).clamp(0, page.position.maxScrollExtent));
      await settle(tester, 6);
      return;
    }
    fail('The line at $pos never came onto the page.');
  }

  for (final theme in ['dark', 'light']) {
    testWidgets('cue, $theme', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      await open(tester, theme, body);
      await snap(tester, 'cue', theme);
    });

    testWidgets('making, $theme', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      final screen = await open(tester, theme, body);
      // Return at the end of the reading nook's line, as typed.
      final view = screen.view!;
      final line = view.state.doc.line(5);
      expect(line.text, nook);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: line.to, insert: '\n'), selection: EditorSelection.single(line.to + 1), userEvent: 'input'));
      await tester.pump();
      expect(lovartIsMaking(noteId, nook), isTrue);
      await settle(tester, 4);
      // The ring at a fixed turn.
      await tester.pump(const Duration(milliseconds: 180));
      await snap(tester, 'making', theme);
    });

    testWidgets('menu, $theme', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      await open(tester, theme, body);
      await tester.tap(find.bySemanticsLabel('More for this note'));
      await settle(tester, 4);
      await Scrollable.ensureVisible(tester.element(find.text('Inspiration images')), alignment: 0.6);
      await settle(tester, 3);
      await snap(tester, 'menu', theme);
    });

    testWidgets('settings, $theme', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      await open(tester, theme, body);
      tester.state<AppShellState>(find.byType(AppShell)).backToList();
      await settle(tester, 4);
      // The home page's dock: Settings at its foot, then Plugins, Lovart, and its own page.
      await tester.tap(find.bySemanticsLabel('Settings').last);
      await settle(tester, 4);
      await tester.ensureVisible(find.text('Plugins').last);
      await settle(tester, 2);
      await tester.tap(find.text('Plugins').last);
      await settle(tester, 4);
      await tester.ensureVisible(find.text('Lovart').last);
      await settle(tester, 2);
      await tester.tap(find.text('Lovart').last);
      await settle(tester, 4);
      // Its card's page, whose Settings row, "Keys kept", is the way to its own.
      if (find.byType(LovartPane).evaluate().isEmpty) {
        await tester.ensureVisible(find.text('Keys kept').first);
        await settle(tester, 2);
        await tester.tap(find.text('Keys kept').first);
        await settle(tester, 6);
      }
      expect(find.byType(LovartPane), findsOneWidget);
      expect(find.text('Keys kept'), findsOneWidget);
      await snap(tester, 'settings', theme);
    });

    testWidgets('done, $theme', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      final names = keepShotImages(store, shotImages().take(2).toList());
      if (names.length < 2) {
        markTestSkipped('No pictures for `done`: set LOVART_SHOT_IMAGES to a folder of Lovart\'s images (.png, .jpg, .webp), two or more.');
        return;
      }
      final text = made(names);
      final screen = await open(tester, theme, text);
      await settle(tester, 10);
      // The first picture's line under the tabs, so the picture and its badge are clear of the page's dock.
      await bringUp(tester, screen, text.indexOf('!['));
      await snap(tester, 'done', theme);
    });

    testWidgets('inspiration, $theme', (tester) async {
      if (!autoUpdateGoldenFiles) return;
      final images = shotImages();
      if (images.length < inspirationCount) {
        markTestSkipped('No pictures for `inspiration`: set LOVART_SHOT_IMAGES to a folder of four or more of Lovart\'s images.');
        return;
      }
      // The cues' pictures first where there are enough, else the moodboard's own for them too.
      final cues = keepShotImages(store, (images.length >= inspirationCount + 2 ? images : images.skip(images.length - inspirationCount)).take(2).toList());
      final board = keepShotImages(store, images.skip(images.length - inspirationCount).toList(), from: 3);
      final text = withInspiration(made(cues), board);
      final screen = await open(tester, theme, text);
      await settle(tester, 10);
      await bringUp(tester, screen, text.indexOf(inspirationHeading));
      await snap(tester, 'inspiration', theme);
    });
  }
}

/// [files] copied into the picture store [dir] as Lovart's pictures are named, `lovart-<n>.<ext>` from [from], and
/// their names.
List<String> keepShotImages(Directory dir, List<File> files, {int from = 1}) => [
      for (final (i, file) in files.indexed)
        () {
          final bytes = file.readAsBytesSync();
          final name = 'lovart-${from + i}.${pictureExtension(bytes) ?? file.path.split('.').last.toLowerCase()}';
          File('${dir.path}/$name').writeAsBytesSync(bytes);
          return name;
        }(),
    ];

/// [body] with its cues made into the pictures [names], in order, as Make images leaves it.
String made(List<String> names) {
  var text = body;
  final cues = imageCues(text);
  for (var i = cues.length - 1; i >= 0; i--) {
    text = withImage(text, cues[i], names[i]);
  }
  return text;
}
