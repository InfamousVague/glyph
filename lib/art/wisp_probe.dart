import 'dart:async';
import 'dart:io' show Directory, File, Platform;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../perf/frame_log.dart' show ghostPerf;

/// What a build made to be measured (`--dart-define=GHOST_PERF=true`, tool/perf.sh) takes away from the smoke, so
/// each part's cost can be read as the difference between two walks of one build: `GHOST_PERF_SMOKE` in the
/// environment of a desktop build (or the same name as a dart-define where a build has no environment), a list of
/// the names below with commas or plus signs between.
///
///     PERF_BUILD=0 GHOST_PERF_SMOKE=phone+first tool/perf.sh mac home+note
///
/// - `off`: no strip is drawn at all, a view paints as if it wore no wisp: the floor.
/// - `phone`: the phone's drawing on a desktop (the smoke under a header and at the foot, the dock's halo bending),
///   since a desktop's own is a blurred strip and a plain fade, and it is the phone the smoke has to be fast on.
/// - `plain`: every strip takes its picture of the view and draws it straight back: what the pictures alone cost.
/// - `noblur`: a smoke without the blur of the bent view, in either drawing. Of the first drawing (three passes,
///   lib/art/wisp_smoke.dart `paintWispSmokeExact`): `nobend`, its picture of the bent view is the view as it is,
///   and `nomerge`, the bent view is drawn and nothing after it. Of the quick one: `nonear`, no search for ink near
///   a point.
/// - `nodock`, `noedge`: no halo round the dock; no strips at a page's own edges.
/// - `frostlayers`: a frosted letter is drawn by its own layers on every frame, as it was before its picture was
///   kept (lib/editor/marks/text_effects.dart).
/// - `noletter`: a letter in smoke (a spoiler's, a typed headline's) is drawn as the letter itself.
/// - `first`: the first drawing of every smoke, three passes a strip and a layer a letter, where a build draws the
///   quick one (lib/art/wisp_settings.dart `wispQuick`), to walk the two beside each other in one build: `phone`
///   against `phone+first`. `quick` asks for the quick one in a build made without it.
/// - `layers`: says, once a second while a view is drawn, what layers lie under it by kind (lib/art/wisp_strips.dart).
/// - `render`: says, once a second while frames are drawn, what the whole window is made of that the engine draws
///   through a picture of its own: opacities, masks, backdrop filters, soft clips, and how many repaint boundaries.
/// - `shots`: a picture of the window as the engine itself draws it, every second and a half, up to sixteen, in `shots-<the names asked>` of `GHOST_PERF_DIR`: for laying one drawing beside another
///   on the engine a device runs, where a test's pictures are another engine's. Not for a walk that is timed.
/// - `onebackdrop`: every backdrop filter in the window is given one key, as a `BackdropGroup` over the app would
///   give those made with `BackdropFilter.grouped`: what is behind them is read once for all of them.
/// - `spans`: says, as frames are drawn, what every frame waited between the end of its build and the start of its
///   raster, beside its raster time, in tenths of a millisecond. The pictures a strip or a sheet of
///   letters is drawn through are drawn by the engine in tasks of their own on the raster thread, before the
///   frame that uses them and outside its raster time: that wait is where they show.
/// - `covered`: every header a page smokes under is taken to hide its smoke (lib/art/wisp_edge.dart
///   `WispEdge.covered`): what that would save, before the pages that have such a header say so.
/// - `scroll=<pixels>`: every page that can scroll that far is put there, and put back there from the walk's fourth
///   second to its eighth: two drawings of one page at one place, for pictures to be laid pixel on pixel (`shots`),
///   or a stretch of a note drawn the same in every walk.
/// - `nobackdrop`: every backdrop filter in the window is switched off (the bars' glass, the dock's), and the log
///   says how often a rebuild switched one back on, since a frame it was on for is a frame that paid for it.
///
/// Nothing here is in a build that does not measure itself: [has] is false by a constant there, and the compiler
/// takes every use of it away.
abstract final class WispProbe {
  static const String _defined = String.fromEnvironment('GHOST_PERF_SMOKE');
  static final Set<String> _asked = _read();

  static Set<String> _read() {
    var said = _defined;
    try {
      said = Platform.environment['GHOST_PERF_SMOKE'] ?? said;
    } catch (_) {
      // No environment to read: the build's own word stands.
    }
    return {
      for (final name in said.split(RegExp(r'[,+\s]+')))
        if (name.isNotEmpty) name,
    };
  }

  static bool has(String name) => ghostPerf && _asked.contains(name);

  /// `scroll=`: every vertical scroller that reaches [to] is put there, twice a second from the walk's fourth second
  /// to its eighth (a walk has opened what it means to by then, and is left alone after).
  static void _scrollTo(double to) {
    var times = 0;
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (++times > 16) timer.cancel();
      if (times < 8) return;
      void visit(Element element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          final position = (element.state as ScrollableState).position;
          if (position.axis == Axis.vertical && position.hasContentDimensions && position.maxScrollExtent >= to && (position.pixels - to).abs() > 0.01) position.jumpTo(to);
        }
        element.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(visit);
    });
  }

  /// `spans`: each frame's wait between its build's end and its raster's start, and its raster, a line a second.
  static void _spans() {
    SchedulerBinding.instance.addTimingsCallback((timings) {
      if (timings.isEmpty) return;
      // A line for each batch the engine hands over (ten a second in a profile build), so a line's own time on the
      // log is near enough its frames' to say which stretch of a walk they were drawn in.
      // ignore: avoid_print
      print('[spans] ${[
        for (final frame in timings)
          '${((frame.timestampInMicroseconds(ui.FramePhase.rasterStart) - frame.timestampInMicroseconds(ui.FramePhase.buildFinish)) / 100).round()}/${(frame.rasterDuration.inMicroseconds / 100).round()}',
      ].join(' ')}');
    });
  }

  /// `shots`: the window's own layers drawn to a picture by the engine, now and then while frames are drawn.
  static void _shoot() {
    final root = Platform.environment['GHOST_PERF_DIR'];
    if (root == null || root.isEmpty) return;
    final dir = Directory('$root/shots-${(_asked.toList()..sort()).join('+')}');
    var taken = 0, busy = false;
    // By the clock and not by the frame: a page at rest draws no frames, and a page at rest is what two drawings
    // are best laid side by side from.
    Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (busy) return;
      if (taken >= 16) {
        timer.cancel();
        return;
      }
      busy = true;
      final n = taken++;
      try {
        final view = RendererBinding.instance.renderViews.first;
        // ignore: invalid_use_of_protected_member
        final layer = view.layer! as OffsetLayer;
        final image = await layer.toImage(Offset.zero & view.size, pixelRatio: view.flutterView.devicePixelRatio);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        dir.createSync(recursive: true);
        File('${dir.path}/shot-${n.toString().padLeft(2, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
      } catch (failure) {
        debugPrint('[perf] no picture: $failure');
      } finally {
        busy = false;
      }
    });
  }

  static bool _watching = false;

  /// Begins what a probe does by itself (`render`, `nobackdrop`), once: asked by the first wisp a build draws.
  static void watch() {
    if (!ghostPerf || _watching) return;
    _watching = true;
    final census = _asked.contains('render'), bare = _asked.contains('nobackdrop'), one = _asked.contains('onebackdrop');
    if (_asked.contains('shots')) _shoot();
    if (_asked.contains('spans')) _spans();
    for (final name in _asked) {
      final to = name.startsWith('scroll=') ? double.tryParse(name.substring(7)) : null;
      if (to != null) _scrollTo(to);
    }
    if (!census && !bare && !one) return;
    final shared = BackdropKey();
    var frames = 0, saidAt = 0, switchedOff = 0, backOn = 0;
    final seen = Expando<bool>();
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      frames += 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      final say = now - saidAt >= 1000;
      // The census once a second; the switching off every frame, since a rebuild may undo it at any one.
      if (!bare && !one && !say) return;
      final kinds = <String, int>{};
      final where = <String>[];
      var all = 0;
      void count(String kind) => kinds[kind] = (kinds[kind] ?? 0) + 1;
      void visit(RenderObject object) {
        all += 1;
        if (object is RenderBackdropFilter) {
          if (one && !identical(object.backdropKey, shared)) object.backdropKey = shared;
          if (bare && object.enabled) {
            if (seen[object] ?? false) backOn += 1;
            seen[object] = true;
            object.enabled = false;
            switchedOff += 1;
          }
          count(object.enabled ? 'backdrop' : 'backdrop(off)');
          // Which one it is, by where it stands: in the order they are painted.
          if (say && object.hasSize) {
            final at = object.localToGlobal(Offset.zero);
            // Not while a page is turned to nothing on its way in or out: it stands nowhere then.
            if (at.isFinite && object.size.isFinite) {
              where.add('${object.size.width.round()}x${object.size.height.round()}@${at.dx.round()},${at.dy.round()}${object.backdropKey == null ? '' : ' grouped'}');
            }
          }
        } else if (object is RenderRepaintBoundary) {
          count('boundary');
        } else if (object is RenderOpacity) {
          if (object.opacity > 0 && object.opacity < 1) count('opacity');
        } else if (object is RenderAnimatedOpacity) {
          if (object.opacity.value > 0 && object.opacity.value < 1) count('opacity(animated)');
        } else if (object is RenderShaderMask) {
          count('shaderMask');
        } else if (object is RenderClipRRect) {
          count('clipRRect(${object.clipBehavior.name})');
        } else if (object is RenderClipPath) {
          count('clipPath(${object.clipBehavior.name})');
        } else if (object is RenderClipOval) {
          count('clipOval(${object.clipBehavior.name})');
        } else if (object is RenderPhysicalModel || object is RenderPhysicalShape) {
          count('physical');
        } else if (object.runtimeType.toString().contains('ImageFilter')) {
          count('imageFilter');
        }
        object.visitChildren(visit);
      }

      for (final view in RendererBinding.instance.renderViews) {
        visit(view);
      }
      if (!say) return;
      saidAt = now;
      final said = (kinds.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((entry) => '${entry.key}=${entry.value}').join(' ');
      debugPrint('[perf] render: $frames frames, $all objects, $said${where.isEmpty ? '' : ' | backdrops: ${where.join('; ')}'}${bare ? ' | backdrops switched off $switchedOff, back on by a rebuild $backOn' : ''}');
      frames = 0;
    });
  }
}
