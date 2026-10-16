import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/shared_files.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/share/share_in.dart';
import 'package:ghost_md/share/share_in_keep.dart';
import 'package:ghost_md/share/ui/share_in_sheet.dart';

import '../support/render.dart';

/// The sheet a share opens (lib/share/ui/share_in_sheet.dart): a new note named for the share, in a workspace or
/// none; or added to a note found by its name, the one added to last first; Cancel.
void main() {
  setUpAll(loadAppFonts);

  late SampleLibrary library;
  late WorkspaceStore workspaces;
  late MemoryStored kept;
  late Directory data;

  setUp(() {
    library = SampleLibrary([
      const Note(id: 'plan', body: '# Weekend plan\n\nPack.\n', createdAt: 1, updatedAt: 30),
      const Note(id: 'reading', body: '# Reading list\n', createdAt: 1, updatedAt: 20),
      const Note(id: 'board', body: '---\ntitle: "Board"\n---\n{"nodes":[],"edges":[]}', createdAt: 1, updatedAt: 40),
      const Note(id: 'recipes', body: '# Recipes\n', createdAt: 1, updatedAt: 10),
    ]);
    workspaces = WorkspaceStore()
      ..addWorkspace('Work', 'moss')
      ..addWorkspace('Home', 'sea');
    kept = MemoryStored();
    data = Directory.systemTemp.createTempSync('ghost-share-ui-');
  });
  tearDown(() => data.deleteSync(recursive: true));

  ShareKeeper keeper() => ShareKeeper(library: library, workspaces: workspaces, keepFile: (source, name) => storeSharedFile(source, name: name, dataDir: data.path), adoptPicture: (path) async => 'p.jpg', kept: kept);

  const link = SharedIn(id: 's1', text: 'https://example.com/houses', subject: 'Houses for rent near the river');

  Future<List<Note?>> open(WidgetTester tester, SharedIn share, {Size size = const Size(430, 932), String theme = 'dark'}) async {
    final done = <Note?>[];
    final keep = keeper();
    await pumpApp(
      tester,
      size: size,
      ratio: 3,
      prefs: AppPreferences(theme: theme),
      home: Builder(builder: (context) => ShareInSheet(share: share, keeper: keep, notes: shareTargets(library.value), onDone: done.add)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return done;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a link: a new note named by the page’s title, filed in the workspace chosen', (tester) async {
    final done = await open(tester, link);
    expect(find.text('A link.'), findsOneWidget);
    expect(find.text('Houses for rent near the river'), findsOneWidget, reason: 'the title it is given, to change');
    await tap(tester, 'share-space-${workspaces.value.list.last.id}');
    await tap(tester, 'share-save');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(done, hasLength(1));
    final note = done.single!;
    expect(note.body, '# Houses for rent near the river\n\n[Houses for rent near the river](https://example.com/houses)\n');
    expect(workspaces.value.of[note.id], workspaces.value.list.last.id);
    debugDisableShadows = true;
  });

  testWidgets('added to a note found by its name, no canvas among them, the one added to last first', (tester) async {
    kept.write(shareRecentKey, ['recipes']);
    final done = await open(tester, const SharedIn(id: 's2', text: 'Pancakes: 2 eggs, 100 g flour.'));
    await tap(tester, 'share-onto');
    final rows = tester.widgetList<Widget>(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('share-to-'))).map((w) => (w.key! as ValueKey<String>).value).toList();
    expect(rows, ['share-to-recipes', 'share-to-plan', 'share-to-reading'], reason: 'the last added to, then the newest; the canvas is never offered');
    await tester.enterText(find.byKey(const ValueKey('share-find')).first, 'read');
    await tester.pump();
    expect(find.byKey(const ValueKey('share-to-reading')), findsOneWidget);
    expect(find.byKey(const ValueKey('share-to-plan')), findsNothing);
    await tap(tester, 'share-to-reading');
    await tap(tester, 'share-save');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(done.single!.id, 'reading');
    expect(library.noteOf('reading')!.body, '# Reading list\n\nPancakes: 2 eggs, 100 g flour.\n');
    expect(kept.read<List<Object?>>(shareRecentKey, const []), ['reading', 'recipes']);
    debugDisableShadows = true;
  });

  testWidgets('Cancel keeps nothing', (tester) async {
    final done = await open(tester, link);
    await tap(tester, 'share-cancel');
    expect(done, [null]);
    expect(library.value, hasLength(4));
    debugDisableShadows = true;
  });

  // Pictures to look at, not held: `FEATURE_SHOTS=1 flutter test --update-goldens test/share_ui/share_in_sheet_test.dart`
  // writes them under build/feature-shots/share-import/.
  final shots = Platform.environment.containsKey('FEATURE_SHOTS');
  for (final (name, size) in [('phone', const Size(430, 932)), ('fold', const Size(900, 1000))]) {
    testWidgets('a picture: the sheet for a link, and for adding to a note, on the $name', (tester) async {
      await open(tester, link, size: size);
      await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/share-import/share-new-$name-dark.png'));
      await tap(tester, 'share-onto');
      await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/share-import/share-onto-$name-dark.png'));
      debugDisableShadows = true;
    }, skip: !shots);
  }
}
