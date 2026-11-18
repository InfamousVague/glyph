import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:ghost_messaging/ui/video_engine.dart';
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
  Future<void> dispose(int playerId) async => calls.add('dispose');
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

/// A stand-in for whichever engine plays a video (lib/ui/video_engine.dart; Matt, 2026-11-18: "add support for playing
/// mkv video files and mp4's within the app in a player themed by glacier UI"): a 2:40 video, 16 by 9, that does what
/// it is told at once and says so in [calls]. [fails] makes it one that can't be played.
class FakeVideoEngine extends VideoEngine {
  FakeVideoEngine({this.fails = false, this.still = false, this.at = const Duration(seconds: 42)});
  final bool fails;

  /// Stays paused when told to play: the player as it is once paused, its controls up.
  final bool still;
  final Duration at;
  final calls = <String>[];
  String? opened;

  @override
  Future<void> open(String path) async {
    opened = path;
    calls.add('open $path');
    value = fails ? const VideoNow(error: 'Failed to recognize file format.') : VideoNow(ready: true, position: at, duration: const Duration(minutes: 2, seconds: 40), aspect: 16 / 9);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    if (!still) value = value.copyWith(playing: true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    value = value.copyWith(playing: false);
  }

  @override
  Future<void> seek(Duration to) async {
    calls.add('seek ${to.inSeconds}');
    value = value.copyWith(position: to);
  }

  @override
  Future<void> setVolume(double volume) async => calls.add('volume ${volume.toStringAsFixed(1)}');

  /// A picture to tell apart from the black round it: a dusk sky over a hill.
  @override
  Widget view() => Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRect(child: Stack(fit: StackFit.expand, children: const [
            DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2B3A67), Color(0xFFE98A5B)]))),
            Align(alignment: Alignment(0, 1.6), child: FractionallySizedBox(widthFactor: 1.4, heightFactor: 0.7, child: DecoratedBox(decoration: BoxDecoration(color: Color(0xFF1B2A2F), shape: BoxShape.circle)))),
          ])),
        ),
      );

  @override
  Future<void> release() async => calls.add('release');
}
