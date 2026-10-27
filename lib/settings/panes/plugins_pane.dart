import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../plugins/registry.dart';
import '../../plugins/types.dart';
import '../kit/settings_kit.dart';
import 'settings_host.dart';
import '../../claude/claude_mark.dart' show ClaudeMark;
import '../../plugins/lovart/lovart_mark.dart' show LovartMark;
import '../../plugins/elevenlabs/elevenlabs_mark.dart' show ElevenLabsMark;

/// What is left in Settings of its Plugins (Matt, 2026-10-26: "move the plugins section out of the settings (leaving
/// plugin specific settings to own their settings) add the plugins setting to the market page"): the catalogue,
/// Settings › Plugins from 2026-10-18 (a marketplace of its own then, its Added and Discover shelves, its search and
/// its categories, and a page in it for every plugin), is the Market now (lib/market/market_screen.dart), a place
/// of the app's own. What stays is each added plugin's own page, a row of Settings' list
/// (lib/settings/settings_sections.dart `pluginPageSections`), with a word at its foot on where the plugin itself is;
/// and the Market's row on the list, which shuts Settings and opens it ([MarketPane] is only what a link that lands
/// on that row finds, where nothing hands Settings the way out).

/// The Market's row on Settings' list: how many plugins are added (SettingsSheet.tsx said how many were on).
String pluginsSummary(Registry registry) => '${registry.all().where((p) => registry.switchedOn(p.manifest.id)).length} of ${registry.all().length} plugins added';

/// The id of a plugin's own page among the sections of Settings, a row of the list of its own while the plugin is
/// on: `plugin:notion`. Links into Settings land on it by this id (the Claude chat's "Add an API key").
String pluginPageId(String pluginId) => 'plugin:$pluginId';

/// A plugin's icon by the kit's name for it (`GlyphPlugin.icon`), at [size]; the puzzle piece for a name the kit
/// does not draw.
Widget pluginIcon(GlyphPlugin plugin, double size) => switch (plugin.manifest.id) {
      // Claude's and Lovart's own marks as icons, in the icon's one colour (Matt, 2026-10-26: "iconize the lovart logo
      // so we can use their logo in the settings, same with the Claude logo"): a little under the box, as a Lucide
      // glyph's drawing sits inside its 24 with room round it, so the marks weigh what the icons beside them do.
      'claude' => _MarkIcon(size: size, draw: (ink, side) => ClaudeMark(size: side, color: ink)),
      // Lovart's is a solid round, heavier than a line: a step smaller again.
      'lovart' => _MarkIcon(size: size, scale: 0.74, draw: (ink, side) => LovartMark(size: side, color: ink)),
      // ElevenLabs' bars, the plugin's own mark (lib/plugins/elevenlabs/elevenlabs_mark.dart), at the box's whole: two
      // bars are lighter than a Lucide glyph's lines.
      'elevenlabs' => _MarkIcon(size: size, scale: 1, draw: (ink, side) => ElevenLabsMark(size: side, color: ink)),
      _ => AppIcon(Lucide.all[plugin.icon] ?? Lucide.puzzle, size: size),
    };

/// A brand's mark drawn as an icon: [size] square, the mark at [scale] of it, in the colour an icon there would
/// take (the settings row's hue, the text's around it).
class _MarkIcon extends StatelessWidget {
  const _MarkIcon({required this.size, required this.draw, this.scale = 0.84});

  final double size;
  final Widget Function(Color ink, double side) draw;

  /// How much of the box the mark takes.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final ink = IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    return SizedBox.square(dimension: size, child: Center(child: draw(ink, (size * scale).roundToDouble())));
  }
}

/// The page behind the Market's row, for when Settings is landed on it with nowhere to send the person (a Settings
/// drawn by itself): what the Market is, and the way there where the host has one.
class MarketPane extends StatelessWidget {
  const MarketPane({super.key, this.registry, this.onMarket});

  final Registry? registry;
  final VoidCallback? onMarket;

  static Widget hosted(BuildContext context) {
    final market = SettingsHost.maybeOf(context)?.onMarket;
    return MarketPane(onMarket: market == null ? null : () => market());
  }

  @override
  Widget build(BuildContext context) {
    final registry = this.registry ?? plugins;
    return PaneBody(
      children: [
        PaneSection(
          children: [
            PaneHero(
              glyph: const AppIcon(Lucide.store, size: 22),
              title: 'Market',
              meta: Text('Plugins, themes and fonts, a place of their own. ${pluginsSummary(registry)}.'),
            ),
            SettingRow(
              icon: const AppIcon(Lucide.store, size: 16),
              label: 'Open the Market',
              hint: const Text('Add and remove plugins, and try a theme or a font.'),
              onPress: onMarket,
            ),
          ],
        ),
      ],
    );
  }
}

/// A plugin's page in Settings (its `PluginSettings.pane`), with a word at its foot on where the plugin itself is:
/// its page in the Market, which says what it may reach and has the way to remove it.
class PluginSettingsPage extends StatelessWidget {
  const PluginSettingsPage({super.key, required this.plugin});

  final GlyphPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final settings = plugin.settings!;
    final market = SettingsHost.maybeOf(context)?.onMarket;
    final name = plugin.manifest.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        settings.pane(context),
        SizedBox(height: context.tokens.space(4)),
        SettingsFootnote(
          key: const ValueKey('plugin-page-foot'),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$name is a plugin. What it may reach, and the way to remove it, are on '),
                WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('its page in the Market', onPress: market == null ? null : () => market(plugin: plugin.manifest.id))),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
