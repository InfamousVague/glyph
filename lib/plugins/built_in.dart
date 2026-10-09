/// The plugins that ship with Ghost.md, and the one call that puts them in place. The foot of
/// `src/app/plugins/registry.ts` (`BUILT_IN`, `plugins`, and the feed's rows handed on).
///
/// On the page the registry is made as its module loads, so every file that imports it has the five. Here nothing
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
/// reason the list is here.
library;

import '../sync/arrived.dart' show onArrived;
import 'claude/claude.dart' show claudePlugin;
import 'github/github.dart' show githubPlugin;
import 'marks_plugin.dart' show marksPlugin;
import 'notion/notion.dart' show notionPlugin;
import 'registry.dart';
import 'slack/slack.dart' show slackPlugin;
import 'types.dart';

/// The plugins that ship with Ghost.md (`BUILT_IN`), in the page's order.
final List<GlyphPlugin> builtIn = List.unmodifiable([notionPlugin, githubPlugin, marksPlugin, claudePlugin, slackPlugin]);

void Function()? _unhear;

/// Makes the five the app's ([plugins]), and hands them every pass of the feed's rows from now on, so the sync
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
