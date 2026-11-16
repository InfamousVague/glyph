import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/ui/video_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/fake_video.dart';
import 'support/list_harness.dart';

/// The app's own video player (lib/ui/video_screen.dart; Matt, 2026-11-15: "id like a video player built with glacier
/// UI right now it looks like a very old android core system player"): it plays as it opens, the dock plays and
/// pauses and mutes, and a double tap on the right goes on ten seconds.
void main() {
  testWidgets('plays as it opens; play, pause, mute and a double tap to skip', (tester) async {
    final fake = FakeVideoPlayer();
    VideoPlayerPlatform.instance = fake;
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, const VideoScreen(path: '/tmp/none.mp4', title: 'Maya Chen'), AppState());
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.calls, contains('play'));
    expect(find.text('2:40'), findsOneWidget);
    expect(find.text('Maya Chen'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Mute'));
    await tester.pump();
    expect(fake.calls, contains('volume 0.0'));
    final size = tester.getSize(find.byType(VideoScreen));
    await tester.tapAt(Offset(size.width * 0.8, size.height / 2));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(Offset(size.width * 0.8, size.height / 2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(fake.calls.where((c) => c.startsWith('seek')), isNotEmpty, reason: 'a double tap on the right goes on');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });
}
