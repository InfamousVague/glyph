/// A note read aloud by ElevenLabs and kept at its top (Matt, 2026-10-27: "allow creating voice overs of notes using
/// elevenlabs with several voices to choose from").
///
/// - **What is read** is the note's words as a person reads them (speech_text.dart), in reads of at most
///   [voiceOverChunk] characters, each asked of ElevenLabs in turn and the MP3s joined end to end: MPEG audio is a
///   run of frames, so the parts play as one.
/// - **What it costs is said first.** ElevenLabs bills by the character, so the row on the note's menu says how many
///   characters it will read and about how many credits that is ([voiceOverCost]) before anything is asked; a note past
///   [voiceOverMost] characters is refused with its count rather than started.
/// - **Where it goes.** The sound is kept as one of the note's files (lib/files/attachment_store.dart), so it travels
///   with the note to the account's other devices as any file does, and its line is a file's line,
///   `[Voice-over, Elara.mp3](file/<uuid>.mp3 "1.2 MB")`, put under the note's title (or at its top where it has
///   none). The editor draws a sound's card with a Play of its own (lib/editor/media/attachments.dart), on the
///   memos' player. A voice-over made again takes the old one's line.
/// - **While it is made** the note says how far it is, [voiceOverMaking] holds it, and the device is held
///   (elevenlabs_hold.dart) so it goes on behind another app.
/// - **Eleven v4 refused** (a key whose text to speech may not use it): the first read is asked again with
///   Multilingual v2, and the note says so.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/attachment_refs.dart' show attachmentOfLine, AttachmentKind;
import '../../core/background_jobs.dart';
import '../../core/note_text.dart' show noteTitle;
import '../../core/front_matter.dart' show frontMatterEnd;
import '../../files/attachment_store.dart' show AttachmentBytes, KeptAttachment, storeAttachment;
import '../types.dart';
import 'client.dart';
import 'speech_text.dart';
import 'voices.dart';

/// The most characters one read asks for: under every model's limit, and short enough to be read in well under a
/// minute.
const int voiceOverChunk = 5000;

/// The most characters a voice-over reads: about fifty minutes, and at most 50,000 credits of the person's.
const int voiceOverMost = 50000;

/// What a voice-over's file is named, its words in the note: "Voice-over, Elara.mp3".
const String voiceOverWord = 'Voice-over';
String voiceOverName(String voice) => '$voiceOverWord, ${voice.replaceAll(RegExp(r'[\[\]\r\n\t/\\]+'), ' ').trim()}.mp3';

/// Whether [line] is a voice-over's: a sound file's line whose words begin "Voice-over".
bool isVoiceOverLine(String line) {
  final file = attachmentOfLine(line);
  return file != null && file.kind == AttachmentKind.sound && file.label.startsWith(voiceOverWord);
}

/// The notes being read now, by id, with how far each is ("Part 2 of 4").
final ValueNotifier<Map<String, String>> voiceOverMaking = ValueNotifier<Map<String, String>>(const {});

void _making(String noteId, String? words) {
  final next = {...voiceOverMaking.value};
  if (words == null) {
    if (next.remove(noteId) == null) return;
  } else {
    if (next[noteId] == words) return;
    next[noteId] = words;
  }
  voiceOverMaking.value = Map.unmodifiable(next);
}

/// Where a voice-over's sound is kept: the app's files, unless a test keeps its own.
Future<KeptAttachment> Function(Uint8List bytes, String name) keepVoiceOver = (bytes, name) => storeAttachment(AttachmentBytes(bytes), name: name);

/// 12345 as "12,345".
String grouped(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i += 1) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// What reading [body] would be: its words, its reads and its characters.
class VoiceOverPlan {
  VoiceOverPlan(String body) : text = speechText(body) {
    chunks = speechChunks(text, most: voiceOverChunk);
  }

  final String text;
  late final List<String> chunks;

  /// What ElevenLabs bills by: every character of every read.
  int get characters => chunks.fold(0, (sum, chunk) => sum + speechCharacters(chunk));
}

/// "3,420 characters, about 3,420 credits", for [characters] read with [model].
String voiceOverCost(int characters, ElevenModel model) {
  final credits = (characters * model.creditsPerCharacter).ceil();
  return '${grouped(characters)} ${characters == 1 ? 'character' : 'characters'}, about ${grouped(credits)} ElevenLabs ${credits == 1 ? 'credit' : 'credits'}';
}

/// Where a person tops up ElevenLabs' credits: its subscription page (the Top up of a voice-over stopped for them,
/// docs/ACTIVITY.md).
const String elevenBillingUrl = 'https://elevenlabs.io/app/subscription';

/// What says ElevenLabs cannot be asked here, or null.
String? voiceOverUnready() => hasElevenKey() ? null : 'Add your ElevenLabs key in Settings › ElevenLabs first.';

/// Why [plan] is not read, or null where it can be.
String? voiceOverRefusal(VoiceOverPlan plan) {
  if (plan.characters == 0) return 'There are no words in this note to read aloud.';
  if (plan.characters > voiceOverMost) return 'This note is ${grouped(plan.characters)} characters to read; a voice-over reads at most ${grouped(voiceOverMost)}. Split it, or make one of a shorter note.';
  return null;
}

/// The row's line on the note's menu: what it would cost, read by whom, or why not.
String voiceOverHint(String body) {
  final unready = voiceOverUnready();
  if (unready != null) return unready;
  final plan = VoiceOverPlan(body);
  final refused = voiceOverRefusal(plan);
  if (refused != null) return refused;
  final model = chosenModel();
  return 'Read aloud by ElevenLabs with ${model.name}: ${voiceOverCost(plan.characters, model)}. Kept at the top of the note.';
}

/// Where a voice-over's line goes in [body]: the line to change (1-based) and what it becomes. Where the note has a
/// voice-over already, its line; else under the title; else above the first words.
({int line, String Function(String text) next}) voiceOverPlace(String body, String markdown) {
  final lines = body.split('\n');
  for (var n = 0; n < lines.length; n += 1) {
    if (isVoiceOverLine(lines[n])) {
      final lead = RegExp(r'^\s*(?:[-*+]\s+)?').firstMatch(lines[n])!.group(0)!;
      return (line: n + 1, next: (_) => '$lead$markdown');
    }
  }
  var at = frontMatterEnd(lines);
  while (at < lines.length && lines[at].trim().isEmpty) {
    at += 1;
  }
  if (at >= lines.length) return (line: lines.isEmpty ? 1 : lines.length, next: (text) => text.trim().isEmpty ? markdown : '$text\n\n$markdown');
  if (RegExp(r'^\s{0,3}#{1,6}\s').hasMatch(lines[at])) {
    final blankAfter = at + 1 < lines.length && lines[at + 1].trim().isEmpty;
    return (line: at + 1, next: (text) => '$text\n\n$markdown${blankAfter || at + 1 >= lines.length ? '' : '\n'}');
  }
  return (line: at + 1, next: (text) => '$markdown\n\n$text');
}

/// Puts [markdown] where [voiceOverPlace] says, through the note's editor.
bool placeVoiceOver(NoteEditing editing, String markdown) {
  final place = voiceOverPlace(editing.body(), markdown);
  return editing.replaceLine((text, line) => line == place.line, place.next);
}

/// MP3 parts end to end.
Uint8List joinParts(List<Uint8List> parts) {
  final out = BytesBuilder(copy: false);
  for (final part in parts) {
    out.add(part);
  }
  return out.toBytes();
}

/// Reads the open note aloud in [voiceId] (the chosen voice where null), keeps it, and puts it at the note's top.
/// Answers whether it was; says why not on the note.
Future<bool> makeVoiceOver(NoteEditing editing, [String? voiceId]) async {
  final unready = voiceOverUnready();
  if (unready != null) {
    editing.say(unready);
    return false;
  }
  final noteId = editing.noteId;
  if (voiceOverMaking.value.containsKey(noteId)) {
    editing.say('ElevenLabs is already reading this note.');
    return false;
  }
  final voice = voiceOf(voiceId) ?? chosenVoice();
  final plan = VoiceOverPlan(editing.body());
  final refused = voiceOverRefusal(plan);
  if (refused != null) {
    editing.say(refused);
    return false;
  }
  final client = elevenLabsClient();
  if (client == null) return false;
  var model = chosenModel();
  var fellBack = false;
  final count = plan.chunks.length;
  _making(noteId, count == 1 ? 'Reading' : 'Part 1 of $count');
  editing.say('ElevenLabs is reading the note in ${voice.name}’s voice…');
  // On the app's record of running work (lib/core/background_jobs.dart; docs/ACTIVITY.md): the teal reels in the
  // ring, "Reading in Elara’s voice, 2 of 4 parts" and its credits in the tray, and "Voice-over ready · Open" as it lands
  // while the note is not on screen. Asked for by the person, so a long one chimes as it ends.
  final title = noteTitle(editing.body());
  final job = activity.begin(
    'voice-over:$noteId',
    kind: JobKind.audio,
    title: title.isEmpty ? 'Reading the note aloud' : 'Reading “$title” aloud',
    line: 'Reading in ${voice.name}’s voice',
    personStarted: true,
    shownHere: activityRoutes.noteShown(noteId),
    estimate: JobEstimate(credits: (plan.characters * model.creditsPerCharacter).ceil(), provider: 'ElevenLabs'),
  );
  var made = false;
  try {
    final parts = <Uint8List>[];
    for (var i = 0; i < count; i += 1) {
      if (count > 1) {
        _making(noteId, 'Part ${i + 1} of $count');
        if (i > 0) editing.say('ElevenLabs is reading part ${i + 1} of $count…');
        job.progress(done: i, total: count, steps: '${i + 1} of $count parts');
      }
      try {
        parts.add(await client.speak(plan.chunks[i], voiceId: voice.id, modelId: model.id));
      } on ElevenFailure catch (failure) {
        // A key whose text to speech may not use Eleven v4 reads with Multilingual v2: nothing was billed for the
        // read refused.
        if (!failure.modelRefused || model.id == multilingualV2.id || i > 0) rethrow;
        model = multilingualV2;
        fellBack = true;
        parts.add(await client.speak(plan.chunks[i], voiceId: voice.id, modelId: model.id));
      }
    }
    final kept = await keepVoiceOver(joinParts(parts), voiceOverName(voice.name));
    if (!placeVoiceOver(editing, kept.markdown)) {
      editing.say('The voice-over was made, but the note had changed under it.');
      return false;
    }
    editing.say('Added a voice-over read by ${voice.name}, at the top of the note.${fellBack ? ' Eleven v4 isn’t open to this key, so ${multilingualV2.name} read it.' : ''}');
    made = true;
    job.done(result: JobResult('Voice-over ready', action: 'Open', onOpen: activityRoutes.noteOpener(noteId)), tally: const JobTally('voice-over', 'voice-overs'));
    return true;
  } on ElevenFailure catch (failure) {
    final said = failure.tooLong ? '${failure.message} Try a shorter note, or another model in Settings › ElevenLabs.' : failure.message;
    editing.say(said);
    // Red in the tray, with its one fix: Top up for spent credits, Sign in again for a key refused.
    job.failed(said, fix: failure.spent ? activityRoutes.topUp(Uri.parse(elevenBillingUrl)) : failure.badKey ? activityRoutes.signIn('elevenlabs') : null);
    return false;
  } on StateError catch (failure) {
    editing.say(failure.message);
    job.failed(failure.message);
    return false;
  } finally {
    _making(noteId, null);
    // The note changed under it, or anything else that is not a failure of ElevenLabs': it goes quietly.
    if (!made) job.stopped();
  }
}
