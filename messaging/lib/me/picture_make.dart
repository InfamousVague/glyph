import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import 'pictures.dart';

/// A profile picture as this person's own is kept and sent: [sharp], the one shown (up to [ProfilePictures.sharpSide]
/// square), and [small], a stand-in that builds from before 0.10.4 take (at most [ProfilePictures.oldMost]) and whose
/// [ProfilePictures.hashOf] a space's greeting carries. Both square base64 JPEG (an older picture: PNG).
class ProfilePicture {
  const ProfilePicture({required this.sharp, required this.small});
  final String sharp;
  final String small;
}

/// [bytes] (any picture Flutter decodes) as a profile picture: the middle square, as JPEG, at the largest of a few
/// sizes and qualities that fits (Matt, 2026-11-20: "my uploaded profile picture is super blurry": a photo made a PNG
/// of at most 24000 characters came out 72 pixels across, drawn at up to 96 points). Null where it can't be read.
Future<ProfilePicture?> profilePictureOf(Uint8List bytes) async {
  final sharp = await _square(bytes, sizes: const [ProfilePictures.sharpSide, 224, 192, 160, 128], qualities: const [84, 74, 64], most: ProfilePictures.sharpMost);
  if (sharp == null) return null;
  final small = await _square(bytes, sizes: const [128, 112, 96, 80, 64], qualities: const [72, 60], most: ProfilePictures.smallMost);
  return ProfilePicture(sharp: sharp, small: small ?? '');
}

/// The middle square of [bytes] as a base64 JPEG of at most [most] characters: the first of [sizes] (pixels a side,
/// largest first) that fits at one of [qualities] (best first). Null where it can't be read or none fits.
Future<String?> _square(Uint8List bytes, {required List<int> sizes, required List<int> qualities, required int most}) async {
  ui.Image? image;
  try {
    // Decoded near the size wanted (a phone's photo is 12 million pixels or more), by the platform.
    final probe = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(probe);
    final short = desc.width < desc.height ? desc.width : desc.height;
    final scale = short > sizes.first * 2 ? sizes.first * 2 / short : 1.0;
    final codec = await desc.instantiateCodec(targetWidth: (desc.width * scale).round(), targetHeight: (desc.height * scale).round());
    image = (await codec.getNextFrame()).image;
    codec.dispose();
    desc.dispose();
    probe.dispose();
    final side = image.width < image.height ? image.width : image.height;
    final from = ui.Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2, side.toDouble(), side.toDouble());
    for (final size in sizes) {
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
