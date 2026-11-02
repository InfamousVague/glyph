/// The Figma plugin's manifest and its host (Matt, 2026-11-02: "Also add a figma plugin", beside the connector's word
/// to the AI to link Figma frames so Ghost.md shows their previews, mcp/docs.ts `FIGMA_INSTRUCTIONS`). The port's own:
/// the web app has none.
///
/// Figma's REST API (api.figma.com) takes the person's own personal access token in an `X-Figma-Token` header
/// (client.dart); the token is kept in the device's secure store under [tokenSecret] and follows the account sealed
/// (lib/sync/connections.dart), as GitHub's does. What the frames' cards learnt is this device's own, under
/// [framesKey] (frames.dart).
///
/// `api.figma.com` is what the plugin asks; `www.figma.com` is Rich embeds' oEmbed, which a Figma card falls back to
/// when Figma's API will not say, and its interactive embed, which a tap opens.
library;

import '../host.dart';
import '../types.dart';

/// The name the token is kept under in the secure store.
const String tokenSecret = 'glyph-figma-token';

/// What the frames' cards learnt of Figma, this device's own (frames.dart).
const String framesKey = 'glyph-figma-frames';

const PluginManifest manifest = PluginManifest(
  id: 'figma',
  name: 'Figma',
  description:
      'Shows a Figma frame’s own picture in your note, with its name and its file’s, where its link is alone on its line: read with your own Figma token, from files you can open, private ones too.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.connections,
  tagline: 'Figma frames shown in your notes',
  adds: [
    'A Figma frame’s link alone on its line drawn as the frame itself, named, with its file’s name',
    'A file’s link without a frame drawn as the file’s thumbnail',
    'Private files you can open in Figma, where Rich embeds shows only shared ones',
  ],
  // Off until added: it needs the person's own token, and Rich embeds already shows a shared file without one.
  standard: false,
  permissions: [
    PluginPermission(
      Permission.network,
      'Asks Figma, with your own token, for a linked frame’s name, its file’s name and its picture, once Link previews are on, and fetches the picture Figma names. Nothing of your notes goes but the link.',
    ),
  ],
  hosts: ['api.figma.com', 'www.figma.com'],
  storage: [framesKey],
  secrets: [tokenSecret],
);

/// The plugin's one way onto the phone (lib/plugins/host.dart).
final PluginHost host = createHost(manifest);
