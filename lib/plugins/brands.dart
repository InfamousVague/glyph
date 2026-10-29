/// Which plugins wear a company's mark, and the one way every place that draws a plugin's icon asks for it (Matt,
/// 2026-10-29: "Iconize real company logos for openAI todoist, GitHub, Google meets, zoom etc and use those for the
/// plugin icons"). The marks themselves are lib/art/brand_marks.dart's.
///
/// Every built-in plugin is one of three (test/plugins/brands_test.dart holds the list to it, so a new plugin is put
/// in one): a company's product with its mark ([pluginBrands]); a company's product that keeps its glyph
/// ([pluginsWithoutMark], with why); or the app's own ([ownPlugins]), which keeps its glyph.
///
/// In monochrome places (Settings' list, a note's More sheet, the setup sheet's band) a mark is drawn in the ink
/// round it, as a glyph is ([pluginGlyph]); on the plugin's tile in the Market and at its page's head in its brand's
/// colour (lib/market/market_plugins.dart, [pluginHeroGlyph]). Google Meet's is the one drawn otherwise
/// ([marksInWhite]). In a build for a store's pictures none is drawn ([brandMarksShown]), and every plugin wears its
/// glyph.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/brand_marks.dart';
import '../art/lucide.g.dart';
import 'types.dart';

/// A plugin's id to the slug of its company's mark (lib/art/brand_marks.g.dart). Calendar reads Google Calendar as
/// well as any iCal address; it wears Google Calendar's mark, the one service it signs in to.
const Map<String, String> pluginBrands = {
  'notion': 'notion',
  'github': 'github',
  'claude': 'claude',
  'calendar': 'googlecalendar',
  'todoist': 'todoist',
  'things': 'things',
  'lovart': 'lovart',
  'discord': 'discord',
  'google-meet': 'googlemeet',
  'elevenlabs': 'elevenlabs',
  'gemini': 'googlegemini',
};

/// A company's product that keeps its glyph, by its plugin's id, and why.
const Map<String, String> pluginsWithoutMark = {
  'slack': 'Simple Icons no longer carries Slack’s mark, and Slack’s media kit is served from Salesforce’s Widen, not from slack.com.',
  'openai': 'Simple Icons carries no OpenAI mark, and openai.com/brand offers no file to fetch (it asks for leave by mail).',
  'aster': 'Simple Icons carries no Aster Lab mark, and asterlab.ai publishes no press kit or SVG (its header logo is a PNG).',
  'zoom': 'Simple Icons’ Zoom mark is its wordmark, which cannot be read at an icon’s size; a video camera instead (Matt, 2026-10-29: “change zoom”).',
};

/// The app's own plugins, by id: no company's product, so each keeps its glyph.
const Set<String> ownPlugins = {'marks', 'place-reminders', 'webhooks', 'contacts', 'rich-embeds', 'custom-ai', 'keyboard-modes'};

/// The plugins whose mark is drawn in white on their own colour and nowhere else (Matt, 2026-10-29: "set the Google
/// meets to use Google meets logo in white but show a generic meetings icon for the meetings page"): Google Meet's on
/// its tile and heads in the Market, in the old way (its colour's wash, the mark in white on it) rather than on a
/// badge in its brand's colour, and in its setup's band. Its page in Settings is the page of meetings, the one Zoom's
/// is too (lib/plugins/meetings/meeting_pane.dart), and its row on Settings' list, the setup card on it and any plain
/// ink place wear the plugin's glyph there, a group of people: the only place Meet's icon is drawn in the ink is that
/// row, and a mark in the ink beside Zoom's camera would make the one page two services'.
const Set<String> marksInWhite = {'google-meet'};

/// The mark plugin [id] wears now: null for one of the app's own, one without a mark, or any in a store-shot build.
BrandMarkData? brandOfId(String id) => brandMarksShown ? brandMark(pluginBrands[id]) : null;

/// The mark [plugin] wears now ([brandOfId]).
BrandMarkData? brandOf(GlyphPlugin plugin) => brandOfId(plugin.manifest.id);

/// The mark [plugin] wears on a badge of its own in its brand's colour (the Market's tile, the chip on its heads):
/// [brandOf], but none for one drawn in white on its colour ([marksInWhite]).
BrandMarkData? badgedBrandOf(GlyphPlugin plugin) => marksInWhite.contains(plugin.manifest.id) ? null : brandOf(plugin);

/// The plugin's glyph, its Lucide icon by the kit's name for it (`GlyphPlugin.icon`), the puzzle piece for a name the
/// kit does not draw.
LucideIcon pluginLucide(GlyphPlugin plugin) => Lucide.all[plugin.icon] ?? Lucide.puzzle;

/// A plugin's icon in one colour, [size] square: its company's mark where it wears one, else its glyph. [color] is the
/// icon's ink; the icon theme's round it, else the text's, where null. [onColour] is a place on the plugin's own
/// colour, in white, where a mark of [marksInWhite] is drawn too. [strokeWidth] and [wash] are the glyph's.
Widget pluginGlyph(GlyphPlugin plugin, double size, {Color? color, bool onColour = false, double strokeWidth = 2, bool wash = true}) {
  final mark = brandOf(plugin);
  if (mark != null && (onColour || !marksInWhite.contains(plugin.manifest.id))) return BrandMarkIcon(mark, size: size, color: color);
  return AppIcon(pluginLucide(plugin), size: size, color: color, strokeWidth: strokeWidth, wash: wash);
}

/// The icon of a plugin's own action or link (a note's More sheet, its menus): its company's mark in the ink round it,
/// where it wears one there, else [glyph], the drawing it had.
Widget Function(BuildContext context, double size) brandedIcon(String pluginId, Widget Function(BuildContext context, double size) glyph) => (context, size) {
      final mark = marksInWhite.contains(pluginId) ? null : brandOfId(pluginId);
      return mark == null ? glyph(context, size) : BrandMarkIcon(mark, size: size);
    };

/// The glyph at the head of a plugin's page in Settings (`PaneHero.glyph`): its company's mark in its brand's colour,
/// held off the page's paper ([brandInkOn]) and else in the hero's own ink, or [fallback] where it wears none there.
Widget pluginHeroGlyph(String pluginId, LucideIcon fallback, {double size = 22}) {
  final mark = marksInWhite.contains(pluginId) ? null : brandOfId(pluginId);
  if (mark == null) return AppIcon(fallback, size: size);
  return Builder(builder: (context) => BrandMarkIcon(mark, size: size, color: brandInkOn(mark, ground: context.tokens.color('app-paper'), ink: inkAt(context))));
}
