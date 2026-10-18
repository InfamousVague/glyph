import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/preferences.dart';
import '../../plugins/catalogue.dart';
import '../../plugins/reach.dart';
import '../../plugins/registry.dart';
import '../../plugins/types.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../settings_search.dart';
import 'settings_host.dart';

/// What Settings' search finds on Plugins: its shelves, where they are drawn. A plugin itself is found by its own
/// name on its own page: its detail page in the catalogue ([pluginInfoId]) while it is not added, or has no page of
/// its own, and its page in Settings ([pluginPageId]) once it is (lib/settings/settings_sections.dart).
List<SettingsFindable> pluginsFindable(Registry registry) {
  final all = registry.all();
  return [
    if (all.any((p) => registry.switchedOn(p.manifest.id))) const SettingsFindable('Added', 'installed on switched on enabled mine'),
    if (all.any((p) => !registry.switchedOn(p.manifest.id))) const SettingsFindable('Discover', 'browse more new add install marketplace catalogue store'),
  ];
}

/// What Settings' search finds on a plugin's page in the catalogue: its cards' titles.
List<SettingsFindable> pluginInfoFindable(GlyphPlugin plugin) => [
      const SettingsFindable('What it does', 'about description'),
      if (plugin.manifest.adds.isNotEmpty || plugin.settings != null) const SettingsFindable('What it adds', 'features gives'),
      const SettingsFindable('What it may reach', 'permissions privacy internet notes phone hosts'),
    ];

/// Plugins' row in the list of sections: how many are added (SettingsSheet.tsx said how many were on).
String pluginsSummary(Registry registry) => '${registry.all().where((p) => registry.switchedOn(p.manifest.id)).length} of ${registry.all().length} added';

/// The id of a plugin's own page among the sections of Settings, a row of the list of its own while the plugin is
/// on: `plugin:notion`. Links into Settings land on it by this id (the Claude chat's "Add an API key").
String pluginPageId(String pluginId) => 'plugin:$pluginId';

/// The id of a plugin's page in the catalogue, a sub-page of Plugins for every plugin, added or not:
/// `plugins/notion`.
String pluginInfoId(String pluginId) => 'plugins/$pluginId';

/// A plugin's icon by the kit's name for it (`GlyphPlugin.icon`), at [size]; the puzzle piece for a name the kit
/// does not draw.
Widget pluginIcon(GlyphPlugin plugin, double size) => AppIcon(Lucide.all[plugin.icon] ?? Lucide.puzzle, size: size);

/// The narrowest a card of the catalogue is drawn, which is how many stand across: one on a phone, two or three on
/// a Fold, a tablet or the Mac.
const double _cardMin = 260;

/// Settings › Plugins, a catalogue of every plugin in this build to browse (Matt, 2026-10-18: "rework the plugins
/// page to be a marketplace, also move plugin settings to their own page under settings").
///
/// It opens on what it is (how many are added, of how many), the way to find one (a search, and a filter by
/// category: AI, Calendar & tasks, Import, Connections, Editor; lib/plugins/catalogue.dart), then two shelves: Added,
/// what this device has switched on, and Discover, the rest. A card is a plugin at a glance: its icon, its name, a
/// line on what it is (`PluginManifest.tagline`) and one on what it uses, in plain words ("Uses your notes and the
/// internet"), and at its end Add, or that it is added. Add is the switch: there is nothing to download, since every
/// plugin ships inside the app. Pressing the card opens its page in the catalogue ([PluginInfoPane]): what it does,
/// what it adds, what it may reach and why, Add or Remove, and the way to its settings once it is added. Where there
/// is room the cards stand two or three across; on a phone, one to a row.
///
/// A plugin's settings are no longer behind its card: each added plugin with a page has a row of its own in
/// Settings' list, among the Plugins card's rows (settings_sections.dart `pluginPageSections`).
///
/// Local only (Settings › Account › Privacy) holds every plugin that uses the internet off, whatever its switch
/// says (lib/plugins/registry.dart); the page says so at the top, and a card it holds says so and cannot be added
/// until it is off. A plugin added and then held stays on the Added shelf, saying why it does nothing.
///
/// What differs from the web original (src/app/plugins/PluginsPane.tsx), which this was a port of until then: the
/// web's page is a card a plugin, each with its switch and its reasons, in the registry's order, and the cards'
/// rects were held to the web's measured ones. This page is the app's own, and the web's has not followed it.
class PluginsPane extends StatefulWidget {
  const PluginsPane({super.key, this.registry, this.onOpen, this.prefs});

  /// The plugins drawn; the app's when null.
  final Registry? registry;

  /// Lands on a page of Settings: a plugin's page in the catalogue, or Account at the Privacy card for "Local only".
  final void Function(String id, {String? setting})? onOpen;

  /// Where Local only is read; the app's preferences when null.
  final ValueNotifier<Preferences>? prefs;

  static Widget hosted(BuildContext context) => PluginsPane(onOpen: SettingsHost.maybeOf(context)?.go);

  @override
  State<PluginsPane> createState() => _PluginsPaneState();
}

class _PluginsPaneState extends State<PluginsPane> {
  String _query = '';

  /// The category chosen; null is All.
  PluginCategory? _category;

  @override
  Widget build(BuildContext context) {
    final registry = widget.registry ?? plugins;
    final prefs = widget.prefs ?? preferences;
    final open = widget.onOpen;
    final toLocalOnly = open == null ? null : () => open('account', setting: 'Privacy');
    return ListenableBuilder(
      listenable: Listenable.merge([registry, prefs]),
      builder: (context, _) {
        final all = catalogueOrder(registry.all());
        final localOnly = prefs.value.localOnly;
        final categories = categoriesOf(all);
        // A category the build has none of any more (a test's registry) is All.
        final category = categories.contains(_category) ? _category : null;
        final shown = [
          for (final plugin in all)
            if (inCatalogue(plugin, query: _query, category: category)) plugin,
        ];
        final added = [
          for (final plugin in shown)
            if (registry.switchedOn(plugin.manifest.id)) plugin,
        ];
        final discover = [
          for (final plugin in shown)
            if (!registry.switchedOn(plugin.manifest.id)) plugin,
        ];
        final count = all.where((p) => registry.switchedOn(p.manifest.id)).length;

        PluginCard card(GlyphPlugin plugin) {
          final id = plugin.manifest.id;
          final held = localOnly && usesNetwork(plugin.manifest);
          return PluginCard(
            key: ValueKey(id),
            plugin: plugin,
            added: registry.switchedOn(id),
            held: held,
            onAdd: held ? null : () => registry.setEnabled(id, true),
            onOpen: open == null ? null : () => open(pluginInfoId(id)),
            onLocalOnly: toLocalOnly,
          );
        }

        return PaneBody(
          children: [
            PaneSection(
              children: [
                PaneHero(
                  glyph: const AppIcon(Lucide.puzzle, size: 22),
                  title: 'Plugins',
                  meta: Text('$count of ${all.length} added. Every one is built in: adding one is a switch, and removing one keeps what it kept.'),
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
            PaneSection(
              children: [
                SettingRowBox(
                  child: _Find(
                    query: _query,
                    onQuery: (query) => setState(() => _query = query),
                    categories: categories,
                    category: category,
                    onCategory: (chosen) => setState(() => _category = chosen),
                  ),
                ),
              ],
            ),
            if (added.isNotEmpty) PluginShelf(key: const ValueKey('shelf added'), title: 'Added', cards: [for (final plugin in added) card(plugin)]),
            if (discover.isNotEmpty) PluginShelf(key: const ValueKey('shelf discover'), title: 'Discover', cards: [for (final plugin in discover) card(plugin)]),
            if (shown.isEmpty)
              SettingsEmpty(
                icon: const AppIcon(Lucide.search, size: 20),
                title: 'No plugin matches',
                body: Text(_query.trim().isEmpty ? 'There is no plugin in ${category?.label ?? 'this build'}.' : 'Nothing ${category == null ? '' : 'in ${category.label} '}matches “${_query.trim()}”.'),
                action: SettingsEmptyAction('Show every plugin', () => setState(() {
                      _query = '';
                      _category = null;
                    })),
              ),
            const SettingsFootnote(
              child: Text('Plugins ship inside Ghost.md and update with it. There is nothing to download, and none reaches anywhere its page does not say.'),
            ),
          ],
        );
      },
    );
  }
}

/// The search and the categories, on a card of their own over the shelves.
class _Find extends StatelessWidget {
  const _Find({required this.query, required this.onQuery, required this.categories, required this.category, required this.onCategory});

  final String query;
  final ValueChanged<String> onQuery;
  final List<PluginCategory> categories;
  final PluginCategory? category;
  final ValueChanged<PluginCategory?> onCategory;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GlacierSearchField(key: const ValueKey('plugins-find'), value: query, onValueChange: onQuery, placeholder: 'Find a plugin', ariaLabel: 'Find a plugin', size: GlacierFieldSize.sm),
        SizedBox(height: t.space(3)),
        // `role="radiogroup"`: one category at a time, All first.
        Semantics(
          container: true,
          label: 'Categories',
          child: Wrap(
            spacing: t.space(2),
            runSpacing: t.space(2),
            children: [
              CategoryChip(label: 'All', chosen: category == null, onPress: () => onCategory(null)),
              for (final each in categories) CategoryChip(label: each.label, chosen: category == each, onPress: () => onCategory(each)),
            ],
          ),
        ),
      ],
    );
  }
}

/// One category in the catalogue's filter: a capsule with its word, inked when it is the one chosen (the home page's
/// chip, lib/home/home_filters.dart, without its cross).
class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.label, required this.chosen, required this.onPress});

  final String label;
  final bool chosen;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
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
            color: chosen
                ? t.colorOf('color-mix(in oklch, var(--app-ink) 10%, transparent)')
                : state.pressed
                    ? t.color('app-paper-3')
                    : const Color(0x00000000),
            border: Border.all(color: chosen ? t.colorOf('color-mix(in oklch, var(--app-ink) 55%, transparent)') : t.color('app-rule'), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('full')),
          ),
          // As wide as its word, the word in the middle of the capsule's height.
          child: Align(
            widthFactor: 1,
            child: ExcludeSemantics(
              child: Text(label, style: pageText(t, sm, weight: 'medium', color: chosen ? t.color('app-ink') : t.color('app-ink-2'))),
            ),
          ),
        ),
      ),
    );
  }
}

/// A shelf of the catalogue: its caption, as a card's title is drawn (`.setk__title`), over its cards, as many
/// across as the room has for [_cardMin] each, the cards of a line all as tall as its tallest.
class PluginShelf extends StatelessWidget {
  const PluginShelf({super.key, required this.title, required this.cards});

  final String title;
  final List<Widget> cards;

  /// How many cards stand across [width], [gap] between them: one, two or three.
  static int across(double width, double gap) => math.max(1, math.min(3, ((width + gap) / (_cardMin + gap)).floor()));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(3);
    final titleSize = t.lenOf('0.72rem');
    final shelf = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(2)),
          child: Semantics(
            header: true,
            label: title,
            child: ExcludeSemantics(
              child: Text(title.toUpperCase(), style: pageText(t, titleSize, weight: 'semibold', color: t.color('app-ink-3'), tracking: t.len('app-tracking-caps', em: titleSize))),
            ),
          ),
        ),
        SizedBox(height: t.space(2)),
        LayoutBuilder(
          builder: (context, box) {
            final n = across(box.maxWidth, gap);
            if (n == 1) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[if (i > 0) SizedBox(height: gap), cards[i]],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var row = 0; row * n < cards.length; row++) ...[
                  if (row > 0) SizedBox(height: gap),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < n; i++) ...[
                          if (i > 0) SizedBox(width: gap),
                          Expanded(child: row * n + i < cards.length ? cards[row * n + i] : const SizedBox.shrink()),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
    final marked = SettingsFindableMark(name: title, child: shelf);
    return SettingsPaneScope.maybeOf(context) == null ? marked : SettingsRise(child: marked);
  }
}

/// One plugin in the catalogue: its icon, name and line, what it uses, and Add, or that it is added; pressed, its
/// page in the catalogue.
class PluginCard extends StatelessWidget {
  const PluginCard({super.key, required this.plugin, required this.added, required this.held, this.onAdd, this.onOpen, this.onLocalOnly});

  final GlyphPlugin plugin;

  /// Switched on here, held off or not.
  final bool added;

  /// Held off by Local only, whatever the switch says.
  final bool held;

  /// Adds it; null where it cannot be added now (held by Local only).
  final VoidCallback? onAdd;

  /// Opens its page in the catalogue; null where the page is drawn outside Settings.
  final VoidCallback? onOpen;

  /// Opens Account at the Privacy card, for "Local only".
  final VoidCallback? onLocalOnly;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final manifest = plugin.manifest;
    final gap = t.space(3);
    final xs = t.fontSize('xs');
    final quiet = pageText(t, xs, color: t.color('app-ink-3'));
    final Widget trailing = added
        ? Semantics(
            label: '${manifest.name} added',
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [AppIcon(Lucide.check, size: 14, color: t.color('app-ink-3')), SizedBox(width: t.space(1)), Text('Added', style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-3')))],
              ),
            ),
          )
        : RowAction(onPress: onAdd ?? () {}, disabled: onAdd == null, child: Text('Add', semanticsLabel: 'Add ${manifest.name}'));
    return ClipRRect(
      borderRadius: BorderRadius.circular(t.radius('lg')),
      child: ColoredBox(
        color: t.color('app-paper-2'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            PaneHero(
              glyph: pluginIcon(plugin, 22),
              title: manifest.name,
              meta: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(manifest.line),
                  SizedBox(height: t.lenOf('0.15rem')),
                  Text(usesLine(manifest), key: const ValueKey('plugin-uses'), style: quiet),
                ],
              ),
              trailing: trailing,
              onPress: onOpen,
            ),
            if (held)
              Padding(
                padding: EdgeInsets.fromLTRB(gap, 0, gap, gap),
                child: DefaultTextStyle(
                  style: pageText(t, t.fontSize('sm'), height: t.len('glacier-leading-sm'), color: t.color('app-ink-2')),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Off while '),
                        WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Local only', onPress: onLocalOnly)),
                        const TextSpan(text: ' is on: it uses the internet.'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A plugin's page in the catalogue, Settings › Plugins › its name: what it is, Add or Remove, the way to its
/// settings once it is added, what it does and adds, and what it may reach, each permission with the plugin's own
/// reason and, for the internet, the hosts it talks to and no others (lib/plugins/host.dart holds it to them).
///
/// Removing a plugin keeps its data, as the registry does: added again, it is as it was.
class PluginInfoPane extends StatelessWidget {
  const PluginInfoPane({super.key, required this.plugin, this.registry, this.onOpen, this.prefs});

  final GlyphPlugin plugin;

  /// The registry it is switched in; the app's when null.
  final Registry? registry;

  /// Lands on a page of Settings: the plugin's settings, or Account at the Privacy card.
  final void Function(String id, {String? setting})? onOpen;

  /// Where Local only is read; the app's preferences when null.
  final ValueNotifier<Preferences>? prefs;

  static Widget hosted(BuildContext context, GlyphPlugin plugin) => PluginInfoPane(plugin: plugin, onOpen: SettingsHost.maybeOf(context)?.go);

  @override
  Widget build(BuildContext context) {
    final registry = this.registry ?? plugins;
    final prefs = this.prefs ?? preferences;
    final open = onOpen;
    final manifest = plugin.manifest;
    final settings = plugin.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([registry, prefs]),
      builder: (context, _) {
        final id = manifest.id;
        final added = registry.switchedOn(id);
        final held = prefs.value.localOnly && usesNetwork(manifest);
        final on = registry.isEnabled(id);
        final toLocalOnly = open == null ? null : () => open('account', setting: 'Privacy');
        return PaneBody(
          children: [
            PaneSection(
              children: [
                PaneHero(
                  glyph: pluginIcon(plugin, 22),
                  title: manifest.name,
                  meta: Text(manifest.line),
                  status: PaneHeroStatus(held ? 'Held off by Local only' : (added ? 'Added' : 'Not added')),
                ),
                SettingRow(
                  label: added ? 'Added to Ghost.md' : 'Not added',
                  hint: Text(added ? 'Removed, it offers nothing anywhere until it is added again, and keeps what it kept.' : 'Adding it is a switch: it ships inside the app, so there is nothing to download.'),
                  control: RowAction(
                    onPress: () => registry.setEnabled(id, !added),
                    disabled: held,
                    child: Text(added ? 'Remove' : 'Add', semanticsLabel: '${added ? 'Remove' : 'Add'} ${manifest.name}'),
                  ),
                ),
                if (held)
                  SettingRow(
                    label: 'Off while Local only is on',
                    hint: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'It uses the internet. Switch '),
                          WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Local only', onPress: toLocalOnly)),
                          const TextSpan(text: ' off to use it.'),
                        ],
                      ),
                    ),
                  ),
                if (on && settings != null && open != null)
                  SettingRow(icon: pluginIcon(plugin, 16), label: 'Settings', hint: Text(settings.summary()), onPress: () => open(pluginPageId(id))),
              ],
            ),
            PaneSection(
              title: 'What it does',
              children: [SettingRowBox(child: Text(manifest.description, style: pageText(context.tokens, context.tokens.fontSize('md'))))],
            ),
            if (manifest.adds.isNotEmpty || settings != null)
              PaneSection(
                title: 'What it adds',
                children: [
                  for (final add in manifest.adds) SettingRow(key: ValueKey(add), label: add),
                  if (settings != null) SettingRow(label: 'A page of its own in Settings', hint: Text(on ? settings.summary() : 'Among Settings’ own pages, once it is added.')),
                ],
              ),
            PaneSection(
              title: 'What it may reach',
              footer: Text('${manifest.category?.label ?? 'Plugin'} · ${manifest.author} · version ${manifest.version}'),
              children: [
                if (manifest.permissions.isEmpty)
                  const SettingRow(label: 'Nothing past the note you are in', hint: Text('It asks for nothing: what it does happens in the note as you type it.')),
                for (final permission in manifest.permissions)
                  SettingRow(
                    key: ValueKey(permission.kind),
                    icon: AppIcon(_permissionIcon(permission.kind), size: 16),
                    label: plainPermissionWords[permission.kind]!,
                    hint: Text(permission.kind == Permission.network && manifest.hosts.isNotEmpty ? '${permission.why} It talks to ${joinAnd(manifest.hosts)} and nowhere else.' : permission.why),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

LucideIcon _permissionIcon(Permission kind) => switch (kind) {
      Permission.notes => Lucide.fileText,
      Permission.network => Lucide.globe,
      Permission.ai => Lucide.sparkles,
      Permission.voice => Lucide.mic,
      Permission.native => Lucide.smartphone,
    };

/// A plugin's page in Settings (its `PluginSettings.pane`), with a word at its foot on where the plugin itself is:
/// its page in the catalogue, which says what it may reach and has the way to remove it.
class PluginSettingsPage extends StatelessWidget {
  const PluginSettingsPage({super.key, required this.plugin});

  final GlyphPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final settings = plugin.settings!;
    final host = SettingsHost.maybeOf(context);
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
                WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('its page in Plugins', onPress: host == null ? null : () => host.go(pluginInfoId(plugin.manifest.id)))),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
