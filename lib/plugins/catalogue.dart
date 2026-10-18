/// The plugins as Settings › Plugins lays them out now that it is a catalogue to browse (Matt, 2026-10-18: "rework
/// the plugins page to be a marketplace, also move plugin settings to their own page under settings"): in what
/// order, under which categories, and which of them a search and a filter leave. Every plugin is built in: the
/// catalogue is the registry's own list (built_in.dart `builtIn`), and there is nothing to fetch, nowhere to fetch
/// it from, and nothing to install. Not on the page, whose Plugins was a list of cards in the registry's order.
library;

import '../settings/settings_search.dart' show wordsFound;
import 'types.dart';

/// [all] in the catalogue's order: by category, as [PluginCategory] lists them, and by name inside one, so a
/// person browsing finds Calendar before Contacts; a plugin with no category comes last, and two of one name stay
/// as the registry has them. Settings' own rows for the plugins' pages are in this order too
/// (lib/settings/settings_sections.dart).
List<GlyphPlugin> catalogueOrder(Iterable<GlyphPlugin> all) {
  final listed = [...all];
  final at = {for (var i = 0; i < listed.length; i++) listed[i]: i};
  int rank(GlyphPlugin plugin) => plugin.manifest.category?.index ?? PluginCategory.values.length;
  return listed
    ..sort((a, b) {
      final byCategory = rank(a).compareTo(rank(b));
      if (byCategory != 0) return byCategory;
      final byName = a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase());
      return byName != 0 ? byName : at[a]!.compareTo(at[b]!);
    });
}

/// The categories [all] has a plugin in, in their order: the filter's words after All.
List<PluginCategory> categoriesOf(Iterable<GlyphPlugin> all) {
  final present = {for (final plugin in all) ?plugin.manifest.category};
  return [
    for (final category in PluginCategory.values)
      if (present.contains(category)) category,
  ];
}

/// Whether [plugin] stays in the catalogue for what is typed ([query]) and the category chosen ([category], null for
/// All): every word typed starts a word of its name, its card's line, what it does, what it adds or its category's
/// name, as Settings' own search matches.
bool inCatalogue(GlyphPlugin plugin, {String query = '', PluginCategory? category}) {
  final manifest = plugin.manifest;
  if (category != null && manifest.category != category) return false;
  return wordsFound(query, [manifest.name, manifest.tagline, manifest.description, manifest.category?.label, ...manifest.adds]);
}
