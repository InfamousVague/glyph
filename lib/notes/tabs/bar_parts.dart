import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'bar_icon.dart';

// The pieces the top bar is made of that are not tabs (notes/NoteTabs.module.css): a ring, a word, a capsule of
// glass, a colour's dot, and the page's own text as the bar sets it.

/// Inter's ascent and descent as parts of its size (hhea: 1984 and 494 of 2048), which is its `line-height: normal`.
const double _ascent = 1984 / 2048, _descent = 494 / 2048;

/// How tall a browser draws a line of the sans face at `line-height: normal`: the ascent and the descent each
/// rounded to a whole pixel, which is what every box around a line of the bar's text is sized by.
double normalLine(double fontSize) => (_ascent * fontSize).roundToDouble() + (_descent * fontSize).roundToDouble();

/// Where a browser puts the baseline of a line of the sans face in a line box [lineHeight] tall (its own
/// `line-height: normal` unless one is given): the rounded ascent under half of whatever the line has over the face,
/// that half taken down to a whole pixel as the browser's layout takes it.
double baselineIn(double fontSize, [double? lineHeight]) {
  final rise = (_ascent * fontSize).roundToDouble();
  final own = rise + (_descent * fontSize).roundToDouble();
  return rise + (((lineHeight ?? own) - own) / 2).floorToDouble();
}

/// One line of the bar's text in a box as tall as a browser makes it ([normalLine]), cut short with an ellipsis where
/// it has no room (`white-space: nowrap; overflow: hidden; text-overflow: ellipsis`).
class BarLine extends StatelessWidget {
  const BarLine(this.text, {super.key, required this.style, this.ellipsis = true});

  final String text;
  final TextStyle style;
  final bool ellipsis;

  @override
  Widget build(BuildContext context) {
    return LineBox(
      height: normalLine(style.fontSize ?? 16),
      baseline: baselineIn(style.fontSize ?? 16),
      child: Text(text, style: style, maxLines: 1, softWrap: false, overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.visible),
    );
  }
}

/// A box as wide as its child and exactly [height] tall, with the child's baseline [baseline] down from its top
/// (or the child in its middle, with none) however tall the child is itself: a line of text in the line box a browser
/// gives it, where the text engine's own box is a fraction off.
class LineBox extends SingleChildRenderObjectWidget {
  const LineBox({super.key, required this.height, this.baseline, required super.child});

  final double height;
  final double? baseline;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLineBox(height, baseline);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) => (renderObject as _RenderLineBox)
    ..line = height
    ..rise = baseline;
}

class _RenderLineBox extends RenderShiftedBox {
  _RenderLineBox(this._line, this._rise) : super(null);

  double _line;
  set line(double value) {
    if (value == _line) return;
    _line = value;
    markNeedsLayout();
  }

  double? _rise;
  set rise(double? value) {
    if (value == _rise) return;
    _rise = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) => _line;

  @override
  double computeMaxIntrinsicHeight(double width) => _line;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inside = child?.getDryLayout(BoxConstraints(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth)) ?? Size.zero;
    return constraints.constrain(Size(inside.width, _line));
  }

  @override
  void performLayout() {
    final inside = child;
    if (inside == null) {
      size = constraints.constrain(Size(0, _line));
      return;
    }
    inside.layout(BoxConstraints(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth), parentUsesSize: true);
    size = constraints.constrain(Size(inside.size.width, _line));
    final rise = _rise;
    final own = rise == null ? null : inside.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true);
    (inside.parentData! as BoxParentData).offset = Offset(0, rise != null && own != null ? rise - own : (size.height - inside.size.height) / 2);
  }
}

/// `color-mix(in oklch, var(--app-ink) N%, transparent)`: the hover wash of a tab and of the + after the last one.
Color inkWash(Tokens t, int percent) => t.colorOf('color-mix(in oklch, var(--app-ink) $percent%, transparent)');

/// The header's glass (app.css `--app-glass-mix`, `--app-glass-blur`): the page's paper at two thirds, over a blur of
/// whatever runs under it.
Color glassTint(Tokens t) => t.colorOf('color-mix(in srgb, var(--glacier-bg) var(--app-glass-mix), transparent)');

/// The colour matrix of CSS's `saturate()`.
List<double> _saturate(double s) => [
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0, //
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0, //
      0, 0, 0, 1, 0,
    ];

/// `backdrop-filter: var(--app-glass-blur)`, which is `blur(18px) saturate(1.1)`: read from the token, so a change to
/// the stylesheet arrives. A CSS blur's length is the Gaussian's deviation itself.
ui.ImageFilter glassFilter(Tokens t) {
  final value = t.raw('app-glass-blur') ?? '';
  final blur = RegExp(r'blur\(([^)]*)\)').firstMatch(value)?.group(1);
  final saturate = RegExp(r'saturate\(([^)]*)\)').firstMatch(value)?.group(1);
  final sigma = blur == null ? 0.0 : t.lenOf(blur);
  final blurred = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp);
  if (saturate == null) return blurred;
  return ui.ImageFilter.compose(outer: ColorFilter.matrix(_saturate(t.lenOf(saturate))), inner: blurred);
}

/// A surface of the header's glass: the blur under a tint, clipped to [radius], with an optional hairline round it
/// and, outside it only, the floating cards' shadow. The filter is laid under the child rather than round it, so
/// what the child draws past its own box is not clipped.
class BarGlass extends StatelessWidget {
  const BarGlass({super.key, this.radius = 0, this.border, this.shadows = const [], this.tint, this.blur = true, required this.child});

  final double radius;

  /// `border: var(--glacier-hairline) solid var(--glacier-border-subtle)`, inside the box.
  final BorderSide? border;

  /// `box-shadow`, its outer layers.
  final List<CssShadow> shadows;

  /// The glass's own tint unless another is given.
  final Color? tint;
  final bool blur;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shape = BorderRadius.circular(radius);
    return CustomPaint(
      painter: shadows.isEmpty ? null : _OuterShadowPainter(shadows, radius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: shape,
              child: blur
                  ? BackdropFilter(filter: glassFilter(t), child: ColoredBox(color: tint ?? glassTint(t)))
                  : ColoredBox(color: tint ?? glassTint(t)),
            ),
          ),
          if (border != null)
            Positioned.fill(
              child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(border: Border.fromBorderSide(border!), borderRadius: shape))),
            ),
          child,
        ],
      ),
    );
  }
}

/// The outer layers of a `box-shadow`, drawn as CSS draws them: only outside the box, so glass does not darken over
/// its own shadow.
class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter(this.shadows, this.radius);
  final List<CssShadow> shadows;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = radius.clamp(0.0, size.shortestSide / 2);
    final box = RRect.fromRectAndRadius(rect, Radius.circular(r));
    var reach = 0.0;
    for (final s in shadows) {
      if (s.inset) continue;
      final far = s.offset.distance + s.blur * 2 + s.spread.abs() + 1;
      if (far > reach) reach = far;
    }
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(reach))
        ..addRRect(box),
    );
    for (final s in shadows.reversed) {
      if (s.inset) continue;
      final paint = Paint()..color = s.color;
      if (s.blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.sigma);
      canvas.drawRRect(box.shift(s.offset).inflate(s.spread), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) => old.radius != radius || old.shadows.length != shadows.length || !identical(old.shadows, shadows);
}

/// `box-shadow: inset 0 0 0 var(--app-line) <color>`: the ring an "on" control wears, inside its own round.
class InsetRing extends StatelessWidget {
  const InsetRing({super.key, required this.on, required this.color, required this.width, required this.radius, required this.child});

  final bool on;
  final Color color;
  final double width;
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(border: Border.all(color: color, width: width), borderRadius: radius),
      child: child,
    );
  }
}

/// `.sidebar` and `.step` (NoteTabs.module.css): one ring of the bar, `--app-bar-ring` across - the sidebar's button,
/// an arrow, the people icon, the bell, the cog, the aside's toggle. Muted until hovered or pressed, when it takes the
/// page's ink on `--app-paper-2`; `on` is a ring round it in its own ink (`[data-on]`); with nothing to do
/// ([onPressed] null) it stays, dead, at 30%, so the row never changes width.
class BarRing extends StatelessWidget {
  const BarRing({
    super.key,
    required this.glyph,
    required this.iconSize,
    required this.label,
    required this.onPressed,
    this.on = false,
    this.expanded,
    this.current = false,
    this.mirrored = false,
    this.dot = false,
    this.anchorKey,
  });

  final BarGlyph glyph;
  final double iconSize;

  /// `aria-label`.
  final String label;
  final VoidCallback? onPressed;

  /// `data-on`: the sidebar showing, Home being the page, something unread.
  final bool on;

  /// `aria-expanded`, where the ring opens something.
  final bool? expanded;

  /// `aria-current="page"`.
  final bool current;
  final bool mirrored;

  /// `.bell[data-unread]::after`: the 6px gold dot at the bell's shoulder, ringed in the page's paper.
  final bool dot;

  /// A key on the ring's own box, for a menu to hang from.
  final Key? anchorKey;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-bar-ring');
    final radius = BorderRadius.circular(t.radius('md'));
    final ink = t.color('glacier-text'), muted = t.color('glacier-text-muted');
    return Semantics(
      expanded: expanded,
      selected: current ? true : null,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) {
          final lit = (state.hovered || state.pressed) && !state.disabled;
          final color = lit || on ? ink : muted;
          Widget face = SizedBox(
            key: anchorKey,
            width: ring,
            height: ring,
            child: InsetRing(
              on: on,
              color: ink,
              width: t.len('app-line'),
              radius: radius,
              child: DecoratedBox(
                decoration: BoxDecoration(color: lit ? t.color('app-paper-2') : null, borderRadius: radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(child: BarIcon(glyph, size: iconSize, color: color, mirrored: mirrored)),
                    if (dot)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GlacierScope(
                          classes: const {'app-gold'},
                          child: Builder(
                            builder: (context) {
                              final gold = context.tokens;
                              return Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: gold.colorOf('var(--app-gold, var(--glacier-text))'),
                                  shape: BoxShape.circle,
                                  // `box-shadow: 0 0 0 2px var(--glacier-bg)`
                                  boxShadow: [BoxShadow(color: gold.color('glacier-bg'), spreadRadius: 2)],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
          // `.step:disabled { opacity: 0.3 }`
          if (state.disabled) face = Opacity(opacity: 0.3, child: face);
          return GlacierFocusRing(visible: state.focused, radius: t.radius('md'), child: face);
        },
      ),
    );
  }
}

/// `.app-word` with `.top .word` (app.css, NoteTabs.module.css): one of the Masthead's controls as a word - Home,
/// Notes, Back, Forward, Teams - a bar ring's height, so the row is the height it always is.
class BarWord extends StatelessWidget {
  const BarWord({super.key, required this.word, required this.onPressed, this.label, this.on = false, this.expanded, this.current = false, this.leading, this.trailing, this.anchorKey});

  final String word;
  final VoidCallback? onPressed;

  /// `aria-label`, where the word alone would not say it.
  final String? label;
  final bool on;
  final bool? expanded;
  final bool current;

  /// A glyph before or after the word: Back's arrow, Forward's.
  final BarGlyph? leading;
  final BarGlyph? trailing;
  final Key? anchorKey;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(t.radius('md'));
    return Semantics(
      expanded: expanded,
      selected: current ? true : null,
      child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: label ?? word,
        builder: (context, state) {
          final lit = state.hovered && !state.disabled;
          final color = state.disabled
              ? t.color('glacier-text-subtle')
              : lit || state.pressed || on
                  ? t.color('glacier-text')
                  : t.color('glacier-text-muted');
          final style = t.textAt(t.fontSize('md'), weight: 'medium', color: color);
          return GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('md'),
            child: Container(
              key: anchorKey,
              constraints: BoxConstraints(minHeight: t.len('app-bar-ring')),
              padding: EdgeInsets.symmetric(horizontal: t.space(2)),
              decoration: BoxDecoration(color: lit ? t.color('app-paper-2') : null, borderRadius: radius),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: t.space(1),
                children: [
                  if (leading != null) BarIcon(leading!, size: 16, color: color),
                  ExcludeSemantics(child: BarLine(word, style: style, ellipsis: false)),
                  if (trailing != null) BarIcon(trailing!, size: 16, color: color),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `.capsule` (NoteTabs.module.css): one of the Islands' capsules of glass, a ring's height with its padding and
/// hairline, the glass and the shadow the app's floating cards wear.
class BarCapsule extends StatelessWidget {
  const BarCapsule({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hairline = t.len('glacier-hairline');
    return BarGlass(
      radius: t.radius('full'),
      border: BorderSide(color: t.color('glacier-border-subtle'), width: hairline),
      shadows: t.cssShadows('app-float-shadow'),
      child: Padding(
        padding: EdgeInsets.all(3 + hairline),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: children),
      ),
    );
  }
}

/// `.hueDot` (NoteTabs.module.css): a colour in a menu, the dot beside its name, 0.7em of the row's type.
class HueDot extends StatelessWidget {
  const HueDot(this.hue, {super.key});

  /// One of the workspace hues; null is ink.
  final String? hue;

  @override
  Widget build(BuildContext context) {
    final em = DefaultTextStyle.of(context).style.fontSize ?? 16;
    return GlacierScope(
      attrs: {'hue': hue ?? 'ink'},
      child: Builder(
        builder: (context) => Container(
          width: 0.7 * em,
          height: 0.7 * em,
          decoration: BoxDecoration(color: context.tokens.colorOf('var(--app-space, var(--app-ink-3))'), shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// `.top` (NoteTabs.module.css): the bar's line of controls - what comes before the slot, the slot pushed to the far
/// end (`margin-inline-start: auto`), and what comes after it, a gap between each two. Nothing on the line gives:
/// where the controls come to more than the line, the slot has no room and the last of them run past the line's end,
/// as they do on the page (the Masthead's words on a narrow phone), rather than being squeezed.
///
/// The line's box runs [endInset] past its own end, to the window's edge, so a control that has run over is still
/// under the finger.
class ToolRow extends MultiChildRenderObjectWidget {
  ToolRow({super.key, required this.gap, this.endInset = 0, required List<Widget> before, required Widget slot, required List<Widget> after})
      : slotAt = before.length,
        super(children: [...before, slot, ...after]);

  final double gap;
  final double endInset;

  /// Which child is the slot.
  final int slotAt;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderToolRow(gap, endInset, slotAt);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) => (renderObject as _RenderToolRow)
    ..gap = gap
    ..endInset = endInset
    ..slotAt = slotAt;
}

class _ToolRowData extends ContainerBoxParentData<RenderBox> {}

class _RenderToolRow extends RenderBox with ContainerRenderObjectMixin<RenderBox, _ToolRowData>, RenderBoxContainerDefaultsMixin<RenderBox, _ToolRowData> {
  _RenderToolRow(this._gap, this._endInset, this._slotAt);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double _endInset;
  set endInset(double value) {
    if (value == _endInset) return;
    _endInset = value;
    markNeedsLayout();
  }

  int _slotAt;
  set slotAt(int value) {
    if (value == _slotAt) return;
    _slotAt = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ToolRowData) child.parentData = _ToolRowData();
  }

  @override
  void performLayout() {
    final line = constraints.maxWidth - _endInset;
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    RenderBox? slot;
    var fixed = 0.0, tallest = 0.0, n = 0;
    for (var child = firstChild, i = 0; child != null; child = childAfter(child), i++) {
      n += 1;
      if (i == _slotAt) {
        slot = child;
        continue;
      }
      child.layout(loose, parentUsesSize: true);
      fixed += child.size.width;
      tallest = math.max(tallest, child.size.height);
    }
    fixed += n > 1 ? (n - 1) * _gap : 0;
    final room = math.max(0.0, line - fixed);
    if (slot != null) {
      slot.layout(BoxConstraints(maxWidth: room, maxHeight: constraints.maxHeight), parentUsesSize: true);
      tallest = math.max(tallest, slot.size.height);
    }
    size = constraints.constrain(Size(constraints.maxWidth, tallest));
    var x = 0.0;
    for (var child = firstChild, i = 0; child != null; child = childAfter(child), i++) {
      final data = child.parentData! as _ToolRowData;
      // The slot's own room is whatever the rest leaves, and it sits at the end of it.
      final lead = i == _slotAt ? room - child.size.width : 0.0;
      data.offset = Offset(x + lead, (size.height - child.size.height) / 2);
      x += lead + child.size.width + _gap;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}
