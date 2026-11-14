/// Settings › Plugins: every plugin with its switch, and under that a card for each one that is on and has settings
/// of its own. The page is a list of the kit's cards and rows like every other section's (lib/ui/settings_panes.dart),
/// so Settings' search finds a plugin, and a plugin's setting, by name.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_kit.dart';
import '../sms.dart';
import '../ui/settings.dart';
import 'plugin.dart';
import 'registry.dart';

/// The plugins' rows for Settings' list: Plugins itself, there once the app has a plugin to switch, and after it a
/// row for each plugin that has a section of its own ([GhostPlugin.settingsPage]), shown while that plugin is on.
List<SettingsSection> pluginsSettings() => PluginRegistry.instance.isEmpty ? const [] : [pluginsSection(), ...pluginPages()];

/// Settings › Plugins, for the app's own plugins or, in a test, for [registry]'s.
SettingsSection pluginsSection([PluginRegistry? registry]) => SettingsSection(
      id: 'plugins',
      label: 'Plugins',
      icon: const AppIcon(Lucide.puzzle, size: 18),
      hue: 'rose',
      group: 'plugins',
      summary: (m) {
        final r = registry ?? PluginRegistry.instance;
        final store = AppStore(m.app);
        final on = [for (final p in r.plugins) if (r.isOn(p, store)) p.name];
        return on.isEmpty ? 'None on' : on.join(' · ');
      },
      page: (context, m) => pluginsPane(context, m.app, registry ?? PluginRegistry.instance),
    );

/// A section of Settings for each plugin that asks for one (Matt, 2026-11-14: "the plugins and all being able to
/// make their own setting sections"): its row is under Plugins while it is on, and its page is its own settings.
List<SettingsSection> pluginPages([PluginRegistry? registry]) {
  final r = registry ?? PluginRegistry.instance;
  return [
    for (final p in r.plugins)
      if (p.settingsPage != null)
        SettingsSection(
          id: 'plugin-${p.id}',
          label: p.settingsPage!.label ?? p.name,
          icon: AppIcon(p.icon, size: 18),
          hue: p.settingsPage!.hue,
          group: 'plugins',
          when: (m) => r.isOn(p, AppStore(m.app)),
          summary: (m) => p.settingsPage!.summary?.call(r.prefsOf(p, AppStore(m.app))) ?? p.description,
          page: (context, m) {
            final store = AppStore(m.app);
            final intro = p.settingsPage!.intro;
            return _own(context, p, r, store, title: null, description: intro);
          },
        ),
  ];
}

List<Widget> pluginsPane(BuildContext context, AppState app, PluginRegistry registry) {
  final store = AppStore(app);
  return [
    PaneSection(
      title: 'Plugins',
      description: Text('Extra things the app can do with your messages. Each one works on this ${Sms.remote ? 'computer' : 'phone'} alone, and does nothing while it is off.'),
      footer: registry.plugins.any((p) => p.settingsPage != null) ? const Text('A plugin with settings of its own has a section of its own in Settings while it is on.') : null,
      children: [
        for (final p in registry.plugins)
          SettingRow(
            icon: AppIcon(p.icon, size: 18),
            label: p.name,
            hint: Text(p.description),
            control: GlacierSwitch(checked: registry.isOn(p, store), onCheckedChange: (on) => registry.setOn(p, store, on), ariaLabel: p.name),
          ),
      ],
    ),
    // A card here for each plugin that is on and keeps its settings on this page.
    for (final p in registry.plugins)
      if (registry.isOn(p, store) && p.settingsPage == null) ..._own(context, p, registry, store, title: p.name),
  ];
}

/// A plugin's own settings as a card: the rows it describes in words ([GhostPlugin.settings]), then what it puts in
/// the settings slot. No card where it has neither.
List<Widget> _own(BuildContext context, GhostPlugin plugin, PluginRegistry registry, PluginStore store, {required String? title, String? description}) {
  final prefs = registry.prefsOf(plugin, store);
  final rows = <Widget>[
    for (final s in registry.settingsOf(plugin))
      SettingRow(
        icon: s.icon == null ? null : AppIcon(s.icon!, size: 18),
        label: s.label,
        hint: s.hint == null ? null : Text(s.hint!),
        control: s.key == null ? null : GlacierSwitch(checked: prefs.flag(s.key!, fallback: s.fallback), onCheckedChange: (on) => prefs.setFlag(s.key!, on), ariaLabel: s.label),
      ),
    ...registry.widgets(Slots.settings, context, const SettingsPlace(), store, only: plugin),
  ];
  return rows.isEmpty ? const [] : [PaneSection(title: title, description: description == null ? null : Text(description), children: rows)];
}
