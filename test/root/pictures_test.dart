// A picture added from the phone, through the app put together (lib/root/note_desk.dart over
// lib/core/phone_pictures.dart): the +'s Picture and the band's Add image are offered only where there is a
// chooser, and what is chosen goes in at the caret on a line of its own. The chooser and the core are this file's.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/band/band.dart' show ContextBand;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/plus/plus.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);
  final seedNow = DateTime(2026, 9, 12, 12).millisecondsSinceEpoch;
  final sent = <({String command, Map<String, Object?> args})>[];

  Future<Object?> core(String command, [Map<String, Object?> args = const <String, Object?>{}]) async {
    sent.add((command: command, args: args));
    return null;
  }

  Future<SampleLibrary> open(WidgetTester tester, {String? picked, bool chooser = true}) async {
    sent.clear();
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(
        launch: false,
        core: core,
        library: library,
        stored: MemoryStored(),
        workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())),
        clock: () => seedNow,
        picturePicker: chooser ? (adopt) => () async => picked == null ? null : adopt(picked) : null,
      ),
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
  NoteScreenState screenOf(WidgetTester tester) => tester.state<NoteScreenState>(find.byType(NoteScreen));

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
  }

  Future<NoteScreenState> launchWeek(WidgetTester tester, SampleLibrary library) async {
    shellOf(tester).openNote(library.value.firstWhere((note) => noteTitle(note.body) == 'Launch week').id);
    await settle(tester);
    return screenOf(tester);
  }

  testWidgets('the +’s Picture keeps what was chosen and writes its line at the caret, as one change', (tester) async {
    final library = await open(tester, picked: '/cache/picked/a.jpg');
    final screen = await launchWeek(tester, library);
    final before = screen.view!.state.doc.toString();
    screen.view!.dispatch(TransactionSpec(selection: EditorSelection.single(before.length)));
    tester.widget<PlusLayer>(find.byType(PlusLayer)).config.onPicture!();
    await settle(tester);
    final kept = sent.singleWhere((call) => call.command == 'sync_put_file_path');
    expect(kept.args['kind'], 'image');
    expect(kept.args['path'], '/cache/picked/a.jpg');
    expect(screen.view!.state.doc.toString(), contains('![](image/${kept.args['name']})'));
    undo(StateCommandTarget(screen.view!.state, (tr) => screen.view!.dispatch(tr)));
    expect(screen.view!.state.doc.toString(), before);
    await close(tester);
  });

  testWidgets('the band’s Add image is the same chooser, and none chosen writes nothing', (tester) async {
    final library = await open(tester);
    final screen = await launchWeek(tester, library);
    final before = screen.view!.state.doc.toString();
    await tester.widget<ContextBand>(find.byType(ContextBand)).onAddImage!();
    await settle(tester);
    expect(screen.view!.state.doc.toString(), before);
    expect(sent.where((call) => call.command == 'sync_put_file_path'), isEmpty);
    await close(tester);
  });

  testWidgets('with no chooser neither is offered', (tester) async {
    final library = await open(tester, chooser: false);
    await launchWeek(tester, library);
    expect(tester.widget<PlusLayer>(find.byType(PlusLayer)).config.onPicture, isNull);
    expect(tester.widget<ContextBand>(find.byType(ContextBand)).onAddImage, isNull);
    await close(tester);
  });
}
