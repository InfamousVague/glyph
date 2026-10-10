// A picture added from the phone, through the app put together (lib/root/note_desk.dart over
// lib/core/phone_pictures.dart): the +'s Picture and the band's Add image are offered only where there is a
// chooser, and what is chosen goes in at the caret on a line of its own. And Pick a date, which is the calendar the
// app was given. The chooser, the calendar and the core are this file's.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/band/band.dart' show ContextBand;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/field_menu.dart' show dayPicker;
import 'package:ghost_md/editor/plus/plus.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/note_desk.dart';
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
        dayPicker: chooser ? (at, current) async => '2026-10-12' : null,
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

  // Unwired 21 (docs/PARITY.md): a keyboard's paste was words alone, so a picture on the clipboard pasted nothing
  // (editor/images.ts `pasteImages`: the picture is taken out of the paste, kept, and put in at the caret; words in
  // the same paste are dropped).
  testWidgets('a keyboard’s paste with a picture on the clipboard keeps the picture and writes its line; with words alone it pastes the words', (tester) async {
    const pictures = MethodChannel('ghost_md/pictures');
    Map<String, Object?> onClipboard = {'path': '/cache/clip/c.png'};
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(pictures, (call) async => call.method == 'clipboard' ? onClipboard : null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => call.method == 'Clipboard.getData' ? {'text': onClipboard['text']} : null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(pictures, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final library = await open(tester);
    final screen = await launchWeek(tester, library);
    final desk = tester.state<NoteDeskState>(find.byType(NoteDesk));
    final before = screen.view!.state.doc.toString();
    screen.view!.dispatch(TransactionSpec(selection: EditorSelection.single(before.length)));
    expect(await tester.runAsync(() => desk.editor.paste()), isTrue);
    await settle(tester);
    final kept = sent.singleWhere((call) => call.command == 'sync_put_file_path');
    expect((kept.args['kind'], kept.args['path']), ('image', '/cache/clip/c.png'));
    final withPicture = screen.view!.state.doc.toString();
    expect(withPicture, contains('![](image/${kept.args['name']})'));

    // Words alone on the clipboard: the paste is the editor's, as it always was.
    onClipboard = {'text': 'and the tripod'};
    expect(await tester.runAsync(() => desk.editor.paste()), isTrue);
    await settle(tester, 2);
    expect(screen.view!.state.doc.toString(), contains('and the tripod'));
    expect(sent.where((call) => call.command == 'sync_put_file_path'), hasLength(1));

    // A picture the phone could not read is said, and nothing is pasted in its place.
    onClipboard = {'error': 'That picture couldn’t be read from the clipboard.'};
    final was = screen.view!.state.doc.toString();
    expect(await tester.runAsync(() => desk.editor.paste()), isTrue);
    await settle(tester, 2);
    expect(screen.view!.state.doc.toString(), was);
    expect(find.text('That picture couldn’t be read from the clipboard.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Pick a date is the calendar the app was given, asked of the open note\'s editor', (tester) async {
    final library = await open(tester);
    final screen = await launchWeek(tester, library);
    final picker = screen.view!.state.facet(dayPicker);
    expect(await picker!(Offset.zero, null), '2026-10-12');
    await close(tester);
  });

  testWidgets('with no chooser neither is offered', (tester) async {
    final library = await open(tester, chooser: false);
    await launchWeek(tester, library);
    expect(tester.widget<PlusLayer>(find.byType(PlusLayer)).config.onPicture, isNull);
    expect(tester.widget<ContextBand>(find.byType(ContextBand)).onAddImage, isNull);
    expect(screenOf(tester).view!.state.facet(dayPicker), isNull);
    await close(tester);
  });
}
