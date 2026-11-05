/// Wrapped's manifest and its host (Matt, 2026-11-05: "create a plugin called "Wrapped" which gives you a "ghost
/// markdown wrapped" kinda like spotify wrapped but go through all the notes in the app in the backround slowly with
/// whatever agent is connected detect stale notes, unfinished items which we can chose to check off or remove from the
/// list, suggested reorginizations and more"; docs/WRAPPED.md).
///
/// It declares no network permission, as Cleanup does not: what it sends goes through the AI the person has connected,
/// by that AI's own plugin and key, or stays on the device with the device's model.
library;

import '../host.dart';
import '../types.dart';

/// The plugin's id.
const String wrappedId = 'wrapped';

/// Where what the pass found is kept on this device while the Library has no file Dart can reach (state.dart).
const String wrappedStateKey = 'glyph-wrapped';

const PluginManifest wrappedManifest = PluginManifest(
  id: wrappedId,
  name: 'Wrapped',
  description:
      'Your year in notes, as a story: how much you wrote, your busiest days, your streaks, your themes and the note you forgot. Then the useful part: the to-dos you never finished, the notes that went stale and the tidying your AI suggests, each with its own button. It reads your notes slowly in the background with the AI you have connected, and changes nothing until you press.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.ai,
  tagline: 'Your year in notes, and what to tidy',
  adds: [
    'A story of your year in notes, to swipe through and share',
    'Unfinished to-dos, stale notes and tidying, each a press away',
    'A Wrapped card on the home page and a row in the sidebar',
  ],
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Reads your own notes to count them and find what is unfinished or stale. Checks off, removes, archives, moves or merges only what you press, and each can be undone.'),
    PluginPermission(Permission.ai, 'Asks the AI you have connected for a one-line gist of each note, a few at a time, and once for themes and tidying. Its page says what is sent and about what it costs.'),
  ],
  storage: [wrappedStateKey],
);

/// The plugin's one way onto the phone.
final PluginHost wrappedHost = createHost(wrappedManifest);
