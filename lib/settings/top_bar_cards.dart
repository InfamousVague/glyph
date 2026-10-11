import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../shell/top_bar.dart' show TopBarStyle;
import 'choice_card.dart';
import 'layout_cards.dart' show ChoiceCardMeta, MiniInk, ScenePreview;

/// Port of `TopBarCards` (src/app/settings/TopBarCards.tsx, TopBarCards.module.css): the top bar's four ways as
/// cards, each a picture of the bar laid out that way over a few lines of a note, drawn in the page's own ink: rings
/// as rings, tabs as tabs or capsules, the Masthead's words as short bars, the Islands' capsules floating. The same
/// radio cards as the themes: the chosen one ringed and ticked, the arrow keys moving between them.
///
/// Nothing differs from the web original but where the styles' names come from, lib/shell/top_bar.dart.
class TopBarCards extends StatelessWidget {
  const TopBarCards({super.key, required this.value, required this.onValueChange});

  /// A style's id as the preferences keep it: `classic`, `ledger`, `masthead`, `islands`.
  final String value;
  final ValueChanged<String> onValueChange;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final byId = {for (final style in TopBarStyle.values) style.id: style};
    return ChoiceCards<String>(
      label: 'Top bar',
      values: byId.keys.toList(),
      value: value,
      onValueChange: onValueChange,
      nameOf: (id) => byId[id]!.label,
      radius: t.radius('lg'),
      layout: (context, cards) => ChoiceGrid(columns: 2, gap: t.space(3), children: cards),
      card: (context, id, selected) => ChoiceCardBody(
        picture: ScenePreview(child: _BarScene(style: byId[id]!)),
        words: ChoiceCardMeta(label: byId[id]!.label, hint: byId[id]!.hint, selected: selected),
      ),
    );
  }
}

enum _TabShape { tab, capsule, indexLine }

/// The bar laid out one way, small (`Scene`, TopBarCards.tsx). Every shape is sized in rem, so the scene scales with
/// the interface.
class _BarScene extends StatelessWidget {
  const _BarScene({required this.style});
  final TopBarStyle style;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    double rem(double n) => t.lenOf('${n}rem');
    final mini = MiniInk(t, line: 22, ground: 7);
    final paper = t.color('glacier-bg');
    final pad = rem(0.5);

    Widget ring() => Container(width: rem(0.62), height: rem(0.62), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: mini.muted)));
    List<Widget> rings(int n) => [
          for (var i = 0; i < n; i++) ...[if (i > 0) SizedBox(width: rem(0.22)), ring()],
        ];

    /// `.tab` on a line: outlined on three sides and opening into the row beneath when it is the open one or the
    /// house; a patch of ground when it is not.
    Widget lineTab({required bool open, double width = 1.4}) {
      final radius = Radius.circular(rem(0.22));
      final box = Container(
        width: rem(width),
        height: rem(0.56),
        decoration: BoxDecoration(
          color: open ? paper : mini.ground,
          borderRadius: BorderRadius.vertical(top: radius),
        ),
        foregroundDecoration: open ? _OpenTabOutline(mini.line, radius) : null,
      );
      // `position: relative; top: 1px`: it stands on the row's line, covering it.
      return open ? Transform.translate(offset: const Offset(0, 1), child: box) : box;
    }

    Widget tabs(_TabShape shape) => switch (shape) {
          _TabShape.tab => Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [lineTab(open: true), SizedBox(width: rem(0.14)), lineTab(open: false), SizedBox(width: rem(0.14)), lineTab(open: false)],
            ),
          // A capsule, the open one the inverse.
          _TabShape.capsule => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) SizedBox(width: rem(0.14)),
                  Container(width: rem(1.4), height: rem(0.5), decoration: ShapeDecoration(color: i == 0 ? mini.ink : mini.ground, shape: const StadiumBorder())),
                ],
              ],
            ),
          // The index: words on the rule, the open one underlined.
          _TabShape.indexLine => Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) SizedBox(width: rem(0.4)),
                  Padding(
                    padding: EdgeInsets.only(bottom: rem(0.18)),
                    child: Container(
                      width: rem(1.4),
                      height: rem(0.3),
                      decoration: ShapeDecoration(
                        color: i == 0 ? mini.ink : mini.muted,
                        shape: const StadiumBorder(),
                        // `box-shadow: 0 0.18rem 0 0 var(--mini-ink)`
                        shadows: i == 0 ? [BoxShadow(color: mini.ink, offset: Offset(0, rem(0.18)))] : null,
                      ),
                    ),
                  ),
                ],
              ],
            ),
        };

    /// `.row`: a line of the bar, its things standing on its foot, at least a ring high.
    Widget row(List<Widget> children, {bool ruled = false}) => Container(
          constraints: BoxConstraints(minHeight: rem(0.62) + (ruled ? 1 : 0)),
          // A row of tabs stands on a line; the Masthead's index on a rule.
          decoration: ruled ? BoxDecoration(border: Border(bottom: BorderSide(color: mini.line))) : null,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: children),
        );

    Widget word({bool short = false}) => Padding(
          padding: EdgeInsets.only(bottom: rem(0.16)),
          child: Container(width: rem(short ? 0.9 : 1.3), height: rem(0.3), decoration: ShapeDecoration(color: mini.muted, shape: const StadiumBorder())),
        );

    /// `.capsule`: a floating island of the bar.
    Widget capsule(List<Widget> children, {bool wide = false}) => Container(
          padding: EdgeInsets.symmetric(vertical: rem(0.14), horizontal: rem(wide ? 0.3 : 0.14)),
          decoration: ShapeDecoration(
            color: paper,
            shape: StadiumBorder(side: BorderSide(color: mini.line, strokeAlign: BorderSide.strokeAlignInside)),
            shadows: t.shadowOf('0 2px 6px rgb(0 0 0 / 18%)'),
          ),
          child: Row(mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min, children: children),
        );

    Widget bar(double fraction, double height, Color color, {double opacity = 1}) => FractionallySizedBox(
          widthFactor: fraction,
          alignment: AlignmentDirectional.centerStart,
          child: Opacity(opacity: opacity, child: Container(height: height, decoration: ShapeDecoration(color: color, shape: const StadiumBorder()))),
        );
    Widget lines({double top = 0.2}) => Padding(
          padding: EdgeInsets.only(top: rem(top)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [bar(0.44, rem(0.36), mini.ink), SizedBox(height: rem(0.3)), bar(0.88, rem(0.24), mini.muted, opacity: 0.6), SizedBox(height: rem(0.3)), bar(0.60, rem(0.24), mini.muted, opacity: 0.6)],
          ),
        );

    final gap = SizedBox(height: rem(0.3));
    const spring = Spacer();
    final List<Widget> children;
    switch (style) {
      case TopBarStyle.ledger:
        children = [
          row([lineTab(open: true, width: 0.7), SizedBox(width: rem(0.22)), tabs(_TabShape.tab)], ruled: true),
          gap,
          // The Ledger's tool row: paper with a line under it, the bar's whole width.
          _Bleed(
            by: pad,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: rem(0.14), horizontal: pad),
              constraints: BoxConstraints(minHeight: rem(0.62)),
              decoration: BoxDecoration(color: paper, border: Border(bottom: BorderSide(color: mini.line))),
              child: Row(children: [...rings(3), spring, ...rings(3)]),
            ),
          ),
          gap,
          lines(),
        ];
      case TopBarStyle.masthead:
        children = [
          row([word(), SizedBox(width: rem(0.22)), word(short: true), spring, ...rings(2)]),
          gap,
          row([tabs(_TabShape.indexLine)], ruled: true),
          gap,
          lines(),
        ];
      case TopBarStyle.islands:
        // The Islands: the page's lines run up under the capsules.
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, rem(0.45), pad, 0),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The two rows' room, less the `-0.9rem` the lines are drawn up by, then their `1.1rem` of padding.
                  Opacity(opacity: 0, child: Column(mainAxisSize: MainAxisSize.min, children: [_islandRows(row, capsule, rings, tabs, rem, gap)])),
                  gap,
                  Transform.translate(offset: Offset(0, -rem(0.9)), child: lines(top: 1.1)),
                ],
              ),
              _islandRows(row, capsule, rings, tabs, rem, gap),
            ],
          ),
        );
      case TopBarStyle.classic:
        children = [
          row([...rings(4), spring, ...rings(3)]),
          gap,
          row([tabs(_TabShape.tab)], ruled: true),
          gap,
          lines(),
        ];
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, rem(0.45), pad, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  static Widget _islandRows(
    Widget Function(List<Widget>, {bool ruled}) row,
    Widget Function(List<Widget>, {bool wide}) capsule,
    List<Widget> Function(int) rings,
    Widget Function(_TabShape) tabs,
    double Function(double) rem,
    Widget gap,
  ) {
    List<Widget> spaced(int n) {
      final all = rings(n);
      // Rings in a capsule are `0.16rem` apart, where a row's are `0.22rem`.
      return [for (final each in all) each is SizedBox ? SizedBox(width: rem(0.16)) : each];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row([capsule(spaced(3)), const Spacer(), capsule(spaced(2))]),
        gap,
        row([Expanded(child: capsule([tabs(_TabShape.capsule)], wide: true))]),
      ],
    );
  }
}

/// `margin-inline: -<by>`: its child drawn that much wider on each side than the room it is given.
class _Bleed extends StatelessWidget {
  const _Bleed({required this.by, required this.child});
  final double by;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: box.maxWidth,
          child: OverflowBox(
            minWidth: box.maxWidth + by * 2,
            maxWidth: box.maxWidth + by * 2,
            fit: OverflowBoxFit.deferToChild,
            child: child,
          ),
        ),
      );
}

/// `border: 1px solid; border-block-end: 0` on a tab with rounded shoulders: a line up one side, over the top and
/// down the other.
class _OpenTabOutline extends Decoration {
  const _OpenTabOutline(this.color, this.radius);
  final Color color;
  final Radius radius;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _OpenTabOutlinePainter(color, radius);
}

class _OpenTabOutlinePainter extends BoxPainter {
  _OpenTabOutlinePainter(this.color, this.radius);
  final Color color;
  final Radius radius;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = (offset & configuration.size!).deflate(0.5);
    final r = radius.x - 0.5;
    final path = Path()
      ..moveTo(rect.left, rect.bottom + 0.5)
      ..lineTo(rect.left, rect.top + r)
      ..arcToPoint(Offset(rect.left + r, rect.top), radius: Radius.circular(r))
      ..lineTo(rect.right - r, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + r), radius: Radius.circular(r))
      ..lineTo(rect.right, rect.bottom + 0.5);
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color);
  }
}
