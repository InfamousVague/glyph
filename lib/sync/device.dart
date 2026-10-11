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
/// - **A share's smaller picture.** The page redraws any picture as a JPEG through a canvas
///   (`smallerImage(bytes, 1024, 0.72)`: its long side at most 1024, the right way up, over white, at quality
///   0.72). Flutter's engine opens a JPEG and writes PNG and nothing else, so the writing is the phone's
///   ([JpegShrink]; lib/core/phone_pictures.dart `phoneJpegShrink` over Kotlin's `Pictures.smaller`), and
///   [smallerPicture] hands it every picture that is not a PNG: a phone's photographs, which is nearly all of them
///   (a picked or pasted picture is always kept as a `.jpg`). A PNG is still redrawn as a PNG ([smallerPng]),
///   where the page made a JPEG of it under its `.png` name: the core keeps a picture only if it is what its name
///   says (`sync_put_file`: "That picture is not what its name says."), so the page's copy of a PNG could be read
///   in a browser and never kept by a phone that saved the share. And a reading copy that came out larger than
///   the picture as kept is not used, where the page used it regardless. On a device with no writer (a desktop
///   until its half has one, a test) a picture that is not a PNG is carried as it is kept, as before.
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

/// The JPEG quality of a share's reading copy, of 100 (the page's 0.72).
const int shareJpegQuality = 72;

/// Draws a picture again as a JPEG: its long side at most [longSide] and never larger than it was, the right way
/// up, over white paper, at [quality] of 100. Null when the picture will not open or there is nothing to draw
/// with. The page's `shrink` (core/imageShrink.ts), which only a platform can do here.
typedef JpegShrink = Future<Uint8List?> Function(Uint8List bytes, {required int longSide, required int quality});

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

/// A share's reading copy of a picture (`smallerImage(bytes, 1024, 0.72)`): a PNG as a smaller PNG ([smallerPng]),
/// anything else as a JPEG by [jpeg], the device's writer. The bytes as they are where there is no writer, where
/// the picture will not open, and where the copy came out no smaller than the picture as kept.
Future<Uint8List> smallerPicture(Uint8List bytes, {JpegShrink? jpeg, int longSide = shareLongSide, int quality = shareJpegQuality}) async {
  if (_isPng(bytes)) return smallerPng(bytes, longSide: longSide);
  if (jpeg == null || bytes.isEmpty) return bytes;
  try {
    final drawn = await jpeg(bytes, longSide: longSide, quality: quality);
    return drawn != null && drawn.isNotEmpty && drawn.length < bytes.length ? drawn : bytes;
  } catch (_) {
    return bytes;
  }
}

/// [SharePictures] over the core.
class CorePictures implements SharePictures {
  /// [smallerWith] draws a picture smaller; [smallerPicture] with [jpeg], this device's JPEG writer, unless given.
  /// [onPicture] as [CoreDeviceBytes.onPicture].
  const CorePictures(this.files, {Future<Uint8List> Function(Uint8List bytes)? smallerWith, this.jpeg, this.onPicture}) : _smaller = smallerWith;

  final CoreFiles files;
  final Future<Uint8List> Function(Uint8List bytes)? _smaller;

  /// Writes a JPEG on this device; null where nothing can, and then only a PNG is drawn smaller.
  final JpegShrink? jpeg;
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
  Future<Uint8List> smaller(Uint8List bytes) => _smaller != null ? _smaller(bytes) : smallerPicture(bytes, jpeg: jpeg);

  @override
  Future<void> keep(String name, Uint8List bytes) async {
    await files.write(CoreFileKind.image, name, bytes);
    onPicture?.call(name);
  }
}
