/// The Places plugin, one of the more tools (docs/PM_PLUGINS.md §10; Matt, 2026-11-01: "think about other things that
/// can be plugins that might be overwhelming for a new user as well"): a note's place, `location:` and `place:` in its
/// front matter written as it is made (lib/core/geotag.dart, place_tags.dart; on by default for every note Matt makes
/// since 2026-09-27), a journal entry's `entry-place:`, the map at a tagged note's top, and a place in the words,
/// `[Name](geo:…)`, drawn as its card, with A place in the +. Settings › Account's Location card is its page now.
///
/// Off, no location is asked for or written, `location:` stays as the text it is in the front matter, a place's line
/// is its link, and nothing is rewritten. Place reminders (places.dart) are a plugin of their own and stay as they are.
/// On for a person whose notes carry a place (lib/plugins/more/more_tools.dart `adoptMoreTools`).
library;

import '../../core/more_tools.dart' show placesTool;
import '../../settings/panes/account_pane.dart' show locationFindable;
import '../types.dart';
import 'places_tool_pane.dart';

export 'places_tool_pane.dart';

const PluginManifest placesToolManifest = PluginManifest(
  id: placesTool,
  name: 'Places',
  description:
      'Where a note was made, written into it as you make it, and its map at the note’s top. A place in your words drawn as its card with its map, and A place in the +. Where you are never leaves your phone through Ghost.md; a place’s name and map are asked of OpenStreetMap, where you allow it.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.editor,
  tagline: 'A note’s place, its map, and place cards',
  adds: [
    'Tag new notes with my location, and Add my location in a note’s More',
    'The map at a tagged note’s top, and a journal entry’s place',
    'A place in your words drawn as its card, and A place in the +',
  ],
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Writes where a note was made into its front matter, as location: and place:.'),
  ],
  storage: [],
);

/// Its page, kept in Simple as Settings › Account's Location card was.
final GlyphPlugin placesToolPlugin = GlyphPlugin(
  manifest: placesToolManifest,
  icon: 'map-pinned',
  settings: PluginSettings(
    pane: PlacesToolPane.hosted,
    summary: () => 'A note’s place and its map',
    hue: 'green',
    simple: true,
    settings: locationFindable,
  ),
);
