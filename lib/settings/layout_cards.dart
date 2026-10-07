import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../home/home_layout.dart' show HomeLayout, homeLayouts;
import 'choice_card.dart';
import 'kit/settings_icons.dart';
import 'kit/settings_type.dart';

/// The words under a picture on the home page and top bar cards (`.meta` of LayoutCards.module.css and
/// TopBarCards.module.css, which are the same rules): a name, a sentence, and the tick at the row's end.
///
/// The tick is `color: var(--glacier-accent-text, var(--glacier-bg))` on the accent's own fill, as the page has it:
/// under the app's ink that is ink on ink, so a chosen card's ring is a filled dot.
class ChoiceCardMeta extends StatelessWidget {
  const ChoiceCardMeta({super.key, required this.label, required this.hint, required this.selected});

  final String label;
  final String hint;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(3)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: pageText(t, t.fontSize('sm'), weight: 'semibold')),
                const SizedBox(height: 1),
                Text(hint, style: pageText(t, t.fontSize('xs'), height: 1.35, color: t.color('glacier-text-muted'))),
              ],
            ),
          ),
          SizedBox(width: t.space(2)),
          ChoiceTick(
            selected: selected,
            size: t.lenOf('1.1rem'),
            border: t.color('glacier-border-subtle'),
            borderWidth: 1,
            tick: t.colorOf('var(--glacier-accent-text, var(--glacier-bg))'),
            child: const SettingsIcon(SettingsGlyph.check, size: 12, strokeWidth: 2.5),
          ),
        ],
      ),
    );
  }
}

/// The ink a small scene is drawn in (`--mini-ink`, `--mini-muted`, `--mini-line`, `--mini-ground` of the two card
/// stylesheets): the page's own ink, and three strengths of it over nothing.
class MiniInk {
  MiniInk(Tokens t, {required int line, required int ground})
      : ink = t.color('app-ink'),
        muted = t.colorOf('color-mix(in oklch, var(--app-ink) 45%, transparent)'),
        line = t.colorOf('color-mix(in oklch, var(--app-ink) $line%, transparent)'),
        ground = t.colorOf('color-mix(in oklch, var(--app-ink) $ground%, transparent)');

  final Color ink;
  final Color muted;
  final Color line;
  final Color ground;
}

/// Port of `LayoutCards` (src/app/settings/LayoutCards.tsx, LayoutCards.module.css): the home page's four layouts as
/// cards, each a picture of the page laid out that way in the page's own ink: the search at the top, then
/// Spotlight's pinned line, cards and rows; Cards' grid; the Timeline's dated groups of rows; the List's lines. The
/// same radio cards as the themes: the chosen one ringed and ticked, the arrow keys moving between them.
///
/// Nothing differs from the web original but where the layouts' names come from, lib/home/home_layout.dart.
class LayoutCards extends StatelessWidget {
  const LayoutCards({super.key, required this.value, required this.onValueChange});

  /// A layout's id as the preferences keep it: `spotlight`, `cards`, `timeline`, `list`.
  final String value;
  final ValueChanged<String> onValueChange;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final byId = {for (final layout in homeLayouts) layout.id.name: layout};
    return ChoiceCards<String>(
      label: 'Home page layout',
      values: byId.keys.toList(),
      value: value,
      onValueChange: onValueChange,
      nameOf: (id) => byId[id]!.label,
      radius: t.radius('lg'),
      layout: (context, cards) => ChoiceGrid(columns: 2, gap: t.space(3), children: cards),
      card: (context, id, selected) => ChoiceCardBody(
        picture: ScenePreview(child: _LayoutScene(layout: byId[id]!.id)),
        words: ChoiceCardMeta(label: byId[id]!.label, hint: byId[id]!.hint, selected: selected),
      ),
    );
  }
}

/// `.preview` of the two card stylesheets: a window 6.2rem high on the page's paper, with a hairline under it, that
/// clips the scene drawn in it.
class ScenePreview extends StatelessWidget {
  const ScenePreview({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      height: t.lenOf('6.2rem'),
      decoration: BoxDecoration(
        color: t.color('glacier-bg'),
        border: Border(bottom: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline'))),
      ),
      // The scene is as tall as it needs and runs out under the window's foot.
      child: ClipRect(
        child: OverflowBox(alignment: Alignment.topCenter, minHeight: 0, maxHeight: double.infinity, child: child),
      ),
    );
  }
}

/// The page laid out one way, small (`Scene`, LayoutCards.tsx). Every shape is sized in rem.
class _LayoutScene extends StatelessWidget {
  const _LayoutScene({required this.layout});
  final HomeLayout layout;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    double rem(double n) => t.lenOf('${n}rem');
    final mini = MiniInk(t, line: 18, ground: 6);
    final gap = SizedBox(height: rem(0.28));

    Widget bar(double fraction, double height, Color color, {double opacity = 1}) => FractionallySizedBox(
          widthFactor: fraction,
          alignment: AlignmentDirectional.centerStart,
          child: Opacity(opacity: opacity, child: Container(height: height, decoration: ShapeDecoration(color: color, shape: const StadiumBorder()))),
        );

    // The search at the top of every layout.
    final search = Container(
      height: rem(0.62),
      decoration: ShapeDecoration(color: mini.ground, shape: StadiumBorder(side: BorderSide(color: mini.line, strokeAlign: BorderSide.strokeAlignInside))),
    );
    // A section's heading, and Spotlight's pinned line: a pin's worth of ink, then a name.
    Widget head() => Padding(padding: EdgeInsets.only(top: rem(0.1)), child: bar(0.30, rem(0.26), mini.ink));
    final pinned = Padding(padding: EdgeInsets.only(top: rem(0.1)), child: bar(0.55, rem(0.26), mini.muted));

    Widget card() => Container(
          padding: EdgeInsets.symmetric(vertical: rem(0.24), horizontal: rem(0.28)),
          decoration: BoxDecoration(color: mini.ground, border: Border.all(color: mini.line), borderRadius: BorderRadius.circular(rem(0.28))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [bar(0.60, rem(0.24), mini.ink), SizedBox(height: rem(0.18)), bar(0.85, rem(0.18), mini.muted, opacity: 0.6)],
          ),
        );
    Widget cards(int n) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < n; i += 2) ...[
              if (i > 0) SizedBox(height: rem(0.24)),
              Row(children: [Expanded(child: card()), SizedBox(width: rem(0.24)), Expanded(child: card())]),
            ],
          ],
        );
    Widget rows(int n, {bool thin = false}) => DecoratedBox(
          decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: mini.line))),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < n; i++)
                  SizedBox(height: rem(thin ? 0.44 : 0.56), child: CustomPaint(painter: _RowPainter(mini, thin: thin, ruled: i > 0, rem: rem(1)))),
              ],
            ),
          ),
        );

    final List<Widget> children = switch (layout) {
      HomeLayout.cards => [search, gap, head(), gap, cards(6)],
      HomeLayout.timeline => [search, gap, head(), gap, rows(2), gap, head(), gap, rows(3)],
      HomeLayout.list => [search, gap, head(), gap, rows(7, thin: true)],
      HomeLayout.spotlight => [search, gap, pinned, gap, cards(2), gap, head(), gap, rows(2)],
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(rem(0.5), rem(0.45), rem(0.5), 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// `.row`: a line of a list, drawn as the stylesheet's layered backgrounds are: a name at the start and a time at
/// the end, and on a thin row how it starts between them; with a line over every row but the first.
class _RowPainter extends CustomPainter {
  _RowPainter(this.mini, {required this.thin, required this.ruled, required this.rem});
  final MiniInk mini;
  final bool thin;
  final bool ruled;
  final double rem;

  @override
  void paint(Canvas canvas, Size size) {
    // `position / size`: a layer [width] of the row wide and [height] high, [at] of the way across what is left.
    void layer(Color color, double width, double height, {double? at, double? from}) {
      final w = size.width * width;
      final x = from ?? (size.width - w) * at!;
      canvas.drawRect(Rect.fromLTWH(x, (size.height - height) / 2, w, height), Paint()..color = color);
    }

    if (thin) {
      layer(mini.ink, 0.30, 0.18 * rem, from: 0.1 * rem);
      layer(mini.muted, 0.36, 0.14 * rem, at: 0.40);
      layer(mini.muted, 0.12, 0.14 * rem, at: 1);
    } else {
      layer(mini.ink, 0.38, 0.2 * rem, from: 0.1 * rem);
      layer(mini.muted, 0.14, 0.16 * rem, at: 1);
    }
    if (ruled) canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 1), Paint()..color = mini.line);
  }

  @override
  bool shouldRepaint(_RowPainter old) => old.thin != thin || old.ruled != ruled || old.rem != rem || old.mini.ink != mini.ink;
}
