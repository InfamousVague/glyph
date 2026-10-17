import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../calendar/calendar.dart' show calendar;
import '../../core/preferences.dart';
import '../../plugins/reach.dart';
import '../../plugins/registry.dart';
import '../../plugins/types.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'calendar_pane.dart' show calendarSummary;
import 'settings_host.dart';

/// What Settings' search finds on Plugins (`findable`, src/app/plugins/PluginsPane.findable.ts): every plugin, on
/// or off, by its name and what it does, since a card is the way to switch on one that is off. A plugin's own page
/// is a sub-page behind its card, with its own list on its `settings` (lib/plugins/types.dart).
List<SettingsFindable> pluginsFindable(Iterable<GlyphPlugin> all) => [for (final plugin in all) SettingsFindable(plugin.manifest.name, plugin.manifest.description)];

/// Plugins' row in the list of sections: how many are on (SettingsSheet.tsx).
String pluginsSummary(Registry registry) => '${registry.enabled().length} of ${registry.all().length} on';

/// The id of a plugin's own page among the sections of Settings: `plugin:notion`.
String pluginPageId(String pluginId) => 'plugin:$pluginId';

/// A plugin's icon by the kit's name for it (`GlyphPlugin.icon`), at [size]; the puzzle piece for a name the kit
/// does not draw.
Widget pluginIcon(GlyphPlugin plugin, double size) => AppIcon(Lucide.all[plugin.icon] ?? Lucide.puzzle, size: size);

/// Port of `PluginsPane` (src/app/plugins/PluginsPane.tsx): Settings > Plugins, every plugin in this build, one
/// card each.
///
/// A card leads with the plugin as a thing (its icon, its name, one line on what it does) and its switch, then the
/// way to its own page when it has one and is on, then what it may reach, said in one line with the reasons a press
/// away. A plugin switched off offers nothing anywhere (its page here, its rows on a note's cog, its swipe, its tips
/// in a pause, its context for the formatter) and keeps its data, so switching it on again brings it back as it was.
///
/// Local only (Settings › Account › Privacy) holds every plugin that uses the internet off, whatever its switch
/// says (lib/plugins/registry.dart); the page says so at the top and on each card it holds, and "Local only" there
/// is a word that opens Account at the Privacy card. A plugin's own page is a sub-page of this one, behind its card,
/// and back from it comes here.
///
/// What differs from the web original:
/// - The registry is handed in ([registry]) and is the app's ([plugins]) when none is: the page reads it as a
///   [Listenable], where the web read `usePlugins()`. Local only is read from [prefs], the app's preferences when
///   none are given.
/// - "Built-in app commands" is still what a plugin that keeps a secret says it reaches, as the web's manifests say
///   it, though the keeping is the device's secure store here and not a command (lib/plugins/types.dart).
class PluginsPane extends StatelessWidget {
  const PluginsPane({super.key, this.registry, this.onOpen, this.prefs});

  /// The plugins drawn; the app's when null.
  final Registry? registry;

  /// Lands on a page of Settings: a plugin's own page, or Account at the Privacy card for "Local only".
  final void Function(String id, {String? setting})? onOpen;

  /// Where Local only is read; the app's preferences when null.
  final ValueNotifier<Preferences>? prefs;

  static Widget hosted(BuildContext context) => PluginsPane(onOpen: SettingsHost.maybeOf(context)?.go);

  @override
  Widget build(BuildContext context) {
    final registry = this.registry ?? plugins;
    final prefs = this.prefs ?? preferences;
    final open = onOpen;
    // Account's Privacy card, where Local only is switched (`LOCAL_ONLY`).
    final toLocalOnly = open == null ? null : () => open('account', setting: 'Privacy');
    return ListenableBuilder(
      listenable: Listenable.merge([registry, prefs]),
      builder: (context, _) {
        final all = registry.all();
        final enabled = registry.enabled();
        final localOnly = prefs.value.localOnly;
        return PaneBody(
          children: [
            PaneSection(
              children: [
                PaneHero(
                  glyph: const AppIcon(Lucide.puzzle, size: 22),
                  title: 'Plugins',
                  meta: Text(
                    '${enabled.length} of ${all.length} on. Each reaches only what its card says. One switched off offers nothing anywhere, not its rows, its commands or its page, until it is on again, and keeps what it kept.',
                  ),
                ),
              ],
            ),
            if (localOnly)
              SettingsCallout(
                child: Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Local only', onPress: toLocalOnly)),
                      const TextSpan(text: ' is on, so plugins that use the internet are held off until it is off.'),
                    ],
                  ),
                ),
              ),
            for (final plugin in all)
              PluginCard(
                key: ValueKey(plugin.manifest.id),
                plugin: plugin,
                on: enabled.contains(plugin),
                held: localOnly && usesNetwork(plugin.manifest),
                onChange: (on) => registry.setEnabled(plugin.manifest.id, on),
                onLocalOnly: toLocalOnly,
                onOpenPage: open == null ? null : () => open(pluginPageId(plugin.manifest.id)),
              ),
            const SettingsFootnote(
              child: Text('Plugins ship inside Ghost.md and update with it. There is nothing to install, and nothing here reaches anywhere its card does not say.'),
            ),
            // The calendars (docs/CALENDAR.md): built in, not a plugin, and their page is behind this one. Drawn where the
            // app reads calendars at all, which is once its root has started them (lib/root/ghost_root.dart).
            if (open != null && calendar.started)
              PaneSection(
                title: 'Calendar',
                children: [
                  SettingRow(
                    key: const ValueKey('plugins-calendar'),
                    icon: const AppIcon(Lucide.calendarDays, size: 20),
                    label: 'Calendars',
                    hint: Text(calendarSummary(prefs.value)),
                    onPress: () => open('calendar'),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

/// One plugin's card (`PluginCard`).
class PluginCard extends StatefulWidget {
  const PluginCard({super.key, required this.plugin, required this.on, required this.held, required this.onChange, this.onLocalOnly, this.onOpenPage});

  final GlyphPlugin plugin;
  final bool on;

  /// Held off by Local only, whatever the switch says.
  final bool held;
  final ValueChanged<bool> onChange;

  /// Opens Account at the Privacy card, for "Local only".
  final VoidCallback? onLocalOnly;

  /// Opens the plugin's own page.
  final VoidCallback? onOpenPage;

  @override
  State<PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<PluginCard> {
  /// Whether the reasons are shown under what it may reach.
  bool _why = false;

  @override
  Widget build(BuildContext context) {
    final plugin = widget.plugin;
    final manifest = plugin.manifest;
    final settings = plugin.settings;
    final on = widget.on && !widget.held;
    final reach = reachLine(manifest);
    return PaneSection(
      footer: Text('${manifest.standard ? 'Ships with Ghost.md' : manifest.author} · version ${manifest.version}'),
      children: [
        PaneHero(
          glyph: pluginIcon(plugin, 22),
          title: manifest.name,
          meta: Text(manifest.description),
          // `.setk-hero__trailing` is a line of the page's text with the switch standing on it: 28px for the switch's
          // 26, so the switch is a pixel above the hero's middle (measured).
          trailing: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: GlacierSwitch(ariaLabel: '${manifest.name} plugin', checked: on, onCheckedChange: widget.onChange, disabled: widget.held),
          ),
        ),
        if (widget.held)
          SettingRow(
            label: 'Off while Local only is on',
            hint: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'It uses the internet. Switch '),
                  WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Local only', onPress: widget.onLocalOnly)),
                  const TextSpan(text: ' off to use it.'),
                ],
              ),
            ),
          ),
        if (on && settings != null && widget.onOpenPage != null)
          SettingRow(icon: pluginIcon(plugin, 16), label: settings.summary(), hint: Text('${manifest.name}’s own page: what it keeps, and how it is set.'), onPress: widget.onOpenPage),
        SettingRow(
          label: 'What it may reach',
          // A plugin that reaches nothing (Marks) has no line under the label, not an empty one.
          hint: reach.isEmpty ? null : Text(reach),
          control: RowAction(onPress: () => setState(() => _why = !_why), child: Text(_why ? 'Less' : 'Why')),
        ),
        if (_why)
          for (final permission in manifest.permissions) SettingRow(key: ValueKey(permission.kind), label: permissionWords[permission.kind]!, hint: Text(permission.why)),
      ],
    );
  }
}
