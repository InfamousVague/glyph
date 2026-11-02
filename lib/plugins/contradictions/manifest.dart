/// The contradiction finder's manifest and its host (docs/CONTRADICTIONS.md; Matt, 2026-11-02: "Contradiction finder:
/// spots when a newer note disagrees with an older one (e.g. 'release is Thursday' in one, 'release moved to Monday' in
/// a later meeting) and flags the stale one inline, 'superseded by …', so old notes stop misleading you or the AI").
///
/// It asks no network of its own: the AI it uses is whichever is connected (the AI plugins' clients, or the model on the
/// device), so Local only does not hold it off; it holds it to the device's model (lib/ai/contradictions/ai.dart).
library;

import '../../ai/contradictions/runner.dart' show contradictionsBookKey, contradictionsSettingsKey;
import '../host.dart';
import '../types.dart';

const PluginManifest manifest = PluginManifest(
  id: 'contradictions',
  name: 'Contradiction finder',
  description:
      'Notices when a newer note disagrees with an older one (“release is Thursday” in a plan, “release moved to Monday” in a later meeting) and marks the older line as possibly out of date, so old notes stop misleading you or the AI. Checked in the background by whichever AI you have connected, or the model on this device with Local only.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.ai,
  tagline: 'Flags old notes a newer one contradicts',
  adds: [
    'A quiet “Out of date?” at the end of a line a newer note contradicts, with what the newer note says',
    'Mark superseded, which writes a “> Superseded by [[Newer note]]” line under it',
    'Not a conflict, remembered so it never comes back',
    'A list of what may be out of date on its page, and a line on the home page',
  ],
  // Off until added: it reads every note and sends pairs of them to the AI.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Reads your notes to find pairs that talk about the same thing, and writes a “Superseded by” line under a stale one when you press Mark superseded.'),
    PluginPermission(Permission.ai, 'Asks the AI you have connected (or the model on this device) whether the newer of two notes changes what the older one says. Only the lines with dates, numbers and shared names go.'),
  ],
  storage: [contradictionsSettingsKey, contradictionsBookKey],
);

/// The plugin's one way onto the phone (lib/plugins/host.dart).
final PluginHost host = createHost(manifest);
