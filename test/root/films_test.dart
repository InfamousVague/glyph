// A film added from the phone, through the app put together (lib/root/note_desk.dart over lib/core/films.dart):
// the +'s A video is offered only where there is a picker, what is chosen is written at the caret as a line of its
// own, its card plays where the film is on this phone, and a picture on the clipboard is pasted by the band's own
// reader. The picker, the device and the core are this file's.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/films.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/band/band.dart' show ContextBand, PhoneClipboard;
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/plus/plus.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

class _Device implements FilmDevice {
  final List<String> opened = <String>[];

  @override
  bool get plays => true;
  @override
  Future<bool> here(String video) async => video == 'kept.mp4';
  @override
  Future<FilmPlaying> open(String video) async {
    opened.add(video);
    return _Film();
  }
}

class _Film implements FilmPlaying {
  final ValueNotifier<bool> on = ValueNotifier<bool>(false);

  @override
  Widget surface() => const SizedBox();
  @override
  ValueListenable<bool> get playing => on;
  @override
  ValueListenable<int> get position => ValueNotifier<int>(0);
  @override
  int get durationMs => 12000;
  @override
  ValueListenable<bool> get failed => ValueNotifier<bool>(false);
  @override
  void play() => on.value = true;
  @override
  void pause() => on.value = false;
  @override
  void seek(int ms) {}
  @override
  void close() {}
}

void main() {
  setUpAll(loadAppFonts);
  final seedNow = DateTime(2026, 9, 12, 12).millisecondsSinceEpoch;
  final sent = <({String command, Map<String, Object?> args})>[];

  Future<Object?> core(String command, [Map<String, Object?> args = const <String, Object?>{}]) async {
    sent.add((command: command, args: args));
    return null;
  }

  final device = _Device();
  final asked = <({bool? wanted})>[];

  Future<SampleLibrary> open(WidgetTester tester, {PickedVideo? picked, bool picker = true, String? failing}) async {
    sent.clear();
    asked.clear();
    device.opened.clear();
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
        picturePicker: (adopt) => () async => null,
        films: Films(
          device: device,
          pick: !picker
              ? null
              : ({keep, copying}) async {
                  copying?.call();
                  if (failing != null) throw StateError(failing);
                  asked.add((wanted: keep?.call()));
                  return picked;
                },
        ),
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

  testWidgets('the +’s A video writes the film’s line at the caret as one change, and its card plays it', (tester) async {
    final library = await open(tester, picked: const PickedVideo(video: 'kept.mp4', poster: 'still.jpg', ms: 12400, width: 1080, height: 1920));
    final screen = await launchWeek(tester, library);
    final before = screen.view!.state.doc.toString();
    screen.view!.dispatch(TransactionSpec(selection: EditorSelection.single(before.length)));
    tester.widget<PlusLayer>(find.byType(PlusLayer)).config.onVideo!();
    await settle(tester);
    expect(asked.single.wanted, isTrue, reason: 'the note still open and its place still kept');
    expect(screen.view!.state.doc.toString(), contains('[![video 0:12](image/still.jpg)](video/kept.mp4)'));
    // The film is here: its card has the disc, and a press opens it on the device.
    expect(find.byKey(const ValueKey<String>('disc')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('disc')), warnIfMissed: false);
    await settle(tester);
    expect(device.opened, ['kept.mp4']);
    undo(StateCommandTarget(screen.view!.state, (tr) => screen.view!.dispatch(tr)));
    expect(screen.view!.state.doc.toString(), before);
    await close(tester);
  });

  testWidgets('none chosen writes nothing, and what goes wrong is said', (tester) async {
    var library = await open(tester);
    var screen = await launchWeek(tester, library);
    final before = screen.view!.state.doc.toString();
    tester.widget<PlusLayer>(find.byType(PlusLayer)).config.onVideo!();
    await settle(tester);
    expect(screen.view!.state.doc.toString(), before);
    await close(tester);

    library = await open(tester, failing: 'This kind of video can’t be added. MP4, MOV and WebM can.');
    screen = await launchWeek(tester, library);
    tester.widget<PlusLayer>(find.byType(PlusLayer)).config.onVideo!();
    await settle(tester, 2);
    expect(find.text('This kind of video can’t be added. MP4, MOV and WebM can.'), findsOneWidget);
    expect(screen.view!.state.doc.toString(), before);
    await close(tester);
  });

  testWidgets('with no picker A video is not offered, and a film’s line is still its card', (tester) async {
    final library = await open(tester, picker: false);
    await launchWeek(tester, library);
    expect(tester.widget<PlusLayer>(find.byType(PlusLayer)).config.onVideo, isNull);
    await close(tester);
  });

  testWidgets('the band’s Paste reads the phone’s clipboard, and adopts a picture copied out of it', (tester) async {
    const channel = MethodChannel('ghost_md/pictures');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'clipboard' ? <String, Object?>{'path': '/cache/picked/clip.jpg'} : null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final library = await open(tester);
    await launchWeek(tester, library);
    final band = tester.widget<ContextBand>(find.byType(ContextBand));
    expect(band.clipboard, isA<PhoneClipboard>());
    final read = await tester.runAsync(() => band.clipboard.read());
    expect((read!.clip.path, read.clip.text, read.read), ('/cache/picked/clip.jpg', null, true));
    expect(band.onPasteImage, isNotNull);
    await tester.runAsync(() => band.onPasteImage!('/cache/picked/clip.jpg'));
    await settle(tester);
    final kept = sent.singleWhere((call) => call.command == 'sync_put_file_path');
    expect((kept.args['kind'], kept.args['path']), ('image', '/cache/picked/clip.jpg'));
    expect(screenOf(tester).view!.state.doc.toString(), contains('![](image/${kept.args['name']})'));
    await close(tester);
  });
}
