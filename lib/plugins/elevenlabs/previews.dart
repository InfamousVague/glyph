/// A voice heard before it is picked: a short line read by it, made once with the person's key and kept in the
/// app's cache, then played on the memos' player (lib/tapes/clip_player.dart), as a voice-over in a note is.
///
/// Made, not fetched: ElevenLabs lists a sample for its voices, but on a host of Google's this plugin does not reach
/// (its manifest holds it to elevenlabs.io), and a line read with the model chosen is what a voice-over will sound
/// like. It costs [previewLine]'s characters once a voice and model, which the page says; kept in the cache, it may be
/// lost, and is made again when asked.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/attachment_refs.dart' show cachedSoundSrc, cachedSoundsFolder;
import '../../core/native/device_paths.dart';
import '../../editor/media/clip_refs.dart' show wholeSound;
import '../../editor/media/clips.dart' show ClipPlayer;
import 'client.dart';

/// What a preview reads.
String previewLine(String name) => 'Hello, I’m $name. This is how your notes will sound, read aloud.';

/// The player previews play on: the memos', which the app's root hands the plugin; none in a test or a build
/// without one.
ClipPlayer? elevenLabsPlayer;

/// The cache's folder of sounds, where previews are kept.
Future<String> Function() previewFolder = () async => '${(await DevicePaths.find()).cacheDir}/$cachedSoundsFolder';

/// A preview's file name, by voice and model: `elevenlabs-<voice>-<model>.mp3`.
String previewName(String voiceId, String modelId) => 'elevenlabs-$voiceId-${modelId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}.mp3';

/// The voice whose preview is being made now, if any.
final ValueNotifier<String?> previewMaking = ValueNotifier<String?>(null);

/// Makes [voiceId]'s preview where it is not kept, and plays it. Answers what to say where it could not be.
Future<String?> playPreview({required String voiceId, required String name, required String modelId}) async {
  final player = elevenLabsPlayer;
  if (player == null) return 'This device can’t play a preview.';
  final file = previewName(voiceId, modelId);
  final String folder;
  try {
    folder = await previewFolder();
  } catch (_) {
    return 'This device can’t keep a preview.';
  }
  final kept = File('$folder/$file');
  if (!await kept.exists()) {
    final client = elevenLabsClient();
    if (client == null) return 'Add your ElevenLabs key first.';
    previewMaking.value = voiceId;
    try {
      final Uint8List bytes = await client.speak(previewLine(name), voiceId: voiceId, modelId: modelId);
      await Directory(folder).create(recursive: true);
      await kept.writeAsBytes(bytes, flush: true);
    } on ElevenFailure catch (failure) {
      return failure.message;
    } on FileSystemException {
      return 'This device can’t keep a preview.';
    } finally {
      if (previewMaking.value == voiceId) previewMaking.value = null;
    }
  }
  try {
    await player.play(cachedSoundSrc(file), wholeSound);
    return null;
  } catch (_) {
    return 'The preview couldn’t be played.';
  }
}

/// Whether [voiceId]'s preview is what the player is sounding now.
bool previewPlaying(String voiceId, String modelId) => elevenLabsPlayer?.playing?.src == cachedSoundSrc(previewName(voiceId, modelId));
