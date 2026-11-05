/// Where the assistant's chat gets its pictures on this device (lib/claude/chat_images.dart [ChatPictureSource]): the
/// chooser the notes use (`ghost_md/pictures` `pick`: Android's chooser, the iPhone's menu of its photo library, its
/// camera and its files, a Mac's open panel), a Mac's clipboard (`clipboard`), and what is dropped on a Mac's window
/// (`ghost_md/drops`, macos/Runner/GhostChannels.swift `PictureDrops`).
///
/// Each platform half answers a picture it has already shrunk into the app's cache (a JPEG, the right way up, its long
/// side at most 1600); it is read here and the file deleted at once, so nothing of it is left on the device once the
/// chat lets go of it. Android writes a smaller JPEG for the chat's own shrink ([phoneJpegShrink]); elsewhere one too
/// big is drawn again as a PNG.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/phone_pictures.dart' show phoneJpegShrink, picturesChannel;
import 'chat_images.dart';

/// The channel a Mac's window says dropped pictures on.
const MethodChannel dropsChannel = MethodChannel('ghost_md/drops');

/// Reads the picture the platform left at [path], and deletes the file.
Future<Uint8List?> _taken(Object? path) async {
  if (path is! String || path.isEmpty) return null;
  final file = File(path);
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  } finally {
    try {
      await file.delete();
    } catch (_) {
      // Gone already, or the cache's to clear.
    }
  }
}

/// The chooser's picture, or null when none was chosen. Throws a [StateError] with a sentence for the chat.
Future<Uint8List?> pickChatPicture({MethodChannel channel = picturesChannel}) async {
  final Map<String, Object?>? answer;
  try {
    answer = await channel.invokeMapMethod<String, Object?>('pick');
  } on MissingPluginException {
    throw StateError('Pictures can’t be added on this device.');
  } on PlatformException catch (failure) {
    throw StateError(failure.message ?? 'The picker did not open.');
  }
  if (answer == null || answer['cancelled'] == true) return null;
  final bytes = await _taken(answer['path']);
  if (bytes == null) throw StateError('The picture could not be read.');
  return bytes;
}

/// What is on the clipboard: a picture, else words.
Future<({Uint8List? picture, String? text})> chatClipboard({MethodChannel channel = picturesChannel}) async {
  final answer = await channel.invokeMapMethod<String, Object?>('clipboard');
  if (answer == null) return (picture: null, text: null);
  if (answer['path'] != null) return (picture: await _taken(answer['path']), text: null);
  if (answer['error'] is String) throw StateError(answer['error'] as String);
  final text = answer['text'];
  return (picture: null, text: text is String ? text : null);
}

/// Pictures dropped on a Mac's window: the window takes a drag only while this is listened to.
class ChatDrops {
  ChatDrops({this.channel = dropsChannel});

  final MethodChannel channel;
  late final StreamController<Uint8List> _out = StreamController<Uint8List>.broadcast(onListen: () => _listen(true), onCancel: () => _listen(false));
  bool _heard = false;

  Stream<Uint8List> get stream => _out.stream;

  void _listen(bool on) {
    if (!_heard) {
      _heard = true;
      channel.setMethodCallHandler((call) async {
        if (call.method != 'dropped') return null;
        final paths = call.arguments;
        for (final path in paths is List ? paths : const []) {
          final bytes = await _taken(path);
          if (bytes != null && _out.hasListener) _out.add(bytes);
        }
        return null;
      });
    }
    unawaited(channel.invokeMethod<void>('listen', on).catchError((Object _) {}));
  }
}

ChatDrops? _drops;

/// This device's [ChatPictureSource]; none on the web, Windows and Linux, which have no chooser here.
ChatPictureSource? deviceChatPictures() {
  if (kIsWeb) return null;
  // Windows and Linux have no picture chooser of the app's yet.
  if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS && defaultTargetPlatform != TargetPlatform.macOS) return null;
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  return ChatPictureSource(
    pick: pickChatPicture,
    clipboard: mac ? chatClipboard : null,
    dropped: mac ? (_drops ??= ChatDrops()).stream : null,
    jpeg: defaultTargetPlatform == TargetPlatform.android ? phoneJpegShrink : null,
  );
}
