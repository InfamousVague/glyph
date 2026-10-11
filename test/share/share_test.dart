// Sharing a note or a book by its link (lib/share/share.dart, lib/share/zip.dart). A port of
// `src/app/share/share.test.ts`, case for case.
//
// The sealing is the tests' crypto (test/support/fake_crypto.dart): what is proved is the payload - the words, the
// GSP1 framing of the pictures, what stays out - and that it opens with its own key and no other. The wire's bytes
// are the Rust core's own vectors.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/share/share.dart';
import 'package:ghost_md/share/zip.dart';

import '../support/fake_crypto.dart';
import 'support.dart';

String said(Shared shared) => jsonEncode(shared.toJson());

void main() {
  final crypto = FakeCrypto();

  group('a share sealed by its link', () {
    test('opens with its own key and with no other, and the link carries both halves after the #', () async {
      const shared = Shared(kind: 'note', title: 'Packing', pages: [SharedPage(title: 'Packing', body: '# Packing\n\n- [ ] Tent')], at: 1);
      final key = newShareKey(crypto);
      final blob = await sealShare(crypto, shared, key);
      expect(blob, isNot(contains('Tent')));
      expect(utf8.decode(fromBase64Url(blob), allowMalformed: true), isNot(contains('Tent')));
      final opened = await openShare(crypto, blob, key);
      expect(said(opened), said(shared));
      expect(opened.pictures, isNull);
      await expectLater(openShare(crypto, blob, newShareKey(crypto)), throwsA(anything));
      final id = newShareId(crypto);
      final link = shareLink(id, key);
      expect(link.split('#')[0], isNot(contains(key)));
      expect(readShareLink(link), (id: id, key: key));
      // Pasted with words round it, or as only what follows the #.
      expect(readShareLink('Here it is: $link - enjoy'), (id: id, key: key));
      expect(readShareLink('$id.$key'), (id: id, key: key));
      expect(readShareLink('https://example.com/nothing'), isNull);
    });

    test('is refused when it was written by a newer build', () async {
      final key = newShareKey(crypto);
      final newer = toBase64Url(await crypto.sealBytes(await crypto.importSealKey(fromBase64Url(key)), utf8.encode('{"v":2,"pages":[]}'), shareContext));
      await expectLater(openShare(crypto, newer, key), throwsA(isA<ShareError>().having((e) => e.message, 'message', contains('newer Ghost.md'))));
    });
  });

  group('what a note or a book shares', () {
    final book = note('b', bookNoteBody('Cabin trip', ['Packing', 'Route map', 'Not written']));
    final notes = [book, note('p', '# Packing\n\n- [ ] Tent'), note('r', '---\ntitle: "Route map"\n---\n{"nodes":[],"edges":[]}'), note('x', '# Elsewhere')];

    test('shares a note as itself, and a book as its index then every chapter that has a note, in order', () {
      final one = sharedOf(notes[1], notes);
      expect((one.kind, one.title), ('note', 'Packing'));
      expect(one.pages.map((p) => p.title), ['Packing']);
      final shared = sharedOf(book, notes);
      expect(shared.kind, 'book');
      expect(shared.pages.map((p) => p.title), ['Cabin trip', 'Packing', 'Route map']);
    });

    test('forks into a library as the reader own copies, renaming what would clash and pointing the index at the copies', () async {
      final shared = sharedOf(book, notes);
      final saved = <String>[];
      final first = await forkShared(
        shared,
        notes: () async => [note('mine', '# Packing\n\nMy own list.')],
        save: (body) async {
          saved.add(body);
          return note('s${saved.length}', body);
        },
      );
      expect(noteTitle(first.body), 'Cabin trip');
      expect(saved.map(noteTitle), ['Cabin trip', 'Packing (shared)', 'Route map']);
      expect(chaptersOf(saved[0]).map((c) => c.title), ['Packing (shared)', 'Route map', 'Not written']);
    });

    test('downloads a note as its Markdown and a book as a zip of its pages', () {
      final one = sharedAsFile(sharedOf(notes[1], notes));
      expect((one.name, one.type), ('Packing.md', 'text/markdown'));
      expect(utf8.decode(one.bytes), '# Packing\n\n- [ ] Tent');
      final many = sharedAsFile(sharedOf(book, notes));
      expect((many.name, many.type), ('Cabin trip.zip', 'application/zip'));
      final bytes = many.bytes;
      // A zip: its first local file header, and its end record naming three files.
      expect(bytes.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
      final end = bytes.length - 22;
      expect(bytes.sublist(end, end + 4), [0x50, 0x4b, 0x05, 0x06]);
      expect(bytes[end + 8], 3);
    });
  });

  group('the zip', () {
    test('checks each file with the CRC-32 zip expects', () {
      expect(crc32(utf8.encode('The quick brown fox jumps over the lazy dog')), 0x414fa339);
      final zip = zipFiles([ZipFile(name: 'a.md', bytes: utf8.encode('hi'))]);
      expect(ByteData.sublistView(zip).getUint32(14, Endian.little), crc32(utf8.encode('hi')));
    });

    test('dates each file on the local clock, where it read as 1980-00-00 before', () {
      final at = DateTime(2026, 10, 1, 21, 42, 5);
      expect(dosTime(at), (time: (21 << 11) | (42 << 5) | 2, date: (46 << 9) | (10 << 5) | 1));
      final zip = ByteData.sublistView(zipFiles([ZipFile(name: 'a.md', bytes: Uint8List.fromList([1]))], at));
      // The local header's time and date, and the central directory's (after the local entry: 30 bytes, the name,
      // the byte).
      expect([zip.getUint16(10, Endian.little), zip.getUint16(12, Endian.little)], [dosTime(at).time, dosTime(at).date]);
      expect([zip.getUint16(35 + 12, Endian.little), zip.getUint16(35 + 14, Endian.little)], [dosTime(at).time, dosTime(at).date]);
      expect(dosTime(DateTime(1970)), (time: 0, date: 33));
    });
  });

  group('the pictures a share carries', () {
    const a = 'aaaa1111-0000-4000-8000-000000000001.jpg';
    const b = 'bbbb2222-0000-4000-8000-000000000002.jpg';
    const c = 'cccc3333-0000-4000-8000-000000000003.jpg';
    const paged = Shared(
      kind: 'book',
      title: 'Trading',
      pages: [
        SharedPage(title: 'Trading', body: '# Trading\n\n- [[Orders]]\n- [[Fills]]'),
        SharedPage(title: 'Orders', body: '# Orders\n\n![The ticket](image/$a)\n\n![Again](image/$a)'),
        SharedPage(title: 'Fills', body: '# Fills\n\n![The fill](image/$b)\n\n![Gone](image/$c)'),
      ],
      at: 1,
    );

    test('seals them with the words and opens them byte for byte, and a share without any is sealed as before', () async {
      final key = newShareKey(crypto);
      final shared = paged.withPictures({a: jpeg(1, 300), b: jpeg(2, 40)});
      final opened = await openShare(crypto, await sealShare(crypto, shared, key), key);
      expect(opened.pages, paged.pages);
      expect(opened.pictures?[a], jpeg(1, 300));
      expect(opened.pictures?[b], jpeg(2, 40));
      final plain = await openShare(crypto, await sealShare(crypto, paged, key), key);
      expect((said(plain), plain.pictures), (said(paged), null));
    });

    test('frames them as GSP1: the words’ length, the words with each picture’s name and size, then the bytes', () async {
      final key = newShareKey(crypto);
      final blob = await sealShare(crypto, paged.withPictures({a: jpeg(1, 3), b: jpeg(2, 2)}), key);
      final framed = await crypto.openBytes(await crypto.importSealKey(fromBase64Url(key)), fromBase64Url(blob), shareContext);
      expect(framed.sublist(0, 4), ascii.encode('GSP1'));
      final length = ByteData.sublistView(framed).getUint32(4);
      final head = jsonDecode(utf8.decode(framed.sublist(8, 8 + length))) as Map;
      expect(head.keys, ['v', 'kind', 'title', 'pages', 'at', 'pictures']);
      expect(head['pictures'], [
        [a, 3],
        [b, 2],
      ]);
      expect(framed.sublist(8 + length), [1, 1, 1, 2, 2]);
    });

    test('refuses a picture named to reach outside the picture store', () async {
      final key = newShareKey(crypto);
      final opened = await openShare(crypto, await sealShare(crypto, paged.withPictures({'../../evil.jpg': jpeg(9), b: jpeg(2)}), key), key);
      expect(opened.pictures?.keys, [b]);
      expect(opened.pictures?[b], jpeg(2));
    });

    test('carries the pictures the pages show, once each, leaving out one this device lacks', () async {
      final pictures = Pictures({a: jpeg(1), b: jpeg(2)});
      final (:shared, :lacked) = await withPictures(paged, pictures);
      expect(shared.pictures?.keys, [a, b]);
      expect(lacked, [c]);
      expect(pictures.reads, [a, b, c]);
    });

    test('draws them smaller when they would not fit, and then keeps as many as fit', () async {
      final words = utf8.encode(jsonEncode(paged.toJson())).length;
      final pictures = Pictures({a: jpeg(1, 1000), b: jpeg(1, 1000)});
      // Room for both only once each is drawn at a tenth.
      pictures.shrink = (bytes) => bytes.sublist(0, 100);
      final shrunk = (await withPictures(paged, pictures, budget: words + 500)).shared;
      expect(shrunk.pictures?.values.map((each) => each.length), [100, 100]);
      // Room for one, even smaller: the first the pages show.
      pictures.shrink = (bytes) => bytes.sublist(0, 400);
      final one = await withPictures(paged, pictures, budget: words + 500);
      expect(one.shared.pictures?.keys, [a]);
      // Left out for room, not lacked: B is here, so it is not looked for again.
      expect(one.lacked, [c]);
    });

    test('downloads the pictures beside the pages, and a note with pictures as a zip', () {
      final one = Shared(kind: 'note', title: 'Orders', pages: [paged.pages[1]], at: 1, pictures: {a: jpeg(1)});
      final file = sharedAsFile(one);
      expect(file.name, 'Orders.zip');
      final text = latin1.decode(file.bytes);
      expect(text, contains('Orders.md'));
      expect(text, contains('image/$a'));
      expect(file.bytes[file.bytes.length - 22 + 8], 2);
    });

    test('keeps them in a saved copy, under their own names', () async {
      final kept = <String>[];
      await forkShared(
        paged.withPictures({a: jpeg(1), b: jpeg(2)}),
        notes: () async => [],
        save: (body) async => note('s-${body.length}', body),
        keep: (name, _) async => kept.add(name),
      );
      expect(kept, [a, b]);
    });
  });

  group('where a shared page was written', () {
    Note tagged(String id, String body) => note(id, '---\nlocation: 51.5074,-0.1278\nplace: "London"\n---\n$body');
    final book = note('b', bookNoteBody('Cabin trip', ['Packing', 'Route']));
    final notes = [book, tagged('p', '# Packing\n\n- [ ] Tent'), note('r', '# Route\n\nNorth.')];

    test('stays out of a share unless the note says to carry it, for a note and for a book’s chapters alike', () {
      expect(sharedOf(notes[1], notes).pages[0].body, '# Packing\n\n- [ ] Tent');
      expect(sharedOf(notes[1], notes, place: true).pages[0].body, '---\nlocation: 51.5074,-0.1278\nplace: "London"\n---\n# Packing\n\n- [ ] Tent');
      expect(sharedOf(book, notes).pages.map((p) => p.body), [book.body, '# Packing\n\n- [ ] Tent', '# Route\n\nNorth.']);
      expect(sharedOf(book, notes, place: true).pages[1].body, contains('location: 51.5074,-0.1278'));
      // The other keys stay whichever way.
      final titled = note('t', '---\ntitle: "Map"\nlocation: 1.0000,2.0000\n---\n{"nodes":[],"edges":[]}');
      expect(sharedOf(titled, [titled]).pages[0].body, '---\ntitle: "Map"\n---\n{"nodes":[],"edges":[]}');
    });

    test('is offered only where a page has one', () {
      expect(sharesPlace(notes[1], notes), isTrue);
      expect(sharesPlace(book, notes), isTrue);
      expect(sharesPlace(notes[2], notes), isFalse);
    });
  });

  group('the places written in a shared page', () {
    const cais = '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)';
    const tag = '---\nlocation: 51.5074,-0.1278\n---\n';
    final placed = note('p', '$tag# Lisbon\n\nLunch\n\n$cais\n\nMet at $cais and <geo:38.7,-9.1>.\n\n- [ ] $cais');
    final book = note('b', bookNoteBody('Trip', ['Lisbon', 'Porto']));
    final lisbon = note('l', '# Lisbon\n\n$cais');
    final porto = note('o', '# Porto\n\nThe bridge.');

    test('stay out, every form of them, unless the share says to carry them', () {
      final body = sharedOf(placed, [placed]).pages[0].body;
      expect(body, isNot(contains('geo:')));
      expect(body, '# Lisbon\n\nLunch\n\nMet at Cais do Sodré, Lisbon and .');
      expect(sharedOf(placed, [placed], places: true).pages[0].body, placed.body.substring(tag.length));
    });

    test('are a switch of their own: the tag’s tick carries the tag and not the places, and the other way round', () {
      final tagOnly = sharedOf(placed, [placed], place: true).pages[0].body;
      expect(tagOnly, contains('location: 51.5074,-0.1278'));
      expect(tagOnly, isNot(contains('geo:')));
      final placesOnly = sharedOf(placed, [placed], places: true).pages[0].body;
      expect(placesOnly, isNot(contains('location:')));
      expect(placesOnly, contains(cais));
    });

    test('are seen in any chapter of a book, and apart from the tag', () {
      final notes = [book, lisbon, porto];
      expect(sharesPlaces(book, notes), isTrue);
      expect(sharesPlace(book, notes), isFalse);
      expect(sharesPlaces(porto, notes), isFalse);
      expect(sharesPlace(placed, [placed]), isTrue);
      expect(sharesPlaces(placed, [placed]), isTrue);
      expect(sharedOf(book, notes).pages[1].body, '# Lisbon');
    });

    test('change nothing a share of a page without them sends', () {
      expect(sharedOf(porto, [porto]).pages[0].body, porto.body);
      expect(sharedOf(porto, [porto], places: true).pages[0].body, porto.body);
    });
  });
}
