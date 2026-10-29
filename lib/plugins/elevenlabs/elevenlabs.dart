/// The ElevenLabs plugin: a note read aloud in a voice the person chooses, kept in the note as a sound (Matt,
/// 2026-10-27: "Build a plugin for elevenlabs and allow creating voice overs of notes using elevenlabs with several
/// voices to choose from"). The app's own: neither the web app nor the Tauri one has it. ElevenLabs was declined for
/// the app as a whole on 2026-09-28 ("elevenlabs is too much"); this is Matt's later ask, and is a plugin, off until
/// added, spending only the person's own ElevenLabs credits.
///
/// Where it shows, once added in the Market (off until then):
/// - **Voice-over** on the note's cog: the voices to choose from (voices.dart), the chosen one first, and on the row
///   what it will cost before anything is asked (voice_over.dart [voiceOverHint]). The sound is kept as the note's
///   file and its line put under the title, where its card plays it (lib/editor/media/attachments.dart).
/// - Its page in Settings: the key, checked before it is kept; the voice, each to hear first; the model
///   (elevenlabs_pane.dart); and its setup at the head (elevenlabs_setup.dart), which the Market opens as it is added.
///
/// While a note is read the device is held (elevenlabs_hold.dart), so it goes on behind another app.
library;

import '../types.dart';
import 'client.dart';
import 'elevenlabs_mark.dart';
import 'elevenlabs_pane.dart';
import 'elevenlabs_setup.dart';
import 'manifest.dart';
import 'voice_over.dart';
import 'voices.dart';

export 'client.dart';
export 'elevenlabs_hold.dart';
export 'elevenlabs_mark.dart';
export 'elevenlabs_pane.dart';
export 'elevenlabs_setup.dart';
export 'manifest.dart' show apiKeySecret, modelKey, ownVoicesKey, voiceKey;
export 'previews.dart';
export 'speech_text.dart';
export 'voice_over.dart';
export 'voices.dart';

String _summary() => hasElevenKey() ? 'Key kept · ${chosenVoice().name}' : 'Not set up';

/// The voices as the Voice-over row's page lists them: the chosen one first, then the rest in order.
List<ActionChoice> voiceOverChoices(String noteId) {
  final chosen = chosenVoice();
  final all = voiceChoices();
  return [
    for (final voice in [chosen, ...all.where((v) => v.id != chosen.id)])
      ActionChoice(id: voice.id, label: voice.name, hint: voice.own ? '${voice.line} · Your own voice' : voice.line),
  ];
}

final GlyphPlugin elevenLabsPlugin = GlyphPlugin(
  manifest: manifest,
  icon: 'audio-lines',
  setup: elevenLabsSetup,
  settings: PluginSettings(
    pane: (context) => const ElevenLabsPane(),
    hue: 'mint',
    settings: elevenLabsFindable,
    summary: _summary,
  ),
  noteActions: [
    NoteAction(
      id: 'elevenlabs-voice-over',
      label: 'Voice-over',
      icon: elevenLabsIcon,
      visible: (noteId, body) => body.trim().isNotEmpty,
      hint: (noteId, body) => voiceOverHint(body),
      enabled: (noteId, body) {
        if (voiceOverUnready() != null || voiceOverMaking.value.containsKey(noteId)) return false;
        return voiceOverRefusal(VoiceOverPlan(body)) == null;
      },
      choices: voiceOverChoices,
      run: (editing, [choice]) => makeVoiceOver(editing, choice),
    ),
  ],
);
