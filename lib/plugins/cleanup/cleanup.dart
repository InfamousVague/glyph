/// The Cleanup plugin (Matt, 2026-11-02: "spawn a task making a 'cleanup' plugin that allows us to use whatever AI we
/// choose that's connected to clean up and sort the notes in a given folder"; docs/CLEANUP.md): a folder's notes read
/// by the AI the person chooses, every suggestion reviewed, only what is ticked applied, and a whole run undone in one.
///
/// Where it shows, once added in the Market (off until then):
/// - Its page in Settings (cleanup_pane.dart): the folder, the AI, the passes, what is sent, the review, Undo.
/// - Clean up with AI… in a folder's menu in All notes and the sidebar, and in a folder page's ••• menu
///   (lib/notes/folder_menu.dart, lib/notes/note_tree_spaces.dart): the page, at that folder.
/// - A job on the Activity tray while it reads, with Stop, wearing the chosen AI's mark.
///
/// The parts: plan.dart (the items and the answer's reader), prompts.dart (what is asked and sent), ai.dart (the AIs
/// connected), run.dart (the folder read and asked about in batches), apply.dart (applied, verified, taken back),
/// records.dart (each run kept), text.dart (titles, merges, the formatting-only check), review.dart, service.dart.
library;

import '../registry.dart' show pluginOn;
import '../types.dart';
import 'cleanup_pane.dart';
import 'manifest.dart';
import 'service.dart';

export 'ai.dart';
export 'apply.dart';
export 'cleanup_pane.dart';
export 'manifest.dart';
export 'plan.dart';
export 'prompts.dart';
export 'records.dart';
export 'review.dart';
export 'run.dart';
export 'service.dart';
export 'text.dart';

/// Whether Cleanup is on: a folder's menu offers Clean up with AI… only then.
bool cleanupOn() => pluginOn(cleanupManifest);

String _summary() {
  final service = CleanupService.current;
  final last = service?.records.all.firstOrNull;
  if (last == null) return 'No runs yet';
  return '${last.folderPath} · ${last.summary}';
}

final GlyphPlugin cleanupPlugin = GlyphPlugin(
  manifest: cleanupManifest,
  icon: 'brush-cleaning',
  settings: PluginSettings(
    pane: (context) => const CleanupPane(),
    hue: 'lime',
    settings: cleanupFindable,
    summary: _summary,
  ),
);
