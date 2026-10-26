/// The Market as the website lists it (Matt, 2026-10-26: "add a browsable marketplace listed under the plugins section
/// on the website that deeplinks to the app"): landing/market.json, which ghostmarkdown.com's market page
/// (landing/market.html) reads and draws, and nothing else. It is made from the very lists the app's Market reads
/// (lib/market/market_items.dart): the plugins the registry has, in the catalogue's order; the themes as Appearance
/// offers them (`themeOptions`), each with the colours its miniature is painted in; the faces (`typefaces`), each with
/// the family it is set in. A plugin, theme or face added to the app is on the website once the file is made again,
/// and test/market/market_listing_test.dart fails until it is:
///
/// ```sh
/// flutter test --no-pub test/market/market_listing_test.dart --update-goldens
/// ```
///
/// What the page needs and the app has, carried across as data rather than written again in JavaScript: each plugin's
/// colours (its hue's two shades, `marketHues`), where it works (`reachOf`), what it adds and may reach, each
/// permission in the plugin page's words with its icon; each theme's palette; each face's roles and the lines its card
/// sets. Every icon is the app's own Lucide glyph (lib/art/lucide.g.dart), as its paths on the 24 grid, so the page
/// draws the same shapes the app does without a sprite of its own. A brand's mark is named only where the app draws
/// one and the site already ships its file (landing/brands/), which today is Claude's, Notion's and Lovart's; GitHub's
/// tile wears its Lucide icon on the site, as no mark of GitHub's is shipped there.
///
/// Every thing carries its link into the app, `ghostmd://market/<kind>/<id>` (lib/share/app_links.dart `MarketPlace`),
/// which the page's Open in Ghost.md follows.
library;

import 'dart:convert';

import 'package:flutter/painting.dart' show Color;

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/preferences.dart';
import '../plugins/catalogue.dart';
import '../plugins/reach.dart';
import '../plugins/types.dart';
import '../settings/theme_cards.dart' show ThemeOption, ThemePalette;
import '../settings/typeface_cards.dart' show typefaceFamilies;
import '../settings/words.dart';
import '../share/app_links.dart' show MarketKind, MarketPlace;
import 'market_items.dart';
import 'market_looks.dart';
import 'market_plugins.dart' show permissionIcon;

/// The icons the page draws around the things themselves: the shelves', the search's, the platforms', a detail's
/// close and its buttons. Carried with the things' own, so the page has one place to read a glyph from.
const List<LucideIcon> _pageIcons = [
  Lucide.puzzle,
  Lucide.swatchBook,
  Lucide.type,
  Lucide.sparkles,
  Lucide.search,
  Lucide.smartphone,
  Lucide.laptop,
  Lucide.x,
  Lucide.plus,
  Lucide.check,
  Lucide.settings,
  Lucide.shieldCheck,
  Lucide.globe,
  Lucide.download,
  Lucide.squareArrowOutUpRight,
];

/// `#rrggbb`, as the page's stylesheet takes a colour.
String _hex(Color colour) => '#${(colour.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// A theme's colours as its miniature paints them ([ThemeMiniature]), the accent already the one it draws.
Map<String, String> _palette(ThemePalette p) => {
      'background': _hex(p.background),
      'sidebar': _hex(p.sidebar),
      'surface': _hex(p.surface),
      'border': _hex(p.border),
      'text': _hex(p.text),
      'muted': _hex(p.muted),
      'accent': _hex(miniatureAccent(p)),
    };

/// The link the page opens a thing with.
String _link(MarketKind kind, String id) => MarketPlace(kind: kind, id: id).toString();

/// The listing, as a map in the order the file keeps it. [plugins] are the registry's, [themes] Appearance's options
/// (`themeOptions`, which reads the kit's tokens), and [marks] the brands whose marks the site ships (the names of
/// landing/brands/*.svg).
Map<String, Object?> marketListing({required Iterable<GlyphPlugin> plugins, required List<ThemeOption> themes, Set<String> marks = const {}}) {
  final ordered = catalogueOrder(plugins);
  final icons = <String, List<String>>{};
  String glyph(LucideIcon icon) {
    icons[icon.name] = icon.shapes;
    return icon.name;
  }

  for (final icon in _pageIcons) {
    glyph(icon);
  }
  const everywhere = {'android': true, 'iphone': true, 'mac': true};

  return {
    'made': 'MADE, not written: test/market/market_listing_test.dart writes it from the app\'s own lists (lib/market/market_listing.dart).',
    'link': const MarketPlace().toString(),
    'shelves': [
      for (final shelf in MarketShelf.values) {'id': shelf.name, 'label': shelf.label},
    ],
    'categories': [
      for (final category in categoriesOf(ordered)) {'id': category.name, 'label': category.label},
    ],
    // The plugins All leads with before anything is typed, as the app's Featured shelf has them.
    'featured': [for (final plugin in featuredPlugins(ordered)) plugin.manifest.id],
    'plugins': [
      for (final plugin in ordered)
        () {
          final manifest = plugin.manifest;
          final reach = reachOf(plugin);
          final (deep, bright) = pluginColours(plugin);
          final id = manifest.id;
          return {
            'id': id,
            'name': manifest.name,
            'line': manifest.line,
            'description': manifest.description,
            'category': manifest.category?.name,
            'icon': glyph(Lucide.all[plugin.icon] ?? Lucide.puzzle),
            'mark': hasBrandMark(plugin) && marks.contains(id) ? id : null,
            'hue': pluginHue(plugin),
            'colours': [_hex(deep), _hex(bright)],
            'platforms': {'android': reach.android, 'iphone': reach.iphone, 'mac': reach.mac},
            'reach': reach.line,
            'adds': manifest.adds,
            'settings': plugin.settings != null,
            'permissions': [
              for (final permission in manifest.permissions)
                {
                  'kind': permission.kind.name,
                  'label': plainPermissionWords[permission.kind],
                  'why': permission.kind == Permission.network && manifest.hosts.isNotEmpty ? '${permission.why} It talks to ${joinAnd(manifest.hosts)} and nowhere else.' : permission.why,
                  'icon': glyph(permissionIcon(permission.kind)),
                },
            ],
            'hosts': manifest.hosts,
            'standard': manifest.standard,
            'author': manifest.author,
            'version': manifest.version,
            'link': _link(MarketKind.plugin, id),
          };
        }(),
    ],
    'themes': [
      for (final option in themes)
        {
          'id': option.value,
          'name': option.label,
          'line': option.description,
          'scheme': option.value == 'system' ? 'system' : themeScheme(option.value),
          'accent': switch (themePresets[option.value]) {
            final preset? => accentWords[preset.accent],
            null => null,
          },
          'palette': _palette(option.palette),
          'alternate': option.alternatePalette == null ? null : _palette(option.alternatePalette!),
          'platforms': everywhere,
          'link': _link(MarketKind.theme, option.value),
        },
    ],
    'fonts': [
      for (final face in typefaces)
        {
          'id': face,
          'name': faceWords[face] ?? face,
          'family': typefaceFamilies[face],
          'roles': faceRoles(face),
          'coding': isCodingFace(face),
          'interface': interfaceFaces.contains(face),
          'platforms': everywhere,
          'link': _link(MarketKind.font, face),
        },
    ],
    'samples': {for (final MapEntry(:key, :value) in faceSamples.entries) key.name: value},
    'icons': {for (final name in icons.keys.toList()..sort()) name: icons[name]},
  };
}

/// The listing as landing/market.json has it: two spaces in, a line at the end.
String marketListingJson({required Iterable<GlyphPlugin> plugins, required List<ThemeOption> themes, Set<String> marks = const {}}) =>
    '${const JsonEncoder.withIndent('  ').convert(marketListing(plugins: plugins, themes: themes, marks: marks))}\n';
