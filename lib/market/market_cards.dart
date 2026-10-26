/// The Market's own parts, shared by its plugins, themes and fonts (lib/market/market_screen.dart): a shelf's
/// heading, the grid its cards stand in and the row they scroll in on a phone, a card's frame, the capsule buttons,
/// a category's chip and the small marks of where a plugin works.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../settings/kit/settings_type.dart';

/// A shelf's heading: its name, a quiet word after it (how many, what it is), and at its end a way to see the whole
/// shelf where the shelf is a taste of it.
class MarketHeading extends StatelessWidget {
  const MarketHeading({super.key, required this.title, this.meta, this.icon, this.more, this.onMore});

  final String title;
  final String? meta;
  final LucideIcon? icon;

  /// The word at its end ("See all"), and what it does.
  final String? more;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(3)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[AppIcon(icon!, size: 18, strokeWidth: 2.1, color: t.color('app-ink-2')), SizedBox(width: t.space(2))],
          Semantics(
            header: true,
            child: Text(title, maxLines: 1, style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: t.color('app-ink'))),
          ),
          SizedBox(width: t.space(2)),
          // The quiet word takes the room left, and gives way first.
          Expanded(child: meta == null ? const SizedBox.shrink() : Text(meta!, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')))),
          if (more != null && onMore != null) MarketWord(word: more!, onPress: onMore!),
        ],
      ),
    );
  }
}

/// A word that goes somewhere, in the ink's second step with an arrow after it: "See all".
class MarketWord extends StatelessWidget {
  const MarketWord({super.key, required this.word, required this.onPress, this.icon = Lucide.chevronRight});

  final String word;
  final VoidCallback onPress;
  final LucideIcon icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: word,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('sm'),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(1), vertical: t.space(1)),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(word, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color(state.hovered || state.pressed ? 'app-ink' : 'app-ink-2'))),
                AppIcon(icon, size: 14, strokeWidth: 2.2, color: t.color('app-ink-3')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cards as many across as [minWidth] each leaves room for, up to [most], the cards of a row as tall as its tallest.
class MarketGrid extends StatelessWidget {
  const MarketGrid({super.key, required this.minWidth, required this.children, this.most = 4, this.gap});

  final double minWidth;
  final int most;
  final double? gap;
  final List<Widget> children;

  /// How many stand across [width].
  static int across(double width, double minWidth, double gap, int most) => math.max(1, math.min(most, ((width + gap) / (minWidth + gap)).floor()));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = this.gap ?? t.space(3);
    return LayoutBuilder(
      builder: (context, box) {
        final n = across(box.maxWidth, minWidth, gap, most);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row * n < children.length; row++) ...[
              if (row > 0) SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < n; i++) ...[
                      if (i > 0) SizedBox(width: gap),
                      Expanded(child: row * n + i < children.length ? children[row * n + i] : const SizedBox.shrink()),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Cards in a row that scrolls sideways, each [width] wide and [height] tall: a phone's shelf. The row is not cut
/// at the page's gutters, so a card half past the edge says there are more.
class MarketRow extends StatelessWidget {
  const MarketRow({super.key, required this.width, required this.height, required this.children});

  final double width;
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final gap = context.tokens.space(3);
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: children.length,
        separatorBuilder: (context, i) => SizedBox(width: gap),
        itemBuilder: (context, i) => SizedBox(width: width, child: children[i]),
      ),
    );
  }
}

/// A card's frame: the page's second paper, a hairline round it, and the press's dip; with [selected], ringed in
/// the ink, never colour alone.
class MarketCard extends StatelessWidget {
  const MarketCard({super.key, required this.child, this.onPress, this.label, this.selected = false, this.padding});

  final Widget child;
  final VoidCallback? onPress;

  /// What a screen reader says for the card's press.
  final String? label;
  final bool selected;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = t.radius('lg');
    Widget frame(bool hovered, bool pressed) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          clipBehavior: Clip.antiAlias,
          padding: padding,
          decoration: BoxDecoration(
            color: pressed ? t.color('app-paper-3') : t.color('app-paper-2'),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: selected ? t.color('app-ink') : (hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 22%, transparent)') : t.color('app-rule')),
              width: selected ? 2 : t.len('glacier-hairline'),
            ),
          ),
          child: child,
        );
    final press = onPress;
    if (press == null) return frame(false, false);
    return GlacierPressable(
      onPressed: press,
      semanticLabel: label,
      selected: selected,
      builder: (context, state) => GlacierFocusRing(visible: state.focused, radius: radius, child: frame(state.hovered, state.pressed)),
    );
  }
}

/// How a capsule is drawn: filled in a colour, the page's ink, or a ring.
enum MarketButtonLook { filled, ink, ring, glass }

/// A capsule button: Add, Remove, Use, Settings. [color] fills a filled one, with white words on it.
class MarketButton extends StatelessWidget {
  const MarketButton({super.key, required this.label, required this.onPress, this.look = MarketButtonLook.ink, this.color, this.icon, this.semantics, this.large = false});

  final String label;
  final VoidCallback? onPress;
  final MarketButtonLook look;
  final Color? color;
  final LucideIcon? icon;

  /// What a screen reader says, where the word alone is not enough: "Add Notion".
  final String? semantics;

  /// The detail page's size, a thumb's height.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final off = onPress == null;
    final height = large ? t.lenOf('2.6rem') : t.lenOf('1.9rem');
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: semantics ?? label,
      builder: (context, state) {
        final (Color ground, Color ink, Color? ring) = switch (look) {
          MarketButtonLook.filled => (color ?? t.color('app-ink'), const Color(0xFFFFFFFF), null),
          MarketButtonLook.ink => (t.color('app-ink'), t.color('app-paper'), null),
          MarketButtonLook.ring => (const Color(0x00000000), t.color('app-ink'), t.color('app-rule')),
          MarketButtonLook.glass => (const Color(0x33FFFFFF), const Color(0xFFFFFFFF), const Color(0x55FFFFFF)),
        };
        return GlacierFocusRing(
          visible: state.focused,
          radius: height / 2,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: off ? 0.45 : (state.pressed ? 0.8 : 1),
            child: Container(
              height: height,
              padding: EdgeInsets.symmetric(horizontal: large ? t.space(5) : t.space(3)),
              decoration: ShapeDecoration(
                color: ground,
                shape: StadiumBorder(side: ring == null ? BorderSide.none : BorderSide(color: ring, width: t.len('glacier-hairline'))),
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[AppIcon(icon!, size: large ? 16 : 14, strokeWidth: 2.3, color: ink, wash: false), SizedBox(width: t.space(1))],
                    Text(label, maxLines: 1, style: pageText(t, large ? t.fontSize('md') : t.fontSize('sm'), weight: 'semibold', color: ink)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "Added", with its tick: what stands where Add was once a plugin is added.
class MarketAdded extends StatelessWidget {
  const MarketAdded({super.key, required this.name, this.color});

  final String name;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = color ?? t.color('app-ink-3');
    return Semantics(
      label: '$name added',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(Lucide.circleCheck, size: 15, strokeWidth: 2.2, color: ink, wash: false),
            SizedBox(width: t.space(1)),
            Text('Added', style: pageText(t, t.fontSize('sm'), weight: 'medium', color: ink)),
          ],
        ),
      ),
    );
  }
}

/// One category in the plugins' filter: a capsule with its word, inked when it is the one chosen (the home page's
/// chip, lib/home/home_filters.dart, without its cross).
class MarketChip extends StatelessWidget {
  const MarketChip({super.key, required this.label, required this.chosen, required this.onPress});

  final String label;
  final bool chosen;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: label,
      selected: chosen,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        child: Container(
          constraints: BoxConstraints(minHeight: t.space(8)),
          padding: EdgeInsets.symmetric(horizontal: t.space(3)),
          decoration: BoxDecoration(
            color: chosen ? t.color('app-ink') : (state.pressed ? t.color('app-paper-3') : const Color(0x00000000)),
            border: Border.all(color: chosen ? t.color('app-ink') : t.color('app-rule'), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          child: Align(
            widthFactor: 1,
            child: ExcludeSemantics(child: Text(label, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: chosen ? t.color('app-paper') : t.color('app-ink-2')))),
          ),
        ),
      ),
    );
  }
}

/// A word in a small capsule of its own: a plugin's category on its tile, a face's role.
class MarketTag extends StatelessWidget {
  const MarketTag({super.key, required this.label, this.ground, this.ink});

  final String label;
  final Color? ground;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.lenOf('0.12rem')),
      decoration: ShapeDecoration(color: ground ?? t.color('app-paper-3'), shape: const StadiumBorder()),
      child: Text(label, maxLines: 1, style: pageText(t, t.fontSize('xs'), weight: 'medium', color: ink ?? t.color('app-ink-2'))),
    );
  }
}
