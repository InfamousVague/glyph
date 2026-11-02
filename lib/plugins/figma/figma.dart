/// The Figma plugin: a Figma frame's link alone on its line drawn as the frame itself, named, with its file's name,
/// read with the person's own token (Matt, 2026-11-02: "Also add a figma plugin", beside the connector's word to the AI
/// to "try to link figma frames with previews where possible", mcp/docs.ts `FIGMA_INSTRUCTIONS`). The app's own: the
/// web app has none.
///
/// Where it shows, once added in the Market (off until then) and connected on its page:
/// - **A note's Figma links** (frames.dart): Rich embeds' card (lib/editor/media/rich_embeds/cards.dart) with what
///   Figma's API says in place of its oEmbed: a frame's own picture where the link has a `node-id`, a file's thumbnail
///   where it has none, and private files the token can open, where the oEmbed shows only shared ones. Drawn even with
///   Rich embeds off, since that is all the plugin does. Not connected, it is Rich embeds' card as before.
/// - **Its page in Settings** (figma_pane.dart): the token, checked, whose it is, Check, and Disconnect.
///
/// What differs from the connected plugins before it: no setup flow (lib/plugins/onboarding/), since each of those is
/// read aloud from clips made with ElevenLabs (tool/plugin_setup_voice.py), and its page is short enough to be the
/// setup itself. Its icon is the kit's `shapes`: Figma's mark is not among the ones fetched (lib/plugins/brands.dart).
library;

import '../types.dart';
import 'figma_pane.dart';
import 'manifest.dart';

export 'client.dart';
export 'figma_pane.dart';
export 'frames.dart';
export 'manifest.dart' show framesKey, tokenSecret;

String _summary() => figmaToken() == null ? 'Not connected' : 'Connected';

final GlyphPlugin figmaPlugin = GlyphPlugin(
  manifest: manifest,
  icon: 'shapes',
  settings: PluginSettings(pane: (context) => const FigmaPane(), hue: 'purple', settings: figmaFindable, summary: _summary),
);
