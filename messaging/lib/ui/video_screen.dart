import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';
import 'package:video_player/video_player.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../kit/settings_type.dart';
import 'common.dart';

/// A video, the whole screen, in the app's own look (Matt, 2026-11-15: "id like a video player built with glacier UI
/// right now it looks like a very old android core system player"): the picture on black, a round way back at the top,
/// and at the foot a frosted dock as the app's own (play and pause, where it has got to, how long it runs, mute).
/// A tap shows the controls or puts them away; they go by themselves after a few seconds while it plays. A double tap
/// on either half goes back or on ten seconds. ExoPlayer plays it underneath (video_player), from a file
/// (android Video.kt videoFile).
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required String this.path, this.title, this.poster}) : file = null;

  /// Opened at once, while its file is still being made or brought down ([file]): a spinner over [poster] until it is
  /// here (Matt, 2026-11-17: "The app has gotten pretty laggy, especially when opening videos and exiting them").
  const VideoScreen.coming({super.key, required Future<String?> this.file, this.title, this.poster}) : path = null;

  final String? path;
  final Future<String?>? file;

  /// Who sent it, or the conversation: said at the top.
  final String? title;

  /// Its picture, shown until the video itself is ready.
  final Uint8List? poster;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

/// The route a video opens in: up from the foot, quickly. Slid, not faded: a whole page faded is drawn apart and laid
/// over what is under it on every frame of the fade.
Route<void> videoRoute(Widget screen) => PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, _) => screen,
      transitionsBuilder: (context, a, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    );

class _VideoScreenState extends State<VideoScreen> {
  VideoPlayerController? _video;
  bool _ready = false;
  String? _problem;
  bool _controls = true;
  bool _muted = false;
  Timer? _hide;

  /// Dragging the scrubber: where it is held, as a part of the whole.
  double? _held;

  /// A double tap's ten seconds, shown for a moment on its side.
  String? _skipped;
  bool _skippedRight = false;
  Timer? _skipShown;

  /// What was last drawn of the player, so a change it reports that shows nothing new draws nothing.
  (bool, bool, int, bool, bool)? _shown;

  @override
  void initState() {
    super.initState();
    // After the first frame: the route is asked about, which initState may not do.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  /// The player is made once the screen has come in: its making is work on the thread that draws, and the fade-in
  /// would stutter under it. The file is waited for meanwhile, where it is still coming.
  Future<void> _start() async {
    final path = widget.path ?? await widget.file;
    if (!mounted) return;
    if (path == null) {
      setState(() => _problem = 'This video couldn\'t be opened.');
      return;
    }
    final animation = ModalRoute.of(context)?.animation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      final came = Completer<void>();
      void listener(AnimationStatus s) {
        if (s == AnimationStatus.completed && !came.isCompleted) came.complete();
      }

      animation.addStatusListener(listener);
      await came.future.timeout(const Duration(milliseconds: 600), onTimeout: () {});
      animation.removeStatusListener(listener);
    }
    if (!mounted) return;
    final video = VideoPlayerController.file(File(path));
    _video = video;
    video.addListener(_changed);
    try {
      await video.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      unawaited(video.play());
      _soon();
    } catch (_) {
      if (mounted) setState(() => _problem = 'This video can\'t be played on this phone.');
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    _skipShown?.cancel();
    final video = _video;
    if (video != null) {
      video.removeListener(_changed);
      // Quiet at once; let go once the screen has gone: ExoPlayer's release waits on its own thread, and done now it
      // would hold up the frames that take the screen away.
      unawaited(video.pause().catchError((_) {}));
      unawaited(video.setVolume(0).catchError((_) {}));
      Timer(const Duration(milliseconds: 400), () => video.dispose());
    }
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final v = _video!.value;
    if (v.hasError && _problem == null) _problem = 'This video can\'t be played on this phone.';
    // At its end: the controls come back, to play it again.
    if (v.isInitialized && !v.isPlaying && v.position >= v.duration && v.duration > Duration.zero) _controls = true;
    // Drawn again only where what shows has changed: the second it is at, playing or not, loaded, an error.
    final now = (v.isInitialized, v.isPlaying, v.position.inSeconds, v.hasError, _controls);
    if (now == _shown && _held == null) return;
    _shown = now;
    setState(() {});
  }

  /// The controls go by themselves a few seconds after the last touch, while it plays.
  void _soon() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_video?.value.isPlaying ?? false) && _held == null) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _soon();
  }

  void _playPause() {
    final video = _video;
    if (video == null) return;
    final v = video.value;
    if (v.isPlaying) {
      video.pause();
    } else {
      if (v.position >= v.duration) video.seekTo(Duration.zero);
      video.play();
    }
    _soon();
  }

  void _skip(bool right) {
    final video = _video;
    if (video == null) return;
    final v = video.value;
    final to = v.position + Duration(seconds: right ? 10 : -10);
    video.seekTo(to < Duration.zero ? Duration.zero : (to > v.duration ? v.duration : to));
    _skipShown?.cancel();
    setState(() {
      _skipped = right ? '+10 s' : '−10 s';
      _skippedRight = right;
    });
    _skipShown = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _skipped = null);
    });
  }

  static String _clock(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}' : '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final v = _video?.value ?? const VideoPlayerValue.uninitialized();
    final total = v.duration;
    final at = _held != null ? total * _held! : v.position;
    final part = total.inMilliseconds == 0 ? 0.0 : (at.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    const white = Color(0xFFFFFFFF);

    Widget round(LucideIcon icon, String label, VoidCallback onPressed, {double size = 44, bool filled = false}) => GlacierPressable(
          onPressed: onPressed,
          semanticLabel: label,
          // A flat fill, not a blur of the video behind it: a blur over a playing video is drawn again for every one of
          // its frames, and needs pictures of its own made as the screen opens (the hitch on opening and closing).
          builder: (context, state) => ClipOval(
            child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? white.withValues(alpha: state.pressed ? 0.8 : 1) : (state.pressed ? const Color(0xB3303030) : const Color(0x8C1E1E1E)),
                  border: filled ? null : Border.all(color: const Color(0x40FFFFFF)),
                ),
                alignment: Alignment.center,
                child: AppIcon(icon, size: size * 0.42, wash: false, color: filled ? const Color(0xFF000000) : white),
              ),
          ),
        );

    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(children: [
        // The picture, and the taps on it: one shows or hides the controls, two go back or on ten seconds.
        Positioned.fill(
          child: LayoutBuilder(builder: (context, box) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTapDown: (d) => _skippedRight = d.localPosition.dx > box.maxWidth / 2,
              onDoubleTap: () => _skip(_skippedRight),
              child: Center(
                child: _problem != null
                    ? Padding(
                        padding: EdgeInsets.all(t.space(6)),
                        child: Text(_problem!, textAlign: TextAlign.center, style: pageText(t, t.fontSize('md'), color: white)),
                      )
                    : !_ready
                        // Its picture under the spinner until the video is ready: the screen is there at once.
                        ? Stack(alignment: Alignment.center, children: [
                            if (widget.poster != null) Image.memory(widget.poster!, fit: BoxFit.contain, gaplessPlayback: true),
                            const GhostSpinner(size: 30),
                          ])
                        : AspectRatio(aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio, child: VideoPlayer(_video!)),
              ),
            );
          }),
        ),
        if (_skipped != null)
          Positioned(
            top: 0,
            bottom: 0,
            left: _skippedRight ? null : t.space(8),
            right: _skippedRight ? t.space(8) : null,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
                decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(t.radius('full'))),
                child: Text(_skipped!, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: white)),
              ),
            ),
          ),
        // The controls, faded in and out together.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_controls,
            child: AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Stack(children: [
                // A shade at the top and the foot, so white reads over a bright picture.
                const Positioned(top: 0, left: 0, right: 0, height: 140, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0x00000000)])))),
                const Positioned(bottom: 0, left: 0, right: 0, height: 200, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xAA000000), Color(0x00000000)])))),
                Positioned(
                  top: pad.top + t.space(3),
                  left: t.space(4),
                  right: t.space(4),
                  child: Row(children: [
                    round(Lucide.arrowLeft, 'Back', () => Navigator.of(context).maybePop()),
                    SizedBox(width: t.space(3)),
                    if (widget.title != null)
                      Expanded(child: Text(widget.title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: white))),
                  ]),
                ),
                if (_ready && _problem == null)
                  Positioned(
                    left: t.space(4),
                    right: t.space(4),
                    bottom: pad.bottom + t.space(4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(t.radius('full')),
                      child: Container(
                          padding: EdgeInsets.fromLTRB(t.space(2), t.space(2), t.space(3), t.space(2)),
                          decoration: BoxDecoration(
                            color: const Color(0xB3141414),
                            borderRadius: BorderRadius.circular(t.radius('full')),
                            border: Border.all(color: const Color(0x33FFFFFF)),
                          ),
                          child: Row(children: [
                            round(v.isPlaying ? Lucide.pause : Lucide.play, v.isPlaying ? 'Pause' : 'Play', _playPause, size: 48, filled: true),
                            SizedBox(width: t.space(3)),
                            Text(_clock(at), style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: white, mono: true)),
                            SizedBox(width: t.space(3)),
                            Expanded(
                              child: _Scrubber(
                                part: part,
                                onHold: (p) {
                                  _hide?.cancel();
                                  setState(() => _held = p);
                                },
                                onLet: (p) {
                                  _video?.seekTo(total * p);
                                  setState(() => _held = null);
                                  _soon();
                                },
                              ),
                            ),
                            SizedBox(width: t.space(3)),
                            Text(_clock(total), style: pageText(t, t.fontSize('sm'), color: const Color(0xCCFFFFFF), mono: true)),
                            SizedBox(width: t.space(2)),
                            round(_muted ? LucideMore.volumeX : Lucide.volume2, _muted ? 'Sound on' : 'Mute', () {
                              setState(() => _muted = !_muted);
                              _video?.setVolume(_muted ? 0 : 1);
                              _soon();
                            }, size: 40),
                          ]),
                        ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Where the video has got to, to drag: a white line on a faint one, and a knob that grows while held.
class _Scrubber extends StatefulWidget {
  const _Scrubber({required this.part, required this.onHold, required this.onLet});
  final double part;
  final ValueChanged<double> onHold;
  final ValueChanged<double> onLet;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  bool _holding = false;
  double _at = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double partOf(double x) => (x / w).clamp(0.0, 1.0);
      final shown = _holding ? _at : widget.part;
      return Semantics(
        slider: true,
        label: 'Where the video is',
        value: '${(shown * 100).round()}%',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => setState(() {
            _holding = true;
            _at = partOf(d.localPosition.dx);
            widget.onHold(_at);
          }),
          onHorizontalDragUpdate: (d) => setState(() {
            _at = partOf(d.localPosition.dx);
            widget.onHold(_at);
          }),
          onHorizontalDragEnd: (_) {
            setState(() => _holding = false);
            widget.onLet(_at);
          },
          onTapUp: (d) => widget.onLet(partOf(d.localPosition.dx)),
          child: SizedBox(
            height: 36,
            child: Stack(alignment: Alignment.centerLeft, clipBehavior: Clip.none, children: [
              Container(height: 4, decoration: BoxDecoration(color: const Color(0x4DFFFFFF), borderRadius: BorderRadius.circular(2))),
              Container(width: w * shown, height: 4, decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(2))),
              Positioned(
                left: (w * shown - (_holding ? 9 : 6)).clamp(-9.0, w - 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: _holding ? 18 : 12,
                  height: _holding ? 18 : 12,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFFFFF)),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}
