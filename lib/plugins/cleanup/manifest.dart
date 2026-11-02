/// The Cleanup plugin's manifest and its host (Matt, 2026-11-02: "spawn a task making a 'cleanup' plugin that allows
/// us to use whatever AI we choose that's connected to clean up and sort the notes in a given folder";
/// docs/CLEANUP.md).
///
/// It declares no network permission: it reaches no host of its own. What it sends goes through the AI the person
/// chose, by that AI's own plugin and key (lib/assistant/), or stays on the device with the device's model; so Local
/// only does not hold it off, it leaves it the device's model alone (ai.dart). The permission's words say so.
library;

import '../host.dart';
import '../types.dart';
import 'records.dart' show cleanupRunsKey;

/// The storage key the page's choices are kept under: the passes and the AI last chosen.
const String cleanupOptionsKey = 'glyph-cleanup';

const PluginManifest cleanupManifest = PluginManifest(
  id: 'cleanup',
  name: 'Cleanup',
  description:
      'Tidies and sorts the notes of a folder with the AI you choose: Claude, OpenAI, Gemini, Aster, your own endpoint or the model on your phone. It suggests sub-folders, better titles, duplicates to merge, broken Markdown to fix, tags, links and stale notes to archive; you review every suggestion, and only what you tick is changed. Nothing is deleted, and a whole run can be undone.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.ai,
  tagline: 'Sort and tidy a folder with your AI',
  adds: [
    'Clean up with AI… in a folder’s menu',
    'A review of every suggestion before anything changes',
    'Undo for a whole run, now or later',
  ],
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Reads the notes of the folder you choose, and moves, retitles, edits, archives or puts in the Trash only the ones you tick on its review.'),
    PluginPermission(Permission.ai, 'Asks the AI you choose on its page: the model on your phone, or a cloud AI you have connected, through that AI’s own plugin and key. Its page says exactly what is sent.'),
  ],
  storage: [cleanupOptionsKey, cleanupRunsKey],
);

/// The plugin's one way onto the phone.
final PluginHost cleanupHost = createHost(cleanupManifest);
