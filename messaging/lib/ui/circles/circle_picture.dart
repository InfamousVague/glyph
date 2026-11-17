/// A circle's own picture in its icon's place (Matt, 2026-11-17: "use iconography and color where possible"): chosen
/// from the phone's or computer's pictures, cut square from the middle and made small enough to ride in the circle's
/// manifest (circlePictureMax), which goes round in one packet on the hub.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../circles/circle.dart';
import '../../sms.dart';
import '../common.dart';

/// Asks for a picture and gives it back as base64 PNG, square and small; null where none was chosen or it couldn't
/// be read (said in a toast).
Future<String?> pickCirclePicture(BuildContext context) async {
  try {
    final picked = await Sms.instance.pickImages();
    if (picked.isEmpty) return null;
    final path = await Sms.instance.cacheCopy(picked.first);
    final bytes = await File(path).readAsBytes();
    final small = await circlePictureOf(bytes);
    if (small == null && context.mounted) toast(context, 'Couldn\'t use that picture.', tone: GlacierToastTone.danger);
    return small;
  } catch (e) {
    if (context.mounted) toast(context, 'Couldn\'t use that picture: $e', tone: GlacierToastTone.danger);
    return null;
  }
}

/// [bytes] (any picture Flutter decodes) as a square base64 PNG of at most [circlePictureMax] characters: the middle
/// square, at the largest of a few sizes that fits. A photo's detail costs bytes, so a busy one ends up smaller.
Future<String?> circlePictureOf(Uint8List bytes) async {
  ui.Image? image;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    image = (await codec.getNextFrame()).image;
    final side = image.width < image.height ? image.width : image.height;
    final from = Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2, side.toDouble(), side.toDouble());
    for (final size in const [160, 128, 96, 72, 56, 40]) {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(image, from, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()), Paint()..filterQuality = FilterQuality.medium);
      final small = await recorder.endRecording().toImage(size, size);
      final png = await small.toByteData(format: ui.ImageByteFormat.png);
      small.dispose();
      if (png == null) continue;
      final b64 = base64.encode(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
      if (b64.length <= circlePictureMax) return b64;
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
  }
}
