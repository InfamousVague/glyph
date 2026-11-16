import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

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
  const VideoScreen({super.key, required this.path, this.title});
  final String path;

  /// Who sent it, or the conversation: said at the top.
  final String? title;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late final VideoPlayerController _video = VideoPlayerController.file(File(widget.path));
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

  @override
  void initState() {
    super.initState();
    _video.addListener(_changed);
    _video.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _video.play();
      _soon();
    }).catchError((Object e) {
      if (mounted) setState(() => _problem = 'This video can\'t be played on this phone.');
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _skipShown?.cancel();
    _video.removeListener(_changed);
    _video.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final v = _video.value;
    if (v.hasError && _problem == null) _problem = 'This video can\'t be played on this phone.';
    // At its end: the controls come back, to play it again.
    if (v.isInitialized && !v.isPlaying && v.position >= v.duration && v.duration > Duration.zero) _controls = true;
    setState(() {});
  }

  /// The controls go by themselves a few seconds after the last touch, while it plays.
  void _soon() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _video.value.isPlaying && _held == null) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _soon();
  }

  void _playPause() {
    final v = _video.value;
    if (v.isPlaying) {
      _video.pause();
    } else {
      if (v.position >= v.duration) _video.seekTo(Duration.zero);
      _video.play();
    }
    _soon();
  }

  void _skip(bool right) {
    final v = _video.value;
    final to = v.position + Duration(seconds: right ? 10 : -10);
    _video.seekTo(to < Duration.zero ? Duration.zero : (to > v.duration ? v.duration : to));
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
    final v = _video.value;
    final total = v.duration;
    final at = _held != null ? total * _held! : v.position;
    final part = total.inMilliseconds == 0 ? 0.0 : (at.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    const white = Color(0xFFFFFFFF);

    Widget round(LucideIcon icon, String label, VoidCallback onPressed, {double size = 44, bool filled = false}) => GlacierPressable(
          onPressed: onPressed,
          semanticLabel: label,
          builder: (context, state) => ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? white.withValues(alpha: state.pressed ? 0.8 : 1) : const Color(0x33FFFFFF).withValues(alpha: state.pressed ? 0.35 : 0.2),
                  border: filled ? null : Border.all(color: const Color(0x40FFFFFF)),
                ),
                alignment: Alignment.center,
                child: AppIcon(icon, size: size * 0.42, wash: false, color: filled ? const Color(0xFF000000) : white),
              ),
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
                        ? const GhostSpinner(size: 30)
                        : AspectRatio(aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio, child: VideoPlayer(_video)),
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
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          padding: EdgeInsets.fromLTRB(t.space(2), t.space(2), t.space(3), t.space(2)),
                          decoration: BoxDecoration(
                            color: const Color(0x40000000),
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
                                  _video.seekTo(total * p);
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
                              _video.setVolume(_muted ? 0 : 1);
                              _soon();
                            }, size: 40),
                          ]),
                        ),
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
