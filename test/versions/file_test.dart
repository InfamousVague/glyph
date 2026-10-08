import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/versions_file.dart';

/// A note's versions file (lib/core/versions_file.dart): the web's `src/app/core/versions/file.test.ts`, case for
/// case. The file is what two devices exchange, so the first case's text is the page's own, to the byte.
int at(int minute) => DateTime.utc(2026, 10, 4, 15, minute).millisecondsSinceEpoch;

String? keep(String? file, String text, int minute, {String by = 'matt', String? label}) => withVersion(file, 'gho-1', text, at: at(minute), by: by, label: label);

void main() {
  group('a versions file', () {
    test('reads like a lock file: a head line per version, and under it only what changed', () {
      var file = keep(null, '# Launch plan\n- book the venue\n', 0)!;
      file = keep(file, '# Launch plan\n- book the venue (done)\n- send invites\n', 42, label: 'Before the review')!;
      expect(
        file,
        [
          '# Ghost.md versions 1',
          '# note gho-1',
          '# A version is the change from the one before it: "=N" keeps N lines, "-" takes a line out, "+" puts one in.',
          '',
          'v1 2026-10-04T15:00:00.000Z matt ${hashText('# Launch plan\n- book the venue\n')} full',
          '  +# Launch plan',
          '  +- book the venue',
          '  +',
          'v2 2026-10-04T15:42:00.000Z matt ${hashText('# Launch plan\n- book the venue (done)\n- send invites\n')} "Before the review"',
          '  =1',
          '  -- book the venue',
          '  +- book the venue (done)',
          '  +- send invites',
          '  =1',
          '',
        ].join('\n'),
      );
    });

    test('hashes as the page does: FNV-1a over UTF-16 units, eight hex digits', () {
      // The page's own answers (`hashText`, asked of the web's module 2026-10-07).
      expect(hashText(''), '811c9dc5');
      expect(hashText('a'), 'e40c292c');
      expect(hashText('# Launch plan\n- book the venue\n'), hashText('# Launch plan\n- book the venue\n'));
      expect(hashText('foobar'), 'bf9cf968');
      expect(hashText('naïve 🥛'), matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(hashText('🥛'), isNot(hashText('🥚')));
    });

    test('gives back every version exactly, with how much each changed', () {
      String? file;
      const texts = ['a', 'a\nb', 'b\nc', '', 'line with "quotes" and  =3 inside\n  +not a step\n'];
      for (final (i, text) in texts.indexed) {
        file = keep(file, text, i) ?? file;
      }
      final read = readFile(file!)!;
      expect(read.noteId, 'gho-1');
      expect(read.damaged, 0);
      expect([for (final v in read.versions) v.text], texts);
      expect([for (final v in read.versions) v.n], [1, 2, 3, 4, 5]);
      final third = read.versions[2];
      expect((third.added, third.removed, third.by, third.at), (1, 1, 'matt', at(2)));
    });

    test('keeps no version of no change, but names the last one when asked to', () {
      final file = keep(null, 'words', 0)!;
      expect(keep(file, 'words', 5), isNull);
      final named = keep(file, 'words', 5, label: 'Sent to Sam')!;
      expect(readFile(named)!.versions, hasLength(1));
      expect(readFile(named)!.versions[0].label, 'Sent to Sam');
      // Named the same again, or with only spaces: nothing to keep.
      expect(keep(named, 'words', 6, label: ' Sent to Sam '), isNull);
      expect(keep(named, 'words', 6, label: '   '), isNull);
    });

    test('writes a whole version every so often, so a damaged one costs only those up to the next', () {
      String? file;
      for (var i = 0; i < fullEvery + 5; i += 1) {
        file = keep(file, 'version $i\nsame tail', i);
      }
      expect(file!.split('\n').where((line) => line.endsWith(' full')), hasLength(2));
      // Break version 3's change: versions 3 to 50 cannot be rebuilt, the whole one at 51 starts again.
      final broken = file.replaceFirst('  +version 2', '  +version two');
      final read = readFile(broken)!;
      expect(read.damaged, fullEvery - 2);
      expect([for (final v in read.versions) v.text.split('\n')[0]], ['version 0', 'version 1', for (var i = 0; i < 5; i += 1) 'version ${fullEvery + i}']);
    });

    test('keeps at most mostVersions, letting the oldest go', () {
      final versions = [for (var i = 0; i < mostVersions + 3; i += 1) VersionWords(at: i, by: 'matt', text: 'v$i')];
      final read = readFile(writeFile('gho-1', versions))!;
      expect(read.versions, hasLength(mostVersions));
      expect(read.versions[0].text, 'v3');
    });

    test('is not a versions file when it does not say so', () {
      expect(readFile('# Shopping\n- milk'), isNull);
      expect(readFile(''), isNull);
      expect(keep('# Shopping', 'fresh', 1), contains('v1 '));
    });

    test('writes a keeper with no spaces, a name as JSON, and reads a head it cannot place as no time', () {
      final file = writeFile('n', const [VersionWords(at: 0, by: 'two  words', text: 'x', label: 'say "hi" \\ there'), VersionWords(at: 1, by: '', text: 'y')]);
      expect(file, contains('v1 1970-01-01T00:00:00.000Z two-words ${hashText('x')} full "say \\"hi\\" \\\\ there"'));
      expect(file, contains('v2 1970-01-01T00:00:00.001Z me ${hashText('y')}\n'));
      final read = readFile(file)!;
      expect(read.versions[0].label, 'say "hi" \\ there');
      expect(read.versions[1].by, 'me');
      expect(readFile(file.replaceFirst('1970-01-01T00:00:00.000Z', 'whenever'))!.versions[0].at, 0);
    });
  });

  group('two devices’ versions, merged', () {
    test('is every version from both, once, in the order they were kept', () {
      final shared = keep(keep(null, 'one', 0)!, 'one\ntwo', 1)!;
      final phone = keep(shared, 'one\ntwo\nphone', 5)!;
      final mac = keep(keep(shared, 'one\ntwo\nmac', 3)!, 'one\ntwo\nmac\nmore', 7, label: 'Done')!;
      final merged = readFile(mergeFiles(phone, mac, 'gho-1')!)!;
      expect(merged.damaged, 0);
      expect([for (final v in merged.versions) v.text], ['one', 'one\ntwo', 'one\ntwo\nmac', 'one\ntwo\nphone', 'one\ntwo\nmac\nmore']);
      expect(merged.versions[4].label, 'Done');
      // Merging again changes nothing, either way round.
      expect(mergeFiles(mergeFiles(phone, mac, 'gho-1'), mac, 'gho-1'), mergeFiles(mac, phone, 'gho-1'));
    });

    test('takes the one there is when the other side has none', () {
      final file = keep(null, 'only', 0)!;
      expect(mergeFiles(null, file, 'gho-1'), file);
      expect(mergeFiles(null, null, 'gho-1'), isNull);
    });

    test('orders two kept in the same moment by who kept them and then by what they held, as the page does', () {
      final a = writeFile('n', const [VersionWords(at: 5, by: 'sam', text: 'sam’s')]);
      final b = writeFile('n', const [VersionWords(at: 5, by: 'Matt', text: 'matt’s'), VersionWords(at: 5, by: 'matt', text: 'lower')]);
      final merged = readFile(mergeFiles(a, b, 'n')!)!;
      // `localeCompare`: matt before Matt before sam, where code units would put Matt first.
      expect([for (final v in merged.versions) v.by], ['matt', 'Matt', 'sam']);
      expect(mergeFiles(b, a, 'n'), mergeFiles(a, b, 'n'));
      expect(compareAsPage('a-b', 'a.b'), lessThan(0));
      expect(compareAsPage('a_b', 'a-b'), lessThan(0));
      expect(compareAsPage('a.b', 'a1'), lessThan(0));
      expect(compareAsPage('a9', 'aa'), lessThan(0));
      expect(compareAsPage('ab', 'abc'), lessThan(0));
      expect(compareAsPage('B', 'a'), greaterThan(0));
      expect(compareAsPage('same', 'same'), 0);
    });
  });
}
