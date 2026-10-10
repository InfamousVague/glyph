// A share's reading copy of a picture (lib/sync/device.dart `smallerPicture`; docs/PARITY.md, Differs 25): the
// page draws any picture again as a JPEG, 1024 on its long side at quality 0.72 (`smallerImage(bytes, 1024, 0.72)`);
// the port drew only a PNG smaller and left a phone's JPEGs as they were kept, so a share that would not hold them
// carried only as many as fit. Here the writer is a stand-in ([JpegShrink]); the phone's own is Kotlin's
// (`Pictures.smaller`), tried over its channel's words below and on a phone.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/phone_pictures.dart';
import 'package:ghost_md/share/share.dart';
import 'package:ghost_md/sync/device.dart';

/// Bytes that begin as a JPEG does, [length] of them.
Uint8List jpeg(int length, [int fill = 7]) => Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, ...List.filled(length - 4, fill)]);

/// A PNG of [width] by [height], drawn by the engine.
Future<Uint8List> png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (var y = 0; y < height; y += 8) {
    canvas.drawRect(ui.Rect.fromLTWH(0, y.toDouble(), width.toDouble(), 4), ui.Paint()..color = ui.Color.fromARGB(255, y % 256, (y * 7) % 256, 120));
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// A device's pictures for a share, drawn smaller the way the app draws them.
class Held implements SharePictures {
  Held(this.held, this.writer);
  final Map<String, Uint8List> held;
  final JpegShrink? writer;

  @override
  Future<Uint8List?> read(String name) async => held[name];

  @override
  Future<Uint8List> smaller(Uint8List bytes) => smallerPicture(bytes, jpeg: writer);

  @override
  Future<void> keep(String name, Uint8List bytes) async => held[name] = bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a reading copy', () {
    test('of a JPEG is the writer’s, asked for 1024 on the long side at quality 72, as the page asks', () async {
      final asked = <(int, int, int)>[];
      Future<Uint8List?> writer(Uint8List bytes, {required int longSide, required int quality}) async {
        asked.add((bytes.length, longSide, quality));
        return jpeg(120);
      }

      final photo = jpeg(4000);
      expect(await smallerPicture(photo, jpeg: writer), jpeg(120));
      expect(asked, [(4000, 1024, 72)]);
      expect((shareLongSide, shareJpegQuality), (1024, 72));
    });

    test('of anything else that is not a PNG is the writer’s too: the page draws every kind as a JPEG', () async {
      final webp = Uint8List.fromList([...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WEBP'), ...List.filled(500, 1)]);
      var asked = 0;
      expect(await smallerPicture(webp, jpeg: (bytes, {required longSide, required quality}) async {
        asked += 1;
        return jpeg(50);
      }), jpeg(50));
      expect(asked, 1);
    });

    test('of a PNG is a smaller PNG, never the writer’s: the core keeps a picture only as what its name says', () async {
      var asked = 0;
      final wide = await png(2048, 512);
      final drawn = await smallerPicture(wide, jpeg: (bytes, {required longSide, required quality}) async {
        asked += 1;
        return jpeg(10);
      });
      expect(asked, 0);
      expect(drawn.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
      final described = await ui.ImageDescriptor.encoded(await ui.ImmutableBuffer.fromUint8List(drawn));
      expect((described.width, described.height), (1024, 256));
    });

    test('is the picture as kept where there is no writer, where it will not open, and where the copy is no smaller', () async {
      final photo = jpeg(4000);
      expect(identical(await smallerPicture(photo), photo), isTrue, reason: 'no writer on this device');
      expect(identical(await smallerPicture(photo, jpeg: (bytes, {required longSide, required quality}) async => null), photo), isTrue, reason: 'it would not open');
      expect(identical(await smallerPicture(photo, jpeg: (bytes, {required longSide, required quality}) async => Uint8List(0)), photo), isTrue);
      expect(identical(await smallerPicture(photo, jpeg: (bytes, {required longSide, required quality}) async => throw StateError('no')), photo), isTrue);
      expect(identical(await smallerPicture(photo, jpeg: (bytes, {required longSide, required quality}) async => jpeg(4000)), photo), isTrue, reason: 'a copy no smaller is no reading copy');
      expect(identical(await smallerPicture(photo, jpeg: (bytes, {required longSide, required quality}) async => jpeg(5000)), photo), isTrue);
      final nothing = Uint8List(0);
      expect(identical(await smallerPicture(nothing, jpeg: (bytes, {required longSide, required quality}) async => jpeg(8)), nothing), isTrue);
    });
  });

  group('a share of a phone’s photographs', () {
    const a = 'aaaa1111-0000-4000-8000-000000000001.jpg';
    const b = 'bbbb2222-0000-4000-8000-000000000002.jpg';
    const c = 'cccc3333-0000-4000-8000-000000000003.jpg';
    const shared = Shared(
      kind: 'note',
      title: 'Lisbon',
      pages: [SharedPage(title: 'Lisbon', body: '# Lisbon\n\n![](image/$a)\n\n![](image/$b)\n\n![](image/$c)')],
      at: 1,
    );
    final words = utf8.encode(jsonEncode(shared.toJson())).length;

    test('that would not hold them as kept carries every one drawn smaller, where it carried only the first that fit', () async {
      // Three photographs of 1,000 bytes and room for 1,500: as kept, one fits.
      final held = {a: jpeg(1000, 1), b: jpeg(1000, 2), c: jpeg(1000, 3)};
      final before = await withPictures(shared, Held(held, null), budget: words + 1500);
      expect(before.shared.pictures?.keys, [a], reason: 'with no writer, as the port was: the others are left out of the link');

      final after = await withPictures(shared, Held(held, (bytes, {required longSide, required quality}) async => jpeg(300, bytes[4])), budget: words + 1500);
      expect(after.shared.pictures?.keys, [a, b, c]);
      expect(after.shared.pictures?.values.map((each) => each.length), [300, 300, 300]);
      expect(after.shared.pictures?[b]?[4], 2, reason: 'each its own copy');
      expect(after.lacked, isEmpty);
    });

    test('that holds them as kept carries them as kept: nothing is drawn again', () async {
      var asked = 0;
      final held = {a: jpeg(1000, 1), b: jpeg(1000, 2), c: jpeg(1000, 3)};
      final carried = await withPictures(shared, Held(held, (bytes, {required longSide, required quality}) async {
        asked += 1;
        return jpeg(300);
      }), budget: words + 5000);
      expect(asked, 0);
      expect(carried.shared.pictures?.values.map((each) => each.length), [1000, 1000, 1000]);
    });
  });

  group('the phone’s writer', () {
    final calls = <MethodCall>[];
    Object? answer;

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(picturesChannel, (call) async {
        calls.add(call);
        return answer;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(picturesChannel, null));
    });

    test('is handed the picture, the long side and the quality, and answers the JPEG', () async {
      answer = jpeg(64);
      final drawn = await phoneJpegShrink(jpeg(900), longSide: 1024, quality: 72);
      expect(drawn, jpeg(64));
      expect(calls.single.method, 'smaller');
      final sent = calls.single.arguments as Map;
      expect((sent['longSide'], sent['quality'], (sent['bytes'] as Uint8List).length), (1024, 72, 900));
    });

    test('answers nothing for a picture the phone could not open, or on a device with no half for it', () async {
      answer = null;
      expect(await phoneJpegShrink(jpeg(900), longSide: 1024, quality: 72), isNull);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(picturesChannel, null);
      expect(await phoneJpegShrink(jpeg(900), longSide: 1024, quality: 72), isNull);
      // And the share then carries the picture as it is kept.
      final photo = jpeg(900);
      expect(identical(await smallerPicture(photo, jpeg: phoneJpegShrink), photo), isTrue);
    });
  });
}
