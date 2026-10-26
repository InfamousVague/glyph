/// What the Market shows and how it is found (Matt, 2026-10-26: "Make the plugins a dedicated "Market" section in the
/// app, include some more themes, fonts an of course all our plugins with vivid iconography and imagery where
/// possible include mobile and desktop support"): its shelves, each plugin's colours and mark, where each plugin
/// works, and which of the plugins, themes and fonts a search leaves.
///
/// Every list is read where the app keeps it, never copied here: the plugins are the registry's
/// (lib/plugins/registry.dart), in the catalogue's order (lib/plugins/catalogue.dart); the themes are
/// `themeOptions` (lib/settings/theme_cards.dart, over `themes` and `themePresets`); the accents `accents`; the faces
/// `typefaces` and `interfaceFaces` (lib/core/preferences.dart), named by `faceWords` (lib/settings/words.dart). A
/// theme or a face added there is on the Market's shelves with nothing done here.
library;

import 'package:flutter/widgets.dart';

import '../art/art.dart';
import '../claude/claude_mark.dart';
import '../core/iphone_app.dart' show notOnIPhone;
import '../core/preferences.dart';
import '../plugins/catalogue.dart';
import '../plugins/github/marks.dart';
import '../plugins/lovart/lovart_mark.dart';
import '../plugins/notion/marks.dart';
import '../plugins/places/places.dart' show placeRemindersId;
import '../plugins/types.dart';
import '../settings/settings_search.dart' show wordsFound;
import '../settings/theme_cards.dart' show ThemeOption;
import '../settings/words.dart';

/// The Market's shelves: everything, or one kind. The segmented control's words, in its order.
enum MarketShelf {
  all('All'),
  plugins('Plugins'),
  themes('Themes'),
  fonts('Fonts');

  const MarketShelf(this.label);
  final String label;
}

// --- colour ------------------------------------------------------------------------------------------------------

/// Each hue the settings draw, as settings.css writes it (lib/settings/settings_css.dart): the deeper shade the light
/// page wears, then the brighter one the dark page wears. A plugin's tile is a wash from the one to the other, so it
/// is vivid on either page and the same plugin in both.
const Map<String, (Color, Color)> marketHues = {
  'blue': (Color(0xFF0A6FE0), Color(0xFF4EA1FF)),
  'purple': (Color(0xFF9A45C9), Color(0xFFC77DFF)),
  'red': (Color(0xFFDD3A30), Color(0xFFFF6B61)),
  'coral': (Color(0xFFC8643F), Color(0xFFF0906B)),
  'green': (Color(0xFF2A9D4B), Color(0xFF4CD571)),
  'yellow': (Color(0xFFB58400), Color(0xFFFFD43B)),
  'mint': (Color(0xFF1F9E8F), Color(0xFF5FE0CF)),
  'amber': (Color(0xFFC27C00), Color(0xFFFFB84D)),
  'indigo': (Color(0xFF4F5BD5), Color(0xFF8C95FF)),
  'orange': (Color(0xFFD9600D), Color(0xFFFF9A4D)),
  'cyan': (Color(0xFF0A86A8), Color(0xFF4CC9F0)),
  'lime': (Color(0xFF5A8A00), Color(0xFFA3D93F)),
  'rose': (Color(0xFFD6336C), Color(0xFFFF7AA8)),
  'magenta': (Color(0xFFB5279F), Color(0xFFF07AE0)),
};

/// The hue of a plugin with no page of its own, by its id, and else by its category's.
const Map<String, String> _ownHues = {'marks': 'amber', 'rich-embeds': 'red'};
const Map<PluginCategory, String> _categoryHues = {
  PluginCategory.ai: 'purple',
  PluginCategory.calendar: 'cyan',
  PluginCategory.imports: 'blue',
  PluginCategory.connections: 'indigo',
  PluginCategory.editor: 'amber',
};

/// A plugin's hue: its page's in Settings where it has one (`PluginSettings.hue`), so its tile and its row there
/// are one colour; otherwise its own or its category's.
String pluginHue(GlyphPlugin plugin) {
  final hue = plugin.settings?.hue ?? _ownHues[plugin.manifest.id] ?? _categoryHues[plugin.manifest.category] ?? 'indigo';
  return marketHues.containsKey(hue) ? hue : 'indigo';
}

/// The two ends of a plugin's tile: its hue's deep shade at the top start, its bright one at the bottom end.
(Color, Color) pluginColours(GlyphPlugin plugin) => marketHues[pluginHue(plugin)]!;

/// The tile itself: a wash across the plugin's hue, with a soft light from the top start corner, so a shelf of them
/// reads as colour and not as flat chips.
BoxDecoration pluginTile(GlyphPlugin plugin, {required double radius}) {
  final (deep, bright) = pluginColours(plugin);
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [deep, Color.lerp(deep, bright, 0.55)!, bright]),
  );
}

/// The light laid over a tile: a glow from the top start corner and a shade at the foot, the tile's depth.
Widget tileLight({required double radius}) => IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const RadialGradient(center: Alignment(-0.8, -0.9), radius: 1.1, colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)]),
        ),
        child: const SizedBox.expand(),
      ),
    );

/// A plugin's mark on its tile, in white: the brand's own where Ghost.md draws one (Claude's, Notion's, GitHub's,
/// Lovart's), else the plugin's Lucide icon. Lovart's mark may be drawn here, inside the app; it is only kept out of
/// a store's listing (lib/plugins/lovart/lovart_mark.dart).
Widget pluginMark(GlyphPlugin plugin, double size, {Color color = const Color(0xFFFFFFFF)}) {
  final Widget mark = switch (plugin.manifest.id) {
    'claude' => ClaudeMark(size: size, color: color),
    'notion' => NotionMark(size: size),
    'github' => RepoMark(size: size),
    'lovart' => LovartMark(size: size, color: color),
    _ => AppIcon(Lucide.all[plugin.icon] ?? Lucide.puzzle, size: size, color: color, strokeWidth: 1.8, wash: false),
  };
  return IconTheme.merge(data: IconThemeData(color: color, size: size), child: mark);
}

/// Whether Ghost.md draws a plugin's own brand mark, which the featured shelf leads with.
bool hasBrandMark(GlyphPlugin plugin) => const {'claude', 'notion', 'github', 'lovart'}.contains(plugin.manifest.id);

// --- where a plugin works ----------------------------------------------------------------------------------------

/// Where a plugin does what it says: on an Android phone, on an iPhone, on the Mac (the desktop app; the Windows
/// app is the Tauri one, tauri/).
@immutable
class PluginReach {
  const PluginReach({required this.android, required this.iphone, required this.mac});

  final bool android;
  final bool iphone;
  final bool mac;

  bool get mobile => android || iphone;

  /// On the card, in a few words: "Mobile · Desktop" where it is everywhere, else what it is on ("Android ·
  /// Desktop", "Android only").
  String get line {
    final phones = android && iphone ? 'Mobile' : (android ? 'Android' : (iphone ? 'iPhone' : null));
    final parts = [?phones, if (mac) 'Desktop'];
    if (parts.length == 1 && !(android && iphone)) return '${parts.single} only';
    return parts.join(' · ');
  }

  /// Each platform with whether it is on it, for the plugin's page.
  List<(String, bool)> get each => [('Android', android), ('iPhone', iphone), ('Mac', mac)];

  /// Whether the device [platform] is one it works on.
  bool on(TargetPlatform platform) => switch (platform) {
        TargetPlatform.android => android,
        TargetPlatform.iOS => iphone,
        TargetPlatform.macOS => mac,
        _ => true,
      };
}

/// Where [plugin] works, as the code says: Notion and Slack answer an iPhone with Rust's "not available on iOS yet"
/// (lib/core/iphone_app.dart `notOnIPhone`); Place reminders watch places through Android's geofences alone
/// (lib/reminders/place_host.dart); Todoist and Things bring notes in through Settings › Import, which an iPhone has
/// not got (lib/settings/settings_sections.dart). The rest work everywhere.
PluginReach reachOf(GlyphPlugin plugin) {
  final id = plugin.manifest.id;
  final iphone = notOnIPhone(id, platform: TargetPlatform.iOS) == null && id != placeRemindersId && id != 'todoist' && id != 'things';
  return PluginReach(android: true, iphone: iphone, mac: id != placeRemindersId);
}

// --- finding -----------------------------------------------------------------------------------------------------

/// Whether a plugin stays for what is typed: what the catalogue matches (lib/plugins/catalogue.dart `inCatalogue`), its name, line, description, what it adds
/// and its category, and where it works ("iphone", "desktop").
bool pluginFound(GlyphPlugin plugin, String query) {
  final manifest = plugin.manifest;
  return wordsFound(query, [manifest.name, manifest.tagline, manifest.description, manifest.category?.label, ...manifest.adds, reachOf(plugin).line, 'plugin plugins add-on extension integration']);
}

/// Whether a theme stays for what is typed: its name, its line ("Dark, with green") and the word theme.
bool themeFound(ThemeOption option, String query) => wordsFound(query, [option.label, option.description, 'theme themes look colour color palette']);

/// Whether a face stays for what is typed: its name, its roles and the word font.
bool faceFound(String face, String query) => wordsFound(query, [faceWords[face] ?? face, faceRoles(face).join(' '), 'font fonts typeface type']);

/// What a face can be set as: every face a note's, a coding face a note's and its code's, a sans the interface's too.
List<String> faceRoles(String face) => [
      'Note font',
      if (isCodingFace(face)) 'Coding face',
      if (interfaceFaces.contains(face)) 'Interface font',
    ];

/// The plugins, in the catalogue's order, that stay for [query].
List<GlyphPlugin> pluginsFound(Iterable<GlyphPlugin> all, String query) => [
      for (final plugin in catalogueOrder(all))
        if (pluginFound(plugin, query)) plugin,
    ];

/// The plugins the featured shelf leads with: those whose brand Ghost.md draws, then those the person has not added,
/// four at most.
List<GlyphPlugin> featuredPlugins(List<GlyphPlugin> all) => [
      ...all.where(hasBrandMark),
    ].take(4).toList();

/// The accent's word, for its swatch's label.
String accentName(String accent) => accentWords[accent] ?? accent;

// --- links -------------------------------------------------------------------------------------------------------

/// Where a link into Settings that once went to the plugins lands now: the Market, at a plugin's page for
/// `plugins/<id>` (Settings › Plugins › its name until 2026-10-26), at its head for `plugins` and `market`. Null for
/// any other id, which is Settings' own.
({String? plugin})? marketLanding(String id) {
  if (id == 'plugins' || id == 'market') return (plugin: null);
  if (id.startsWith('plugins/') && id.length > 'plugins/'.length) return (plugin: id.substring('plugins/'.length));
  return null;
}
