// The words read in a note's pictures and files (lib/files/read_text.dart): one plain-text sidecar beside each, a
// form feed between a PDF's pages; read in at launch; and the one hook a search takes (lib/core/note_text.dart
// `searchExtra`), by which a note is found by the words in what it shows, and its row says where they were read.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' as note_text show matches;
import 'package:ghost_md/core/note_text.dart' show searchExtra;
import 'package:ghost_md/core/search_hits.dart';
import 'package:ghost_md/files/read_text.dart';

const String picture = 'a1b2c3d4-0000-4000-8000-000000000001.jpg';
const String lease = 'b1b2c3d4-0000-4000-8000-000000000002.pdf';

Note note(String id, String body) => Note(id: id, body: body, createdAt: 0, updatedAt: 1);

void main() {
  late Directory data;
  late ReadTexts texts;

  setUp(() {
    data = Directory.systemTemp.createTempSync('read-text');
    texts = ReadTexts(dataDir: data.path);
  });
  tearDown(() {
    searchExtra = null;
    data.deleteSync(recursive: true);
  });

  test('a sidecar is the words as read, beside the thing, a form feed between pages, and is read back at launch', () async {
    await texts.keep(const ReadThing.picture(picture), 'TOTAL 42.10\nThank you');
    await texts.keep(const ReadThing.file(lease), textOfPages(['Lease agreement', '', 'Rent is due monthly']));
    expect(File('${data.path}/images/$picture.ocr.txt').readAsStringSync(), 'TOTAL 42.10\nThank you');
    expect(File('${data.path}/images/files/$lease.ocr.txt').readAsStringSync(), 'Lease agreement\f\fRent is due monthly');
    expect(pagesOf(texts.wordsOf(const ReadThing.file(lease))!), ['Lease agreement', '', 'Rent is due monthly']);
    // A PDF's own words, as Android hands them: their line ends made plain, a page's form feed kept out of it.
    expect(textOfPages(['Lease agreement \r\n \r\nThis lease\r\n', 'a\fb']), 'Lease agreement \n \nThis lease\fa b');

    final again = ReadTexts(dataDir: data.path);
    expect(again.has(const ReadThing.picture(picture)), isFalse);
    await again.load();
    expect(again.wordsOf(const ReadThing.picture(picture)), 'TOTAL 42.10\nThank you');
    expect(again.count, 2);
    expect(again.pathOf(const ReadThing.picture('../escape.jpg')), isNull);
  });

  test('an empty sidecar is a thing read with nothing in it, and none is a thing not read', () async {
    await texts.keep(const ReadThing.picture(picture), '');
    expect(texts.has(const ReadThing.picture(picture)), isTrue);
    expect(texts.has(const ReadThing.file(lease)), isFalse);
    expect(texts.of('![](image/$picture)'), '', reason: 'nothing to find a note by');
  });

  test('a note is found by the words read in its pictures and files, and its row says where', () async {
    searchExtra = texts;
    final flat = note('flat', '# The flat\n\n[Lease 2026.pdf](file/$lease "2.4 MB")\n');
    final dinner = note('dinner', '# Dinner\n\n![](image/$picture)\n');
    final other = note('other', '# Something else\n');
    expect(note_text.matches(flat, 'monthly'), isFalse);

    await texts.keep(const ReadThing.file(lease), textOfPages(['Lease agreement', 'Rent is due monthly on the first']));
    await texts.keep(const ReadThing.picture(picture), 'TOTAL 42.10');
    // The words moved: what the search had read of each note is read again, once.
    expect(note_text.matches(flat, 'rent monthly'), isTrue);
    expect(note_text.matches(dinner, 'total'), isTrue);
    expect(note_text.matches(other, 'rent'), isFalse);

    final found = findNotes([flat, dinner, other], 'rent monthly');
    expect(found.map((f) => f.note.id), ['flat']);
    final snippet = found.single.snippet!;
    expect(snippet.text, 'Rent is due monthly on the first in Lease 2026.pdf, page 2');
    expect(snippet.marks.map((m) => snippet.text.substring(m.$1, m.$2)), ['Rent', 'monthly']);
    expect(findNotes([dinner], 'total').single.snippet!.text, 'TOTAL 42.10 in a picture');
    await texts.keep(const ReadThing.file(lease), textOfPages(['Lease', 'The deposit is returned within thirty days.']));
    expect(findNotes([flat], 'thirty').single.snippet!.text, 'The deposit is returned within thirty days in Lease 2026.pdf, page 2');

    // Its words gone with the file: the note is not found by them any more.
    await texts.forget(const ReadThing.file(lease));
    expect(note_text.matches(flat, 'monthly'), isFalse);
  });

  test('a note’s own words come first, and the hook asks nothing of a note that shows nothing read', () async {
    searchExtra = texts;
    await texts.keep(const ReadThing.picture(picture), 'receipt from the bakery');
    final both = note('both', '# Bakery run\n\nbought bread at the bakery\n\n![Till slip](image/$picture)\n');
    final found = findNotes([both], 'bread');
    expect(found.single.snippet!.text, 'bought bread at the bakery');
    expect(findNotes([both], 'receipt').single.snippet!.text, 'receipt from the bakery in Till slip');
    expect(texts.of('# Plain words only'), '');
  });

  test('things are named in a body in order, once each, pictures and files alike', () {
    const body = '![](image/$picture)\n[Lease.pdf](file/$lease)\n![again](image/$picture)\n';
    expect(thingsIn(body).map((t) => t.key), ['image/$picture', 'file/$lease']);
    expect(const ReadThing.file('a.pdf').readable, isTrue);
    expect(const ReadThing.file('a.zip').readable, isFalse);
    expect(ReadThing.ofKey('file/a.pdf'), const ReadThing.file('a.pdf'));
    expect(ReadThing.ofKey('video/a.mp4'), isNull);
  });
}
