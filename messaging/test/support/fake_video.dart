import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// The app's own video player (lib/ui/video_screen.dart; Matt, 2026-11-15: "id like a video player built with glacier
/// UI right now it looks like a very old android core system player"), with a stand-in for ExoPlayer that says it has
/// a 2:40 video, 1920 by 1080, at 0:42.
class FakeVideoPlayer extends VideoPlayerPlatform {
  final _events = StreamController<VideoEvent>.broadcast();
  final calls = <String>[];

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;
  @override
  Future<int?> create(DataSource dataSource) async => 1;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    scheduleMicrotask(() => _events.add(VideoEvent(eventType: VideoEventType.initialized, duration: const Duration(minutes: 2, seconds: 40), size: const Size(1920, 1080))));
    return _events.stream;
  }
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async => calls.add('play');
  @override
  Future<void> pause(int playerId) async => calls.add('pause');
  @override
  Future<void> setVolume(int playerId, double volume) async => calls.add('volume $volume');
  @override
  Future<void> seekTo(int playerId, Duration position) async => calls.add('seek ${position.inSeconds}');
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<Duration> getPosition(int playerId) async => const Duration(seconds: 42);
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const ColoredBox(color: Color(0xFF2A3B4C));
  @override
  Widget buildView(int playerId) => const ColoredBox(color: Color(0xFF2A3B4C));
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}
