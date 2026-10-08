/// This device's recordings and pictures, as sync and a share ask for them, over the Rust core's file commands
/// (lib/core/native/files.dart): the answer to the two asks local.dart ([DeviceBytes]) and lib/share/share.dart
/// ([SharePictures]) make. What `deviceFiles` in `src/app/core/sync/engine.ts` did with the page's `img` and `rec`
/// schemes, `recording_digest` and `sync_put_file`, and what `imageBytes`, `smallerImage` and `keepImage` of
/// `core/images.ts` did for a share.
///
/// What differs:
/// - A recording's fingerprint is the core's `file_digest`, which is already the sixteen bytes sync keeps (thirty-two
///   hex characters), where the page's `recording_digest` answered the whole hash and the pass cut it. [KeptFiles]
///   cuts at thirty-two, so it reads either.
/// - A file the core refuses to read (a name that may not name one) is no file, as the page's was; one it refuses to
///   WRITE throws its sentence, which the pass counts against that note and says.
/// - **A share's smaller picture.** The page redraws any picture as a JPEG through a canvas. Flutter's engine
///   writes PNG and nothing else, and a picture must stay the kind its name says to be kept by the core, so
///   [CorePictures.smaller] redraws a PNG smaller (1024 on its long side) and answers anything else as it is: a
///   share that would not hold a phone's photographs as kept carries as many as fit, in the order the pages show
///   them (share.dart `withPictures`), until there is a JPEG writer. A test, or a device with one, gives its own.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/native/files.dart';
import '../share/share.dart' show SharePictures;
import 'local.dart';
import 'notes.dart' show FileKind;

CoreFileKind _kind(FileKind kind) => switch (kind) {
      FileKind.recording => CoreFileKind.recording,
      FileKind.image => CoreFileKind.image,
      FileKind.versions => CoreFileKind.versions,
    };

/// [DeviceBytes] over the core.
class CoreDeviceBytes implements DeviceBytes {
  /// [onPicture] is told a picture's name once it is kept: whatever was drawing its place draws it.
  const CoreDeviceBytes(this.files, {this.onPicture});

  final CoreFiles files;
  final void Function(String name)? onPicture;

  @override
  Future<Uint8List?> read(FileKind kind, String name) => files.read(_kind(kind), name);

  @override
  Future<void> write(FileKind kind, String name, Uint8List bytes) async {
    await files.write(_kind(kind), name, bytes);
    if (kind == FileKind.image) onPicture?.call(name);
  }

  /// The core's own fingerprint of the tape, hashed where it lies; empty for no tape by that name.
  @override
  Future<String?> recordingSha256(String name) async => await files.digest(CoreFileKind.recording, name) ?? '';
}

/// The long side a share's reading copy is drawn to (`smallerImage(bytes, 1024, 0.72)`).
const int shareLongSide = 1024;

const List<int> _pngMagic = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

bool _isPng(Uint8List bytes) {
  if (bytes.length < _pngMagic.length) return false;
  for (var i = 0; i < _pngMagic.length; i += 1) {
    if (bytes[i] != _pngMagic[i]) return false;
  }
  return true;
}

/// A PNG drawn again with its long side at [longSide] at most; the bytes as they are for anything else, for one
/// already that small, for one that will not decode, and where the smaller drawing came out larger.
Future<Uint8List> smallerPng(Uint8List bytes, {int longSide = shareLongSide}) async {
  if (!_isPng(bytes)) return bytes;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final described = await ui.ImageDescriptor.encoded(buffer);
    final width = described.width, height = described.height;
    final most = width > height ? width : height;
    if (most <= longSide) {
      described.dispose();
      buffer.dispose();
      return bytes;
    }
    final codec = await described.instantiateCodec(targetWidth: width >= height ? longSide : null, targetHeight: height > width ? longSide : null);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    described.dispose();
    buffer.dispose();
    if (data == null) return bytes;
    final drawn = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return drawn.length < bytes.length ? Uint8List.fromList(drawn) : bytes;
  } catch (_) {
    return bytes;
  }
}

/// [SharePictures] over the core.
class CorePictures implements SharePictures {
  /// [smallerWith] draws a picture smaller; [smallerPng] unless given. [onPicture] as [CoreDeviceBytes.onPicture].
  const CorePictures(this.files, {Future<Uint8List> Function(Uint8List bytes)? smallerWith, this.onPicture}) : _smaller = smallerWith;

  final CoreFiles files;
  final Future<Uint8List> Function(Uint8List bytes)? _smaller;
  final void Function(String name)? onPicture;

  /// The picture, or null where this device has none or the name may not name one.
  @override
  Future<Uint8List?> read(String name) async {
    try {
      return await files.read(CoreFileKind.image, name);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List> smaller(Uint8List bytes) => (_smaller ?? smallerPng)(bytes);

  @override
  Future<void> keep(String name, Uint8List bytes) async {
    await files.write(CoreFileKind.image, name, bytes);
    onPicture?.call(name);
  }
}
