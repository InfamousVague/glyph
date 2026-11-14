import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/desktop/platform.dart';
import 'package:integration_test/integration_test.dart';

/// The Mac's half of a video in a message (macos/Runner/DeskVideo.swift), with a real video and the Mac's own
/// AVFoundation: a picture is made of where it starts, its length is read, and a window plays it.
///
///   flutter test integration_test/desk_video_test.dart -d macos --dart-define=DESK_VIDEO=/path/to/clip.mp4
///
/// DESK_VIDEO_HOLD (seconds) keeps the player's window open that long, to look at it from outside.
const _video = String.fromEnvironment('DESK_VIDEO');
const _hold = int.fromEnvironment('DESK_VIDEO_HOLD', defaultValue: 1);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('a video\'s picture and length are made, and a window plays it', (tester) async {
    await tester.pumpWidget(const SizedBox());
    expect(_video, isNotEmpty, reason: 'give a video: --dart-define=DESK_VIDEO=/path/to/clip.mp4');
    final bytes = File(_video).readAsBytesSync();
    final preview = (await MacPlatform.videoPreview(7, bytes, 'mp4'))!;
    final picture = preview['picture'] as List<int>?;
    debugPrint('DESK-VIDEO-PREVIEW ${picture?.length} bytes ${preview['width']}x${preview['height']} ${preview['millis']} ms');
    expect(picture, isNotNull);
    expect(picture!.take(2).toList(), [0xFF, 0xD8], reason: 'a JPEG');
    expect(preview['millis'] as int, greaterThan(500));
    expect(preview['width'] as int, greaterThan(0));
    expect((preview['width'] as int) <= 720 && (preview['height'] as int) <= 720, isTrue);
    // What is not a video has no picture, and is not played.
    final nothing = (await MacPlatform.videoPreview(8, File(_video).readAsBytesSync().sublist(0, 2000), 'mp4'))!;
    expect(nothing['picture'], isNull);
    expect(await MacPlatform.videoPlay(8, File(_video).readAsBytesSync().sublist(0, 2000), 'mp4', 'Not a video'), isNotNull);
    // And the real one plays, in a window of its own.
    expect(await MacPlatform.videoPlay(7, bytes, 'mp4', 'Video'), isNull);
    debugPrint('DESK-VIDEO-PLAYING pid $pid');
    await Future<void>.delayed(const Duration(seconds: _hold));
  });
}
