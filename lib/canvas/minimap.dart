/// The minimap (choice 10), in the bottom corner of the canvas: the whole canvas small, with the screen's box over
/// it. A port of `src/app/canvas/Minimap.tsx` and Minimap.module.css.
///
/// It is the canvas itself, small, and not a diagram of it: a card of words shows the shape of its words
/// (map_detail.dart), a note its title and a few lines, an address a ring; the lines are the canvas's own curves
/// and arrow heads; a group is its dashed box and its name. A card with a colour wears it. The screen's box is a
/// soft line with round corners, and what is outside it is shaded. A canvas of fewer than two cards has no map.
///
/// A press on it grows it, and it stays grown until a press lands on the canvas. A drag on the map, small or
/// grown, moves the screen's box with the finger, and a tap on the grown map goes to the spot tapped.
///
/// What differs from the web:
/// - It is one painter that reads the camera as it paints, where the web drew an SVG again from the view copied
///   once a frame; [MapFrame] is the sum both do, kept apart so a press reads the same frame the paint drew.
/// - One of Ghost.md's own pictures is decoded small for the map by the map itself, from where the cards draw
///   theirs ([Minimap.pictures]), where the page handed an `<image>` the address; until it is, and for a picture
///   from elsewhere, the card is the block it was.
/// - Lines that stay a pixel wide whatever the map's size (`vector-effect: non-scaling-stroke`) are stroked at a
///   pixel over the map's scale.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Canvas;
import 'package:glacier/glacier.dart';

import '../art/svg_path.dart';
import '../core/images.dart';
import '../sheet/css.dart';
import 'camera.dart';
import 'card_looks.dart';
import 'geometry.dart';
import 'json_canvas.dart';
import 'map_detail.dart';
import 'paint.dart';
import 'viewport.dart';

/// The map's frame and the room inside it, in the map's own units; grown, it is drawn half again as big.
const double mapWidth = 204;
const double mapHeight = 136;
const double _room = 8;

/// The round of the screen's box, in the map's units.
const double _seenRound = 5;

/// A press that moves this far, in pixels on the page, is a drag rather than a tap.
const double _mapDrag = 3;

/// Where the canvas sits in the map: the whole of the canvas and the screen's box together, scaled into the frame
/// and centred, so the screen is always drawn even when it is off the cards.
class MapFrame {
  MapFrame._(this.left, this.top, this.scale, this.ox, this.oy, this.seen);

  static MapFrame? of(Canvas canvas, CameraView view, double width, double height) {
    final box = bounds(canvas);
    if (box == null || canvas.nodes.length < 2) return null;
    final seen = shown(view, width, height);
    final left = math.min(box.x, seen.x);
    final top = math.min(box.y, seen.y);
    final right = math.max(box.x + box.width, seen.x + seen.width);
    final bottom = math.max(box.y + box.height, seen.y + seen.height);
    final scale = math.min((mapWidth - _room * 2) / math.max(right - left, 1), (mapHeight - _room * 2) / math.max(bottom - top, 1));
    final ox = _room + (mapWidth - _room * 2 - (right - left) * scale) / 2;
    final oy = _room + (mapHeight - _room * 2 - (bottom - top) * scale) / 2;
    return MapFrame._(left, top, scale, ox, oy, seen);
  }

  final double left;
  final double top;

  /// Units of the map to a pixel of the canvas.
  final double scale;
  final double ox;
  final double oy;

  /// What the screen shows, in the canvas's pixels.
  final BoxOf seen;

  double sx(double x) => ox + (x - left) * scale;
  double sy(double y) => oy + (y - top) * scale;

  /// The screen's box, in the map's units.
  Rect get seenRect => Rect.fromLTWH(sx(seen.x), sy(seen.y), seen.width * scale, seen.height * scale);

  /// The point of the canvas at a point of the map, in the map's units.
  Point at(double mx, double my) => (x: left + (mx - ox) / scale, y: top + (my - oy) / scale);
}

/// `kindOf`: what a card is on the map.
String mapKind(CanvasNode n) => n.type == NodeType.file ? (isImageFile(n.file) ? 'picture' : 'note') : n.type.name;

class Minimap extends StatefulWidget {
  const Minimap({super.key, required this.canvas, required this.lines, required this.camera, required this.big, required this.onBig, required this.own, this.pictures});

  final Canvas canvas;

  /// Where the canvas's own pictures are kept: the map draws a picture card's picture in it (`<image href={url}
  /// preserveAspectRatio="xMidYMid slice">`). Without one, a picture card is drawn plain.
  final PictureStore? pictures;

  /// The canvas's lines as the view draws them, so the map's are the same curves.
  final List<DrawnLine> lines;
  final CanvasCamera camera;
  final bool big;
  final VoidCallback onBig;
  final Widget Function(Widget child) own;

  @override
  State<Minimap> createState() => _MinimapState();
}

class _MinimapState extends State<Minimap> {
  /// The press under way: where the finger was last, on the page, and whether it has dragged.
  ({int pointer, Offset at, bool moved, bool wasBig})? _press;

  MapFrame? _frame() => MapFrame.of(widget.canvas, widget.camera.view, widget.camera.width, widget.camera.height);

  /// The pictures the store has for the canvas's own picture cards, by card, decoded for the map: asked for as the
  /// canvas or the store changes, never as the map is painted, and the map is drawn again when one arrives
  /// (`pictures`, the page's list of `id\turl`).
  final Map<String, _MapPicture> _pictures = <String, _MapPicture>{};
  Map<String, ui.Image> _images = const <String, ui.Image>{};

  @override
  void initState() {
    super.initState();
    widget.pictures?.addListener(_look);
    _look();
  }

  @override
  void didUpdateWidget(Minimap old) {
    super.didUpdateWidget(old);
    if (!identical(old.pictures, widget.pictures)) {
      old.pictures?.removeListener(_look);
      widget.pictures?.addListener(_look);
    }
    if (!identical(old.pictures, widget.pictures) || !identical(old.canvas, widget.canvas)) _look();
  }

  @override
  void dispose() {
    widget.pictures?.removeListener(_look);
    for (final picture in _pictures.values) {
      picture.stop();
    }
    _pictures.clear();
    super.dispose();
  }

  void _look() {
    final store = widget.pictures;
    final wanted = <String>{};
    var changed = false;
    if (store != null) {
      for (final n in widget.canvas.nodes) {
        final own = ownPicture(n);
        final picture = own == null ? null : store.pictureOf(own);
        if (own == null || picture == null) continue;
        wanted.add(n.id);
        final had = _pictures[n.id];
        if (had != null && had.name == own && had.version == picture.version) continue;
        final was = had?.image != null;
        had?.stop();
        // One decoded before (the map made again, a card of the same picture) answers as it is asked for, before
        // it is kept here: it is drawn with the rest, below.
        final made = _pictures[n.id] = _MapPicture(own, picture, _arrived);
        changed = changed || was || made.image != null;
      }
    }
    for (final id in _pictures.keys.toList()) {
      if (wanted.contains(id)) continue;
      final gone = _pictures.remove(id)!;
      changed = changed || gone.image != null;
      gone.stop();
    }
    if (changed) _arrived();
  }

  /// A picture was decoded, or one drawn is no longer the card's: the map is drawn with what there is now.
  void _arrived() {
    if (!mounted) return;
    final now = <String, ui.Image>{
      for (final entry in _pictures.entries) entry.key: ?entry.value.image,
    };
    // Told as a frame is built where a picture was decoded already (the image cache answers at once).
    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      _images = now;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() => _images = now);
  }

  /// The map's own box on the page, its line included, and how much of the page a pixel of it takes: the web's
  /// `getBoundingClientRect()` of the map, at the size it has now, mid-growth included.
  ({Rect rect, double factor})? _onPage(BuildContext inner, double line) {
    final box = inner.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.width == 0) return null;
    final rect = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    final factor = rect.width / box.size.width;
    return (rect: rect.inflate(line * factor), factor: factor);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.canvas.nodes.length < 2) return const SizedBox.shrink();
    final t = context.tokens;
    final line = t.len('glacier-hairline');
    final radius = BorderRadius.circular(t.radius('lg'));
    // On a phone's width the map is smaller, so it takes less of the page.
    final small = MediaQuery.sizeOf(context).width <= 600;
    final grow = widget.big ? 1.5 : 1.0;
    Widget map = Builder(
      builder: (inner) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _press = (pointer: event.pointer, at: event.position, moved: false, wasBig: widget.big);
          widget.onBig();
        },
        onPointerMove: (event) {
          final p = _press;
          if (p == null || p.pointer != event.pointer) return;
          final delta = event.position - p.at;
          if (!p.moved && delta.distance < _mapDrag) return;
          _press = (pointer: p.pointer, at: event.position, moved: true, wasBig: p.wasBig);
          final frame = _frame();
          if (frame == null) return;
          final page = _onPage(inner, line);
          if (page == null) return;
          // Pixels on the page per unit of the map.
          final k = page.rect.width / mapWidth;
          widget.camera.panBy(delta.dx / k / frame.scale, delta.dy / k / frame.scale);
        },
        onPointerUp: (event) {
          final p = _press;
          _press = null;
          // A tap on the grown map goes there; the tap that grew it only grew it.
          if (p == null || p.moved || !p.wasBig) return;
          final frame = _frame();
          final page = _onPage(inner, line);
          if (frame == null || page == null) return;
          final k = page.rect.width / mapWidth;
          widget.camera.centreOn(frame.at((event.position.dx - page.rect.left) / k, (event.position.dy - page.rect.top) / k));
        },
        onPointerCancel: (_) => _press = null,
        child: CustomPaint(
          painter: MapPainter(canvas: widget.canvas, lines: widget.lines, camera: widget.camera, t: t, images: _images),
          child: const SizedBox.expand(),
        ),
      ),
    );
    map = Semantics(
      key: const ValueKey('map'),
      container: true,
      image: true,
      label: 'A map of the canvas; press to grow it, drag on it to move the screen, tap the grown map to go there',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.ease,
        width: mapWidth * grow,
        height: mapHeight * grow,
        decoration: BoxDecoration(borderRadius: radius, boxShadow: const [BoxShadow(color: Color(0x38000000), offset: Offset(0, 6), blurRadius: 20)]),
        child: ClipRRect(
          borderRadius: radius,
          // One of the window's group of glass (BackdropGroup, at the app's root): what lies behind is read once
          // for the bars, the tools, the picked card's bar and this, where each read the screen for itself.
          child: BackdropFilter.grouped(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.colorOf('color-mix(in oklch, var(--glacier-bg) 86%, transparent)'),
                borderRadius: radius,
                border: Border.all(color: t.color('glacier-border-subtle'), width: line),
              ),
              child: Padding(padding: EdgeInsets.all(line), child: map),
            ),
          ),
        ),
      ),
    );
    map = widget.own(map);
    return small ? Transform.scale(scale: 0.72, alignment: Alignment.bottomRight, child: map) : map;
  }
}

/// What a card is on the map, worked out once for the card as it is and the tokens it is drawn with: its kind, its
/// colours, and the bars its words make. The map is painted again at every move of the camera, and each paint read
/// every card's words into bars and mixed every card's colours again.
class _CardMark {
  _CardMark(this.t, this.paint, this.kind, this.fill, this.stroke, this.ring);
  final Tokens t;
  final CardPaint? paint;
  final String kind;
  final Color? fill;
  final Color stroke;

  /// A link's ring.
  final Color? ring;
  List<MapBar>? bars;
  Color? strong;
  Color? weak;
}

final Expando<_CardMark> _cardMarks = Expando<_CardMark>('a card on the map');

/// A group on the map: its paint (a preset's hue only), its wash, its line and its name's colour.
typedef _GroupMark = ({Tokens t, CardPaint? paint, Color wash, Color line, Color name});
final Expando<_GroupMark> _groupMarks = Expando<_GroupMark>('a group on the map');

/// A line's colour on the map, by the edge and the tokens.
final Expando<({Tokens t, Color color})> _lineMarks = Expando<({Tokens t, Color color})>('a line on the map');

/// One of the canvas's own pictures, being decoded for the map: no wider than the map is ever drawn, so a
/// photograph costs the map a thumbnail's memory.
class _MapPicture {
  _MapPicture(this.name, Picture picture, VoidCallback arrived) : version = picture.version {
    final bytes = picture.bytes;
    final ImageProvider from = bytes != null ? MemoryImage(bytes) : FileImage(File(picture.path!));
    _stream = ResizeImage(from, width: _decodedWidth).resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener(
      (info, _) {
        final before = _info;
        _info = info;
        if (before != null) SchedulerBinding.instance.addPostFrameCallback((_) => before.dispose());
        // Not while it is being made: whoever makes it reads [image] then.
        if (_asked) arrived();
      },
      onError: (Object _, StackTrace? _) {
        // A file that is not a picture: the card stays the block it was.
      },
    );
    _stream.addListener(_listener);
    _asked = true;
  }

  bool _asked = false;

  /// The map grown is 306 units wide, and a card is never the whole of it on a screen of three pixels to the unit.
  static const int _decodedWidth = 256;

  final String name;
  final int version;
  late final ImageStream _stream;
  late final ImageStreamListener _listener;
  ImageInfo? _info;

  ui.Image? get image => _info?.image;

  /// Let go. What was decoded is let go after the frame: the map's last drawing may still hold it until the map is
  /// built again without it.
  void stop() {
    _stream.removeListener(_listener);
    final info = _info;
    _info = null;
    if (info != null) SchedulerBinding.instance.addPostFrameCallback((_) => info.dispose());
  }
}

/// Everything on the canvas, in the canvas's own pixels under one transform: the groups under, then the lines,
/// then the cards; then what the screen does not show, shaded, and the screen's box.
class MapPainter extends CustomPainter {
  MapPainter({required this.canvas, required this.lines, required this.camera, required this.t, this.images = const <String, ui.Image>{}}) : super(repaint: camera);

  final Canvas canvas;
  final List<DrawnLine> lines;
  final CanvasCamera camera;
  final Tokens t;

  /// The decoded pictures of the canvas's own picture cards, by card ([Minimap.pictures]).
  final Map<String, ui.Image> images;

  /// What the last paint drew, for a test to read: each card's kind, hue and bars, the lines and heads, the name.
  static MapDrawn? lastDrawn;

  Color _mix(String share, CardPaint? paint) => spaceColor(t, 'color-mix(in oklch, var(--app-space, var(--app-ink)) $share, transparent)', paint);

  @override
  void paint(ui.Canvas ctx, Size size) {
    final frame = MapFrame.of(canvas, camera.view, camera.width, camera.height);
    if (frame == null) return;
    final drawn = MapDrawn();
    lastDrawn = drawn;
    // The map is drawn in one set of units, whatever its size on the page.
    final k = size.width / mapWidth;
    ctx.save();
    ctx.clipRect(Offset.zero & size);
    ctx.scale(k);
    final scale = frame.scale;
    // A hairline on the screen: a pixel, whatever the map's size and the canvas's.
    final hair = 1 / (scale * k);
    // A line of a card's words is worth drawing once it is a quarter of a unit thick.
    final detail = scale * 8 >= 0.25;
    final unit = 1 / scale;
    ctx.save();
    ctx.translate(frame.ox - frame.left * scale, frame.oy - frame.top * scale);
    ctx.scale(scale);
    for (final n in canvas.nodes) {
      if (!n.isGroup) continue;
      var mark = _groupMarks[n];
      if (mark == null || !identical(mark.t, t)) {
        // A group wears a preset's hue; a hex is the cards' own, not the group's, on the map.
        final paint = paintOf(n.color)?.hue == null ? null : paintOf(n.color);
        mark = _groupMarks[n] = (t: t, paint: paint, wash: _mix('6%', paint), line: _mix('40%', paint), name: spaceOver(t, paint, 0.75, 'glacier-text-muted'));
      }
      final box = RRect.fromRectAndRadius(Rect.fromLTWH(n.x, n.y, n.width, n.height), const Radius.circular(16));
      ctx.drawRRect(box, Paint()..color = mark.wash);
      _dashed(ctx, Path()..addRRect(box), mark.line, hair, 3 * hair, 2 * hair);
      final label = n.label;
      if (label != null && n.width / unit > 36) {
        drawn.name = label;
        final size = 7 * unit;
        final words = TextPainter(
          text: TextSpan(text: label, style: pageText(t, size, weight: 'semibold', tracking: 0.02 * size, color: mark.name)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        // `<text x y>` sets the words' baseline at y.
        words.paint(ctx, Offset(n.x + 4 * unit, n.y - 3 * unit - words.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
        words.dispose();
      }
    }
    for (final line in lines) {
      var worn = _lineMarks[line.edge];
      if (worn == null || !identical(worn.t, t)) worn = _lineMarks[line.edge] = (t: t, color: _mix('50%', paintOf(line.edge.color)));
      final color = worn.color;
      drawn.lines += 1;
      ctx.drawPath(
        linePath(line.path.d),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hair
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      for (final head in [line.path.fromHead, line.path.toHead]) {
        if (head == null) continue;
        drawn.heads += 1;
        ctx.drawPath(linePath(head), Paint()..color = color);
      }
    }
    for (final n in canvas.nodes) {
      if (n.isGroup) continue;
      var mark = _cardMarks[n];
      if (mark == null || !identical(mark.t, t)) {
        final paint = paintOf(n.color);
        final kind = mapKind(n);
        final (fill, stroke) = switch (kind) {
          'note' => (spaceOver(t, paint, 0.06, 'glacier-bg'), _mix('60%', paint)),
          'picture' => (spaceOver(t, paint, 0.45, 'glacier-bg'), _mix('42%', paint)),
          'link' => (null, _mix('55%', paint)),
          _ => (spaceOver(t, paint, 0.14, 'glacier-bg'), _mix('42%', paint)),
        };
        mark = _cardMarks[n] = _CardMark(t, paint, kind, fill, stroke, kind == 'link' ? _mix('70%', paint) : null);
      }
      final paint = mark.paint;
      final kind = mark.kind;
      final fill = mark.fill;
      final box = RRect.fromRectAndRadius(Rect.fromLTWH(n.x, n.y, n.width, n.height), const Radius.circular(12));
      if (fill != null) ctx.drawRRect(box, Paint()..color = fill);
      ctx.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hair
          ..color = mark.stroke,
      );
      // The card's own picture, filling its box from the middle and cut to its corners (`preserveAspectRatio="xMidYMid
      // slice"`, `clip-path` the box's own `rx`).
      final image = images[n.id];
      if (image != null) {
        drawn.pictures.add(n.id);
        ctx.save();
        ctx.clipRRect(box);
        paintImage(canvas: ctx, rect: box.outerRect, image: image, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
        ctx.restore();
      }
      // The bars are a card's words and its size, which a card moved keeps: read once for the node as it is.
      final bars = !detail ? const <MapBar>[] : (mark.bars ??= n.type == NodeType.text ? wordBars(n.text, n.width, n.height) : (kind == 'note' ? noteBars(fileTitle(n.file), n.width, n.height) : const <MapBar>[]));
      for (final bar in bars) {
        ctx.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(n.x + bar.x, n.y + bar.y, bar.width, bar.height), Radius.circular(bar.height / 2)),
          Paint()..color = bar.strong ? (mark.strong ??= _mix('82%', paint)) : (mark.weak ??= _mix('46%', paint)),
        );
      }
      final ring = mark.ring;
      if (ring != null) {
        ctx.drawCircle(
          Offset(n.x + n.width / 2, n.y + n.height / 2),
          math.min(14, n.height / 3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.25 * hair
            ..color = ring,
        );
      }
      drawn.cards.add((id: n.id, kind: kind, paint: paint, bars: [for (final bar in bars) bar.strong], ring: kind == 'link'));
    }
    ctx.restore();
    // What the screen does not show, shaded toward the page; and the screen's box, a soft line with round corners.
    final seen = frame.seenRect;
    drawn.seen = seen;
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(const Rect.fromLTWH(0, 0, mapWidth, mapHeight))
      ..addPath(svgPath(roundedBox(seen.left, seen.top, seen.width, seen.height, _seenRound)), Offset.zero);
    ctx.drawPath(shade, Paint()..color = t.colorOf('color-mix(in oklch, var(--glacier-bg) 52%, transparent)'));
    ctx.drawRRect(
      RRect.fromRectAndRadius(seen, Radius.circular(math.min(_seenRound, math.min(seen.width / 2, seen.height / 2)))),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..color = t.colorOf('color-mix(in oklch, var(--app-ink) 46%, transparent)'),
    );
    ctx.restore();
  }

  void _dashed(ui.Canvas ctx, Path path, Color color, double width, double dash, double gap) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash + gap) {
        ctx.drawPath(metric.extractPath(at, math.min(at + dash, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(MapPainter old) => !identical(old.canvas, canvas) || !identical(old.lines, lines) || old.camera != camera || !identical(old.t, t) || !identical(old.images, images);
}

/// What a paint of the map drew.
class MapDrawn {
  final List<({String id, String kind, CardPaint? paint, List<bool> bars, bool ring})> cards = [];
  int lines = 0;
  int heads = 0;
  String? name;
  Rect? seen;

  /// The cards whose own picture was drawn in their box.
  final Set<String> pictures = <String>{};
}
