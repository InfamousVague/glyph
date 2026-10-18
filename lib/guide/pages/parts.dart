/// The pieces more than one guide page is built of. A port of `src/app/guide/pages/parts.tsx` (`Choice`) with the
/// rules of `Guide.module.css` the pages share: `.title`, `.lead`, `.stepTitle`, `.note`, `.choices`, `.choice`,
/// `.choiceText` and `.swatch`.
///
/// What differs: a row's swatch is a widget the page builds ([GuideSwatch] is `.swatch` itself, which a page fills
/// and colours), where the stylesheet coloured it by `data-swatch` or a second class.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../home/home_parts.dart' show CssLines;

/// `.title`: a page's headline.
TextStyle guideTitleStyle(Tokens t) {
  final px = t.fontSize('4xl');
  return t.textAt(px, weight: 'bold', height: 1.02, tracking: t.len('app-tracking-display', em: px));
}

/// `.lead`: the paragraph under it.
TextStyle guideLeadStyle(Tokens t) => t.textAt(t.fontSize('lg'), height: 1.45, color: t.color('glacier-text-muted'));

/// [child], a block of text in [style], with each line as tall as the stylesheet's `line-height` makes it, where
/// Flutter rounds a line to a whole pixel (lib/home/home_parts.dart [CssLines]).
///
/// A paragraph of plain text also has each line where the page has it (the kit's [ExactLines]: the lead's six lines
/// ended 2.7 device pixels above the page's); a headline that comes out of smoke is its own drawing, and keeps the
/// box alone.
Widget guideLines(TextStyle style, Widget child) {
  final line = style.fontSize! * style.height!;
  return child is Text ? ExactLines(lineHeight: line, child: child) : CssLines(lineHeight: line, child: child);
}

/// `max-inline-size: <n>ch`: [count] times the width of a nought in [style].
double chWidth(TextStyle style, double count) {
  final nought = TextPainter(text: TextSpan(text: '0', style: style), textDirection: TextDirection.ltr)..layout();
  final width = nought.width;
  nought.dispose();
  return width * count;
}

/// A page's headline, as `<h1 class="title">` sets it: no wider than fourteen noughts.
class GuideTitle extends StatelessWidget {
  const GuideTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = guideTitleStyle(context.tokens);
    return Semantics(header: true, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: chWidth(style, 14)), child: guideLines(style, Text(text, style: style))));
  }
}

/// The paragraph under the headline (`<p class="lead">`): a `--glacier-space-5` under it, no wider than thirty-two
/// noughts.
class GuideLead extends StatelessWidget {
  const GuideLead(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = guideLeadStyle(t);
    return Padding(
      padding: EdgeInsets.only(top: t.space(5)),
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: chWidth(style, 32)), child: guideLines(style, Text(text, style: style))),
    );
  }
}

/// `.app-word` (app.css) with a size of its page's own: a button that is only its word, muted until pressed, and
/// `--glacier-space-12` tall. [bleed] is `padding-inline` with the same pulled back by a negative margin, which the
/// caller's own padding gives back; [color] is a colour of the rule's own in place of the muted one.
class GuideWord extends StatelessWidget {
  const GuideWord(this.text, {super.key, required this.onPressed, required this.style, this.color, this.bleed});

  final String text;
  final VoidCallback? onPressed;
  final TextStyle style;
  final Color? color;

  /// `--glacier-space-2` when null.
  final double? bleed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      builder: (context, state) {
        final ink = state.disabled
            ? t.color('glacier-text-subtle')
            : state.pressed
            ? t.color('glacier-text')
            : (color ?? t.color('glacier-text-muted'));
        return GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('sm'),
          child: Container(
            constraints: BoxConstraints(minHeight: t.space(12)),
            padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: bleed ?? t.space(2)),
            child: Align(alignment: Alignment.center, widthFactor: 1, heightFactor: 1, child: Text(text, style: style.copyWith(color: ink), maxLines: 1, softWrap: false)),
          ),
        );
      },
    );
  }
}

/// `.choices`: a page's radiogroup, its rows a `--glacier-space-1` apart.
class GuideChoices extends StatelessWidget {
  const GuideChoices({super.key, required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(top: t.space(6)),
      child: Semantics(
        container: true,
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, child) in children.indexed) ...[if (index > 0) SizedBox(height: t.space(1)), child],
          ],
        ),
      ),
    );
  }
}

/// `.swatch`: what a row shows of its choice, 3.5rem square. The colours are the caller's: literal ones for a theme,
/// because each has to look like its theme whichever theme is on screen around it.
class GuideSwatch extends StatelessWidget {
  const GuideSwatch({super.key, required this.text, required this.style, this.color, this.gradient, required this.border, this.child});
  final String text;
  final TextStyle style;
  final Color? color;
  final Gradient? gradient;
  final Color border;

  /// Drawn in place of [text] where the choice is not a look but a size (the mode page's icons).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = t.lenOf('3.5rem');
    return ExcludeSemantics(
      child: Container(
        width: side,
        height: side,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, gradient: gradient, borderRadius: BorderRadius.circular(t.radius('lg')), border: Border.all(color: border, width: 2)),
        child: child ?? Text(text, style: style, maxLines: 1, softWrap: false),
      ),
    );
  }
}

/// `.swatch`'s own type: the choice drawn, "Aa" in its colours.
TextStyle guideSwatchStyle(Tokens t, Color color) {
  final px = t.fontSize('xl');
  return t.textAt(px, weight: 'bold', tracking: t.len('app-tracking-title', em: px), color: color);
}

/// One radio of a page's radiogroup (`Choice`). The chosen row is printed in reverse (`app-inverse`); a tap is the
/// choice, with nothing to confirm.
class GuideChoice extends StatelessWidget {
  const GuideChoice({super.key, required this.label, required this.hint, required this.on, required this.onPick, required this.swatch});

  final String label;

  /// The line under the label.
  final String hint;

  /// Whether this is the choice made.
  final bool on;
  final VoidCallback onPick;

  /// What the swatch shows, built under the row's own tokens: the reversed ones when it is chosen.
  final WidgetBuilder swatch;

  @override
  Widget build(BuildContext context) {
    final outer = context.tokens;
    final gap = outer.space(3);
    return GlacierPressable(
      onPressed: onPick,
      button: false,
      excludeSemantics: true,
      builder: (context, state) => Semantics(
        inMutuallyExclusiveGroup: true,
        checked: on,
        button: true,
        label: '$label. $hint',
        onTap: onPick,
        // The band reaches a `--glacier-space-3` past the words at each end, which stay in line with the page.
        child: _Bleed(
          by: gap,
          child: GlacierScope(
            classes: on ? const {'app-inverse'} : const {},
            child: Builder(
              builder: (context) {
                final t = context.tokens;
                final titlePx = t.fontSize('xl');
                final title = t.textAt(titlePx, weight: 'semibold', height: 1.25, tracking: t.len('app-tracking-title', em: titlePx));
                final note = t.textAt(t.fontSize('md'), height: t.len('glacier-leading-md'), color: t.color('glacier-text-muted'));
                final row = Row(
                  children: [
                    swatch(context),
                    SizedBox(width: t.space(4)),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          guideLines(title, Text(label, style: title)),
                          SizedBox(height: t.space(2)),
                          guideLines(note, Text(hint, style: note)),
                        ],
                      ),
                    ),
                  ],
                );
                return GlacierFocusRing(
                  visible: state.focused,
                  radius: t.radius('xl'),
                  child: AnimatedContainer(
                    duration: t.reducedMotion ? Duration.zero : t.duration('glacier-duration-fast'),
                    curve: t.curve('glacier-ease-out'),
                    padding: EdgeInsets.all(gap),
                    decoration: BoxDecoration(color: on ? t.color('glacier-bg') : t.color('glacier-bg').withValues(alpha: 0), borderRadius: BorderRadius.circular(t.radius('xl'))),
                    child: row,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// `inline-size: calc(100% + 2 * by); margin-inline: calc(-1 * by)`: the child is laid out [by] wider than its place
/// at each side, and takes the taps there too.
class _Bleed extends SingleChildRenderObjectWidget {
  const _Bleed({required this.by, required Widget super.child});
  final double by;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBleed(by);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) => (renderObject as _RenderBleed).by = by;
}

class _RenderBleed extends RenderShiftedBox {
  _RenderBleed(this._by) : super(null);

  double _by;
  set by(double value) {
    if (value == _by) return;
    _by = value;
    markNeedsLayout();
  }

  BoxConstraints _inner(BoxConstraints constraints) => BoxConstraints.tightFor(width: constraints.maxWidth + 2 * _by);

  @override
  Size computeDryLayout(BoxConstraints constraints) => Size(constraints.maxWidth, child?.getDryLayout(_inner(constraints)).height ?? 0);

  @override
  void performLayout() {
    final inner = child;
    if (inner == null) {
      size = constraints.smallest;
      return;
    }
    inner.layout(_inner(constraints), parentUsesSize: true);
    (inner.parentData! as BoxParentData).offset = Offset(-_by, 0);
    size = Size(constraints.maxWidth, inner.size.height);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => hitTestChildren(result, position: position);
}
