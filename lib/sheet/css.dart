/// Small things a stylesheet does that neither Flutter nor the kit does by itself, shared by the sheet, its kit and
/// the sidebar's surfaces: a line of text as tall as a browser makes it, a border as thick as a browser draws it, the
/// sigma of a `blur()`, and the one way these surfaces draw an icon. Worked round here rather than in the kit
/// (packages/glacier), which is another hand's; each is a candidate for it.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';

export '../art/app_icon.dart' show LucideIcon;
export '../art/lucide.g.dart' show Lucide;

/// What each [Tokens] has been asked for, so a line is measured once per face, size and weight for as long as those
/// tokens stand (a window that changes width makes new ones).
final Expando<Map<Object, double>> _lines = Expando('normal line heights');

/// `line-height: normal` for text at [px], as a multiple of [px], the way Chromium works it out: the face's ascent
/// and its descent, each rounded to a whole pixel, and added. Flutter's text engine rounds their sum instead, which
/// is the same line most of the time and a pixel shorter or taller where the two halves round apart; over a list of
/// rows that is pixels of drift.
///
/// Measured on the page (Chromium on a Mac, 2026-10-07): 10.02px is 12, 11.13 is 14, 12.06 is 15, 13.39 is 16, 16.12
/// is 20, 19.39 is 24. Chromium on Android may round a descent up where this rounds it down; that was not measured.
double normalLine(Tokens t, double px, {String weight = 'regular', bool mono = false}) {
  final held = _lines[t] ??= {};
  return held[(px, weight, mono)] ??= () {
    final painter = TextPainter(text: TextSpan(text: 'x', style: t.textAt(px, weight: weight, mono: mono)), textDirection: TextDirection.ltr)..layout();
    final line = painter.computeLineMetrics().first;
    final rounded = line.ascent.roundToDouble() + line.descent.roundToDouble();
    painter.dispose();
    return rounded / px;
  }();
}

/// The page's own text at [px]: the kit's [Tokens.textAt], with `line-height: normal` as the page's engine rounds it
/// ([normalLine]) where no [height] is given. [height] is a unitless line-height, [tracking] a letter-spacing in px.
TextStyle pageText(Tokens t, double px, {String weight = 'regular', Color? color, double? height, double tracking = 0, bool mono = false}) =>
    t.textAt(px, weight: weight, mono: mono, color: color, height: height ?? normalLine(t, px, weight: weight, mono: mono), tracking: tracking);

/// A border's width as a browser draws it (CSS Backgrounds, "snap a length as a border width"): a whole number of
/// device pixels, rounded down, and never less than one. `--app-line` is 1.5px, which is three device pixels at 2
/// and four (1.33px) at 3.
double snapBorder(BuildContext context, double px) {
  if (px <= 0) return 0;
  final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
  final device = px * ratio;
  if ((device - device.roundToDouble()).abs() < 1e-6) return px;
  return device < 1 ? 1 / ratio : device.floorToDouble() / ratio;
}

final RegExp _blur = RegExp(r'blur\(\s*([\d.]+)px\s*\)');

/// The sigma of a `backdrop-filter: blur(Npx)` token such as `--app-float-blur`: CSS's `blur(N)` takes the
/// Gaussian's standard deviation itself. Zero where the token is not a blur.
double blurSigma(Tokens t, String name) {
  final found = _blur.firstMatch(t.raw(name) ?? '');
  return found == null ? 0 : double.parse(found.group(1)!);
}

/// One of the kit's Lucide marks at [size] pixels, in [color]: the one way the sheet and the sidebar draw an icon.
/// `<Search size={17} strokeWidth={2.1} />` is `lucide(Lucide.search, size: 17, strokeWidth: 2.1, color: …)`: the
/// stroke is the JSX's at that place, Lucide's own 2 where it says none, and the icon wears the page's wash inside
/// its body ([AppIcon]).
Widget lucide(LucideIcon icon, {required double size, required Color color, double strokeWidth = 2}) => AppIcon(icon, size: size, strokeWidth: strokeWidth, color: color);

/// Text whose lines are as tall as its stylesheet says, to the fraction: `line-height: 1.3` at 12.78px is 16.61px a
/// line on the page, and two of them are 33.22. Flutter's text engine makes every line a whole number of pixels
/// (17, and 34), so a row of such text is taller here than there, and a list of rows drifts.
///
/// [child] is a [Text] in one style whose `height` times its size is [line]; this takes the room the page gives it,
/// [line] for each line the text came to, and sets the text in the middle of that. A line is still drawn where the
/// engine put it, a fraction of a pixel from the page's.
///
/// On a phone the first line stands on the page's own baseline ([pageBaseline]) where the middle is not it: the
/// engine sets words in a line by the face's exact ascent and half the leading to the fraction, a phone's page by
/// whole device pixels with the leading floored, and a notebook's page title stood three device pixels under the
/// page's beside the Tauri app (17.66px on a line of 26.49: 52.3 device pixels under the line's top against 50).
class CssLines extends SingleChildRenderObjectWidget {
  const CssLines({super.key, required this.line, required Widget super.child});

  /// The line's height in logical pixels: the font size times the rule's `line-height`.
  final double line;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderCssLines(line, pageBaseline(context, child, line));

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) => (renderObject as _RenderCssLines)
    ..line = line
    ..baseline = pageBaseline(context, child, line);
}

/// Where a phone's page has the first baseline of [text] under the top of its line, [line] tall
/// ([leadedBaseline]: the face's ascent and descent in whole device pixels, half the leading floored). Nothing at a
/// ratio of 1, a desktop's and the one the tests' rectangles were measured at, where the engine's own place is
/// within a tenth of a pixel of the page's; and nothing where [text] is not one [Text] in a style of its own.
double? pageBaseline(BuildContext context, Widget? text, double line) {
  if (text is! Text || text.textSpan != null) return null;
  final style = text.style;
  if (style == null || style.fontSize == null || line <= 0) return null;
  final dpr = context.tokens.css.lineDpr;
  return dpr == 1 ? null : leadedBaseline(style, line, dpr: dpr);
}

class _RenderCssLines extends RenderShiftedBox {
  _RenderCssLines(this._line, this._baseline) : super(null);

  double _line;
  set line(double value) {
    if (value == _line) return;
    _line = value;
    markNeedsLayout();
  }

  /// Where the first line's baseline goes under the box's top, or null for the middle.
  double? _baseline;
  set baseline(double? value) {
    if (value == _baseline) return;
    _baseline = value;
    markNeedsLayout();
  }

  /// What the page makes of [drawn], the height the engine gave the text: as many lines, each [_line] tall.
  double _page(double drawn) {
    final each = _line.roundToDouble();
    return each <= 0 ? drawn : (drawn / each).round() * _line;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _page(super.computeMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) => _page(super.computeMaxIntrinsicHeight(width));

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final inner = child?.getDryLayout(constraints.copyWith(minHeight: 0, maxHeight: double.infinity)) ?? Size.zero;
    return constraints.constrain(Size(inner.width, _page(inner.height)));
  }

  @override
  void performLayout() {
    final inner = child;
    if (inner == null) {
      size = constraints.smallest;
      return;
    }
    inner.layout(constraints.copyWith(minHeight: 0, maxHeight: double.infinity), parentUsesSize: true);
    final height = _page(inner.size.height);
    size = constraints.constrain(Size(inner.size.width, height));
    var dy = (size.height - inner.size.height) / 2;
    final wanted = _baseline;
    if (wanted != null) {
      final drawn = inner.getDistanceToBaseline(TextBaseline.alphabetic, onlyReal: true);
      if (drawn != null) dy = wanted - drawn;
    }
    (inner.parentData! as BoxParentData).offset = Offset(0, dy);
  }
}

/// [text] in [style], its lines as tall as the style's own `height` says to the fraction ([CssLines]).
Widget cssLines(String text, TextStyle style, {int? maxLines, bool softWrap = true, TextOverflow? overflow, TextAlign? textAlign}) => CssLines(
      line: style.fontSize! * (style.height ?? 1),
      child: Text(text, style: style, maxLines: maxLines, softWrap: softWrap, overflow: overflow, textAlign: textAlign),
    );
