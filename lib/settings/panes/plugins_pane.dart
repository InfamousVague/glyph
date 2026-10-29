import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../plugins/registry.dart';
import '../../plugins/types.dart';
import '../kit/settings_kit.dart';
import 'settings_host.dart';
import '../../plugins/brands.dart' show pluginGlyph;

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

/// A plugin's icon on Settings' list, at [size], in the row's ink: its company's mark where it wears one (Matt,
/// 2026-10-29: "Iconize real company logos for openAI todoist, GitHub, Google meets, zoom etc and use those for the
/// plugin icons"; lib/plugins/brands.dart), else its glyph by the kit's name for it, the puzzle piece for a name the
/// kit does not draw. Claude's and Lovart's were marks of their own here from 2026-10-26 ("iconize the lovart logo so
/// we can use their logo in the settings, same with the Claude logo"); they are two of the brands now.
Widget pluginIcon(GlyphPlugin plugin, double size) => pluginGlyph(plugin, size);

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
