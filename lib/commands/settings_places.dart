/// What the command bar finds in Settings and among the plugins (Matt, 2026-10-29: "Add the ability to search settings
/// and plugins from the command search"): every page of Settings and every setting on one, every plugin Ghost.md
/// carries, and each added plugin's own settings, offered under Settings and Plugins after the notes and the commands
/// (palette.dart).
///
/// Nothing here is a second list of the settings. The index is Settings' own table (lib/settings/settings_sections.dart
/// `settingsSections`) read with the facts Settings itself reads (lib/settings/settings_sheet.dart
/// `settingsFactsFor`): each page that is among the sections just now, its line, its words, and what its search finds
/// on it, by the names the page draws ([SettingsFindable], each page's own list beside it, held to the page by
/// test/settings/panes/panes_test.dart and test/commands/settings_places_test.dart). So a page Simple puts away, the
/// developer's pages while they are locked, and a plugin's page while it is not added are not found here either, and
/// what is found is matched as Settings' search matches it (lib/settings/settings_search.dart `searchSettings`: every
/// word typed starting a word of the name, the line or the words, in any case and with or without its accents).
///
/// The plugins are the registry's, in the catalogue's order, found as the Market finds them (lib/market/market_items.dart
/// `pluginFound`), each saying whether it is added. A plugin's own page in Settings is its row's, so the page is not
/// offered twice; a setting on that page is, with the plugin's name beside it. A plugin added whose setup is not done
/// has a second row, Set up, since the palette has one press to a row.
///
/// Choosing one: a page or a setting opens Settings there, the setting brought into view and lit, as Settings' own
/// search opens one, and a More that keeps it out of sight in Simple opens in place for it
/// (lib/settings/kit/settings_kit.dart `settingsSought`). A plugin with a page in Settings opens that page; one without,
/// or not added, its page in the Market (Advanced's; in Simple only the plugins whose page Simple keeps are offered).
/// Set up opens the plugin's page with its setup over it.
library;

import 'package:flutter/foundation.dart';

import '../market/market_items.dart' show pluginFound;
import '../plugins/catalogue.dart' show catalogueOrder;
import '../plugins/onboarding/setup_card.dart' show setupFindableName;
import '../plugins/registry.dart' show Registry;
import '../plugins/types.dart' show GlyphPlugin;
import '../settings/panes/plugins_pane.dart' show pluginPageId;
import '../settings/settings_search.dart';
import '../settings/settings_sections.dart';

/// One page of Settings as the search reads it, as it stands.
@immutable
class IndexedSection implements SearchableSection {
  const IndexedSection({required this.id, required this.label, this.summary, this.words, this.settings = const [], this.parent});

  @override
  final String id;
  @override
  final String label;
  @override
  final String? summary;
  @override
  final String? words;
  @override
  final List<SettingsFindable> settings;

  /// The page it is opened from, for a sub-page.
  final String? parent;

  @override
  bool get searched => true;

  /// The plugin whose own page this is, or null for one of Settings' own.
  String? get plugin => id.startsWith('plugin:') ? id.substring('plugin:'.length) : null;
}

/// A plugin as the bar offers it.
@immutable
class IndexedPlugin {
  const IndexedPlugin({required this.plugin, required this.added, required this.on, required this.page, this.setUp});

  final GlyphPlugin plugin;

  /// Added, as its switch is set ([Registry.switchedOn]); [on] says whether it is at work, which Local only may hold off.
  final bool added;
  final bool on;

  /// Whether it has a page in Settings just now: where its row goes.
  final bool page;

  /// The name of its setup, where it is added, has a page, and still needs setting up: its Set up row.
  final String? setUp;

  String get id => plugin.manifest.id;
  String get name => plugin.manifest.name;
}

/// Everything the bar can find of Settings and the plugins, as they stand ([settingsIndex]).
@immutable
class SettingsIndex {
  const SettingsIndex({this.sections = const [], this.plugins = const []});

  final List<IndexedSection> sections;
  final List<IndexedPlugin> plugins;
}

/// The plugins whose setup has read the stores its keys are in (`PluginSetup.prepare`), so whether it is done can be
/// trusted: a setup asked before its keys are read would say it is needed. Read once per run of the app, the first
/// time the bar's index is made, as a plugin's page reads them when it is put up (setup_card.dart).
final Set<String> _prepared = {};
final Set<String> _preparing = {};

/// The index for [facts]: each section of [specs] (Settings' own table unless a test gives one) that is among the
/// sections for these facts, and each plugin of [registry]. The Market's row is left out, the palette having its own
/// Market. In Simple only the plugins whose page Simple keeps are in it, Simple having no Market.
SettingsIndex settingsIndex(SettingsFacts facts, {required Registry registry, List<SettingsSectionSpec>? specs}) {
  final sections = [
    for (final spec in specs ?? settingsSections)
      if ((spec.where?.call(facts) ?? true) && spec.searched && spec.id != marketSectionId)
        IndexedSection(id: spec.id, label: spec.label, summary: spec.summary?.call(facts), words: spec.words, settings: spec.settings?.call(facts) ?? const [], parent: spec.parent),
  ];
  final pages = {for (final section in sections) section.id};
  final plugins = <IndexedPlugin>[];
  for (final plugin in catalogueOrder(registry.all())) {
    final id = plugin.manifest.id;
    final page = pages.contains(pluginPageId(id));
    // Simple has no Market: a plugin is offered there only by the page Simple keeps for it.
    if (facts.simple && !page) continue;
    final added = registry.switchedOn(id);
    plugins.add(IndexedPlugin(plugin: plugin, added: added, on: registry.isEnabled(id), page: page, setUp: page ? _stillToSetUp(plugin) : null));
  }
  return SettingsIndex(sections: sections, plugins: plugins);
}

/// The name of [plugin]'s setup while it still needs doing, once its keys have been read; null otherwise.
String? _stillToSetUp(GlyphPlugin plugin) {
  final made = plugin.setup;
  if (made == null) return null;
  final setup = made();
  final id = plugin.manifest.id;
  final prepare = setup.prepare;
  if (prepare != null && !_prepared.contains(id)) {
    if (_preparing.add(id)) {
      prepare().then((_) => _prepared.add(id), onError: (Object _) => _prepared.add(id)).whenComplete(() => _preparing.remove(id));
    }
    return null;
  }
  return setup.ready() ? null : setup.name;
}

/// Forgets which setups have read their keys, for a test.
@visibleForTesting
void forgetPreparedSetups() {
  _prepared.clear();
  _preparing.clear();
}

/// What a found thing is.
enum SettingsPlaceKind {
  /// A page of Settings.
  page,

  /// A setting on one.
  setting,

  /// A plugin.
  plugin,

  /// A setting on a plugin's own page.
  pluginSetting,

  /// An added plugin's setup, not done.
  setUp,
}

/// One thing found ([findPlaces]), and where choosing it goes.
@immutable
class SettingsPlace {
  const SettingsPlace({required this.kind, required this.id, required this.label, this.detail, this.words = const [], this.page, this.setting, this.plugin});

  final SettingsPlaceKind kind;

  /// Its row's id in the palette: `find:settings:<page>`, `find:settings:<page>/<setting>`, `find:plugin:<id>`,
  /// `find:plugin:<id>/<setting>`, `find:setup:<id>`.
  final String id;
  final String label;

  /// Where it is, or how it stands, beside its name: its page's name, its page's line, Added.
  final String? detail;

  /// What it was found by besides its name, for the palette to find it by too.
  final List<String?> words;

  /// The page of Settings it opens, and the setting there; null for a plugin whose page is the Market's.
  final String? page;
  final String? setting;

  /// The plugin it is, or is of.
  final String? plugin;

  /// Whether it is under Plugins rather than Settings.
  bool get ofPlugins => kind == SettingsPlaceKind.plugin || kind == SettingsPlaceKind.pluginSetting || kind == SettingsPlaceKind.setUp;

  @override
  String toString() => 'SettingsPlace(${kind.name}, $id, "$label"${detail == null ? '' : ' · $detail'})';
}

/// How many of Settings' and how many of the plugins' are offered for one query, the best of them: past this the
/// list is a list of settings rather than of what was asked for.
const int mostSettings = 12;
const int mostPlugins = 10;

/// What [query] finds in [index] (empty for nothing typed): Settings' pages and settings, then the plugins, their
/// settings and their setups, each run its best [mostSettings] or [mostPlugins] in the index's order. [market] is
/// whether a plugin with no page in Settings can be opened in the Market; without it such a plugin is not offered.
List<SettingsPlace> findPlaces(SettingsIndex index, String query, {bool market = true}) {
  if (fold(query).trim().isEmpty) return const [];
  final settings = <SettingsPlace>[];
  final ofPlugins = <SettingsPlace>[];
  final named = {for (final section in index.sections) section.id: section.label};
  for (final hit in searchSettings(index.sections, query)) {
    final section = hit.section;
    final setting = hit.setting;
    final plugin = section.plugin;
    if (plugin != null) {
      // A plugin's page is its row's, below; its settings are its own.
      if (setting == null) continue;
      ofPlugins.add(SettingsPlace(
        kind: SettingsPlaceKind.pluginSetting,
        id: 'find:plugin:$plugin/$setting',
        label: setting,
        detail: section.label,
        words: [_wordsFor(section, setting), section.label],
        page: section.id,
        setting: setting,
        plugin: plugin,
      ));
      continue;
    }
    if (setting == null) {
      settings.add(SettingsPlace(kind: SettingsPlaceKind.page, id: 'find:settings:${section.id}', label: section.label, detail: section.summary, words: [section.summary, section.words], page: section.id));
    } else {
      // A sub-page's settings say both names: "About › Cheat sheet".
      final parent = section.parent == null ? null : named[section.parent];
      settings.add(SettingsPlace(
        kind: SettingsPlaceKind.setting,
        id: 'find:settings:${section.id}/$setting',
        label: setting,
        detail: parent == null ? section.label : '$parent › ${section.label}',
        words: [_wordsFor(section, setting)],
        page: section.id,
        setting: setting,
      ));
    }
  }
  final plugins = <SettingsPlace>[];
  for (final each in index.plugins) {
    if (!each.page && !market) continue;
    final found = pluginFound(each.plugin, query);
    final setUp = each.setUp;
    final setUpFound = setUp != null && (found || wordsFound(query, [setupFindableName(setUp), 'setup onboarding keys account']));
    if (!found && !setUpFound) continue;
    final manifest = each.plugin.manifest;
    final words = [manifest.tagline, manifest.description, manifest.category?.label, ...manifest.adds, 'plugin plugins add-on extension integration'];
    if (found) {
      plugins.add(SettingsPlace(
        kind: SettingsPlaceKind.plugin,
        id: 'find:plugin:${each.id}',
        label: each.name,
        detail: !each.added ? 'Not added' : (each.on ? 'Added' : 'Off: Local only'),
        words: words,
        page: each.page ? pluginPageId(each.id) : null,
        plugin: each.id,
      ));
    }
    if (setUpFound) {
      plugins.add(SettingsPlace(
        kind: SettingsPlaceKind.setUp,
        id: 'find:setup:${each.id}',
        label: setupFindableName(setUp),
        detail: 'Not set up yet',
        words: [each.name, 'setup onboarding keys account', ...words],
        page: pluginPageId(each.id),
        setting: setupFindableName(setUp),
        plugin: each.id,
      ));
    }
  }
  return [..._best(settings, query, mostSettings), ..._best([...plugins, ...ofPlugins], query, mostPlugins)];
}

/// A setting's words, as the search found it by.
String? _wordsFor(IndexedSection section, String setting) {
  for (final each in section.settings) {
    if (each.name == setting) return each.words;
  }
  return null;
}

/// The best [most] of [places] for [query], in their order: by name first (the whole of what is typed starting the
/// name, then each word starting one of its words), then by the rest.
List<SettingsPlace> _best(List<SettingsPlace> places, String query, int most) {
  if (places.length <= most) return places;
  final typed = fold(query).trim();
  final words = typed.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  int score(SettingsPlace place) {
    final name = fold(place.label);
    if (name.startsWith(typed)) return 0;
    final its = name.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true));
    return words.every((want) => its.any((word) => word.startsWith(want))) ? 1 : 2;
  }

  final order = [for (var i = 0; i < places.length; i++) (i, score(places[i]))]..sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);
  final kept = (order.take(most).map((each) => each.$1).toList())..sort();
  return [for (final i in kept) places[i]];
}

/// What a place is found by in the palette's own matching (glacier's `matchCommands`, which looks for each word typed
/// inside the row's name, its heading and these words, in lower case): its words, those words with their accents off,
/// and any word typed that the palette would not find in them, since the search above has found the place already and
/// the palette is only to keep it. So a place is never dropped for an accent or a hyphen.
String placeKeywords(SettingsPlace place, String group, String query) {
  final said = [for (final words in place.words) ?words].join(' ');
  final plain = fold(said);
  var keywords = plain == said.toLowerCase() ? said : '$said $plain';
  final hay = '${place.label} $group $keywords'.toLowerCase();
  for (final term in query.trim().toLowerCase().split(RegExp(r'\s+'))) {
    if (term.isNotEmpty && !hay.contains(term)) keywords = '$keywords $term';
  }
  return keywords;
}
