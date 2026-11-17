/// A plugin on the Plugins page's shelves (Matt, 2026-11-17: "redo how the plugins look with their own dedicated
/// plugins page with a marketplace like look how ghostmd has"), after Ghost.md's Market cards: a row card on a phone,
/// a card with a coloured head standing in a grid with room, and a featured card that is all colour. Each says Add,
/// or that it is added, and opens the plugin's page when pressed.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../kit/settings_type.dart';
import '../../plugins/plugin.dart';
import '../dialup/bevel.dart';
import '../dialup/title_bar.dart';
import 'market_parts.dart';
import 'plugin_art.dart';

/// Add, or that it is added: the end of a plugin's card. [onColour] is on the plugin's own colour (the featured card).
Widget addOrAdded(BuildContext context, GhostPlugin plugin, {required bool added, required VoidCallback onAdd, bool onColour = false}) {
  final t = context.tokens;
  final c = PluginHues.of(t, plugin.hue);
  if (added) return MarketAdded(key: ValueKey('plugins-added-${plugin.id}'), name: plugin.name, color: onColour && !isBevelChrome(t) ? c.on : null);
  return MarketButton(
    key: ValueKey('plugins-add-${plugin.id}'),
    label: 'Add',
    semantics: 'Add ${plugin.name}',
    icon: Lucide.plus,
    look: onColour ? MarketButtonLook.glass : MarketButtonLook.filled,
    color: c.start,
    onColor: c.on,
    onPress: onAdd,
  );
}

/// One plugin on a shelf: its tile, its name, its line, and Add or that it is added; pressed, its page. [wide] is a
/// card standing in a grid, its colour across its head; otherwise a row, a phone's, its tile at its start.
class PluginCard extends StatelessWidget {
  const PluginCard({super.key, required this.plugin, required this.added, required this.onAdd, required this.onOpen, this.wide = false, this.selected = false});

  final GhostPlugin plugin;
  final bool added;
  final VoidCallback onAdd;
  final VoidCallback onOpen;
  final bool wide;

  /// Its page is the one open beside the shelves.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bevel = isBevelChrome(t);
    final ink = bevel ? DialupColors.of(t).onChrome : t.color('app-ink');
    final soft = bevel ? DialupColors.of(t).onChrome : t.color('app-ink-2');
    final name = Text(plugin.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: bevel ? 'bold' : 'semibold', color: ink));
    final line = Text(plugin.tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), height: 1.35, color: soft));
    final end = addOrAdded(context, plugin, added: added, onAdd: onAdd);
    if (!wide || bevel) {
      return MarketCard(
        key: ValueKey('plugins-card-${plugin.id}'),
        onPress: onOpen,
        label: plugin.name,
        selected: selected,
        padding: EdgeInsets.all(t.space(3)),
        child: Row(
          children: [
            PluginTile(plugin: plugin, size: t.lenOf('3.2rem')),
            SizedBox(width: t.space(3)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [name, SizedBox(height: t.lenOf('0.15rem')), line],
              ),
            ),
            SizedBox(width: t.space(2)),
            end,
          ],
        ),
      );
    }
    final c = PluginHues.of(t, plugin.hue);
    final head = t.lenOf('5rem');
    return MarketCard(
      key: ValueKey('plugins-card-${plugin.id}'),
      onPress: onOpen,
      label: plugin.name,
      selected: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The head: the plugin's colour edge to edge, its icon large and faint past the end, and its shelf on it.
          SizedBox(
            height: head,
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: c.gradient),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                fit: StackFit.expand,
                children: [
                  hueGlow(c, radius: 0),
                  // Faint, and mostly past the head's bottom end, clear of its tag.
                  Positioned(right: -head * 0.3, bottom: -head * 0.45, child: AppIcon(plugin.icon, size: head * 1.15, strokeWidth: 1.6, color: c.faint, wash: false)),
                  Positioned(left: t.space(3), bottom: t.space(3), child: AppIcon(plugin.icon, size: head * 0.42, strokeWidth: 2, color: c.on, wash: false)),
                  Positioned(top: t.space(2), right: t.space(2), child: MarketTag(label: plugin.shelf.label, ground: c.tag, ink: c.on, ring: c.tagRing)),
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
                  Align(alignment: AlignmentDirectional.centerEnd, child: end),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plugin at the head of the page: the whole card in its colour, its icon large and faint, its name and line on it,
/// and Add on glass. Under Dial-Up, a small window of its own: its name on a title bar, its line on the silver.
class FeaturedPluginCard extends StatelessWidget {
  const FeaturedPluginCard({super.key, required this.plugin, required this.added, required this.onAdd, required this.onOpen});

  final GhostPlugin plugin;
  final bool added;
  final VoidCallback onAdd;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (isBevelChrome(t)) return _window(context, t);
    final c = PluginHues.of(t, plugin.hue);
    final radius = pluginCorner(t, t.radius('lg') * 1.5);
    return GlacierPressable(
      key: ValueKey('plugins-featured-${plugin.id}'),
      onPressed: onOpen,
      semanticLabel: plugin.name,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: radius,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: state.pressed ? 0.98 : 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: c.gradient),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  hueGlow(c, radius: radius),
                  // Faint, in the empty middle of the card's end and half past it: under the shelf's tag it made the
                  // tag hard to read, and low down it ran under Add.
                  Positioned(right: -t.space(8), top: t.space(12), child: AppIcon(plugin.icon, size: t.lenOf('6rem'), strokeWidth: 1.5, color: c.faint, wash: false)),
                  Padding(
                    padding: EdgeInsets.all(t.space(4)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          GlassChip(plugin: plugin, size: t.lenOf('2.6rem')),
                          const Spacer(),
                          MarketTag(label: plugin.shelf.label, ground: c.tag, ink: c.on, ring: c.tagRing),
                        ]),
                        const Spacer(),
                        Text(plugin.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xl'), weight: 'bold', color: c.on)),
                        SizedBox(height: t.lenOf('0.1rem')),
                        // Its pitch, written to be whole in three lines (four where three cards share a narrowed shelf): the tagline cut off mid-word hid what it does.
                        Text(plugin.pitch, maxLines: 4, overflow: TextOverflow.fade, style: pageText(t, t.fontSize('sm'), height: 1.3, color: c.on.withValues(alpha: 0.92))),
                        SizedBox(height: t.space(3)),
                        Align(alignment: AlignmentDirectional.centerEnd, child: addOrAdded(context, plugin, added: added, onAdd: onAdd, onColour: true)),
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

  Widget _window(BuildContext context, Tokens t) {
    final c = DialupColors.of(t);
    return GlacierPressable(
      key: ValueKey('plugins-featured-${plugin.id}'),
      onPressed: onOpen,
      semanticLabel: plugin.name,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: 0,
        child: Bevel(
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitleBar(title: plugin.name, leading: AppIcon(plugin.icon, size: 16, strokeWidth: 2.2, color: c.titlebarInk, wash: false)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        PluginTile(plugin: plugin, size: 40),
                        const SizedBox(width: 10),
                        Expanded(child: Text(plugin.shelf.label, style: pageText(t, 13, color: c.onChrome))),
                      ]),
                      const SizedBox(height: 8),
                      Expanded(child: Text(plugin.pitch, maxLines: 3, overflow: TextOverflow.fade, style: pageText(t, 14, height: 1.3, color: c.onChrome))),
                      Align(alignment: AlignmentDirectional.centerEnd, child: addOrAdded(context, plugin, added: added, onAdd: onAdd)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
