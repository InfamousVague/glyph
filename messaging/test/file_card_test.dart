import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/files/files_model.dart';
import 'package:ghost_messaging/friends/file_card.dart';
import 'package:ghost_messaging/souls/souls_send.dart';

// Matt, 2026-11-25: "also allow sending pictures and attachements to ghost users". lib/friends/file_card.dart.

SpaceFile _file(String name, {int size = 1258291, int thumb = 0}) => SpaceFile(
      id: 'ab' * 16,
      name: name,
      size: size,
      mime: 'image/jpeg',
      sha: 'cd' * 32,
      key: Uint8List.fromList(List.generate(32, (i) => i)),
      prefix: Uint8List.fromList(List.generate(8, (i) => i)),
      by: 'me',
      byName: 'Matt',
      at: 1795000000000,
      thumb: thumb == 0 ? null : Uint8List(thumb),
    );

void main() {
  final seed = 'e1' * 32;

  test('a card is its line, then where the files are, and reads back as it was', () {
    final card = FileCard(seed: seed, files: [_file('photo.jpg')]);
    final lines = card.words.split('\n');
    expect(lines, hasLength(2));
    expect(lines.first, '📎 photo.jpg (1.3 MB)', reason: 'what an app from before cards shows');
    final back = FileCard.of(card.words, by: '@maya', at: 5);
    expect(back, isNotNull);
    expect(back!.seed, seed);
    expect(back.files.single.name, 'photo.jpg');
    expect(back.files.single.size, 1258291);
    expect(back.files.single.key, card.files.single.key);
    expect(back.files.single.by, '@maya', reason: 'whose it is comes from who sent the message, not from the card');
    expect(FileCard(seed: seed, files: [_file('a.jpg'), _file('b.pdf')]).line, '📎 2 files');
  });

  test('words that are not a card are not one', () {
    expect(FileCard.of('hello'), isNull);
    expect(FileCard.of('📎 photo.jpg (1.3 MB)'), isNull);
    expect(FileCard.of('📎 photo.jpg\nGhost file: not json'), isNull);
    expect(FileCard.of('📎 photo.jpg\nGhost file: {"s":"short","a":[]}'), isNull);
    expect(FileCard.of('📎 photo.jpg\nGhost file: {"s":"$seed","a":[]}'), isNull, reason: 'no files');
    expect(FileCard.of('📎 photo.jpg\nGhost file: {"s":"$seed","a":[{"id":"nope"}]}'), isNull, reason: 'a file that does not read');
    expect(FileCard.of('📎 a\nmore words\nGhost file: {"s":"$seed","a":[]}'), isNull, reason: 'only on the second line');
    final six = FileCard(seed: seed, files: [for (var i = 0; i < 6; i++) _file('$i.jpg')]);
    expect(FileCard.of(six.words), isNull, reason: 'more than a card carries');
  });

  test('a list shows a card as its line and other words as they are', () {
    final card = FileCard(seed: seed, files: [_file('photo.jpg')]);
    expect(FileCard.preview(card.words), '📎 photo.jpg (1.3 MB)');
    expect(FileCard.preview('see you at 7'), 'see you at 7');
    expect(FileCard.preview(SoulsCard.preview('📎 just an emoji line')), '📎 just an emoji line');
  });

  test('a full card fits a packet and a part of history, with every small picture as large as it may be', () {
    for (final n in [1, 3, FileCard.mostFiles]) {
      final card = FileCard(seed: seed, files: [for (var i = 0; i < n; i++) _file('holiday photograph number $i.jpeg', thumb: FileCard.thumbMost(n))]);
      expect(card.words.length, lessThan(36 * 1024), reason: '$n files');
      expect(FileCard.of(card.words), isNotNull);
    }
  });

  test('the space an account keeps them in is made from its shared key, and is not its drive', () {
    final key = List.generate(32, (i) => i);
    expect(FileCard.seedOf(key), hasLength(64));
    expect(FileCard.seedOf(key), FileCard.seedOf(key));
    expect(FileCard.seedOf(key), isNot(FileCard.seedOf(List.generate(32, (i) => i + 1))));
    expect(FileCard.channelOf(seed).owner, '', reason: 'no owner: a key made from the seed would be everyone\'s who was sent a card');
  });
}
