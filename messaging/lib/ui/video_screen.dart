import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';
import 'package:media_kit_video/media_kit_video.dart' show defaultEnterNativeFullscreen, defaultExitNativeFullscreen;

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../backgrounds.dart' show strongFill;
import '../files/file_platform.dart';
import '../kit/settings_type.dart';
import 'common.dart';
import 'dialup/bevel.dart';
import 'dialup/parts.dart' show DialupTool;
import 'dialup/retro_button.dart';
import 'dialup/title_bar.dart';
import 'video_engine.dart';

/// A video, the whole screen, in the app's own look (Matt, 2026-11-15: "id like a video player built with glacier UI
/// right now it looks like a very old android core system player"): the picture on black, a way back at the top, and
/// at the foot a dock in the look's own colours (play and pause, where it has got to, how long it runs, the sound).
/// A tap shows the controls or puts them away; they go by themselves after a few seconds while it plays. A double tap
/// on either half goes back or on ten seconds.
///
/// It plays MP4 and MKV alike on every device (Matt, 2026-11-18: "add support for playing mkv video files and mp4's
/// within the app in a player themed by glacier UI"): what plays it is a [VideoEngine] (ExoPlayer on Android,
/// AVFoundation on an iPhone, libmpv on a computer), and these controls drive whichever it is. On a computer they also
/// answer the keyboard (space, the arrows, F for full screen, Esc to go back), show a volume slider, and come back as
/// the mouse moves. A file that can't be played says so and offers the app the device would open it with.
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required String this.path, this.title, this.poster, this.desk, this.dropFile = false}) : file = null;

  /// Opened at once, while its file is still being made or brought down ([file]): a spinner over [poster] until it is
  /// here (Matt, 2026-11-17: "The app has gotten pretty laggy, especially when opening videos and exiting them").
  const VideoScreen.coming({super.key, required Future<String?> this.file, this.title, this.poster, this.desk, this.dropFile = false}) : path = null;

  final String? path;
  final Future<String?>? file;

  /// Who sent it, or the file's name: said at the top.
  final String? title;

  /// Its picture, shown until the video itself is ready.
  final Uint8List? poster;

  /// Drawn for a computer (keys, volume slider, full screen); by the device when null.
  final bool? desk;

  /// The file is a copy made only to be played here (a computer's copy of a video on the phone, lib/desktop/remote.dart):
  /// removed once the screen has gone, so nothing of a conversation stays on the computer's disk (docs/desktop.md).
  final bool dropFile;

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

/// Whether this device is a computer, for the controls a computer gets.
bool get _deskDevice => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

class _VideoScreenState extends State<VideoScreen> {
  VideoEngine? _engine;
  String? _path;
  String? _problem;
  String? _problemWhy;
  bool _controls = true;
  bool _muted = false;
  double _volume = 1;
  bool _fullscreen = false;
  bool _handedOn = false;
  Timer? _hide;
  final _focus = FocusNode(debugLabel: 'video');

  /// Dragging the scrubber: where it is held, as a part of the whole.
  double? _held;

  /// A skip's ten seconds, shown for a moment on its side.
  String? _skipped;
  bool _skippedRight = false;
  Timer? _skipShown;

  /// What was last drawn of the player, so a change it reports that shows nothing new draws nothing.
  (bool, bool, int, int, String?)? _shown;

  bool get _desk => widget.desk ?? _deskDevice;
  VideoNow get _now => _engine?.value ?? const VideoNow();

  @override
  void initState() {
    super.initState();
    // After the first frame: the route is asked about, which initState may not do.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  /// The player is made once the screen has come in: its making is work on the thread that draws, and the slide-in
  /// would stutter under it. The file is waited for meanwhile, where it is still coming.
  Future<void> _start() async {
    final path = widget.path ?? await widget.file;
    if (!mounted) return;
    _path = path;
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
    final engine = VideoEngine.make();
    _engine = engine;
    engine.addListener(_changed);
    await engine.open(path);
    if (!mounted) return;
    if (engine.value.error != null) {
      if (_problem == null) _failed(engine.value.error!);
      return;
    }
    setState(() {});
    unawaited(engine.play());
    _soon();
  }

  /// Can't be played: said plainly, with the engine's own words kept for the log only.
  void _failed(String why) {
    debugPrint('video: $why');
    setState(() {
      _problem = 'This video can\'t be played here.';
      _problemWhy = 'This ${_desk ? 'computer' : 'phone'} can\'t read what\'s inside it. Another app may.';
      _controls = true;
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _skipShown?.cancel();
    _focus.dispose();
    if (_fullscreen) unawaited(defaultExitNativeFullscreen());
    final engine = _engine;
    final drop = widget.dropFile && !_handedOn ? _path : null;
    if (engine != null) {
      engine.removeListener(_changed);
      // Quiet at once; let go once the screen has gone: ExoPlayer's release waits on its own thread, and done now it
      // would hold up the frames that take the screen away.
      unawaited(engine.pause().catchError((_) {}));
      unawaited(engine.setVolume(0).catchError((_) {}));
      Timer(const Duration(milliseconds: 400), () async {
        try {
          await engine.release();
        } catch (_) {}
        engine.dispose();
        _drop(drop);
      });
    } else {
      _drop(drop);
    }
    super.dispose();
  }

  static void _drop(String? path) {
    if (path == null) return;
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  void _changed() {
    if (!mounted) return;
    final v = _now;
    if (v.error != null && _problem == null) {
      _failed(v.error!);
      return;
    }
    // At its end: the controls come back, to play it again.
    if (v.ended) _controls = true;
    // Drawn again only where what shows has changed: the second it is at, playing or not, loaded, its length.
    final now = (v.ready, v.playing, v.position.inSeconds, v.duration.inSeconds, v.error);
    if (now == _shown && _held == null) return;
    _shown = now;
    setState(() {});
  }

  /// The controls go by themselves a few seconds after the last touch, while it plays.
  void _soon() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _now.playing && _held == null && _problem == null) setState(() => _controls = false);
    });
  }

  void _show() {
    if (!_controls) setState(() => _controls = true);
    _soon();
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _soon();
  }

  void _playPause() {
    final engine = _engine;
    if (engine == null || !_now.ready) return;
    if (_now.playing) {
      engine.pause();
    } else {
      engine.play();
    }
    _show();
  }

  void _skip(bool right) {
    final engine = _engine;
    if (engine == null || !_now.ready) return;
    final v = _now;
    final to = v.position + Duration(seconds: right ? 10 : -10);
    engine.seek(to < Duration.zero ? Duration.zero : (to > v.duration ? v.duration : to));
    _skipShown?.cancel();
    setState(() {
      _skipped = right ? '+10 s' : '−10 s';
      _skippedRight = right;
    });
    _skipShown = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _skipped = null);
    });
  }

  void _setVolume(double v) {
    setState(() {
      // Near either end is the end: a click at the slider's very start is silence, not almost.
      _volume = v < 0.03 ? 0 : (v > 0.97 ? 1 : v);
      _muted = _volume == 0;
    });
    _engine?.setVolume(_volume);
    _show();
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      if (!_muted && _volume == 0) _volume = 1;
    });
    _engine?.setVolume(_muted ? 0 : _volume);
    _show();
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _fullscreen = !_fullscreen);
    await (_fullscreen ? defaultEnterNativeFullscreen() : defaultExitNativeFullscreen());
  }

  Future<void> _back() async {
    if (_fullscreen) await _toggleFullscreen();
    if (mounted) await Navigator.of(context).maybePop();
  }

  void _openElsewhere() {
    final path = _path;
    if (path == null) return;
    _handedOn = true;
    unawaited(FilePlatform.open(path, path.split(Platform.pathSeparator).last));
  }

  /// A computer's keys (Matt, 2026-11-18): space plays and pauses, the arrows go back and on and turn the sound, F is
  /// full screen and Esc goes back (out of full screen first).
  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final repeat = e is KeyRepeatEvent;
    if (k == LogicalKeyboardKey.escape && !repeat) {
      unawaited(_back());
    } else if (k == LogicalKeyboardKey.space && !repeat) {
      _playPause();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _skip(false);
      _show();
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _skip(true);
      _show();
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _setVolume((_muted ? 0 : _volume) + 0.1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _setVolume((_muted ? 0 : _volume) - 0.1);
    } else if (k == LogicalKeyboardKey.keyF && !repeat) {
      unawaited(_toggleFullscreen());
    } else if (k == LogicalKeyboardKey.keyM && !repeat) {
      _toggleMute();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static String _clock(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}' : '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bevel = isBevelChrome(t);
    final pad = MediaQuery.paddingOf(context);
    final v = _now;
    final ready = v.ready && _problem == null;
    final total = v.duration;
    final at = _held != null ? total * _held! : v.position;
    final part = total.inMilliseconds == 0 ? 0.0 : (at.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final look = _DockLook.of(t, bevel);

    final dock = _Dock(
      look: look,
      desk: _desk,
      playing: v.playing,
      at: _clock(at),
      total: _clock(total),
      part: part,
      muted: _muted,
      volume: _muted ? 0 : _volume,
      fullscreen: _fullscreen,
      onPlayPause: _playPause,
      onHold: (p) {
        _hide?.cancel();
        setState(() => _held = p);
      },
      onLet: (p) {
        _engine?.seek(total * p);
        setState(() => _held = null);
        _soon();
      },
      onMute: _toggleMute,
      onVolume: _setVolume,
      onFullscreen: () => unawaited(_toggleFullscreen()),
    );

    final top = bevel
        ? TitleBar(
            title: widget.title ?? 'Video',
            onClose: () => unawaited(_back()),
            actions: [
              if (_desk) DialupTool(icon: _fullscreen ? LucideMore.minimize : Lucide.maximize, label: _fullscreen ? 'Leave full screen' : 'Full screen', onPressed: () => unawaited(_toggleFullscreen()), size: 16, box: 32),
            ],
          )
        : Row(children: [
            _Round(look: look, icon: Lucide.arrowLeft, label: 'Back', onPressed: () => unawaited(_back())),
            SizedBox(width: t.space(3)),
            if (widget.title != null)
              Flexible(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
                  decoration: look.panel(t),
                  child: Text(widget.title!, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: look.ink)),
                ),
              ),
          ]);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: MouseRegion(
        // The pointer goes with the controls while it plays, and brings them back as it moves.
        cursor: _controls || !ready ? MouseCursor.defer : SystemMouseCursors.none,
        onHover: (_) {
          if (_desk) _show();
        },
        child: ColoredBox(
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
                  child: _problem != null
                      ? Center(
                          child: _Problem(look: look, words: _problem!, why: _problemWhy, onOpen: _path != null && !Platform.isIOS ? _openElsewhere : null),
                        )
                      : !ready
                          // Its picture under the spinner until the video is ready: the screen is there at once.
                          ? Stack(alignment: Alignment.center, fit: StackFit.expand, children: [
                              if (widget.poster != null) Image.memory(widget.poster!, fit: BoxFit.contain, gaplessPlayback: true),
                              const Center(child: GhostSpinner(size: 30)),
                            ])
                          // The engine's own picture, which fits the video to the screen itself.
                          : _engine!.view(),
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
                  child: IgnorePointer(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
                      decoration: look.panel(t),
                      child: Text(_skipped!, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: look.ink)),
                    ),
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
                    // A shade at the top and the foot, so the controls stand off a bright picture.
                    if (!bevel) ...[
                      const Positioned(top: 0, left: 0, right: 0, height: 140, child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0x00000000)]))))),
                      const Positioned(bottom: 0, left: 0, right: 0, height: 200, child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xAA000000), Color(0x00000000)]))))),
                    ],
                    Positioned(
                      top: bevel ? 0 : pad.top + t.space(3),
                      left: bevel ? 0 : t.space(4),
                      right: bevel ? 0 : t.space(4),
                      // Dial-Up's title bar runs the width, from under the status bar, as its windows' do.
                      child: bevel ? ColoredBox(color: DialupColors.of(t).titlebar, child: Padding(padding: EdgeInsets.only(top: pad.top), child: top)) : top,
                    ),
                    if (ready)
                      Positioned(
                        left: bevel ? 0 : t.space(4),
                        right: bevel ? 0 : t.space(4),
                        bottom: bevel ? 0 : pad.bottom + t.space(4),
                        child: Center(
                          child: ConstrainedBox(
                            // On a wide computer window the dock keeps to a width a hand can cross.
                            constraints: BoxConstraints(maxWidth: bevel ? double.infinity : t.lenOf('56rem')),
                            child: bevel ? dock.withFoot(pad.bottom) : dock,
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The colours the controls draw in, from the look's own tokens: the page's paper, frosted over the picture, with its
/// ink and the look's one strong fill for play and for how far it has got; Dial-Up's silver, bevels and navy instead.
class _DockLook {
  _DockLook._({required this.bevel, required this.ground, required this.ink, required this.soft, required this.strong, required this.onStrong, required this.track, required this.rim});

  factory _DockLook.of(Tokens t, bool bevel) {
    if (bevel) {
      final c = DialupColors.of(t);
      return _DockLook._(bevel: true, ground: c.chrome, ink: c.onChrome, soft: c.onChrome, strong: c.titlebar, onStrong: c.titlebarInk, track: c.paper, rim: c.dark);
    }
    final (strong, onStrong) = strongFill(t);
    final ink = t.color('app-ink');
    return _DockLook._(
      bevel: false,
      ground: t.color('app-paper').withValues(alpha: 0.9),
      ink: ink,
      soft: t.color('app-ink-3'),
      strong: strong,
      onStrong: onStrong,
      track: ink.withValues(alpha: 0.18),
      rim: ink.withValues(alpha: 0.12),
    );
  }

  final bool bevel;
  final Color ground, ink, soft, strong, onStrong, track, rim;

  BoxDecoration panel(Tokens t) => BoxDecoration(color: ground, borderRadius: BorderRadius.circular(t.radius('full')), border: Border.all(color: rim));
}

/// A round button in the look's colours (the way back, mute, full screen); filled with the strong colour for play.
class _Round extends StatelessWidget {
  const _Round({required this.look, required this.icon, required this.label, required this.onPressed, this.size = 44, this.filled = false, this.flat = false});
  final _DockLook look;
  final LucideIcon icon;
  final String label;
  final VoidCallback onPressed;
  final double size;
  final bool filled;

  /// Inside the dock: no ground of its own, only a shade while pressed.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    if (look.bevel) return RetroButton(onPressed: onPressed, icon: icon, semanticLabel: label, faceHeight: 32, minFaceWidth: 36, padding: const EdgeInsets.symmetric(horizontal: 6));
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      // A flat fill, not a blur of the video behind it: a blur over a playing video is drawn again for every one of
      // its frames, and needs pictures of its own made as the screen opens (the hitch on opening and closing).
      builder: (context, state) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? look.strong.withValues(alpha: state.pressed ? 0.82 : 1) : (flat ? look.ink.withValues(alpha: state.pressed ? 0.12 : (state.hovered ? 0.06 : 0)) : look.ground),
          border: filled || flat ? null : Border.all(color: look.rim),
        ),
        alignment: Alignment.center,
        child: AppIcon(icon, size: size * 0.42, wash: false, color: filled ? look.onStrong : look.ink),
      ),
    );
  }
}

/// The dock at the foot: play, the time, where it has got to, how long, the sound; on a computer a volume slider and
/// full screen beside them.
class _Dock extends StatelessWidget {
  const _Dock({
    required this.look,
    required this.desk,
    required this.playing,
    required this.at,
    required this.total,
    required this.part,
    required this.muted,
    required this.volume,
    required this.fullscreen,
    required this.onPlayPause,
    required this.onHold,
    required this.onLet,
    required this.onMute,
    required this.onVolume,
    required this.onFullscreen,
    this.foot = 0,
  });

  final _DockLook look;
  final bool desk, playing, muted, fullscreen;
  final String at, total;
  final double part, volume;
  final VoidCallback onPlayPause, onMute, onFullscreen;
  final ValueChanged<double> onHold, onLet, onVolume;

  /// Room under it for the phone's own bar (Dial-Up's panel runs to the foot of the screen).
  final double foot;

  _Dock withFoot(double foot) => _Dock(look: look, desk: desk, playing: playing, at: at, total: total, part: part, muted: muted, volume: volume, fullscreen: fullscreen, onPlayPause: onPlayPause, onHold: onHold, onLet: onLet, onMute: onMute, onVolume: onVolume, onFullscreen: onFullscreen, foot: foot);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) => _row(context, box.maxWidth));

  Widget _row(BuildContext context, double width) {
    final t = context.tokens;
    final time = pageText(t, t.fontSize('sm'), weight: 'semibold', color: look.ink, mono: true);
    // A computer's window made narrow keeps the scrubber long enough to use: the volume slider goes first (the arrows
    // and mute still turn the sound).
    final slider = desk && width >= t.lenOf('34rem');
    final row = Row(children: [
      _Round(look: look, icon: playing ? Lucide.pause : Lucide.play, label: playing ? 'Pause' : 'Play', onPressed: onPlayPause, size: 48, filled: true),
      SizedBox(width: t.space(3)),
      Text(at, style: time),
      SizedBox(width: t.space(3)),
      Expanded(child: _Track(look: look, part: part, label: 'Where the video is', onHold: onHold, onLet: onLet)),
      SizedBox(width: t.space(3)),
      Text(total, style: time.copyWith(color: look.soft, fontWeight: FontWeight.w400)),
      SizedBox(width: t.space(2)),
      _Round(look: look, icon: muted ? LucideMore.volumeX : Lucide.volume2, label: muted ? 'Sound on' : 'Mute', onPressed: onMute, size: 40, flat: true),
      if (slider) ...[
        SizedBox(width: t.lenOf('6rem'), child: _Track(look: look, part: volume, label: 'Volume', onHold: onVolume, onLet: onVolume)),
        SizedBox(width: t.space(2)),
      ],
      if (desk) ...[
        if (!look.bevel) _Round(look: look, icon: fullscreen ? LucideMore.minimize : Lucide.maximize, label: fullscreen ? 'Leave full screen' : 'Full screen', onPressed: onFullscreen, size: 40, flat: true),
      ],
    ]);
    if (look.bevel) {
      // Dial-Up: the window's silver panel along the foot, raised, its buttons the era's square ones.
      return Bevel(padding: EdgeInsets.fromLTRB(t.space(2), t.space(2), t.space(3), t.space(2) + foot), child: row);
    }
    return Container(
      padding: EdgeInsets.fromLTRB(t.space(2), t.space(2), t.space(3), t.space(2)),
      decoration: look.panel(t),
      child: row,
    );
  }
}

/// A line to drag along (where the video is, or the volume): the strong colour up to where it is, on a faint line, and
/// a knob that grows while held. A mouse drags it, or clicks a place on it, as a finger does. Dial-Up's is a white
/// well sunk into the panel with navy filling it and a raised silver knob.
class _Track extends StatefulWidget {
  const _Track({required this.look, required this.part, required this.label, required this.onHold, required this.onLet});
  final _DockLook look;
  final double part;
  final String label;
  final ValueChanged<double> onHold;
  final ValueChanged<double> onLet;

  @override
  State<_Track> createState() => _TrackState();
}

class _TrackState extends State<_Track> {
  bool _holding = false;
  bool _hover = false;
  double _at = 0;

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double partOf(double x) => (x / w).clamp(0.0, 1.0);
      final shown = _holding ? _at : widget.part;
      final big = _holding || _hover;
      final Widget line;
      if (look.bevel) {
        final knob = 12.0;
        line = Stack(alignment: Alignment.centerLeft, clipBehavior: Clip.none, children: [
          SizedBox(width: w, height: 10, child: Sunken(color: look.track, child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: shown, child: ColoredBox(color: look.strong)))),
          Positioned(left: (w * shown - knob / 2).clamp(0.0, w - knob), child: SizedBox(width: knob, height: 20, child: const Bevel())),
        ]);
      } else {
        final knob = big ? 16.0 : 12.0;
        line = Stack(alignment: Alignment.centerLeft, clipBehavior: Clip.none, children: [
          Container(height: 4, decoration: BoxDecoration(color: look.track, borderRadius: BorderRadius.circular(2))),
          Container(width: w * shown, height: 4, decoration: BoxDecoration(color: look.strong, borderRadius: BorderRadius.circular(2))),
          Positioned(
            left: (w * shown - knob / 2).clamp(-knob / 2, w - knob / 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: knob,
              height: knob,
              decoration: BoxDecoration(shape: BoxShape.circle, color: look.strong, border: Border.all(color: look.ground, width: 1.5)),
            ),
          ),
        ]);
      }
      return Semantics(
        slider: true,
        label: widget.label,
        value: '${(shown * 100).round()}%',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
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
            child: SizedBox(height: 36, child: line),
          ),
        ),
      );
    });
  }
}

/// A video that can't be played: what is wrong in a card of the look's own, and the device's own app for it.
class _Problem extends StatelessWidget {
  const _Problem({required this.look, required this.words, this.why, this.onOpen});
  final _DockLook look;
  final String words;
  final String? why;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = look.bevel ? DialupColors.of(t).ink : look.ink;
    final soft = look.bevel ? DialupColors.of(t).inkSoft : look.soft;
    final body = Column(mainAxisSize: MainAxisSize.min, children: [
      AppIcon(Lucide.film, size: 28, color: soft, wash: false),
      SizedBox(height: t.space(3)),
      Text(words, textAlign: TextAlign.center, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: ink)),
      if (why != null) ...[
        SizedBox(height: t.space(1)),
        Text(why!, textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: soft, height: 1.4)),
      ],
      if (onOpen != null) ...[
        SizedBox(height: t.space(4)),
        if (look.bevel)
          RetroButton(onPressed: onOpen, icon: Lucide.externalLink, label: 'Open with another app', primary: true)
        else
          GlacierPressable(
            onPressed: onOpen,
            semanticLabel: 'Open with another app',
            excludeSemantics: true,
            builder: (context, state) => Container(
              padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2) + 2),
              decoration: BoxDecoration(color: look.strong.withValues(alpha: state.pressed ? 0.85 : 1), borderRadius: BorderRadius.circular(t.radius('full'))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(Lucide.externalLink, size: 16, color: look.onStrong, wash: false),
                SizedBox(width: t.space(2)),
                Flexible(child: Text('Open with another app', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: look.onStrong))),
              ]),
            ),
          ),
      ],
    ]);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: t.lenOf('24rem')),
      child: Padding(
        padding: EdgeInsets.all(t.space(4)),
        child: look.bevel
            ? Bevel(padding: EdgeInsets.all(t.space(5)), child: Sunken(padding: EdgeInsets.all(t.space(5)), child: body))
            : Container(
                padding: EdgeInsets.all(t.space(6)),
                decoration: BoxDecoration(color: t.color('app-paper'), borderRadius: BorderRadius.circular(t.radius('lg')), border: Border.all(color: look.rim)),
                child: body,
              ),
      ),
    );
  }
}
