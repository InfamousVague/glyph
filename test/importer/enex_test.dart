import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/importer/enex.dart';

import 'support.dart';

/// An Evernote export read as it streams (lib/importer/enex.dart): the fixture's three notes, the same whatever
/// size of pieces the file arrives in, a 2 MB note, a resource of several megabytes, and the reader's own isolate.
void main() {
  final fixtureBytes = File(fixture('evernote/Recipes.enex')).readAsBytesSync();

  Stream<List<int>> inPieces(List<int> bytes, int size) async* {
    for (var at = 0; at < bytes.length; at += size) {
      yield bytes.sublist(at, at + size > bytes.length ? bytes.length : at + size);
    }
  }

  String export(String notes) => '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE en-export SYSTEM "http://xml.evernote.com/pub/evernote-export4.dtd">\n<en-export export-date="20261015T090000Z" application="Evernote">$notes</en-export>\n';

  test('reads each note, its dates, tags, attributes and resources by their MD5', () async {
    final notes = await readEnex(Stream.value(fixtureBytes)).toList();
    expect(notes.map((n) => n.title), ['Pancakes & more', '', 'Pancakes & more']);
    final first = notes.first;
    expect(first.created, DateTime.utc(2024, 1, 2, 3, 4, 5).millisecondsSinceEpoch);
    expect(first.updated, DateTime.utc(2025, 6, 7, 8, 9, 10).millisecondsSinceEpoch);
    expect(first.tags, ['Breakfast', 'Quick meals', '2024']);
    expect(first.sourceUrl, 'https://example.com/clip');
    expect(first.author, 'Matt');
    expect(first.resources.map((r) => (r.mime, r.fileName)), [('image/png', 'pan.png'), ('application/pdf', 'Menu.pdf'), ('image/png', null)]);
    for (final resource in first.resources) {
      expect(resource.hash, md5.convert(resource.data).toString());
      expect(first.content.contains(resource.hash) || resource.fileName == null, isTrue);
    }
    expect(first.resources[1].data, utf8.encode('%PDF-1.4\n% evernote attachment\n%%EOF\n'));
    expect(first.content, startsWith('<?xml version="1.0" encoding="UTF-8" standalone="no"?>'));
    expect(first.content, contains('Ünïcödé — 日本語 🥞 مرحبا'));
    expect(notes[1].updated, isNull);
  });

  test('the same notes whatever pieces the file arrives in', () async {
    final whole = await readEnex(Stream.value(fixtureBytes)).toList();
    for (final size in [1, 7, 64, 1000]) {
      final pieced = await readEnex(inPieces(fixtureBytes, size)).toList();
      expect(pieced.map((n) => (n.title, n.content, n.tags.join(','), n.resources.map((r) => r.hash).join(','))), whole.map((n) => (n.title, n.content, n.tags.join(','), n.resources.map((r) => r.hash).join(','))), reason: 'pieces of $size bytes');
    }
  });

  test('a 2 MB note and a resource of several megabytes, in small pieces, read once each', () async {
    final line = '<div>${'The quick brown fox jumps over the lazy dog. ' * 20}</div>';
    final body = '<en-note>${line * (2 * 1024 * 1024 ~/ line.length + 1)}</en-note>';
    expect(body.length, greaterThan(2 * 1024 * 1024));
    final data = Uint8List.fromList(List<int>.generate(6 * 1024 * 1024, (i) => (i * 31) & 0xff));
    final encoded = base64.encode(data).replaceAllMapped(RegExp('.{76}'), (m) => '${m.group(0)}\n');
    final text = export('<note><title>Big</title><content><![CDATA[$body]]></content><resource><data encoding="base64">$encoded</data><mime>application/octet-stream</mime></resource></note><note><title>After</title><content><![CDATA[<en-note/>]]></content></note>');
    final watch = Stopwatch()..start();
    final notes = await readEnex(inPieces(utf8.encode(text), 64 * 1024)).toList();
    watch.stop();
    expect(notes.map((n) => n.title), ['Big', 'After']);
    expect(notes.first.content, body);
    expect(notes.first.resources.single.data, data);
    expect(notes.first.resources.single.hash, md5.convert(data).toString());
    // Read twice over at every piece, this was minutes; read once, it is a second or two even on a busy machine.
    expect(watch.elapsed, lessThan(const Duration(seconds: 30)));
  });

  test('pieces end just before markup, never inside a CDATA or an entity', () async {
    const text = '<a>one &amp; two</a><![CDATA[x < y <b> ]]> ]]><!-- a < b --><c/>';
    final pieces = await const EnexPieces(piece: 1).bind(Stream.fromIterable(text.split(''))).toList();
    expect(pieces.join(), text);
    for (final piece in pieces.skip(1)) {
      expect(piece, startsWith('<'));
    }
    expect(pieces, contains('<![CDATA[x < y <b> ]]> ]]>'));
    expect(pieces, contains('<!-- a < b -->'));
    // Words with no markup, longer than a piece may wait: let go, but never in the middle of an entity.
    final words = await const EnexPieces(piece: 1, longest: 8).bind(Stream.fromIterable('<a>one two three &amp; four five six</a>'.split(''))).toList();
    expect(words.join(), '<a>one two three &amp; four five six</a>');
    for (final piece in words) {
      expect(RegExp(r'&[a-z]*$').hasMatch(piece), isFalse, reason: piece);
    }
  });

  test('dates as ENEX writes them', () {
    expect(enexDate('20231015T120000Z'), DateTime.utc(2023, 10, 15, 12).millisecondsSinceEpoch);
    expect(enexDate('2023-10-15'), isNull);
    expect(enexDate(null), isNull);
  });

  test('the reader in its own isolate hands notes over one at a time, and says a broken export', () async {
    final reader = await EnexReader.open(fixture('evernote/Recipes.enex'));
    final titles = <String>[];
    for (var note = await reader.next(); note != null; note = await reader.next()) {
      titles.add(note.title);
    }
    await reader.close();
    expect(titles, ['Pancakes & more', '', 'Pancakes & more']);

    final dir = Directory.systemTemp.createTempSync('enex-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final broken = File('${dir.path}/broken.enex')..writeAsStringSync(export('<note><title>Fine</title><content><![CDATA[<en-note/>]]></content></note><note><title>Cut off<'));
    final bad = await EnexReader.open(broken.path);
    expect((await bad.next())?.title, 'Fine');
    await expectLater(bad.next(), throwsA(isA<StateError>()));
    await bad.close();
  });
}
