/// Note decay alerts' manifest, its host and its settings (docs/NOTE_DECAY.md; Matt, 2026-11-02: "Note decay alerts:
/// docs and pages that reference things that have since changed (a renamed ticket, a merged PR on GitHub, an old
/// date) get a quiet 'may be out of date' mark with the reason"). The app's own: no company's product.
///
/// It declares no network of its own, so Local only leaves it on: what it reads is the library, and the two lookups
/// outside the phone (a GitHub link's state, a Figma frame's) are asked through the GitHub and Figma plugins, with
/// their tokens and under their own permissions, which Local only holds off as it holds them (lookups.dart). The AI
/// pass asks whatever AI is connected, or the phone's own model under Local only (ai.dart).
library;

import '../host.dart';
import '../types.dart';

/// The plugin's id: its switch, and its page's (`plugin:note-decay`).
const String noteDecayId = 'note-decay';

/// Whether the AI pass runs: its own switch, off until moved.
const String decayAiKey = 'glyph-note-decay-ai';

/// Whether GitHub and Figma are asked about a page's links: on, where those plugins are connected.
const String decayLookupsKey = 'glyph-note-decay-lookups';

/// How many months a docs page goes unedited before the `stale` check asks about the pages it links: 3.
const String decayMonthsKey = 'glyph-note-decay-months';

/// What each title was before a rename, heard on this device (signals.dart [DecayLibrary.renamedTo]): a cache, since
/// the library keeps no rename of its own and a `[[link]]` keeps the name it was written with (lib/core/link_index.dart).
const String decayRenamesKey = 'glyph-note-decay-renames';

const PluginManifest noteDecayManifest = PluginManifest(
  id: noteDecayId,
  name: 'Note decay alerts',
  description:
      'Marks a line of a page, quietly, where what it refers to has changed since it was written: a linked note renamed or put away, a ticket closed, a GitHub pull request merged, a date it speaks of as ahead now past. Each mark says why; Still right puts it away, and Update with AI suggests the edit for you to accept.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.ai,
  tagline: 'Pages that may be out of date, marked',
  adds: [
    'A quiet “May be out of date” mark on a line, with the reason',
    'Still right, which keeps it away until the thing changes again',
    'Update with AI: the edit shown as a change to accept or reject',
    'Pages that may be out of date, on a teamspace’s home and a docs notebook',
  ],
  // Off until added: a mark on a line is something a person should ask for.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Reads your notes to find what each page refers to, and writes “Still right” into a page’s front matter (decay-ok) when you tap it.'),
    PluginPermission(Permission.ai, 'With Check with AI on, asks your connected AI, or the phone’s own model with Local only, whether a flagged page is out of date and how to update it.'),
  ],
  storage: [decayAiKey, decayLookupsKey, decayMonthsKey, decayRenamesKey],
);

/// The plugin's one way onto the phone (lib/plugins/host.dart).
final PluginHost noteDecayHost = createHost(noteDecayManifest);

/// Whether the AI pass runs.
bool decayAiOn([PluginHost? via]) => (via ?? noteDecayHost).storage.get<Object?>(decayAiKey, false) == true;
void setDecayAi(bool on, [PluginHost? via]) => (via ?? noteDecayHost).storage.set(decayAiKey, on);

/// Whether GitHub and Figma are asked.
bool decayLookupsOn([PluginHost? via]) => (via ?? noteDecayHost).storage.get<Object?>(decayLookupsKey, true) != false;
void setDecayLookups(bool on, [PluginHost? via]) => (via ?? noteDecayHost).storage.set(decayLookupsKey, on);

/// The `stale` check's months, 1 to 12.
int decayMonths([PluginHost? via]) {
  final kept = (via ?? noteDecayHost).storage.get<Object?>(decayMonthsKey, 3);
  return kept is num ? kept.toInt().clamp(1, 12) : 3;
}

void setDecayMonths(int months, [PluginHost? via]) => (via ?? noteDecayHost).storage.set(decayMonthsKey, months.clamp(1, 12));

/// The renames heard, old title to new.
Map<String, String> decayRenames([PluginHost? via]) {
  final kept = (via ?? noteDecayHost).storage.get<Object?>(decayRenamesKey, const {});
  return kept is Map ? {for (final MapEntry(:key, :value) in kept.entries) if (key is String && value is String) key: value} : const {};
}

void setDecayRenames(Map<String, String> renames, [PluginHost? via]) => (via ?? noteDecayHost).storage.set(decayRenamesKey, renames);
