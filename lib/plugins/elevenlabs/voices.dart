/// The voices a voice-over can be read in, and the model it is read with (Matt, 2026-10-27: "with several voices to
/// choose from"): a choice of eight from ElevenLabs' own, each with a line on how it sounds, then the person's own
/// voices as ElevenLabs lists them (client.dart [ElevenLabsClient.voices]); and the choice kept, which follows the
/// account (lib/sync/connections.dart).
///
/// **The eight** are ElevenLabs' current default voices, by the ids its help page "What are Default voices?" gives as
/// read on 2026-10-27. Not the older ones (Rachel, Adam, Roger, Sarah …): that page says those stop working at the end
/// of 2026 and only accounts made before March 2026 have them. The ids were read from ElevenLabs' page, not tried with
/// a key here (this Mac had none); a voice ElevenLabs refuses is said as such, and the person's own voices are always
/// offered beside these.
///
/// **The model** is Eleven v4 unless the person picks another (Matt: the newest, "Eleven v4", launched 2026-09-28).
/// Its id, `eleven_v4`, is from ElevenLabs' models page and its v4 page ("Eleven v4 (`eleven_v4`) — our
/// highest-quality model") as read on 2026-10-27. That page also says v4 is "available via the Text to Dialogue API",
/// so a key whose text to speech refuses it is read with Multilingual v2 instead (voice_over.dart).
library;

import 'package:flutter/foundation.dart';

import 'client.dart' show ElevenVoice;
import 'manifest.dart';

/// One of the voices the plugin offers of its own.
@immutable
class OfferedVoice {
  const OfferedVoice(this.id, this.name, this.line);
  final String id;
  final String name;

  /// How it sounds, in a few words.
  final String line;
}

/// The eight, in the order the page lists them.
const List<OfferedVoice> offeredVoices = [
  OfferedVoice('WQP7cQUF5aAS6Axh5yaa', 'Elara', 'A crisp, professional narrator'),
  OfferedVoice('gOupLcAkjEnguROwi4oS', 'Darian', 'A warm, grounded storyteller'),
  OfferedVoice('OZ0L6eISlOejga3XjDFt', 'Talia', 'A warm, soft guide'),
  OfferedVoice('6WwXjDDEMyNmFG95zycZ', 'Eldrin', 'A crisp British baritone'),
  OfferedVoice('dvbL7qkNGZY1IqPGZAjM', 'Elowen', 'An upbeat, modern narrator'),
  OfferedVoice('fnYMz3F5gMEDGMWcH1ex', 'Finley', 'An articulate news anchor'),
  OfferedVoice('22N9cF8z0o7y23njdyaY', 'Florence', 'An atmospheric storyteller'),
  OfferedVoice('jSuBIjxMKhqIfb0wCK1F', 'Baxter', 'A dry, calm Australian'),
];

/// The voice read in until another is picked: Elara, whose narrating suits a note best.
const String defaultVoiceId = 'WQP7cQUF5aAS6Axh5yaa';

/// A model a voice-over can be read with.
@immutable
class ElevenModel {
  const ElevenModel({required this.id, required this.name, required this.line, required this.most, this.creditsPerCharacter = 1});
  final String id;
  final String name;
  final String line;

  /// The most characters it reads in one request (ElevenLabs' "Character limits" table).
  final int most;

  /// What a character costs, in credits: Flash costs half.
  final double creditsPerCharacter;
}

/// The model of the newest voices.
const ElevenModel elevenV4 = ElevenModel(id: 'eleven_v4', name: 'Eleven v4', line: 'The newest, and the most expressive', most: 10000);

/// What a key Eleven v4 is refused for reads with.
const ElevenModel multilingualV2 = ElevenModel(id: 'eleven_multilingual_v2', name: 'Multilingual v2', line: 'Steady and natural, in 29 languages', most: 10000);

/// The models offered, Eleven v4 first.
const List<ElevenModel> elevenModels = [
  elevenV4,
  multilingualV2,
  ElevenModel(id: 'eleven_flash_v2_5', name: 'Flash v2.5', line: 'Quickest, at half the credits', most: 40000, creditsPerCharacter: 0.5),
];

/// The model of [id], or Eleven v4 for one this build does not offer.
ElevenModel modelOf(String? id) => elevenModels.firstWhere((model) => model.id == id, orElse: () => elevenV4);

/// The model chosen now.
ElevenModel chosenModel() => modelOf(host.storage.get<Object?>(modelKey, null) as String?);

void setModel(String id) => host.storage.set(modelKey, modelOf(id).id);

/// The person's own voices as last listed on this device.
List<ElevenVoice> ownVoices() {
  final Object? kept = host.storage.get<Object?>(ownVoicesKey, const <Object?>[]);
  if (kept is! List) return const [];
  return [for (final raw in kept) ?ElevenVoice.fromJson(raw)];
}

void keepOwnVoices(List<ElevenVoice> voices) => host.storage.set(ownVoicesKey, [for (final voice in voices) voice.toJson()]);

/// A voice as a choice: the offered ones and the person's own, by id.
@immutable
class VoiceChoice {
  const VoiceChoice({required this.id, required this.name, required this.line, this.own = false});
  final String id;
  final String name;
  final String line;

  /// One of the person's own voices.
  final bool own;
}

/// Every voice to choose from: the eight, then the person's own, each once.
List<VoiceChoice> voiceChoices() {
  final seen = <String>{};
  return [
    for (final voice in offeredVoices)
      if (seen.add(voice.id)) VoiceChoice(id: voice.id, name: voice.name, line: voice.line),
    for (final voice in ownVoices())
      if (seen.add(voice.id)) VoiceChoice(id: voice.id, name: voice.name, line: voice.line.isEmpty ? 'Your own voice' : voice.line, own: true),
  ];
}

/// The voice of [id] among the choices, or null.
VoiceChoice? voiceOf(String? id) {
  for (final voice in voiceChoices()) {
    if (voice.id == id) return voice;
  }
  return null;
}

/// The voice a voice-over is read in when none is picked: the one chosen, while it is still to be had, else Elara.
VoiceChoice chosenVoice() => voiceOf(host.storage.get<Object?>(voiceKey, null) as String?) ?? voiceOf(defaultVoiceId)!;

void setVoice(String id) => host.storage.set(voiceKey, id);
