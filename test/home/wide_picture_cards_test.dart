// Two cards across on an opened Fold, one of them with its picture drawn: the row of cards (lib/home/note_card.dart
// `CardRow`) asks each card its height before laying it out, and a picture sized by a LayoutBuilder could not say
// it, so the home page threw ("LayoutBuilder does not support returning intrinsic dimensions") and its slivers
// after it. One card to a row (430 wide) never asked. The picture's box says its height now
// (lib/editor/media/images.dart `FitPictureBox`); this holds the home page to it, through the app put together.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/note_card.dart' show CardRow;
import 'package:ghost_md/root/ghost_root.dart';

import '../core/make_note.dart';
import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);
  final seedNow = DateTime(2026, 9, 12, 12).millisecondsSinceEpoch;
  final porch = File('test/editor/media/fixtures/porch.png');

  Future<Object?> core(String command, [Map<String, Object?> args = const <String, Object?>{}]) async {
    if (command == 'file_path' && args['kind'] == 'image') return {'path': porch.path, 'bytes': porch.lengthSync()};
    return null;
  }

  for (final width in [669.0, 900.0]) {
    testWidgets('a note’s card with its picture drawn lays out two across at $width wide, its row one height', (tester) async {
      final library = SampleLibrary([...seedLibrary(seedNow), makeNote('pictured', body: '# One picture\n\nWords.\n\n![a](image/a.jpg)\n', updatedAt: seedNow + 1000)], clock: () => seedNow);
      await pumpApp(
        tester,
        size: Size(width, 1000),
        ratio: 3,
        prefs: const Preferences(theme: 'dark'),
        home: GhostRoot(
          launch: false,
          core: core,
          library: library,
          stored: MemoryStored(),
          workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
          clock: () => seedNow,
        ),
      );
      // The picture's file is found, and read, on the clock of the world.
      for (var i = 0; i < 10; i += 1) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(CardRow), findsWidgets, reason: 'two cards across');
      final pictured = find.ancestor(of: find.text('One picture'), matching: find.byType(CardRow));
      expect(pictured, findsWidgets);
      expect(find.descendant(of: pictured.first, matching: find.byType(RawImage)), findsOneWidget, reason: 'its picture drawn');
      final row = tester.renderObject<RenderBox>(pictured.first);
      expect(row.hasSize, isTrue);
      // Every card of the row stands as tall as the row.
      final cells = find.descendant(of: pictured.first, matching: find.byType(RepaintBoundary)).evaluate().map((e) => e.renderObject! as RenderBox).where((box) => (box.parent) == row);
      expect(cells.length, greaterThan(1));
      for (final cell in cells) {
        expect(cell.size.height, row.size.height);
      }
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
