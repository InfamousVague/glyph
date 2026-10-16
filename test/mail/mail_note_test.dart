// A mail, opened, as the note it becomes (lib/mail/mail_note.dart): what the service laid out read back, the note's
// id and its pictures' names made from the mail's so filing twice writes one note, and the note itself as plain
// Markdown with its pictures in place.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/mail/mail_note.dart';

import 'support.dart';

final RegExp uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

void main() {
  test('reads what the service laid out: the head, then each file in its order', () {
    final mail = readMail(gml1(files: [
      (name: 'door.png', type: 'image/png', bytes: png, cid: 'pic1@x'),
      (name: 'menu.pdf', type: 'application/pdf', bytes: '%PDF-1.4\n'.codeUnits, cid: null),
    ]));
    expect((mail.subject, mail.from, mail.to, mail.date), ('Café plans', 'Sam Lee <sam@example.com>', 'k7m2q9xh4t3vbn8p@in.ghostmarkdown.com', 1792159500000));
    expect(mail.files.map((f) => (f.name, f.type, f.cid, f.isPicture)), [('door.png', 'image/png', 'pic1@x', true), ('menu.pdf', 'application/pdf', null, false)]);
    expect(mail.files[1].bytes, '%PDF-1.4\n'.codeUnits);
  });

  test('refuses what is not a mail, and says a newer one is newer', () {
    expect(() => readMail(Uint8List.fromList([1, 2, 3])), throwsA(isA<MailError>()));
    final newer = gml1()..setRange(0, 4, 'GML9'.codeUnits);
    expect(() => readMail(newer), throwsA(predicate((e) => '$e'.contains('newer Ghost.md'))));
  });

  test('a mail\'s note and pictures are named from its id: the same each time, a UUID, and never each other', () {
    const id = 'AbCdEfGhIjKlMnOpQrStUv';
    expect(mailNoteId(id), mailNoteId(id));
    expect(mailNoteId(id), matches(uuid));
    expect(mailNoteId('AbCdEfGhIjKlMnOpQrStUw'), isNot(mailNoteId(id)));
    final first = mailPictureName(id, 0, 'png'), second = mailPictureName(id, 1, 'png');
    expect(first, endsWith('.png'));
    expect(first.split('.').first, matches(uuid));
    expect({first, second, '${mailNoteId(id)}.png'}, hasLength(3));
    expect(mailNoteId('not the service\'s shape at all'), matches(uuid));
  });

  test('the note is its sender in the front matter, its subject as the title, the words, and the pictures in place', () {
    final mail = readMail(gml1(
      body: '## Plans\n\nMeet at the **café**.\n\n![the door](cid:pic1@x)\n\n![lost](cid:not-carried)',
      files: [
        (name: 'door.png', type: 'image/png', bytes: png, cid: 'pic1@x'),
        (name: 'map.png', type: 'image/png', bytes: png, cid: null),
      ],
    ));
    final body = mailNoteBody(mail, pictures: {0: 'a.png', 1: 'b.png'}, others: ['Came with it, not kept: menu.pdf (9 bytes).']);
    expect(body, '---\nfrom: "Sam Lee <sam@example.com>"\n---\n# Café plans\n\n## Plans\n\nMeet at the **café**.\n\n![the door](image/a.png)\n\nlost\n\n![map.png](image/b.png)\n\nCame with it, not kept: menu.pdf (9 bytes).\n');
    expect(noteTitle(body), 'Café plans');
  });

  test('a mail with no subject is named for who sent it, and one with no sender has no front matter', () {
    expect(mailTitle(readMail(gml1(subject: '  '))), 'A mail from Sam Lee');
    expect(mailTitle(readMail(gml1(subject: '', from: 'a@example.com'))), 'A mail from a@example.com');
    final bare = mailNoteBody(readMail(gml1(subject: '', from: '', body: '')));
    expect(bare, '# A mail\n');
    expect(mailTitle(readMail(gml1(subject: 'Two\n  lines'))), 'Two lines');
  });

  test('a file that is not kept is named with its size, as a person says it', () async {
    final pdf = MailFile(name: 'menu.pdf', type: 'application/pdf', bytes: Uint8List(240000));
    expect(await notKeptLine(pdf, 0), 'Came with it, not kept: menu.pdf (240 KB).');
    expect(sizeWords(1), '1 byte');
    expect(sizeWords(3400000), '3.4 MB');
  });
}
