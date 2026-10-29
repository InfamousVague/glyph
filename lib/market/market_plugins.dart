/// The Market's plugins (Matt, 2026-10-26: "all our plugins with vivid iconography and imagery where possible
/// include mobile and desktop support"): a card each, a featured card for the plugins whose brand Ghost.md draws, and
/// a plugin's page, which is what Settings › Plugins › its name was (lib/settings/panes/plugins_pane.dart until
/// then): what it does, what it adds, what it may reach and why, Add or Remove, and the way to its own page in
/// Settings once it is added.
///
/// Each wears its colour (lib/market/market_items.dart [pluginTile]): a wash across its hue, the one its page in
/// Settings wears, with its Lucide icon in white; a company's plugin wears its company's mark instead, in its brand's
/// colour on a badge of its own ([PluginBadge]; lib/plugins/brands.dart), but Google Meet, whose mark is in white on
/// its colour as the icons are (`marksInWhite`). Each says where it works ([reachOf]): "Mobile · Desktop", "Android · Desktop", "Android
/// only".
///
/// Adding one is the registry's switch (`registry.setEnabled`), as the catalogue's Add was, so the switches the
/// account carries (Claude, Slack, Discord, GitHub, Lovart; lib/sync/connections.dart) still follow it. Local only holds a
/// plugin that uses the internet off: its card says so and cannot be added until Local only is off.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../art/brand_marks.dart';
import '../plugins/brands.dart' show badgedBrandOf;
import '../plugins/reach.dart';
import '../plugins/types.dart';
import '../settings/kit/settings_type.dart';
import 'market_cards.dart';
import 'market_items.dart';

const Color _white = Color(0xFFFFFFFF);

/// A plugin's tile: its colour with its mark in the middle, [size] square; for a plugin that wears its company's mark,
/// that mark in its brand's colour on a badge of the page's raised paper ([PluginBadge]).
class PluginTile extends StatelessWidget {
  const PluginTile({super.key, required this.plugin, required this.size});

  final GlyphPlugin plugin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.28;
    final brand = badgedBrandOf(plugin);
    // A filled mark on the light badge reads smaller than a white glyph on colour: a little larger.
    if (brand != null) return PluginBadge(mark: brand, size: size, radius: radius, markSize: size * 0.58);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: pluginTile(plugin, radius: radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            tileLight(radius: radius),
            Center(child: pluginMark(plugin, size * 0.5)),
          ],
        ),
      ),
    );
  }
}

/// A company's mark on a badge of its own, [size] square (Matt, 2026-10-29: "Iconize real company logos ... and use
/// those for the plugin icons"): the page's raised paper with its rule round it, and the mark at [markSize] in its
/// brand's colour (Simple Icons' hex), or in the ink where that colour would not stand out from the paper (a black
/// or near-black mark on the dark one; lib/art/brand_marks.dart `brandInkOn`). The plugin's tile, and the chip that
/// holds its mark on a coloured head.
class PluginBadge extends StatelessWidget {
  const PluginBadge({super.key, required this.mark, required this.size, required this.radius, required this.markSize});

  final BrandMarkData mark;
  final double size;
  final double radius;
  final double markSize;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // On a dark page the raised paper is the card's own black, and the badge would read as a hole in it: a step lighter.
    final ground = t.color(t.isDark ? 'app-paper-2' : 'app-raised');
    return Container(
      key: ValueKey('plugin-badge-${mark.slug}'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(radius), border: Border.all(color: t.color('app-rule'))),
      child: BrandMarkIcon(mark, size: markSize, color: brandInkOn(mark, ground: ground, ink: t.color('app-ink'))),
    );
  }
}

/// The chip that holds a plugin's mark on its coloured head, [size] square: glass with the mark in white, or the
/// company's mark on its badge ([PluginBadge]).
Widget _markChip(GlyphPlugin plugin, {required double size, required double radius, required double markSize}) {
  final brand = badgedBrandOf(plugin);
  if (brand != null) return PluginBadge(mark: brand, size: size, radius: radius, markSize: markSize);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(radius), border: Border.all(color: const Color(0x40FFFFFF))),
    alignment: Alignment.center,
    child: pluginMark(plugin, markSize),
  );
}

/// Add, or that it is added: the end of a plugin's card.
Widget _addOrAdded(GlyphPlugin plugin, {required bool added, required VoidCallback? onAdd, bool onColour = false}) {
  final name = plugin.manifest.name;
  if (added) return MarketAdded(name: name, color: onColour ? _white : null);
  return MarketButton(
    key: ValueKey('market-add-${plugin.manifest.id}'),
    label: 'Add',
    semantics: 'Add $name',
    icon: Lucide.plus,
    look: onColour ? MarketButtonLook.glass : MarketButtonLook.filled,
    color: pluginColours(plugin).$1,
    onPress: onAdd,
  );
}

/// Where a plugin works, quietly, with a phone and a laptop drawn by it where it is on one.
class PluginReachLine extends StatelessWidget {
  const PluginReachLine({super.key, required this.plugin, this.color});

  final GlyphPlugin plugin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reach = reachOf(plugin);
    final ink = color ?? t.color('app-ink-3');
    return Row(
      key: const ValueKey('plugin-reach'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reach.mobile) AppIcon(Lucide.smartphone, size: 12, strokeWidth: 2.2, color: ink, wash: false),
        if (reach.mac) ...[if (reach.mobile) SizedBox(width: t.lenOf('0.15rem')), AppIcon(Lucide.laptop, size: 12, strokeWidth: 2.2, color: ink, wash: false)],
        SizedBox(width: t.space(1)),
        Flexible(child: Text(reach.line, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'medium', color: ink))),
      ],
    );
  }
}

/// One plugin on a shelf: its tile, its name, its line, where it works, and Add or that it is added; pressed, its
/// page. [wide] is a card standing in a grid, its tile across its head; otherwise it is a row, a phone's, its tile at
/// its start.
class MarketPluginCard extends StatelessWidget {
  const MarketPluginCard({super.key, required this.plugin, required this.added, required this.held, required this.onAdd, required this.onOpen, this.wide = false, this.selected = false});

  final GlyphPlugin plugin;
  final bool added;

  /// Held off by Local only.
  final bool held;
  final VoidCallback? onAdd;
  final VoidCallback onOpen;
  final bool wide;

  /// Its page is the one open beside the shelves.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final manifest = plugin.manifest;
    final name = Text(manifest.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink')));
    final line = Text(manifest.line, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), height: 1.35, color: t.color('app-ink-2')));
    final end = held
        ? Semantics(label: '${manifest.name} is off while Local only is on', child: ExcludeSemantics(child: MarketTag(label: 'Local only')))
        : _addOrAdded(plugin, added: added, onAdd: onAdd);
    if (!wide) {
      return MarketCard(
        key: ValueKey('market-plugin-${manifest.id}'),
        onPress: onOpen,
        label: manifest.name,
        selected: selected,
        padding: EdgeInsets.all(t.space(3)),
        child: Row(
          children: [
            PluginTile(plugin: plugin, size: t.lenOf('3.4rem')),
            SizedBox(width: t.space(3)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [name, SizedBox(height: t.lenOf('0.1rem')), line, SizedBox(height: t.space(1)), PluginReachLine(plugin: plugin)],
              ),
            ),
            SizedBox(width: t.space(2)),
            end,
          ],
        ),
      );
    }
    final head = t.lenOf('5.5rem');
    return MarketCard(
      key: ValueKey('market-plugin-${manifest.id}'),
      onPress: onOpen,
      label: manifest.name,
      selected: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The head: the plugin's colour edge to edge, its mark large and its category on it.
          SizedBox(
            height: head,
            child: DecoratedBox(
              decoration: pluginTile(plugin, radius: 0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  tileLight(radius: 0),
                  // The mark again, large and faint past the end: the card's picture.
                  Positioned(right: -head * 0.18, bottom: -head * 0.3, child: Opacity(opacity: 0.16, child: pluginMark(plugin, head * 1.15))),
                  // A company's mark on its badge, in its colour; any other in white on the head.
                  Positioned(left: t.space(3), bottom: t.space(3), child: badgedBrandOf(plugin) == null ? pluginMark(plugin, head * 0.42) : PluginTile(plugin: plugin, size: head * 0.52)),
                  if (manifest.category != null)
                    Positioned(top: t.space(2), right: t.space(2), child: MarketTag(label: manifest.category!.label, ground: const Color(0x33000000), ink: _white)),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(t.space(3)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  name,
                  SizedBox(height: t.lenOf('0.15rem')),
                  line,
                  SizedBox(height: t.space(3)),
                  const Spacer(),
                  Row(children: [Expanded(child: PluginReachLine(plugin: plugin)), SizedBox(width: t.space(2)), end]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plugin at the head of the Market: the whole card in its colour, its mark large, its name and its line in white,
/// and Add on glass.
class FeaturedPluginCard extends StatelessWidget {
  const FeaturedPluginCard({super.key, required this.plugin, required this.added, required this.held, required this.onAdd, required this.onOpen});

  final GlyphPlugin plugin;
  final bool added;
  final bool held;
  final VoidCallback? onAdd;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final manifest = plugin.manifest;
    final radius = t.radius('lg') * 1.5;
    return GlacierPressable(
      key: ValueKey('market-featured-${manifest.id}'),
      onPressed: onOpen,
      semanticLabel: manifest.name,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: radius,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: state.pressed ? 0.98 : 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: DecoratedBox(
              decoration: pluginTile(plugin, radius: radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  tileLight(radius: radius),
                  Positioned(right: -t.space(6), top: -t.space(4), child: Opacity(opacity: 0.18, child: pluginMark(plugin, t.lenOf('9rem')))),
                  Padding(
                    padding: EdgeInsets.all(t.space(4)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _markChip(plugin, size: t.lenOf('2.6rem'), radius: t.lenOf('0.75rem'), markSize: t.lenOf('1.4rem')),
                        const Spacer(),
                        Text(manifest.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xl'), weight: 'bold', color: _white)),
                        SizedBox(height: t.lenOf('0.1rem')),
                        Text(manifest.line, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), height: 1.3, color: const Color(0xE6FFFFFF))),
                        SizedBox(height: t.space(3)),
                        Row(
                          children: [
                            Expanded(child: PluginReachLine(plugin: plugin, color: const Color(0xD9FFFFFF))),
                            SizedBox(width: t.space(2)),
                            held ? MarketTag(label: 'Local only', ground: const Color(0x33000000), ink: _white) : _addOrAdded(plugin, added: added, onAdd: onAdd, onColour: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A plugin's page in the Market, Settings › Plugins › its name until 2026-10-26: its colour across the head with its
/// mark, name and line; Add or Remove; the way to its own page in Settings once it is added ([onSettings]); where it
/// works; what it does and what it adds; and what it may reach, each permission with the plugin's own reason and,
/// for the internet, the hosts it talks to and no others (lib/plugins/host.dart holds it to them).
///
/// Removing a plugin keeps its data, as the registry does: added again, it is as it was.
class PluginDetail extends StatelessWidget {
  const PluginDetail({super.key, required this.plugin, required this.added, required this.on, required this.held, required this.onSwitch, this.onSettings, this.onLocalOnly, this.onClose});

  final GlyphPlugin plugin;

  /// Switched on here, held off or not.
  final bool added;

  /// Switched on and not held: what it adds is in the app now.
  final bool on;
  final bool held;

  /// Adds it, or removes it.
  final ValueChanged<bool> onSwitch;

  /// Opens its own page in Settings; null where it has none, or none while it is off.
  final VoidCallback? onSettings;

  /// Opens Account at its Privacy card, for "Local only".
  final VoidCallback? onLocalOnly;

  /// Shuts the page, where it stands beside the shelves; null where the bar's arrow does.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final manifest = plugin.manifest;
    final settings = plugin.settings;
    final (deep, bright) = pluginColours(plugin);
    final radius = t.radius('lg') * 1.5;
    final gap = t.space(4);
    final body = pageText(t, t.fontSize('md'), height: 1.45, color: t.color('app-ink'));
    final quiet = pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3'));
    final reach = reachOf(plugin);
    final status = held ? 'Held off by Local only' : (added ? 'Added' : 'Not added');

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

    Widget point(LucideIcon icon, String label, {String? hint, Key? key}) => Padding(
          key: key,
          padding: EdgeInsets.only(top: t.space(2)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: t.lenOf('1.9rem'),
                height: t.lenOf('1.9rem'),
                decoration: BoxDecoration(color: deep.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(t.lenOf('0.55rem'))),
                alignment: Alignment.center,
                child: AppIcon(icon, size: 15, strokeWidth: 2.2, color: t.isDark ? bright : deep, wash: false),
              ),
              SizedBox(width: t.space(3)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(padding: EdgeInsets.only(top: t.lenOf('0.2rem')), child: Text(label, style: pageText(t, t.fontSize('md'), weight: hint == null ? 'regular' : 'medium', height: 1.35, color: t.color('app-ink')))),
                    if (hint != null) Padding(padding: EdgeInsets.only(top: t.lenOf('0.15rem')), child: Text(hint, style: quiet)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Column(
      key: ValueKey('market-detail-${manifest.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The head: the plugin's colour, its mark large and faint as its picture, and its name and line on it.
        ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: DecoratedBox(
            decoration: pluginTile(plugin, radius: radius),
            child: Stack(
              children: [
                Positioned.fill(child: tileLight(radius: radius)),
                Positioned(right: -t.space(8), bottom: -t.space(10), child: Opacity(opacity: 0.16, child: pluginMark(plugin, t.lenOf('12rem')))),
                Padding(
                  padding: EdgeInsets.all(t.space(5)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _markChip(plugin, size: t.lenOf('3.6rem'), radius: t.lenOf('1rem'), markSize: t.lenOf('1.9rem')),
                          const Spacer(),
                          if (onClose != null)
                            GlacierPressable(
                              key: const ValueKey('market-detail-close'),
                              onPressed: onClose,
                              semanticLabel: 'Close ${manifest.name}',
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
                      Semantics(header: true, child: Text(manifest.name, style: pageText(t, t.fontSize('2xl'), weight: 'bold', color: _white))),
                      SizedBox(height: t.space(1)),
                      Text(manifest.line, style: pageText(t, t.fontSize('md'), height: 1.35, color: const Color(0xE6FFFFFF))),
                      SizedBox(height: t.space(3)),
                      Wrap(
                        spacing: t.space(2),
                        runSpacing: t.space(2),
                        children: [
                          MarketTag(key: const ValueKey('market-detail-status'), label: status, ground: const Color(0x33000000), ink: _white),
                          if (manifest.category != null) MarketTag(label: manifest.category!.label, ground: const Color(0x26FFFFFF), ink: _white),
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
        // Add or Remove, and the way to its settings.
        Wrap(
          spacing: t.space(2),
          runSpacing: t.space(2),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MarketButton(
              key: ValueKey(added ? 'market-remove-${manifest.id}' : 'market-add-${manifest.id}'),
              label: added ? 'Remove' : 'Add to Ghost.md',
              semantics: '${added ? 'Remove' : 'Add'} ${manifest.name}',
              icon: added ? Lucide.minus : Lucide.plus,
              look: added ? MarketButtonLook.ring : MarketButtonLook.filled,
              color: deep,
              large: true,
              onPress: held ? null : () => onSwitch(!added),
            ),
            if (on && settings != null && onSettings != null)
              MarketButton(
                key: ValueKey('market-settings-${manifest.id}'),
                label: 'Settings',
                semantics: '${manifest.name} settings',
                icon: Lucide.settings,
                look: MarketButtonLook.ring,
                large: true,
                onPress: onSettings,
              ),
          ],
        ),
        SizedBox(height: t.space(2)),
        Text(
          held
              ? 'It uses the internet, so it is off while Local only is on.'
              : added
                  ? (settings == null ? 'Removed, it offers nothing until it is added again, and keeps what it kept.' : settings.summary())
                  : 'Built in: adding it is a switch, with nothing to download.',
          key: const ValueKey('market-detail-hint'),
          style: quiet,
        ),
        if (held && onLocalOnly != null) Padding(padding: EdgeInsets.only(top: t.space(1)), child: Align(alignment: AlignmentDirectional.centerStart, child: MarketWord(word: 'Local only', onPress: onLocalOnly!))),
        section('Works on', [
          Wrap(
            spacing: t.space(2),
            runSpacing: t.space(2),
            children: [
              for (final (where, yes) in reach.each)
                Container(
                  key: ValueKey('market-reach-$where'),
                  padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
                  decoration: ShapeDecoration(
                    color: yes ? deep.withValues(alpha: 0.12) : const Color(0x00000000),
                    shape: StadiumBorder(side: BorderSide(color: yes ? deep.withValues(alpha: 0.35) : t.color('app-rule'), width: t.len('glacier-hairline'))),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(where == 'Mac' ? Lucide.laptop : Lucide.smartphone, size: 14, strokeWidth: 2.2, color: yes ? (t.isDark ? bright : deep) : t.color('app-ink-4'), wash: false),
                      SizedBox(width: t.space(1)),
                      Text(yes ? where : '$where: not yet', style: pageText(t, t.fontSize('sm'), weight: 'medium', color: yes ? t.color('app-ink') : t.color('app-ink-3'))),
                    ],
                  ),
                ),
            ],
          ),
        ]),
        section('What it does', [Text(manifest.description, style: body)]),
        if (manifest.adds.isNotEmpty || settings != null)
          section('What it adds', [
            for (final add in manifest.adds) point(Lucide.sparkles, add, key: ValueKey(add)),
            if (settings != null) point(Lucide.settings, 'A page of its own in Settings', hint: on ? settings.summary() : 'Among Settings’ own pages, once it is added.'),
          ]),
        section('What it may reach', [
          if (manifest.permissions.isEmpty) point(Lucide.shieldCheck, 'Nothing past the note you are in', hint: 'It asks for nothing: what it does happens in the note as you type it.'),
          for (final permission in manifest.permissions)
            point(
              permissionIcon(permission.kind),
              plainPermissionWords[permission.kind]!,
              key: ValueKey(permission.kind),
              hint: permission.kind == Permission.network && manifest.hosts.isNotEmpty ? '${permission.why} It talks to ${joinAnd(manifest.hosts)} and nowhere else.' : permission.why,
            ),
        ]),
        Padding(
          padding: EdgeInsets.only(top: gap * 1.5),
          child: Text('${manifest.category?.label ?? 'Plugin'} · ${manifest.author} · version ${manifest.version}', style: quiet),
        ),
      ],
    );
  }
}

/// Each permission's icon on a plugin's page, and on the website's (lib/market/market_listing.dart).
LucideIcon permissionIcon(Permission kind) => switch (kind) {
      Permission.notes => Lucide.fileText,
      Permission.network => Lucide.globe,
      Permission.ai => Lucide.sparkles,
      Permission.voice => Lucide.mic,
      Permission.native => Lucide.smartphone,
    };
