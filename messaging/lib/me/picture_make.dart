import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import 'pictures.dart';

/// A profile picture as this person's own is kept and sent: [sharp], the one shown (up to [ProfilePictures.sharpSide]
/// square), and [small], a stand-in that builds from before 0.10.4 take (at most [ProfilePictures.oldMost]) and whose
/// [ProfilePictures.hashOf] a space's greeting carries. Both square base64 JPEG (an older picture: PNG).
class ProfilePicture {
  const ProfilePicture({required this.sharp, required this.small, this.full = ''});
  final String sharp;
  final String small;

  /// The same picture larger (up to [ProfilePictures.fullSide] square), for this person's own screens: kept on this
  /// device and never sent. '' where the picture chosen was no larger than [sharp].
  final String full;
}

/// [bytes] (any picture Flutter decodes) as a profile picture: the middle square, as JPEG, at the largest of a few
/// sizes and qualities that fits (Matt, 2026-11-20: "my uploaded profile picture is super blurry": a photo made a PNG
/// of at most 24000 characters came out 72 pixels across, drawn at up to 96 points). Null where it can't be read.
///
/// [crop] is the square of it to keep, as shares of its width and height (0 to 1 each way; lib/ui/picture_crop.dart);
/// the middle square where none is given.
Future<ProfilePicture?> profilePictureOf(Uint8List bytes, {ui.Rect? crop}) async {
  final sharp = await _square(bytes, sizes: const [ProfilePictures.sharpSide, 224, 192, 160, 128], qualities: const [84, 74, 64], most: ProfilePictures.sharpMost, crop: crop);
  if (sharp == null) return null;
  final small = await _square(bytes, sizes: const [128, 112, 96, 80, 64], qualities: const [72, 60], most: ProfilePictures.smallMost, crop: crop);
  final full = await _square(bytes, sizes: const [ProfilePictures.fullSide, 512, 384], qualities: const [90, 82], most: ProfilePictures.fullMost, crop: crop, larger: false);
  return ProfilePicture(sharp: sharp, small: small ?? '', full: full ?? '');
}

/// The middle square of [bytes] as a base64 JPEG of at most [most] characters: the first of [sizes] (pixels a side,
/// largest first) that fits at one of [qualities] (best first). Null where it can't be read or none fits.
///
/// [crop]: the part to keep, as shares of the picture ([profilePictureOf]). [larger] false: never made larger than the
/// part kept is, and null where it is smaller than every one of [sizes].
Future<String?> _square(Uint8List bytes, {required List<int> sizes, required List<int> qualities, required int most, ui.Rect? crop, bool larger = true}) async {
  ui.Image? image;
  try {
    // Decoded near the size wanted (a phone's photo is 12 million pixels or more), by the platform.
    final probe = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(probe);
    final whole = desc.width < desc.height ? desc.width : desc.height;
    final part = crop == null ? 1.0 : (crop.width * desc.width < crop.height * desc.height ? crop.width * desc.width : crop.height * desc.height) / whole;
    final short = whole * part.clamp(0.02, 1.0);
    final scale = short > sizes.first * 2 ? sizes.first * 2 / short : 1.0;
    final codec = await desc.instantiateCodec(targetWidth: (desc.width * scale).round(), targetHeight: (desc.height * scale).round());
    image = (await codec.getNextFrame()).image;
    codec.dispose();
    desc.dispose();
    probe.dispose();
    final ui.Rect from;
    if (crop == null) {
      final side = image.width < image.height ? image.width : image.height;
      from = ui.Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2, side.toDouble(), side.toDouble());
    } else {
      // The part chosen, square, and inside the picture.
      final w = crop.width * image.width, h = crop.height * image.height;
      final side = (w < h ? w : h).clamp(1.0, (image.width < image.height ? image.width : image.height).toDouble());
      final left = (crop.left * image.width).clamp(0.0, image.width - side), top = (crop.top * image.height).clamp(0.0, image.height - side);
      from = ui.Rect.fromLTWH(left, top, side, side);
    }
    for (final size in sizes) {
      if (!larger && size > from.width + 0.5) continue;
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(image, from, ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()), ui.Paint()..filterQuality = ui.FilterQuality.high);
      final square = await recorder.endRecording().toImage(size, size);
      final rgba = await square.toByteData(format: ui.ImageByteFormat.rawRgba);
      square.dispose();
      if (rgba == null) continue;
      final pixels = img.Image.fromBytes(width: size, height: size, bytes: rgba.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
      for (final q in qualities) {
        final b64 = base64.encode(img.encodeJpg(pixels, quality: q, chroma: img.JpegChroma.yuv420));
        if (b64.length <= most) return b64;
      }
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
  }
}
