/// The Market's icon packs (Matt, 2026-10-27: "I would like you to add three icon styles (outline, solid and filled)
/// and add a few different icon packs for the app to choose from"): a shelf of its own, Icons, beside the themes and
/// the fonts, each pack a card with twelve of the app's own icons drawn in it in all three styles; and a page for
/// each, with the way to use it, the style chooser with its preview, how the pack draws each style and how much of
/// the app it draws.
///
/// The packs are lib/art/icon_packs.dart's `iconPacks`, and every icon here is an [AppIcon] drawn in a look of its own,
/// so a card is the pack as the app would draw it, the wash and Lucide's stand-ins included. Choosing writes the
/// preferences `iconPack` and `iconStyle` (lib/core/preferences.dart), which travel with the person like the theme
/// and the faces, and every icon in the app is redrawn at once (lib/app/ghost_app.dart puts the look round it).
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/preferences.dart';
import '../settings/kit/settings_type.dart';
import '../settings/settings_search.dart' show wordsFound;
import 'market_cards.dart';
import 'market_items.dart' show marketHues, tileLight;
import 'market_looks.dart' show MarketInUse;

const Color _white = Color(0xFFFFFFFF);

/// Every glyph the app draws, by Lucide's name: Lucide's own (lib/art/lucide.g.dart) and what the app's own drawings
/// draw (lib/art/icons.dart). tool/icons/map.json has a line for each.
final Set<String> appGlyphNames = {
  for (final icon in Lucide.all.values) icon.name,
  for (final drawn in AppIcons.all.values) drawn.like,
  'house',
};

/// How much of the app [pack] draws with its own glyphs, and which it leaves to Lucide.
({int own, int of, List<String> lucides}) packCoverage(IconPack pack) {
  final glyphs = pack.glyphs;
  final names = appGlyphNames.toList()..sort();
  if (glyphs == null) return (own: names.length, of: names.length, lucides: const []);
  final lucides = [for (final name in names) if (!glyphs.containsKey(name)) name];
  return (own: names.length - lucides.length, of: names.length, lucides: lucides);
}

/// The look [prefs] draw in.
IconLook lookOf(Preferences prefs) => IconLook(iconPackOf(prefs.iconPack).id, IconStyle.of(prefs.iconStyle));

/// Whether a pack stays for what is typed: its name, its line, whose it is, and the words for icons.
bool iconPackFound(IconPack pack, String query) => wordsFound(query, [pack.name, pack.line, pack.author, pack.licence, 'icon icons pack glyphs symbols style outline solid filled']);

/// A pack's two colours, as a plugin's tile has them (`marketHues`): the light page's deep one, the dark page's bright.
(Color, Color) packColours(IconPack pack) => marketHues[pack.hue] ?? marketHues['indigo']!;

/// [names] drawn in [look], [size] points each, in a row that wraps; or, [fit], in one line, made smaller where the
/// line is short of room for them all at [size].
class IconPreviewRow extends StatelessWidget {
  const IconPreviewRow({super.key, required this.look, this.names = iconPreviewNames, this.size = 16, this.gap, this.color, this.fit = false});

  final IconLook look;
  final List<String> names;
  final double size;
  final double? gap;
  final Color? color;
  final bool fit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = this.gap ?? size * 0.45;
    final icons = [for (final name in names) ?Lucide.all[name]];
    if (fit) {
      // Scaled down as a whole where the line is short of room: a card's grid asks its height first, which a layout
      // that measured the room could not answer.
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: gap,
          children: [for (final icon in icons) AppIcon(icon, size: size, strokeWidth: 2.1, color: color ?? t.color('app-ink'), look: look)],
        ),
      );
    }
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [for (final icon in icons) AppIcon(icon, size: size, strokeWidth: 2.1, color: color ?? t.color('app-ink'), look: look)],
    );
  }
}

/// The twelve in each of the three styles, a row each, the style's word before it where there is room ([labels]),
/// and the chosen style's row marked.
class IconPackPreview extends StatelessWidget {
  const IconPackPreview({super.key, required this.pack, this.size = 15, this.labels = false, this.chosen});

  final IconPack pack;
  final double size;
  final bool labels;

  /// The style in use, whose row is marked; null marks none.
  final IconStyle? chosen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final style in IconStyle.values) ...[
          if (style != IconStyle.outline) SizedBox(height: size * 0.6),
          Row(
            key: ValueKey('icon-preview-${pack.id}-${style.name}'),
            children: [
              if (labels)
                SizedBox(
                  width: t.lenOf('4.6rem'),
                  child: Text(style.label, maxLines: 1, style: pageText(t, t.fontSize('xs'), weight: style == chosen ? 'semibold' : 'medium', color: t.color(style == chosen ? 'app-ink' : 'app-ink-3'))),
                ),
              Expanded(child: IconPreviewRow(look: IconLook(pack.id, style), size: size, gap: size * 0.35, fit: true)),
            ],
          ),
        ],
      ],
    );
  }
}

/// One pack on the Icons shelf: its twelve in three styles, its name and line, how much of the app it draws and its
/// licence, and the tick on the one in use. Pressed, it opens the pack's page.
class MarketIconPackCard extends StatelessWidget {
  const MarketIconPackCard({super.key, required this.pack, required this.selected, required this.onPress, this.open = false});

  final IconPack pack;

  /// The pack in use.
  final bool selected;

  /// Whether its page is open beside the shelves.
  final bool open;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final coverage = packCoverage(pack);
    return MarketCard(
      key: ValueKey('market-icons-${pack.id}'),
      onPress: onPress,
      label: 'Icon pack ${pack.name}${selected ? ', in use' : ''}',
      selected: selected || open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: t.color('app-paper-3'),
            padding: EdgeInsets.fromLTRB(t.space(3), t.space(3), t.space(3), t.space(3)),
            child: ExcludeSemantics(child: IconPackPreview(pack: pack, size: 20)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(3)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(pack.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink'))),
                      Text(pack.line, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
                      Text('${coverage.own} of ${coverage.of} icons · ${pack.licence}', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
                    ],
                  ),
                ),
                SizedBox(width: t.space(2)),
                MarketInUse(on: selected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Outline, Solid and Filled to choose between, and the twelve drawn in [pack] in the chosen one below it, so the
/// choice is seen as it is made: on the Icons shelf, on a pack's page, and in Settings › Appearance.
class IconStyleChooser extends StatelessWidget {
  const IconStyleChooser({super.key, required this.pack, required this.style, required this.onStyle, this.size = 20});

  final IconPack pack;
  final IconStyle style;
  final ValueChanged<IconStyle> onStyle;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlacierSegmentedControl(
          key: const ValueKey('icon-style'),
          ariaLabel: 'Icon style',
          fullWidth: true,
          size: GlacierSegmentedSize.sm,
          options: [for (final each in IconStyle.values) GlacierSegmentedOption(value: each.name, label: Text(each.label))],
          value: style.name,
          onValueChange: (value) => onStyle(IconStyle.of(value)),
        ),
        SizedBox(height: t.space(3)),
        Semantics(
          label: '${pack.name}, ${style.label}',
          child: ExcludeSemantics(child: IconPreviewRow(key: ValueKey('icon-style-preview-${pack.id}-${style.name}'), look: IconLook(pack.id, style), size: size, gap: size * 0.55, fit: true)),
        ),
      ],
    );
  }
}

/// A pack's page: its colour and its glyphs, its name and line; Use this pack, or that it is in use; the style to draw
/// it in, with the twelve drawn in it; the three styles side by side and what each is drawn from; how much of the
/// app it draws and the glyphs it leaves to Lucide; and whose it is, under what licence, from which release.
class IconPackDetail extends StatelessWidget {
  const IconPackDetail({super.key, required this.pack, required this.inUse, required this.style, required this.onUse, required this.onStyle, this.onClose});

  final IconPack pack;
  final bool inUse;

  /// The style the app draws in.
  final IconStyle style;
  final VoidCallback onUse;
  final ValueChanged<IconStyle> onStyle;

  /// Shuts the page, where it stands beside the shelves; null where the bar's arrow does.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (deep, bright) = packColours(pack);
    final radius = t.radius('lg') * 1.5;
    final gap = t.space(4);
    final body = pageText(t, t.fontSize('md'), height: 1.45, color: t.color('app-ink'));
    final quiet = pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3'));
    final coverage = packCoverage(pack);

    Widget section(String title, List<Widget> children) => Padding(
          padding: EdgeInsets.only(top: gap * 1.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(title, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink')))),
              SizedBox(height: t.space(2)),
              ...children,
            ],
          ),
        );

    return Column(
      key: ValueKey('market-icons-detail-${pack.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The head: the pack's colour, a few of its glyphs large and faint, its name and line on it.
        ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [deep, Color.lerp(deep, bright, 0.55)!, bright]),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: tileLight(radius: radius)),
                Positioned(
                  right: -t.space(2),
                  bottom: -t.space(3),
                  child: Opacity(
                    opacity: 0.2,
                    child: ExcludeSemantics(child: SizedBox(width: t.lenOf('11rem'), child: IconPreviewRow(look: IconLook(pack.id, style), names: iconPreviewNames.take(6).toList(), size: t.lenOf('3rem'), color: _white))),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(t.space(5)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: t.lenOf('3.6rem'),
                            height: t.lenOf('3.6rem'),
                            decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(t.lenOf('1rem')), border: Border.all(color: const Color(0x40FFFFFF))),
                            alignment: Alignment.center,
                            child: AppIcon(Lucide.shapes, size: t.lenOf('1.9rem'), color: _white, look: IconLook(pack.id, style)),
                          ),
                          const Spacer(),
                          if (onClose != null)
                            GlacierPressable(
                              key: const ValueKey('market-detail-close'),
                              onPressed: onClose,
                              semanticLabel: 'Close ${pack.name}',
                              builder: (context, state) => GlacierFocusRing(
                                visible: state.focused,
                                child: Container(
                                  width: t.space(8),
                                  height: t.space(8),
                                  decoration: const ShapeDecoration(color: Color(0x33000000), shape: CircleBorder()),
                                  alignment: Alignment.center,
                                  child: const AppIcon(Lucide.x, size: 16, strokeWidth: 2.4, color: _white, wash: false),
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: t.space(4)),
                      Semantics(header: true, child: Text(pack.name, style: pageText(t, t.fontSize('2xl'), weight: 'bold', color: _white))),
                      SizedBox(height: t.space(1)),
                      Text(pack.line, style: pageText(t, t.fontSize('md'), height: 1.35, color: const Color(0xE6FFFFFF))),
                      SizedBox(height: t.space(3)),
                      Wrap(
                        spacing: t.space(2),
                        runSpacing: t.space(2),
                        children: [
                          MarketTag(key: const ValueKey('market-detail-status'), label: inUse ? 'In use' : 'Not in use', ground: const Color(0x33000000), ink: _white),
                          MarketTag(label: 'Icon pack', ground: const Color(0x26FFFFFF), ink: _white),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: gap),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: MarketButton(
            key: ValueKey(inUse ? 'market-icons-in-use-${pack.id}' : 'market-icons-use-${pack.id}'),
            label: inUse ? 'In use' : 'Use this pack',
            semantics: inUse ? '${pack.name}, in use' : 'Use ${pack.name}',
            icon: inUse ? Lucide.check : Lucide.plus,
            look: inUse ? MarketButtonLook.ring : MarketButtonLook.filled,
            color: deep,
            large: true,
            onPress: inUse ? null : onUse,
          ),
        ),
        SizedBox(height: t.space(2)),
        Text(
          inUse ? 'Every icon in Ghost.md is drawn in it, on every device you use.' : 'Built in: using it redraws every icon at once, on every device you use, with nothing to download.',
          style: quiet,
        ),
        section('Style', [
          IconStyleChooser(pack: pack, style: style, onStyle: onStyle, size: 22),
          SizedBox(height: t.space(2)),
          Text('The style is yours whichever pack you use, and changes every icon at once.', style: quiet),
        ]),
        section('All three', [
          Container(
            padding: EdgeInsets.all(t.space(3)),
            decoration: BoxDecoration(
              color: t.color('app-paper-2'),
              borderRadius: BorderRadius.circular(t.radius('lg')),
              border: Border.all(color: t.color('app-rule'), width: t.len('glacier-hairline')),
            ),
            child: IconPackPreview(pack: pack, size: 18, labels: true, chosen: style),
          ),
          for (final each in IconStyle.values)
            Padding(
              key: ValueKey('market-icons-style-${each.name}'),
              padding: EdgeInsets.only(top: t.space(2)),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${each.label}: ', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink'))),
                  TextSpan(text: pack.styles[each]!.words, style: quiet),
                ]),
              ),
            ),
        ]),
        section('How much of Ghost.md it draws', [
          Text(
            coverage.lucides.isEmpty
                ? 'All ${coverage.of} of the app’s icons.'
                : coverage.lucides.length == 1
                    ? '${coverage.own} of the app’s ${coverage.of} icons. ${pack.name} has nothing for the other one, which is drawn as Lucide’s, in the same style:'
                    : '${coverage.own} of the app’s ${coverage.of} icons. ${pack.name} has nothing for the other ${coverage.lucides.length}, which are drawn as Lucide’s, in the same style:',
            key: const ValueKey('market-icons-coverage'),
            style: body,
          ),
          if (coverage.lucides.isNotEmpty) ...[
            SizedBox(height: t.space(2)),
            IconPreviewRow(look: IconLook(pack.id, style), names: coverage.lucides, size: 18),
          ],
        ]),
        section('About it', [Text(pack.about, style: body)]),
        Padding(
          padding: EdgeInsets.only(top: gap * 1.5),
          child: Text('${pack.author} · ${pack.licence} · ${pack.version} · ${pack.home}', key: const ValueKey('market-icons-credit'), style: quiet),
        ),
      ],
    );
  }
}
