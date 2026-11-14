import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/stickers.dart';

/// The sticker packs (tool/sticker_packs.py makes them; Matt, 2026-11-13: "generate 4 sticker packs using our ghost
/// mascot"): what is bundled, how a sticker is named as it travels, and what counts as one when it arrives.
void main() {
  testWidgets('five packs of sixteen are bundled, each sticker a picture that opens', (tester) async {
    final packs = (await tester.runAsync(stickerPacks))!;
    expect(packs.map((p) => p.id), ['ghost', 'love', 'party', 'sweet', 'mischief']);
    for (final pack in packs) {
      expect(pack.stickers, hasLength(16), reason: pack.id);
      expect(pack.stickers.first, 'assets/stickers/${pack.id}/01.webp');
      for (final asset in pack.stickers) {
        final data = (await tester.runAsync(() => rootBundle.load(asset)))!;
        // A WebP: RIFF…WEBP. Small enough that sixty-four of them are no weight in the app.
        final head = String.fromCharCodes(data.buffer.asUint8List(0, 12));
        expect(head.startsWith('RIFF') && head.endsWith('WEBP'), isTrue, reason: asset);
        expect(data.lengthInBytes, lessThan(60 * 1024), reason: asset);
      }
    }
  });

  test('a sticker travels under its pack and number', () {
    expect(stickerName('assets/stickers/love/03.webp'), 'love-03');
    expect(stickerName('assets/stickers/sweet/16.webp'), 'sweet-16');
  });

  test('a picture part is a sticker by its name alone', () {
    expect(const Attachment(id: 1, type: 'image/png', name: 'ghost-sticker-love-03.png').isSticker, isTrue);
    expect(const Attachment(id: 1, type: 'image/png', name: 'parts/ghost-sticker-love-03.png').isSticker, isTrue);
    expect(const Attachment(id: 1, type: 'image/jpeg', name: 'image0.jpg').isSticker, isFalse);
    expect(const Attachment(id: 1, type: 'image/png').isSticker, isFalse);
    // Only a picture: a text part with the name is not drawn as one.
    expect(const Attachment(id: 1, type: 'text/plain', name: 'ghost-sticker-love-03.png').isSticker, isFalse);
  });
}
