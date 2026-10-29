/// ElevenLabs' setup (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-29: "add the voiceover onboarding for the
/// rest of the plugins"). Lovart's shape, in ElevenLabs' mint, over the key the plugin's page keeps (elevenlabs_pane.dart):
///
/// 1. **Notes read aloud**: what it does and what it costs, the person's own credits, a credit a character.
/// 2. **Make an ElevenLabs account**: its sign-up ([elevenSignUpUrl]).
/// 3. **Make a key**: profile › API Keys ([elevenKeysUrl]), a key that may use Text to Speech and read Voices, as the
///    page says. Neither address was opened while this was written (unverified).
/// 4. **Paste your key**: kept where the page keeps it ([apiKeySecret] in the secure store, through the plugin's host),
///    so the sealed sync follows it.
/// 5. **Check it works**: `GET /v1/user` ([ElevenLabsClient.check]), which spends nothing. Said in plain words
///    ([elevenSetupResult]), the page's own where it has them: a refused key let go of and pasted again; a key that
///    may not read the account still reads aloud (a warning); the month's credits spent (a warning); no connection.
/// 6. **Try it**: Voice-over, on a note's cog.
library;

import '../../art/lucide.g.dart';
import '../host.dart' show onPluginStorage;
import '../onboarding/setup_flow.dart';
import '../types.dart' show PluginHost;
import 'client.dart';
import 'manifest.dart' as eleven;

/// ElevenLabs' sign-up (unverified).
const String elevenSignUpUrl = 'https://elevenlabs.io/app/sign-up';

/// ElevenLabs' API keys, under the profile (unverified).
const String elevenKeysUrl = 'https://elevenlabs.io/app/settings/api-keys';

String? _keyShape(String text) {
  if (RegExp(r'\s').hasMatch(text)) return 'Paste the key alone: it has no spaces in it.';
  if (text.length < 20) return 'That key looks cut short. Copy all of it from ElevenLabs.';
  return null;
}

/// The check's answer (see the header). [via] is the host the key is read through; [client] a test's own ElevenLabs.
Future<SetupResult> elevenSetupResult({PluginHost? via, ElevenLabsClient? Function()? client}) async {
  final on = via ?? eleven.host;
  final asked = (client ?? () => ElevenLabsClient.kept(via: via))();
  if (asked == null) return const SetupResult.failed('No key is kept yet. Paste it first.', pasteAgain: true);
  final wrong = await asked.check();
  if (wrong == null) return const SetupResult.ok('Your key works. ElevenLabs is ready to read your notes.');
  if (wrong.badKey) {
    // Never kept once refused, as the page has it.
    await on.secrets.write(eleven.apiKeySecret, null);
    return const SetupResult.failed('ElevenLabs refused that key. Copy it again from your ElevenLabs profile, under API Keys.', pasteAgain: true);
  }
  if (wrong.missingPermission) return const SetupResult.warn('Kept. This key may not read your account, so what is left of the month isn’t shown; voice-overs still work if it may read aloud.');
  if (wrong.spent) return SetupResult.warn('The key works, but ElevenLabs says the credits are spent: ${wrong.message}');
  return SetupResult.failed(wrong.message);
}

/// ElevenLabs' setup (see the header). [via] is the host its key is kept through; [client] a test's own ElevenLabs.
PluginSetup elevenLabsSetup({PluginHost? via, ElevenLabsClient? Function()? client}) {
  final on = via ?? eleven.host;
  return PluginSetup(
    id: 'elevenlabs',
    name: 'ElevenLabs',
    hues: const ['mint', 'cyan', 'green'],
    tiles: const [Lucide.audioLines, Lucide.volume2, Lucide.mic, Lucide.sparkles],
    ready: () => hasElevenKey(on),
    watch: onPluginStorage,
    prepare: on.secrets.warm,
    steps: [
      const SetupIntro(
        id: 'intro',
        title: 'Notes read aloud',
        icon: Lucide.audioLines,
        points: [
          (Lucide.volume2, 'Voice-over, on any note’s cog: read aloud and kept at its top, to play where it sits'),
          (Lucide.mic, 'A choice of voices, with your own from ElevenLabs beside them, each to hear first'),
          (Lucide.gauge, 'With your ElevenLabs credits: a credit a character'),
        ],
      ),
      const SetupOpen(id: 'account', title: 'Make an ElevenLabs account', icon: Lucide.userPlus, links: [SetupLink('Open ElevenLabs', elevenSignUpUrl, verified: false)]),
      const SetupOpen(id: 'key', title: 'Make a key', icon: Lucide.keyRound, links: [SetupLink('Open API Keys', elevenKeysUrl, verified: false)]),
      SetupPaste(
        id: 'paste',
        title: 'Paste your key',
        icon: Lucide.clipboardPaste,
        fields: const [SetupField(id: 'key', label: 'API key', placeholder: 'sk_…', shape: _keyShape)],
        save: (values) async {
          await on.secrets.write(eleven.apiKeySecret, values['key']);
          return null;
        },
      ),
      SetupCheck(id: 'check', title: 'Check it works', icon: Lucide.shieldCheck, checking: 'Asking ElevenLabs…', run: () => elevenSetupResult(via: via, client: client)),
      const SetupDone(id: 'done', title: 'Try it', icon: Lucide.wandSparkles),
    ],
  );
}
