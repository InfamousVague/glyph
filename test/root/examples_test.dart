import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

/// Settings › About › Examples (App.tsx `openSample`): each of its four rows makes its note and opens it. They
/// were drawn and could not be pressed on any platform: the root gave the sheet no press for them, so the pane
/// dimmed each row and a tap did nothing (found walking the iPhone app, 2026-10-09).
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  Future<SampleLibrary> open(WidgetTester tester) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: MemoryStored()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return library;
  }

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));
  SettingsSheet sheetOf(WidgetTester tester) => tester.widget<SettingsSheet>(find.byType(SettingsSheet));

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('every row has a press: none is left dimmed', (tester) async {
    await open(tester);
    final sheet = sheetOf(tester);
    expect(sheet.onSample, isNotNull);
    expect(sheet.onBoard, isNotNull);
    expect(sheet.onCanvas, isNotNull);
    expect(sheet.onHowCanvas, isNotNull);
    await close(tester);
  });

  testWidgets('the example canvas and the How Ghost.md works canvas are made and opened', (tester) async {
    final library = await open(tester);
    for (final press in [(SettingsSheet sheet) => sheet.onCanvas!, (SettingsSheet sheet) => sheet.onHowCanvas!]) {
      final before = library.value.length;
      await tester.runAsync(() async {
        press(sheetOf(tester))();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await settle(tester);
      expect(library.value.length, before + 1);
      final made = library.noteOf(shellOf(tester).shown!)!;
      expect(isCanvasBody(made.body), isTrue, reason: 'the note opened is the canvas just made');
      // Settings went as the note was made.
      expect(sheetOf(tester).open, isFalse);
      shellOf(tester).backToList();
      await settle(tester, 2);
    }
    await close(tester);
  });

  // Differs 35 (docs/PARITY.md): the sample note came without its picture and the example canvas without its picture
  // card (core/seed.ts `samplePicture`: the bundled photograph kept as a picture of this device's, where one can be).
  testWidgets('where pictures are kept, the sample note is made with its picture and the example canvas with its picture card', (tester) async {
    final sent = <({String command, Map<String, Object?> args})>[];
    Future<Object?> core(String command, [Map<String, Object?> args = const <String, Object?>{}]) async {
      sent.add((command: command, args: args));
      return null;
    }

    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, core: core, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, stored: MemoryStored()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      sheetOf(tester).onSample!();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await settle(tester);
    final kept = [for (final call in sent) if (call.command == 'sync_put_file' && call.args['kind'] == 'image') call.args['name'] as String];
    expect(kept, hasLength(1), reason: 'the bundled photograph was kept among the library\'s pictures');
    final note = library.noteOf(shellOf(tester).shown!)!.body;
    expect(note, contains('## Pictures\n\nPaste one, or press and hold and choose Add image. It sits under its own line, and the line stays:\n\n![A wisp of smoke, by Jocelyn Morales](image/${kept.single})\n\n## Without typing'));
    expect(note.replaceFirst(RegExp(r'## Pictures[\s\S]*?(?=## Without typing)'), ''), sampleNoteBody, reason: 'and is the sample note in every other word');
    shellOf(tester).backToList();
    await settle(tester, 2);

    await tester.runAsync(() async {
      sheetOf(tester).onCanvas!();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await settle(tester);
    final names = [for (final call in sent) if (call.command == 'sync_put_file' && call.args['kind'] == 'image') call.args['name'] as String];
    expect(names, hasLength(2));
    final canvas = canvasOf(library.noteOf(shellOf(tester).shown!)!.body)!;
    final card = canvas.nodes.firstWhere((node) => node.id == 'view');
    expect(card.file, names.last);
    expect(canvas.edges.any((edge) => edge.id == 'e8'), isTrue, reason: 'and the line to it, "the view"');
    await close(tester);
  });

  testWidgets('the sample note and the example board are made and opened', (tester) async {
    final library = await open(tester);
    await tester.runAsync(() async {
      sheetOf(tester).onSample!();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester);
    expect(library.noteOf(shellOf(tester).shown!)!.body, sampleNoteBody);
    shellOf(tester).backToList();
    await settle(tester, 2);
    await tester.runAsync(() async {
      sheetOf(tester).onBoard!();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester);
    expect(library.noteOf(shellOf(tester).shown!)!.body, boardNoteBody);
    await close(tester);
  });
}
