/// A picture chosen on the phone and kept among the library's pictures: the [PicturePicker] and the
/// [PictureAdopter] over the channel `ghost_md/pictures` (Kotlin's `Pictures`) and the core's files. Ports
/// `pickNative` and `adoptImagePath` of `src/app/core/images.ts`.
///
/// The phone's half opens Android's own chooser and answers with the picture already shrunk and turned the right
/// way up in its cache (the page's `image` event); the core then moves it among the pictures under a fresh name,
/// which is the name its note's line carries (`![](image/<name>)`) and the name sync carries it by.
///
/// What differs:
/// - `save_image` named the picture in Rust; the Flutter core takes a picture under the name it is given
///   (`sync_put_file_path`, lib/core/native/files.dart [CoreFiles.adopt]), so the name is made here, as the Rust
///   made it: a version 4 UUID and `.jpg`, which is what the phone's half always writes.
/// - A run with no phone half (a desktop, a test) says what a bridge without the picker said
///   ([cannotAddPictures]).
library;

import 'package:flutter/services.dart';

import 'ids.dart';
import 'images.dart';
import 'native/core.dart' show CoreError;
import 'native/files.dart';

/// The channel the phone's picture chooser answers on.
const MethodChannel picturesChannel = MethodChannel('ghost_md/pictures');

/// A picture drawn again as a JPEG by the phone (`smaller`, Kotlin's `Pictures`): a share's reading copy, which
/// Flutter's engine can open and cannot write (lib/sync/device.dart `JpegShrink`). Null where the picture will not
/// open, and on a run with no phone half or one from before it (a desktop, an iPhone, a test), where a share's
/// pictures are carried as they are kept.
Future<Uint8List?> phoneJpegShrink(Uint8List bytes, {required int longSide, required int quality, MethodChannel channel = picturesChannel}) async {
  try {
    return await channel.invokeMethod<Uint8List>('smaller', {'bytes': bytes, 'longSide': longSide, 'quality': quality});
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Moves a picture the phone put in its cache among the library's pictures, and answers its name
/// (`adoptImagePath`).
PictureAdopter corePictureAdopter(CoreFiles files, {String Function()? name}) => (path) async {
      final named = '${name?.call() ?? randomId('img')}.jpg';
      await files.adopt(CoreFileKind.image, named, path);
      return named;
    };

/// Lets the person choose a picture with the phone's chooser, keeps it, and answers its name; null when they chose
/// none (`pickNative`). Throws a [StateError] with a sentence for the note.
PicturePicker phonePicturePicker(PictureAdopter adopt, {MethodChannel channel = picturesChannel}) => () async {
      final Map<String, Object?>? answer;
      try {
        answer = await channel.invokeMapMethod<String, Object?>('pick');
      } on MissingPluginException {
        throw StateError(cannotAddPictures);
      } on PlatformException catch (failure) {
        throw StateError(failure.message ?? 'The picker did not open.');
      }
      if (answer == null || answer['cancelled'] == true) return null;
      final path = answer['path'];
      if (path is! String || path.isEmpty) throw StateError('The picture could not be read.');
      try {
        return await adopt(path);
      } catch (failure) {
        // The core's own sentence, where it has one (`save_image`'s were the note's line too).
        throw StateError(failure is StateError ? failure.message : (failure is CoreError ? failure.message : 'That picture could not be added.'));
      }
    };
