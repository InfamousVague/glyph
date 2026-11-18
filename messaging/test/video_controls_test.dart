import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/desktop/remote.dart';
import 'package:ghost_messaging/files/file_kinds.dart';
import 'package:ghost_messaging/files/files_model.dart';
import 'package:ghost_messaging/files/files_store.dart';
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/hub_carrier.dart';
import 'package:ghost_messaging/ui/files_space/file_preview.dart';
import 'package:ghost_messaging/ui/video_engine.dart';
import 'package:ghost_messaging/ui/video_screen.dart';
import 'package:ghost_messaging/voice/voice.dart';

import 'support/fake_video.dart';
import 'support/list_harness.dart';

/// The player's controls over whichever engine plays the video (lib/ui/video_screen.dart, lib/ui/video_engine.dart;
/// Matt, 2026-11-18: "add support for playing mkv video files and mp4's within the app in a player themed by glacier
/// UI"): play and pause, going back and on, the scrubber, the computer's keys, the volume, full screen, a file that
/// can't be played; and an .mkv opened from a Files space on a computer playing in the app, not elsewhere.
void main() {
  late FakeVideoEngine engine;
  final fullscreen = <String>[];

  setUp(() {
    engine = FakeVideoEngine();
    VideoEngine.make = () => engine;
    fullscreen.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.alexmercerind/media_kit_video'), (call) async {
      fullscreen.add(call.method);
      return null;
    });
  });
  tearDown(() {
    VideoEngine.make = VideoEngine.defaultEngine;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('com.alexmercerind/media_kit_video'), null);
  });

  /// Opens [screen] and lets the player come in (it is made once the screen has, at most 600 ms on).
  Future<void> open(WidgetTester tester, Widget screen, {Size size = const Size(1100, 700)}) async {
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, screen, AppState(), size: size);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the dock plays, pauses, seeks and turns the sound; the engine is let go after the screen', (tester) async {
    await open(tester, const VideoScreen(path: '/tmp/clip.mkv', title: 'Maya Chen', desk: true));
    expect(engine.opened, '/tmp/clip.mkv');
    expect(engine.calls, contains('play'), reason: 'it plays as it opens');
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.text('0:42'), findsOneWidget);
    expect(find.text('2:40'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump();
    expect(engine.calls.last, 'pause');
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect(engine.calls.last, 'play');

    // A click halfway along the scrubber goes to halfway (1:20).
    final scrubber = tester.getRect(find.bySemanticsLabel('Where the video is'));
    await tester.tapAt(scrubber.center);
    await tester.pump();
    expect(engine.calls.last, 'seek 80');
    // Dragged with the mouse to near its end.
    final mouse = await tester.startGesture(scrubber.centerLeft + const Offset(10, 0), kind: PointerDeviceKind.mouse);
    await mouse.moveBy(const Offset(40, 0));
    await mouse.moveTo(scrubber.centerRight - const Offset(2, 0));
    await tester.pump();
    await mouse.up();
    await tester.pump();
    expect(engine.calls.last, startsWith('seek 15'), reason: 'dragged to its end: ${engine.calls.last}');

    await tester.tap(find.bySemanticsLabel('Mute'));
    await tester.pump();
    expect(engine.calls.last, 'volume 0.0');
    await tester.tap(find.bySemanticsLabel('Sound on'));
    await tester.pump();
    expect(engine.calls.last, 'volume 1.0');
    // The volume slider, a computer's: a click at its start is silence.
    final volume = tester.getRect(find.bySemanticsLabel('Volume'));
    await tester.tapAt(volume.centerLeft + const Offset(1, 0));
    await tester.pump();
    expect(engine.calls.last, 'volume 0.0');
    expect(find.bySemanticsLabel('Sound on'), findsOneWidget, reason: 'silence shows as muted');

    await tester.pumpWidget(const SizedBox());
    expect(engine.calls, isNot(contains('release')), reason: 'not while the screen goes');
    await tester.pump(const Duration(milliseconds: 500));
    expect(engine.calls.last, 'release');
  });

  testWidgets('a computer\'s keys: space, the arrows, F and Esc', (tester) async {
    await open(tester, const VideoScreen(path: '/tmp/clip.mp4', desk: true));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.calls.last, 'pause');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.calls.last, 'play');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.calls.last, 'seek 52');
    expect(find.text('+10 s'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(engine.calls.last, 'seek 42');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(engine.calls.last, 'volume 0.9');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(fullscreen, ['Utils.EnterNativeFullscreen']);
    expect(find.bySemanticsLabel('Leave full screen'), findsOneWidget);
    // Esc leaves full screen, then goes back.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(fullscreen, ['Utils.EnterNativeFullscreen', 'Utils.ExitNativeFullscreen']);
    await tester.pump(const Duration(milliseconds: 600));
    await close(tester);
  });

  testWidgets('a double tap on the left goes back ten seconds; the controls go by themselves while it plays', (tester) async {
    await open(tester, const VideoScreen(path: '/tmp/clip.mp4', desk: false), size: const Size(412, 892));
    expect(find.bySemanticsLabel('Volume'), findsNothing, reason: 'a phone turns the sound with its own buttons');
    await tester.tapAt(const Offset(80, 446));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(80, 446));
    await tester.pump(const Duration(milliseconds: 400));
    expect(engine.calls.last, 'seek 32');
    await tester.pump(const Duration(seconds: 4));
    final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
    expect(opacity.opacity, 0, reason: 'hidden after a few seconds of playing');
    await close(tester);
  });

  testWidgets('a file that can\'t be played says so, and offers another app', (tester) async {
    engine = FakeVideoEngine(fails: true);
    await open(tester, const VideoScreen(path: '/tmp/clip.mkv', title: 'Maya Chen', desk: true));
    expect(find.text('This video can\'t be played here.'), findsOneWidget);
    expect(find.textContaining('This computer can\'t read'), findsOneWidget);
    expect(find.bySemanticsLabel('Open with another app'), findsOneWidget);
    expect(find.bySemanticsLabel('Play'), findsNothing, reason: 'no dock for what does not play');
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    await close(tester);
  });

  // Matt, 2026-11-18: an .mkv on a computer used to go to another app (Files) or a window of AVFoundation's, which
  // could not read it (a chat's video). Now both are the app's own player.
  testWidgets('an .mkv from a Files space opens in the app\'s own player', (tester) async {
    final dir = Directory.systemTemp.createTempSync('ghost-video-mkv');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = FilesStore.forTest(base: null, signer: KeysSigner(NetKeys.generate()), data: dir);
    const space = VoiceChannel(seed: '9191919191919191919191919191919191919191919191919191919191919191', name: 'Drop box', kind: SpaceKind.files);
    final f = SpaceFile(id: '0' * 31 + '7', name: 'holiday.mkv', size: 4, mime: FileKind.mimeOf('holiday.mkv'), sha: '', key: Uint8List(32), prefix: Uint8List(8), by: 'maya', byName: 'Maya', at: 1);
    expect(f.kind, FileKind.video);
    // Already brought down, so it opens from where it is.
    File(store.cachedPath(f))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3, 4]);
    expect(playsVideo, isTrue);
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, Builder(builder: (context) => GestureDetector(key: const ValueKey('open'), behavior: HitTestBehavior.opaque, onTap: () => openSpaceFile(context, space, f, store: store), child: const SizedBox.expand())), AppState(), size: const Size(1100, 700));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(VideoScreen), findsOneWidget);
    expect(engine.opened, store.cachedPath(f));
    expect(find.text('holiday.mkv'), findsOneWidget, reason: 'its name at the top');
    await close(tester);
    await store.clear();
  });

  test('a computer keeps a chat\'s video as a file of its own kind, for the player, in a folder it sweeps', () async {
    final dir = Directory.systemTemp.createTempSync('ghost-video-copy');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = (await LinkCalls.videoCopy(12, Uint8List.fromList([1, 2, 3]), 'MKV', under: dir))!;
    expect(path, endsWith('.mkv'));
    expect(path, contains('${dir.path}/ghost-messaging-video/$pid/12-'));
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
    final odd = (await LinkCalls.videoCopy(13, Uint8List.fromList([1]), '../x', under: dir))!;
    expect(odd, endsWith('.mp4'), reason: 'an ending that is not one is not used');
  });
}
