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
/// Meetings; then ElevenLabs; then the other AI providers, OpenAI, Gemini, a custom OpenAI-compatible endpoint and
/// Aster (docs/AI_PROVIDERS.md); then Keyboard modes. The app's own Claude is the Claude plugin's other half.
library;

import '../integrations/webhooks/plugin.dart' show webhooksPlugin;
import '../sync/arrived.dart' show onArrived;
import 'aster/aster.dart' show asterPlugin;
import 'calendar/calendar.dart' show calendarPlugin;
import 'claude/claude.dart' show claudePlugin;
import 'cleanup/cleanup.dart' show cleanupPlugin;
import 'contacts/contacts.dart' show contactsPlugin;
import 'contradictions/contradictions.dart' show contradictionsPlugin;
import 'custom_ai/custom_ai.dart' show customAiPlugin;
import 'discord/discord.dart' show discordPlugin;
import 'elevenlabs/elevenlabs.dart' show elevenLabsPlugin;
import 'figma/figma.dart' show figmaPlugin;
import 'gemini/gemini.dart' show geminiPlugin;
import 'git_backup/git_backup.dart' show gitBackupPlugin;
import 'github/github.dart' show githubPlugin;
import 'keymaps/keymaps.dart' show keymapsPlugin;
import 'lovart/lovart.dart' show lovartPlugin;
import 'marks_plugin.dart' show marksPlugin;
import 'meetings/meetings.dart' show googleMeetPlugin, zoomPlugin;
import 'more/more_tools.dart' show morePlugins;
import 'notion/notion.dart' show notionPlugin;
import 'openai/openai.dart' show openAiPlugin;
import 'places/places.dart' show placesPlugin;
import 'projects/suite.dart' show projectPlugins;
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
  // Matt, 2026-10-29: "Add support for aster 6 and other Ai models as plugins in addition to claude like openAI google
  // gemini etc": each a plugin of its own, off until added (docs/AI_PROVIDERS.md; lib/assistant/ is what they share).
  openAiPlugin,
  geminiPlugin,
  customAiPlugin,
  // Matt, 2026-10-29: "aster 6 is OpenAI-compatible, add it as a plugin": Custom AI model's shape at Aster's address
  // (aster/aster.dart).
  asterPlugin,
  // Matt, 2026-10-29: "add vim controls to the app via a plugin as well", then "add a vim / emac controls via a
  // plugin": a note typed from a hardware keyboard as Vim or Emacs types (keymaps/keymaps.dart).
  keymapsPlugin,
  // Matt, 2026-10-31: "add a plugin to backup on git": the Library folder committed and pushed to a repository the
  // person owns (git_backup/git_backup.dart, docs/GIT_BACKUP.md).
  gitBackupPlugin,
  // Matt, 2026-11-01: "move the project managment stuff like gantts and stuff into a suite of plugins that are
  // disabled by default": Tickets, Planning, Gantt and timelines, Boards, Automations, Time tracking and Forms, each
  // off until added, and an organization's own in its home page (projects/suite.dart, docs/PM_PLUGINS.md).
  ...projectPlugins,
  // Matt, 2026-11-01: "think about other things that can be plugins that might be overwhelming for a new user as
  // well": Canvas, Meetings, Diagrams and math, Places, Email to a note and Publishing, each off for a new person and on
  // where it was in use (more/more_tools.dart, docs/PM_PLUGINS.md §10).
  ...morePlugins,
  // Matt, 2026-11-02: "Also add a figma plugin": a Figma frame's link drawn as the frame itself, with the person's own
  // token, off until added (figma/figma.dart).
  figmaPlugin,
  // Matt, 2026-11-02, from a list of AI ideas: "Contradiction finder: spots when a newer note disagrees with an older
  // one … and flags the stale one inline, 'superseded by …'": off until added (contradictions/, docs/CONTRADICTIONS.md).
  contradictionsPlugin,
  // Matt, 2026-11-02: "spawn a task making a 'cleanup' plugin that allows us to use whatever AI we choose that's
  // connected to clean up and sort the notes in a given folder": a folder's notes sorted, retitled, merged and tidied
  // by the AI the person chooses, reviewed before anything changes, off until added (cleanup/cleanup.dart,
  // docs/CLEANUP.md).
  cleanupPlugin,
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
