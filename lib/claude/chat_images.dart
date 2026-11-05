/// Pictures given to the assistant in its chat (docs/CLAUDE_APP.md, "Pictures"; Matt, 2026-11-05: "Add the ability to
/// upload images to Claude in app (or whatever AI were using) so that it can inject contents of images broken apart
/// into notes such as a list of appointments").
///
/// A picture is chosen, pasted or dropped in the chat (lib/claude/claude_chat.dart), made ready here ([readyChatImage]:
/// its kind read from its first bytes, its long side brought down to [chatImageLongSide]) and sent with the ask as a
/// Messages API `image` block before the words ([claudeImageBlock]). Every other provider's client translates that
/// block into its own (lib/plugins/openai/chat_api.dart an `image_url` part with a data URL, lib/plugins/gemini an
/// `inlineData` part), as it translates the rest of the conversation (lib/assistant/provider.dart).
///
/// **Who can see one** ([aiSeesImages]): a picture is only offered to a model that reads pictures, so none is sent
/// where it would be dropped without a word. Claude's models all do; OpenAI's and Gemini's by their names; a custom
/// endpoint's and Aster's only where the model's name says it sees (`vision`, `-vl`, `llava`, a GPT-4o…). The chat's
/// attach button says so where they cannot, and points at Settings › AI.
///
/// **Kept nowhere.** The picture's bytes live in the chat's conversation, in memory, until New chat or the app closes;
/// the file the picker left in the cache is deleted as soon as it is read. Only where the person switches on "Keep
/// pictures in notes" is the AI offered a tool that puts the picture itself into a note ([ClaudePictureTool]), through
/// the library's own pictures.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// How many pictures one message may carry.
const int chatImageLimit = 5;

/// How many pictures one conversation may carry in all, every follow-up sending them again: New chat starts over.
const int chatConversationImageLimit = 20;

/// The long side a picture is sent at, at most: what Claude reads a picture at before it scales one down itself.
const int chatImageLongSide = 1568;

/// The JPEG quality a picture drawn smaller is written at, of 100.
const int chatImageQuality = 85;

/// The most a picture may weigh once ready: under the 5 MB the providers take, once it is base64.
const int chatImageMaxBytes = 3750000;

/// Draws a picture again as a JPEG, its long side at most [longSide]: the device's writer (lib/sync/device.dart's
/// `JpegShrink`, Kotlin's `Pictures.smaller` on Android). Null where the picture would not open.
typedef ChatJpeg = Future<Uint8List?> Function(Uint8List bytes, {required int longSide, required int quality});

/// Why a picture cannot be sent, in a sentence for the chat.
class ChatImageProblem implements Exception {
  const ChatImageProblem(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A picture ready to send: its bytes, what kind they are, and how big it is drawn.
@immutable
class ChatImage {
  const ChatImage({required this.bytes, required this.mediaType, required this.width, required this.height});

  final Uint8List bytes;

  /// `image/jpeg`, `image/png`, `image/webp` or `image/gif`.
  final String mediaType;
  final int width;
  final int height;

  /// The name's ending for its kind, for a picture kept in a note.
  String get extension => switch (mediaType) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
        _ => 'jpg',
      };
}

/// The kind of picture [bytes] are, by their first bytes; null for anything a provider would not read.
String? chatImageType(Uint8List bytes) {
  bool starts(List<int> magic, [int at = 0]) {
    if (bytes.length < at + magic.length) return false;
    for (var i = 0; i < magic.length; i += 1) {
      if (bytes[at + i] != magic[i]) return false;
    }
    return true;
  }

  if (starts(const [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (starts(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'image/png';
  if (starts(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (starts(const [0x52, 0x49, 0x46, 0x46]) && starts(const [0x57, 0x45, 0x42, 0x50], 8)) return 'image/webp';
  return null;
}

/// How big [bytes] are drawn, or null where they will not open.
Future<({int width, int height})?> _sizeOf(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final described = await ui.ImageDescriptor.encoded(buffer);
    final size = (width: described.width, height: described.height);
    described.dispose();
    buffer.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

/// [bytes] drawn again as a PNG with its long side [longSide]: where the device has no JPEG writer.
Future<Uint8List?> _png(Uint8List bytes, int width, int height, int longSide) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final described = await ui.ImageDescriptor.encoded(buffer);
    final codec = await described.instantiateCodec(targetWidth: width >= height ? longSide : null, targetHeight: height > width ? longSide : null);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    described.dispose();
    buffer.dispose();
    return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}

/// [bytes] made ready to send (see the header): a picture whose long side is over [longSide] (by more than a twentieth)
/// drawn again smaller,
/// as a JPEG by [jpeg] where the device writes one, else as a PNG. Throws [ChatImageProblem] with the chat's
/// sentence for what is not a picture, will not open, or is still too heavy.
Future<ChatImage> readyChatImage(Uint8List bytes, {ChatJpeg? jpeg, int longSide = chatImageLongSide, int maxBytes = chatImageMaxBytes}) async {
  final type = chatImageType(bytes);
  if (type == null) throw const ChatImageProblem('That isn’t a picture the AI can read. Send a JPEG, PNG, WebP or GIF.');
  final size = await _sizeOf(bytes);
  if (size == null || size.width < 1 || size.height < 1) throw const ChatImageProblem('That picture couldn’t be opened.');
  var out = bytes, kind = type, width = size.width, height = size.height;
  final long = math.max(width, height);
  // A little over is let be: the device's chooser keeps 1600, which every provider scales the rest of the way itself,
  // and drawing it again would only make it heavier (a PNG) or blurrier (a second JPEG).
  if (long > longSide * 1.05) {
    final scale = longSide / long;
    final w = math.max(1, (width * scale).round()), h = math.max(1, (height * scale).round());
    Uint8List? drawn;
    if (jpeg != null) {
      try {
        drawn = await jpeg(bytes, longSide: longSide, quality: chatImageQuality);
      } catch (_) {
        drawn = null;
      }
      if (drawn != null && chatImageType(drawn) == 'image/jpeg') {
        kind = 'image/jpeg';
      } else {
        drawn = null;
      }
    }
    if (drawn == null) {
      drawn = await _png(bytes, width, height, longSide);
      if (drawn != null) kind = 'image/png';
    }
    if (drawn != null) {
      out = drawn;
      width = w;
      height = h;
    } else {
      kind = type;
    }
  }
  if (out.length > maxBytes) throw const ChatImageProblem('That picture is too large to send. Try a smaller one, or a screenshot of it.');
  return ChatImage(bytes: out, mediaType: kind, width: width, height: height);
}

/// [image] as a Messages API content block: what the run sends before the words of the ask.
Map<String, Object?> claudeImageBlock(ChatImage image) => {
      'type': 'image',
      'source': {'type': 'base64', 'media_type': image.mediaType, 'data': base64Encode(image.bytes)},
    };

/// An `image` block's picture as `(mediaType, base64)`, or null for any other block: for the providers' translators.
({String mediaType, String data})? imageBlockData(Object? block) {
  if (block is! Map || block['type'] != 'image') return null;
  final source = block['source'];
  if (source is! Map || source['type'] != 'base64') return null;
  final type = source['media_type'], data = source['data'];
  if (type is! String || data is! String || data.isEmpty) return null;
  return (mediaType: type, data: data);
}

/// Words for a model's name, lower case, for [aiSeesImages].
final RegExp _openAiSees = RegExp(r'^(?:[a-z-]+/)?(?:gpt-4o|chatgpt-4o|gpt-4\.1|gpt-4\.5|gpt-4-turbo|gpt-4-vision|gpt-[5-9]|o1(?!-mini|-preview)|o3(?!-mini)|o4)');
final RegExp _openAiBlind = RegExp(r'audio|realtime|transcribe|tts|embedding|search|codex|moderation|whisper|dall-e');
final RegExp _otherSees = RegExp(
  r'vision|[-_/]vl\b|\bvl[-_]|-vl-|llava|bakllava|pixtral|gpt-4o|gpt-4\.1|gpt-[5-9]|claude|gemini|gemma-?3|llama-?4|llama-3\.2-(?:11|90)b|minicpm-v|moondream|qwen[0-9.]*-?vl|qvq|glm-[0-9.]+v|internvl|molmo|phi-[34](?:\.\d)?-(?:multimodal|vision)|mistral-(?:small|medium)-3|kimi-vl|grok-(?:[2-9]-)?vision',
);

/// Whether [model], asked through [provider] (`claude`, `openai`, `gemini`, `custom-ai`, `aster`), reads pictures
/// (see the header). Anything not known to is taken not to: a picture is never sent where it would be dropped.
bool aiSeesImages(String provider, String model) {
  final m = model.trim().toLowerCase();
  if (m.isEmpty) return false;
  switch (provider) {
    case 'claude':
      // Every Claude since the third reads pictures; the second and Instant did not.
      return m.startsWith('claude-') && !m.startsWith('claude-2') && !m.startsWith('claude-instant');
    case 'openai':
      return _openAiSees.hasMatch(m) && !_openAiBlind.hasMatch(m);
    case 'gemini':
      final name = m.startsWith('models/') ? m.substring(7) : m;
      if (name.contains('embedding') || name.startsWith('aqa') || name.contains('-tts') || name.contains('imagen')) return false;
      if (name == 'gemini-pro' || name.startsWith('gemini-1.0-pro')) return false;
      return name.startsWith('gemini-') || RegExp(r'^gemma-?3').hasMatch(name);
    case 'local':
      // The device's own model reads words only.
      return false;
    default:
      return _otherSees.hasMatch(m);
  }
}

/// What the chat says where the model asked cannot see pictures.
const String chatImageHint = 'Pick a model that can see images in Settings › AI.';

/// The chips offered when a picture is attached and nothing is written yet: each sent as the ask.
const List<String> chatImageChips = ['Make a note of this', 'Add these appointments', 'Make a to-do list', 'Summarise'];

/// What is asked where a picture is sent with no words.
const String chatImageDefaultAsk = 'Make a note of this';

/// The tool that puts a picture of the conversation into a note, offered only where the person lets it (see the
/// header).
abstract final class ClaudePictureTool {
  static const add = 'add_picture_to_note';
}

/// [ClaudePictureTool.add], as the API is told it.
final Map<String, Object?> claudePictureTool = {
  'name': ClaudePictureTool.add,
  'description':
      'Puts one of the pictures the person sent in this chat into a note, as a picture at the note’s end, kept among their pictures. Only where the picture itself belongs in the note (a photo of a whiteboard or a receipt kept beside its words); the words you read from it are written with the other tools.',
  'input_schema': {
    'type': 'object',
    'properties': {
      'id': {'type': 'string', 'description': 'The note’s id.'},
      'picture': {'type': 'integer', 'description': 'Which picture, counting from 1 in the order they were sent in this chat.'},
      'caption': {'type': 'string', 'description': 'A few words under it, or none.'},
    },
    'required': ['id', 'picture'],
  },
};

/// Keeps a picture's bytes among the library's pictures and answers its name (`image/<name>` in a note).
typedef ChatPictureKeeper = Future<String> Function(Uint8List bytes, String extension);

/// The system prompt's words on pictures (lib/claude/claude_tools.dart `claudeSystem`).
const String claudePictureSystem = '''When the person sends a picture (a photo, a screenshot, a scan), read everything in it, small print included, before you answer.
When they ask, or when the picture is plainly a list (appointments, a schedule, a timetable, a receipt, a to-do list, a flyer’s dates, a business card), break it into structured markdown and write it with the note tools: one line per item, in the order the picture has them, nothing invented, and anything you can’t read said so (“[unclear]”) rather than guessed.
Ghost.md’s own marks, so the lines work in the app: a to-do is `- [ ] Words`; a day goes after the words as `📅 2026-11-12` (ISO, which puts it on the app’s calendar), and a time in the words as `14:30`; a place in the words, as the picture writes it. An appointment is `- [ ] Dentist, Dr Lee, 14:30, 12 High St 📅 2026-11-12`. Use the year the picture gives, else the next one that date falls in from today. A receipt is a table or a list of items with their prices and the total; a business card the person’s name, role, company and each way to reach them; a whiteboard or a handwritten page its words as headings and lists.
One note for the whole picture unless they ask for one note per item. Then say in a sentence what you made, naming each note as [[Title]].''';

/// Where the chat's pictures come from, as the app has them (lib/root/root_claude.dart): the device's chooser (a
/// phone's photo library, camera and files, a Mac's open panel), the clipboard (a Mac's paste), and what is dropped
/// on the window (a Mac). Each answers a picture's bytes, read and let go of: nothing is left in the cache.
@immutable
class ChatPictureSource {
  const ChatPictureSource({this.pick, this.clipboard, this.dropped, this.jpeg});

  /// The chooser; null when none was chosen. Throws with a sentence for the chat.
  final Future<Uint8List?> Function()? pick;

  /// What is on the clipboard: a picture, else words, else neither. None where the paste is the field's own.
  final Future<({Uint8List? picture, String? text})> Function()? clipboard;

  /// Pictures dropped on the window while the chat is up.
  final Stream<Uint8List>? dropped;

  /// The device's JPEG writer, for [readyChatImage].
  final ChatJpeg? jpeg;
}
