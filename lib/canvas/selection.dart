/// What the picked card wears: a ring with a handle at each corner and the middle of each side, and a small bar of
/// what can be done to it. A port of `src/app/canvas/Selection.tsx` and Selection.module.css.
///
/// Both are children of the world at the card's own place, so they pan and zoom with it without being laid out
/// again; and both are held to one size on the screen (world.dart `Placed.fixed`), so a handle is a finger's width
/// and the bar a thumb's height at any zoom. A handle's dot is small; what takes the press is the 44px round it. A
/// press on either is theirs alone and never reaches the page's gestures.
///
/// What differs from the web:
/// - The ring is painted (the web's is an `outline`), a pixel and a half wide and 3px out at any zoom, read from
///   the camera as it paints.
/// - A handle's place is the stylesheet's sum split in two: the part that scales with the canvas (the card's own
///   corner round) is its place in the world, and the part that does not (the ring's 3.75px) is a nudge on the
///   screen. The same point, to the fraction (test/canvas/reference_test.dart).
/// - `@media (pointer: coarse)` (a finger has the four corners, a little larger) is [Handles.coarse], which the
///   view answers from the kind of pointer last seen.
/// - The handle's dot does not grow under a pointer (`:hover`, `:active`).
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Canvas;
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import 'camera.dart';
import 'card_looks.dart';
import 'edits.dart';
import 'json_canvas.dart';
import 'paint.dart';
import 'world.dart';

/// How far outside the card the middle of the ring's line is: its offset and half its width (`--ring`).
const double ringOut = 3.75;

/// The side of the round a handle takes a press in.
const double handleRoom = 44;

const Map<Handle, String> handleNames = {
  Handle.nw: 'top left corner',
  Handle.n: 'top side',
  Handle.ne: 'top right corner',
  Handle.e: 'right side',
  Handle.se: 'bottom right corner',
  Handle.s: 'bottom side',
  Handle.sw: 'bottom left corner',
  Handle.w: 'left side',
};

/// Where a handle's middle is: a point of the canvas, and how far from it on the screen.
({Offset at, Offset nudge}) handlePlace(CanvasNode node, Handle handle, double round) {
  // `--arc: (round + ring) * 0.2929`, `--near: arc - ring`, `--far: 100% + ring - arc`.
  const k = 0.2929;
  final nearAt = round * k;
  const nearNudge = ringOut * k - ringOut;
  final w = node.width;
  final h = node.height;
  final (at, nudge) = switch (handle) {
    Handle.nw => (Offset(nearAt, nearAt), const Offset(nearNudge, nearNudge)),
    Handle.ne => (Offset(w - nearAt, nearAt), const Offset(-nearNudge, nearNudge)),
    Handle.se => (Offset(w - nearAt, h - nearAt), const Offset(-nearNudge, -nearNudge)),
    Handle.sw => (Offset(nearAt, h - nearAt), const Offset(nearNudge, -nearNudge)),
    Handle.n => (Offset(w / 2, 0), const Offset(0, -ringOut)),
    Handle.s => (Offset(w / 2, h), const Offset(0, ringOut)),
    Handle.e => (Offset(w, h / 2), const Offset(ringOut, 0)),
    Handle.w => (Offset(0, h / 2), const Offset(-ringOut, 0)),
  };
  return (at: Offset(node.x, node.y) + at, nudge: nudge);
}

/// The picked card's ring and handles, as children of the world.
class Handles {
  const Handles({required this.node, required this.camera, required this.snap, required this.coarse, required this.onPreview, required this.onResize, required this.own, this.felt});

  final CanvasNode node;
  final CanvasCamera camera;

  /// Whether the sides a handle moves land on the grid's lines, with a tick each time one does.
  final bool snap;

  /// A finger rather than a pointer: the four corners, a little larger.
  final bool coarse;

  /// The card at each size on the way, drawn but not yet handed on.
  final void Function(CanvasNode node) onPreview;

  /// The card at the size it was let go at.
  final void Function(CanvasNode node) onResize;
  final Widget Function(Widget child) own;
  final void Function()? felt;

  List<Widget> build(BuildContext context) {
    final t = context.tokens;
    final round = t.radius('lg') + (node.isGroup ? 4 : 0);
    return [
      Placed(
        key: ValueKey('ring ${node.id}'),
        at: Offset(node.x, node.y),
        size: Size(node.width, node.height),
        child: IgnorePointer(
          child: CustomPaint(painter: _RingPainter(camera: camera, ink: t.color('app-ink'), round: round)),
        ),
      ),
      for (final handle in Handle.values)
        if (!coarse || handle.name.length == 2)
          () {
            final place = handlePlace(node, handle, round);
            return Placed(
              key: ValueKey('handle ${node.id} ${handle.name}'),
              at: place.at,
              nudge: place.nudge,
              anchor: Alignment.center,
              fixed: true,
              size: const Size(handleRoom, handleRoom),
              child: own(_Handle(node: node, handle: handle, camera: camera, snap: snap, coarse: coarse, onPreview: onPreview, onResize: onResize, felt: felt)),
            );
          }(),
    ];
  }
}

/// `.handles`' outline: `1.5px * inv`, `3px * inv` out, round as the card is.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.camera, required this.ink, required this.round}) : super(repaint: camera);
  final CanvasCamera camera;
  final Color ink;
  final double round;

  @override
  void paint(ui.Canvas canvas, Size size) {
    final inv = 1 / camera.view.scale;
    final out = ringOut * inv;
    canvas.drawRRect(
      RRect.fromRectAndRadius((Offset.zero & size).inflate(out), Radius.circular(round + out)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * inv
        ..color = ink,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.camera != camera || old.ink != ink || old.round != round;
}

class _Handle extends StatefulWidget {
  const _Handle({required this.node, required this.handle, required this.camera, required this.snap, required this.coarse, required this.onPreview, required this.onResize, this.felt});
  final CanvasNode node;
  final Handle handle;
  final CanvasCamera camera;
  final bool snap;
  final bool coarse;
  final void Function(CanvasNode node) onPreview;
  final void Function(CanvasNode node) onResize;
  final void Function()? felt;

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  /// The press under way: the pointer, where it landed on the screen, the card as it was, and the view's scale then.
  ({int pointer, Offset at, CanvasNode node, double zoom})? _take;

  /// The box the card last had: with snapping on, a new one is a side landed on a new line, and is felt.
  String _last = '';

  String _box(CanvasNode n) => '${n.x},${n.y},${n.width},${n.height}';

  CanvasNode _sized(Offset now) {
    final take = _take!;
    return resizedBy(take.node, widget.handle, (now.dx - take.at.dx) / take.zoom, (now.dy - take.at.dy) / take.zoom, widget.snap);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final corner = widget.handle.name.length == 2;
    final upright = widget.handle == Handle.e || widget.handle == Handle.w;
    final dot = corner ? Size.square(widget.coarse ? 16 : 13) : (upright ? const Size(7, 18) : const Size(18, 7));
    return Semantics(
      label: 'Drag the ${handleNames[widget.handle]} to resize',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          final zoom = widget.camera.view.scale;
          _take = (pointer: event.pointer, at: event.position, node: widget.node, zoom: zoom == 0 ? 1 : zoom);
          _last = _box(widget.node);
        },
        onPointerMove: (event) {
          if (_take?.pointer != event.pointer) return;
          final next = _sized(event.position);
          final box = _box(next);
          if (widget.snap && box != _last) widget.felt?.call();
          _last = box;
          widget.onPreview(next);
        },
        onPointerUp: (event) {
          if (_take?.pointer != event.pointer) return;
          final next = _sized(event.position);
          _take = null;
          widget.onResize(next);
        },
        onPointerCancel: (event) {
          if (_take?.pointer != event.pointer) return;
          final next = _sized(event.position);
          _take = null;
          widget.onResize(next);
        },
        child: Center(
          child: SizedBox.fromSize(
            size: dot,
            // Solid, with a gap of the page's colour round it, so the ring's line stops short of the handle.
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.color('glacier-bg'),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: t.color('app-ink'), width: 2),
                boxShadow: [BoxShadow(color: t.color('glacier-bg'), spreadRadius: 2.5)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The spec's presets in the order the page's hues run.
const List<({String color, CanvasHue hue, String name})> hues = [
  (color: '1', hue: CanvasHue.rose, name: 'Rose'),
  (color: '2', hue: CanvasHue.ember, name: 'Ember'),
  (color: '3', hue: CanvasHue.amber, name: 'Amber'),
  (color: '4', hue: CanvasHue.moss, name: 'Moss'),
  (color: '5', hue: CanvasHue.sea, name: 'Sea'),
  (color: '6', hue: CanvasHue.violet, name: 'Violet'),
];

/// A round button of the canvas's bars: `.barButton`, and `.tool` (CanvasView.module.css), which is the same
/// button. [on] is ink (the next tap is the tool's); [held] a wash (how the canvas is set).
class RoundButton extends StatelessWidget {
  const RoundButton({super.key, required this.label, required this.icon, required this.onPress, this.on = false, this.held = false, this.pressed, this.iconSize = 17, this.stroke = 2.2});
  final String label;
  final LucideIcon icon;
  final VoidCallback onPress;
  final bool on;
  final bool held;

  /// `aria-pressed`, where the button is a switch.
  final bool? pressed;
  final double iconSize;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = t.lenOf('2.25rem');
    final color = on ? t.color('glacier-bg') : (held ? t.color('app-ink') : t.color('app-ink-2'));
    final ground = on ? t.color('app-ink') : (held ? inkOf(t, 'color-mix(in oklch, var(--app-ink) 14%, transparent)') : null);
    return Semantics(
      button: true,
      label: label,
      toggled: pressed,
      onTap: onPress,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPress,
        child: Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: ground == null ? null : BoxDecoration(color: ground, shape: BoxShape.circle),
          child: AppIcon(icon, size: iconSize, strokeWidth: stroke, color: color, wash: false),
        ),
      ),
    );
  }
}

/// A pill of glass: `.bar`, `.tools`.
class GlassPill extends StatelessWidget {
  const GlassPill({super.key, required this.share, required this.blur, required this.padding, this.shadow, required this.child});

  /// How much of the page's ground the glass is, in a hundred.
  final int share;
  final double blur;
  final double padding;
  final BoxShadow? shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final line = t.len('glacier-hairline');
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), boxShadow: shadow == null ? null : [shadow!]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        // One of the window's group of glass (BackdropGroup, at the app's root), as the map is.
        child: BackdropFilter.grouped(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: inkOf(t, 'color-mix(in oklch, var(--glacier-bg) $share%, transparent)'),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.color('glacier-border-subtle'), width: line),
            ),
            child: Padding(padding: EdgeInsets.all(line + padding), child: child),
          ),
        ),
      ),
    );
  }
}

/// The bar over the picked card (`CardBar`), as a child of the world.
class CardBar extends StatefulWidget {
  const CardBar({
    super.key,
    required this.node,
    required this.editing,
    required this.onEdit,
    required this.onDone,
    this.onOpen,
    required this.onLine,
    required this.onColour,
    required this.onDuplicate,
    required this.onRemove,
    this.onComment,
  });

  final CanvasNode node;

  /// Open to be written in, or a group's name being written: the first button closes it.
  final bool editing;

  /// Write in a card of words, or name a group.
  final VoidCallback onEdit;
  final VoidCallback onDone;

  /// Open the note or the address a card stands for.
  final VoidCallback? onOpen;

  /// Start a line from this card.
  final VoidCallback onLine;
  final void Function(String? color) onColour;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;

  /// Start a comment thread on this card; left out where the canvas keeps none.
  final VoidCallback? onComment;

  /// The bar's place: over the card's top, or under its foot when its top is at the top of the screen.
  static Placed place({required CanvasNode node, required bool below, required Widget child}) => Placed(
    key: ValueKey('bar ${node.id}'),
    at: Offset(node.x + node.width / 2, below ? node.y + node.height : node.y),
    anchor: below ? Alignment.topCenter : Alignment.bottomCenter,
    nudge: Offset(0, below ? 14 : -14),
    fixed: true,
    child: child,
  );

  @override
  State<CardBar> createState() => _CardBarState();
}

class _CardBarState extends State<CardBar> {
  bool _colouring = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final paint = paintOf(node.color);
    final group = node.isGroup;
    final writes = node.type == NodeType.text || group;
    final List<Widget> buttons;
    if (_colouring) {
      buttons = [
        RoundButton(label: 'No colour', icon: Lucide.ban, onPress: () => widget.onColour(null), on: node.color == null, pressed: node.color == null),
        for (final each in hues) _Swatch(name: each.name, hue: each.hue, worn: paint?.hue == each.hue, onPress: () => widget.onColour(each.color)),
        RoundButton(label: 'Done with the colour', icon: Lucide.check, stroke: 2.4, onPress: () => setState(() => _colouring = false)),
      ];
    } else {
      buttons = [
        if (writes && widget.editing)
          RoundButton(label: group ? 'Done naming' : 'Done writing', icon: Lucide.check, stroke: 2.4, onPress: widget.onDone, on: true, pressed: true)
        else if (writes)
          RoundButton(label: group ? 'Name this group' : 'Write in this card', icon: Lucide.pencil, onPress: widget.onEdit)
        else if (widget.onOpen != null && ownPicture(node) == null)
          RoundButton(label: node.type == NodeType.link ? 'Open the address' : 'Open the note', icon: Lucide.externalLink, onPress: widget.onOpen!),
        if (!group) RoundButton(label: 'Draw a line from this card', icon: Lucide.spline, onPress: widget.onLine),
        if (widget.onComment != null) RoundButton(label: 'Comment on this card', icon: Lucide.messageSquare, onPress: widget.onComment!),
        RoundButton(label: 'Colour', icon: Lucide.palette, onPress: () => setState(() => _colouring = true)),
        RoundButton(label: group ? 'Copy this group’s box' : 'Make a copy', icon: Lucide.copyPlus, onPress: widget.onDuplicate),
        RoundButton(label: group ? 'Take this group off the canvas; its cards stay' : 'Take this card off the canvas', icon: Lucide.trash2, onPress: widget.onRemove),
      ];
    }
    return Semantics(
      container: true,
      label: group ? 'This group' : 'This card',
      child: GlassPill(
        share: 86,
        blur: 10,
        padding: 3,
        shadow: const BoxShadow(color: Color(0x47000000), offset: Offset(0, 6), blurRadius: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < buttons.length; i += 1) ...[if (i > 0) const SizedBox(width: 2), buttons[i]],
          ],
        ),
      ),
    );
  }
}

/// `.swatch`: a hue to wear, a dot of it, ringed when it is the one worn.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.hue, required this.worn, required this.onPress});
  final String name;
  final CanvasHue hue;
  final bool worn;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final rem = t.lenOf('1rem');
    return Semantics(
      button: true,
      label: name,
      toggled: worn,
      onTap: onPress,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPress,
        child: Padding(
          padding: EdgeInsets.all(0.375 * rem),
          child: Container(
            width: 1.5 * rem,
            height: 1.5 * rem,
            decoration: BoxDecoration(
              color: spaceColor(t, 'var(--app-space)', CardPaint.hue(hue)),
              shape: BoxShape.circle,
              border: worn ? Border.all(color: t.color('glacier-bg'), width: 2) : null,
              boxShadow: worn ? [BoxShadow(color: t.color('app-ink'), spreadRadius: 2)] : null,
            ),
          ),
        ),
      ),
    );
  }
}
