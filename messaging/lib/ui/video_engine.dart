import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:video_player/video_player.dart';

/// What the player shows of a video, from whichever engine plays it (lib/ui/video_screen.dart draws its controls from
/// this alone, so they are the same over either).
@immutable
class VideoNow {
  const VideoNow({this.ready = false, this.playing = false, this.position = Duration.zero, this.duration = Duration.zero, this.aspect = 0, this.error});
  final bool ready;
  final bool playing;
  final Duration position;
  final Duration duration;

  /// Width over height; 0 until known (or for sound alone).
  final double aspect;

  /// Why it cannot be played, in the engine's words; null while it can.
  final String? error;

  bool get ended => ready && !playing && duration > Duration.zero && position >= duration;

  VideoNow copyWith({bool? ready, bool? playing, Duration? position, Duration? duration, double? aspect, String? error}) =>
      VideoNow(ready: ready ?? this.ready, playing: playing ?? this.playing, position: position ?? this.position, duration: duration ?? this.duration, aspect: aspect ?? this.aspect, error: error ?? this.error);

  @override
  bool operator ==(Object other) => other is VideoNow && other.ready == ready && other.playing == playing && other.position == position && other.duration == duration && other.aspect == aspect && other.error == error;

  @override
  int get hashCode => Object.hash(ready, playing, position, duration, aspect, error);
}

/// What plays a video under the app's own controls (Matt, 2026-11-18: "add support for playing mkv video files and
/// mp4's within the app in a player themed by glacier UI"). Two engines, because no one engine is right everywhere:
///
/// - Android and iPhone: [VideoPlayerEngine], the video_player package. On Android that is ExoPlayer, whose default
///   extractors read Matroska as well as MP4 (video_player_android's LocalVideoAsset uses DefaultMediaSourceFactory),
///   so an .mkv plays where the phone has a decoder for what is inside it; it adds nothing to the APK. On an iPhone it
///   is AVFoundation, which reads MP4 and MOV but not Matroska: an .mkv there says it can't be played and offers
///   another app.
/// - Mac and Windows: [MediaKitEngine], libmpv by way of media_kit, which reads MKV, WebM, HEVC, AV1 and the rest.
///   AVFoundation (the Mac's old DeskVideo window) could not open an .mkv at all, and Windows had no player.
abstract class VideoEngine extends ValueNotifier<VideoNow> {
  VideoEngine() : super(const VideoNow());

  /// The engine for this device; a test puts its own stand-in here.
  static VideoEngine Function() make = defaultEngine;

  static VideoEngine defaultEngine() => usesMediaKit ? MediaKitEngine() : VideoPlayerEngine();

  /// Whether this device plays through libmpv: the computers.
  static bool get usesMediaKit => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Opens [path]; once it is ready [value] says so, or says why not in [VideoNow.error]. Never throws.
  Future<void> open(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration to);

  /// From 0 (silent) to 1.
  Future<void> setVolume(double volume);

  /// The picture, filling the box it is given and fitting the video inside it on black.
  Widget view();

  /// Lets the engine go. Quiet first ([pause], [setVolume]) where the screen is still going.
  Future<void> release();

  /// Sets [value] only while the engine is still held: a late report after [release] would be a call on a disposed
  /// notifier.
  bool _released = false;
  void _set(VideoNow now) {
    if (!_released && now != value) value = now;
  }

  @override
  void dispose() {
    _released = true;
    super.dispose();
  }
}

/// video_player under the controls: ExoPlayer on Android, AVFoundation on an iPhone.
class VideoPlayerEngine extends VideoEngine {
  VideoPlayerController? _video;

  @override
  Future<void> open(String path) async {
    final video = VideoPlayerController.file(File(path));
    _video = video;
    video.addListener(_changed);
    try {
      await video.initialize();
      _changed();
    } catch (e) {
      _set(value.copyWith(error: _words(e)));
    }
  }

  void _changed() {
    final v = _video?.value;
    if (v == null) return;
    _set(VideoNow(
      ready: v.isInitialized,
      playing: v.isPlaying,
      position: v.position,
      duration: v.duration,
      aspect: v.isInitialized ? v.aspectRatio : 0,
      error: v.hasError ? (v.errorDescription ?? 'unknown') : null,
    ));
  }

  static String _words(Object e) => e is Exception ? e.toString() : '$e';

  @override
  Future<void> play() async => _video?.play();
  @override
  Future<void> pause() async => _video?.pause();
  @override
  Future<void> seek(Duration to) async => _video?.seekTo(to);
  @override
  Future<void> setVolume(double volume) async => _video?.setVolume(volume);

  @override
  Widget view() {
    final video = _video;
    if (video == null) return const SizedBox.expand();
    return Center(child: AspectRatio(aspectRatio: value.aspect == 0 ? 16 / 9 : value.aspect, child: VideoPlayer(video)));
  }

  @override
  Future<void> release() async {
    final video = _video;
    _video = null;
    if (video == null) return;
    video.removeListener(_changed);
    await video.dispose();
  }
}

/// libmpv under the controls, by way of media_kit: the computers. It draws through a texture (media_kit_video) the
/// controls lie over as they do over ExoPlayer's.
class MediaKitEngine extends VideoEngine {
  mk.Player? _player;
  mkv.VideoController? _controller;
  final _listening = <StreamSubscription<Object?>>[];

  /// How long a file has to say how long it runs before it is taken as one libmpv can't read.
  static const _patience = Duration(seconds: 12);

  @override
  Future<void> open(String path) async {
    try {
      mk.MediaKit.ensureInitialized();
      final player = mk.Player();
      _player = player;
      _controller = mkv.VideoController(player);
      final s = player.stream;
      final loaded = Completer<void>();
      _listening
        ..add(s.playing.listen((p) => _set(value.copyWith(playing: p))))
        ..add(s.position.listen((p) => _set(value.copyWith(position: p))))
        ..add(s.duration.listen((d) {
          _set(value.copyWith(duration: d));
          if (d > Duration.zero && !loaded.isCompleted) loaded.complete();
        }))
        ..add(s.width.listen((_) => _aspect()))
        ..add(s.height.listen((_) => _aspect()))
        ..add(s.completed.listen((done) {
          // At its end libmpv stops where it is; it is shown as ended, to be played again.
          if (done) _set(value.copyWith(playing: false, position: value.duration));
        }))
        ..add(s.error.listen((e) {
          // An error before it has loaded is the file itself; one after is a moment's (a frame it skips).
          if (!loaded.isCompleted) {
            loaded.completeError(e);
          }
        }));
      await player.open(mk.Media(Uri.file(path).toString()), play: false);
      await loaded.future.timeout(_patience);
      _aspect();
      _set(value.copyWith(ready: true));
    } on TimeoutException {
      _set(value.copyWith(error: 'it did not start'));
    } catch (e) {
      _set(value.copyWith(error: '$e'));
    }
  }

  void _aspect() {
    final st = _player?.state;
    if (st == null) return;
    final w = st.width, h = st.height;
    if (w != null && h != null && w > 0 && h > 0) _set(value.copyWith(aspect: w / h));
  }

  @override
  Future<void> play() async {
    final player = _player;
    if (player == null) return;
    // Played again from its end: libmpv starts it over from where it stopped, which is the end.
    if (value.ended) await player.seek(Duration.zero);
    await player.play();
  }

  @override
  Future<void> pause() async => _player?.pause();
  @override
  Future<void> seek(Duration to) async => _player?.seek(to);

  /// libmpv's volume runs 0 to 100.
  @override
  Future<void> setVolume(double volume) async => _player?.setVolume(volume * 100);

  @override
  Widget view() {
    final controller = _controller;
    if (controller == null) return const SizedBox.expand();
    return mkv.Video(controller: controller, controls: mkv.NoVideoControls, fill: const Color(0xFF000000));
  }

  @override
  Future<void> release() async {
    for (final l in _listening) {
      unawaited(l.cancel());
    }
    _listening.clear();
    final player = _player;
    _player = null;
    _controller = null;
    await player?.dispose();
  }
}
