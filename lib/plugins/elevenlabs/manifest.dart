/// The ElevenLabs plugin's manifest and its host (Matt, 2026-10-27: "Build a plugin for elevenlabs and allow creating
/// voice overs of notes using elevenlabs with several voices to choose from"). The port's own: the web app has none.
///
/// ElevenLabs (elevenlabs.io) reads words aloud in a voice of the person's choosing. Its API takes the person's own key
/// in an `xi-api-key` header (client.dart); the key is kept in the device's secure store under [apiKeySecret] and
/// follows the account sealed (lib/sync/connections.dart), as Lovart's keys do.
///
/// `elevenlabs.io` covers `api.elevenlabs.io`, the one host it reaches: the voice-overs and the previews are both made
/// there, never fetched from anywhere else.
library;

import '../host.dart';
import '../types.dart';

/// The name the key is kept under in the secure store.
const String apiKeySecret = 'glyph-elevenlabs-key';

/// The voice a voice-over is read in when none is picked: a voice id (voices.dart). Follows the account.
const String voiceKey = 'glyph-elevenlabs-voice';

/// The model it is read with (voices.dart [elevenModels]). Follows the account.
const String modelKey = 'glyph-elevenlabs-model';

/// The person's own voices, as ElevenLabs last listed them: this device's copy, fetched again on the page.
const String ownVoicesKey = 'glyph-elevenlabs-own-voices';

const PluginManifest manifest = PluginManifest(
  id: 'elevenlabs',
  name: 'ElevenLabs',
  description: 'Voice-overs of your notes, read aloud by ElevenLabs in a voice you choose, kept in the note as a sound you can play.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.ai,
  tagline: 'Your notes, read aloud in the voice you choose',
  adds: [
    'Voice-over, on any note: read aloud by ElevenLabs and kept at its top, to play where it sits',
    'A choice of voices, with your own from ElevenLabs beside them, each to hear before you pick',
  ],
  // Off until added: it sends a note's words to ElevenLabs and spends the person's ElevenLabs credits.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Puts the voice-over it makes at the top of the note it reads.'),
    PluginPermission(Permission.network, 'Asks ElevenLabs to read a note aloud, with your own ElevenLabs key: only the words of the note you ask a voice-over for go there.'),
  ],
  hosts: ['elevenlabs.io'],
  storage: [voiceKey, modelKey, ownVoicesKey],
  secrets: [apiKeySecret],
);

/// The plugin's one way onto the phone (lib/plugins/host.dart).
final PluginHost host = createHost(manifest);
