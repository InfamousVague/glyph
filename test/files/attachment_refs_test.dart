// The line a file is written as in a note (lib/core/attachment_refs.dart), and the names sync carries a file and
// the words read in a thing by (lib/sync/notes.dart `fileId`).
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/attachment_refs.dart';
import 'package:ghost_md/sync/notes.dart' show FileKind, fileId;

const String uuid = '5f0c2e9a-1b2c-4d3e-8f40-0a1b2c3d4e5f';

void main() {
  group('the line', () {
    test('is the file’s own name linked to its kept name, its size the title', () {
      expect(attachmentMarkdown('$uuid.pdf', 'Lease 2026.pdf', bytes: 2400000), '[Lease 2026.pdf](file/$uuid.pdf "2.4 MB")');
      expect(attachmentMarkdown('$uuid.pdf', 'Lease.pdf'), '[Lease.pdf](file/$uuid.pdf)');
      expect(attachmentMarkdown('$uuid.txt', 'notes.txt', bytes: 12), '[notes.txt](file/$uuid.txt "12 bytes")');
    });

    test('takes out what would end the link, and names a file with no name', () {
      expect(attachmentWords('Q3 [draft]\nfinal.docx'), 'Q3 draft final.docx');
      expect(attachmentWords('  '), 'File');
      expect(attachmentMarkdown('$uuid.bin', '[]'), '[File](file/$uuid.bin)');
    });

    test('is read back from a line, past a list’s lead and a quote’s marks, and nowhere else', () {
      const line = '[Lease 2026.pdf](file/$uuid.pdf "2.4 MB")';
      expect(attachmentOfLine(line), const AttachmentLine(name: '$uuid.pdf', label: 'Lease 2026.pdf', size: '2.4 MB'));
      expect(attachmentOfLine('- $line')?.name, '$uuid.pdf');
      expect(attachmentOfLine('> $line')?.label, 'Lease 2026.pdf');
      expect(attachmentOfLine('[Lease.pdf](file/$uuid.pdf)')?.size, isNull);
      expect(attachmentOfLine('See $line'), isNull, reason: 'a link inside a sentence is a link, not a card');
      expect(attachmentOfLine('[Lease](file/../secret.pdf)'), isNull);
      expect(attachmentOfLine('[Lease](https://example.com/file/a.pdf)'), isNull);
      expect(attachmentOfLine('![a picture](image/$uuid.jpg)'), isNull);
    });

    test('names every file a body links, once each and in order', () {
      const body = '# Trip\n\n[Tickets.pdf](file/a1.pdf "80 KB")\n\nand again [Tickets.pdf](file/a1.pdf) and [map.png](file/b2.png)\n';
      expect(attachmentNames(body), ['a1.pdf', 'b2.png']);
      expect(attachmentNames('no files here'), isEmpty);
    });
  });

  group('the name it is kept by', () {
    test('keeps the extension it came with in lower case, and .bin for none', () {
      expect(keptExtension('Lease.PDF'), 'pdf');
      expect(keptExtension('archive.tar.gz'), 'gz');
      expect(keptExtension('Makefile'), 'bin');
      expect(keptExtension('weird.ext!'), 'bin');
      expect(attachmentName.hasMatch('$uuid.pdf'), isTrue);
      expect(attachmentName.hasMatch('../$uuid.pdf'), isFalse);
      expect(attachmentName.hasMatch('$uuid.PDF'), isFalse);
    });

    test('says what kind a file is, and what to hand it to another app as', () {
      expect(attachmentKindOf('a.pdf'), AttachmentKind.pdf);
      expect(attachmentKindOf('a.xlsx'), AttachmentKind.sheet);
      expect(attachmentKindOf('a.mp3'), AttachmentKind.sound);
      expect(attachmentKindOf('a.bin'), AttachmentKind.file);
      expect(attachmentKindWord(AttachmentKind.sheet), 'Spreadsheet');
      expect(attachmentMimeOf('a.pdf'), 'application/pdf');
      expect(attachmentMimeOf('a.bin'), 'application/octet-stream');
    });

    test('reads a title’s size back about as many bytes as it said', () {
      expect(bytesOfSize('2.4 MB'), 2400000);
      expect(bytesOfSize('830 KB'), 830000);
      expect(bytesOfSize('12 bytes'), 12);
      expect(bytesOfSize('big'), isNull);
      expect(bytesOfSize(null), isNull);
    });
  });

  group('what sync calls it', () {
    test('a file a note links is a-<ext>-<stem>, and the words read in a thing t-i or t-a', () {
      expect(fileId(FileKind.attachment, '$uuid.pdf'), 'a-pdf-$uuid');
      expect(fileId(FileKind.attachment, '$uuid.7z'), 'a-7z-$uuid');
      expect(fileId(FileKind.text, 'image/$uuid.jpg'), 't-i-jpg-$uuid');
      expect(fileId(FileKind.text, 'file/$uuid.pdf'), 't-a-pdf-$uuid');
      expect(fileId(FileKind.text, '$uuid.jpg'), isNull, reason: 'words are named for the thing they were read in');
      expect(fileId(FileKind.attachment, '../$uuid.pdf'), isNull);
      expect(fileId(FileKind.image, '$uuid.jpg'), 'i-jpg-$uuid', reason: 'a picture’s name is what it was');
    });
  });
}
