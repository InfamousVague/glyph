/// The Rich embeds plugin, standard in Ghost.md: a YouTube, Spotify or Figma link alone on its line drawn as a card
/// that plays or shows it (lib/editor/media/rich_embeds/: Matt, "Rich embeds: YouTube, Spotify and Figma links as
/// playable or previewable cards, not just link cards"). Matt, 2026-10-17: "Ask Claude and other integrations
/// should be shipped as plugins".
///
/// The cards are the editor's (lib/editor/media/link_cards.dart), which asks [richEmbedsOn] as it draws a note's
/// links: off, such a link is a plain link card, as any other link is, and nothing is asked of the three services.
/// It has no page: there is nothing to set but the switch. Link previews and Local only still hold back what a card
/// asks of a service, as they did before it was a plugin; under Local only it is off with every plugin that uses the
/// internet.
library;

import '../registry.dart' show pluginOn;
import '../types.dart';

const PluginManifest richEmbedsManifest = PluginManifest(
  id: 'rich-embeds',
  name: 'Rich embeds',
  description: 'Plays a YouTube video or a Spotify song in its link’s card, and shows a Figma file, where the link is alone on its line.',
  version: '1.0.0',
  author: 'Ghost.md',
  standard: true,
  permissions: [
    PluginPermission(Permission.network, 'Asks YouTube, Spotify or Figma for a link’s title and picture once Link previews are on, and plays it only when you tap it. Nothing of your notes goes but the link.'),
  ],
  hosts: ['www.youtube.com', 'open.spotify.com', 'www.figma.com'],
  storage: [],
);

/// Whether a rich embed's link draws its rich card: the plugin's switch, asked as a note's links are drawn.
bool richEmbedsOn() => pluginOn(richEmbedsManifest);

final GlyphPlugin richEmbedsPlugin = GlyphPlugin(manifest: richEmbedsManifest, icon: 'play');
