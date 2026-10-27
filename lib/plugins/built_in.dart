/// The plugins that ship with Ghost.md, and the one call that puts them in place. The foot of
/// `src/app/plugins/registry.ts` (`BUILT_IN`, `plugins`, and the feed's rows handed on).
///
/// On the page the registry is made as its module loads, so every file that imports it has its five. Here nothing
/// runs until it is asked, and registry.dart cannot name the plugins it is the ground of (each of them imports it),
/// so the list lives in this file and the app's root says when:
///
/// ```dart
/// installBuiltInPlugins(localOnly: () => preferences.value.localOnly);
/// ```
///
/// once, before the first screen is built (Settings' rows, the editor's parser and the guide all read [plugins]).
///
/// The order is the page's, and it is what a person sees: the cards of Settings > Plugins, and whose item action
/// wins when two could send a line (Notion before GitHub). The web took `library-folder` out of the list when the
/// folder became the library's own page; it is not here either.
///
/// What differs: `localOnly` is handed in, where registry.ts read the preferences it imports (registry.dart knows
/// none); and the feed's rows reach the plugins from here rather than from the registry's own module, for the same
/// reason the list is here. And the list is longer: the web's five, then the integrations the app has of its own,
/// each made a plugin (Matt, 2026-10-17: "Ask Claude and other integrations should be shipped as plugins"): Calendar,
/// Contacts, Rich embeds, Todoist and Things; then Lovart and Discord; then Google Meet and Zoom, which were Settings ›
/// Meetings; then ElevenLabs. The app's own Claude is the Claude plugin's other half.
library;

import '../integrations/webhooks/plugin.dart' show webhooksPlugin;
import '../sync/arrived.dart' show onArrived;
import 'calendar/calendar.dart' show calendarPlugin;
import 'claude/claude.dart' show claudePlugin;
import 'contacts/contacts.dart' show contactsPlugin;
import 'discord/discord.dart' show discordPlugin;
import 'elevenlabs/elevenlabs.dart' show elevenLabsPlugin;
import 'github/github.dart' show githubPlugin;
import 'lovart/lovart.dart' show lovartPlugin;
import 'marks_plugin.dart' show marksPlugin;
import 'meetings/meetings.dart' show googleMeetPlugin, zoomPlugin;
import 'notion/notion.dart' show notionPlugin;
import 'places/places.dart' show placesPlugin;
import 'registry.dart';
import 'rich_embeds/rich_embeds.dart' show richEmbedsPlugin;
import 'slack/slack.dart' show slackPlugin;
import 'things/things.dart' show thingsPlugin;
import 'todoist/todoist.dart' show todoistPlugin;
import 'types.dart';

/// The plugins that ship with Ghost.md (`BUILT_IN`): the page's five in its order, then the app's own, which the
/// page never had, one a line: Place reminders (places/places.dart), Webhooks (docs/INTEGRATIONS.md, §1), and the
/// integrations made plugins after them.
final List<GlyphPlugin> builtIn = List.unmodifiable([
  notionPlugin,
  githubPlugin,
  marksPlugin,
  claudePlugin,
  slackPlugin,
  placesPlugin,
  webhooksPlugin,
  calendarPlugin,
  contactsPlugin,
  richEmbedsPlugin,
  todoistPlugin,
  thingsPlugin,
  lovartPlugin,
  // Matt, 2026-10-26: "Add a new plugin to post notes to discord chats": the Slack plugin's shape, for Discord.
  discordPlugin,
  // Ghost in meetings, a plugin for each service (Matt, 2026-10-26: "Make sure the Google Meet and the Zoom plugins
  // are two different plugins"): meetings/meetings.dart.
  googleMeetPlugin,
  zoomPlugin,
  // Matt, 2026-10-27: "Build a plugin for elevenlabs and allow creating voice overs of notes using elevenlabs with
  // several voices to choose from": Lovart's shape, for a note read aloud (elevenlabs/elevenlabs.dart).
  elevenLabsPlugin,
]);

void Function()? _unhear;

/// Makes the built-in plugins the app's ([plugins]), and hands them every pass of the feed's rows from now on, so the sync
/// engine never names one. [store] is where the switches are kept (the device's, unless a test says); [localOnly]
/// is the preference, asked on every question. Asked twice, the second registry takes the first's place and the
/// rows go to it alone.
Registry installBuiltInPlugins({SwitchStore store = const StoredSwitches(), bool Function()? localOnly}) {
  final registry = createRegistry(builtIn, store: store, localOnly: localOnly);
  usePlugins(registry);
  _unhear?.call();
  // Asked of whichever registry is the app's by then: a test's own is not passed over.
  _unhear = onArrived((before, rows) => plugins.newRows(before, rows));
  return registry;
}
