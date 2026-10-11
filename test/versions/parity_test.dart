import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/versions_diff.dart';
import 'package:ghost_md/core/versions_file.dart';

/// The Dart port held to the web's own modules: `fixtures/web_versions.json` is what `core/versions/diff.ts` and
/// `core/versions/file.ts` answered (fixtures/web_versions.mjs, run under Node against tauri/, 2026-10-07) for a
/// few hundred seeded cases - edit scripts, hashes, files grown a version at a time, two devices' files merged -
/// and the port has to answer every one the same. A versions file is exchanged between this app and the web's, so
/// "the same" is to the byte.
void main() {
  final web = jsonDecode(File('test/versions/fixtures/web_versions.json').readAsStringSync()) as Map<String, dynamic>;

  Object stepJson(Step step) => switch (step) {
        Keep(:final count) => {'keep': count},
        Del(:final line) => {'del': line},
        Add(:final line) => {'add': line},
      };

  Object? readJson(String? file) {
    final read = file == null ? null : readFile(file);
    if (read == null) return null;
    return {
      'noteId': read.noteId,
      'damaged': read.damaged,
      'versions': [
        for (final v in read.versions) {'n': v.n, 'at': v.at, 'by': v.by, 'hash': v.hash, 'added': v.added, 'removed': v.removed, 'label': v.label, 'text': v.text},
      ],
    };
  }

  test('finds the page’s edit script, step for step, and its first change', () {
    final diffs = (web['diffs'] as List).cast<Map<String, dynamic>>();
    expect(diffs, hasLength(60));
    for (final (i, each) in diffs.indexed) {
      final before = each['before'] as String, after = each['after'] as String;
      final steps = diffLines(linesOf(before), linesOf(after));
      expect(steps.map(stepJson).toList(), each['steps'], reason: 'diff $i');
      expect(applySteps(linesOf(before), steps)?.join('\n'), after, reason: 'diff $i');
      final first = firstChange(each['firstBefore'] as String?, after);
      expect(first == null ? null : {'kind': first.kind, 'text': first.text}, each['first'], reason: 'first $i');
    }
  });

  test('hashes a text as the page does', () {
    for (final each in (web['hashes'] as List).cast<Map<String, dynamic>>()) {
      expect(hashText(each['text'] as String), each['hash'], reason: jsonEncode(each['text']));
    }
  });

  test('grows a file a version at a time into the page’s file, and reads it back as the page does', () {
    final histories = (web['histories'] as List).cast<Map<String, dynamic>>();
    expect(histories, hasLength(24));
    for (final history in histories) {
      final noteId = history['noteId'] as String;
      String? file;
      for (final (i, kept) in (history['kept'] as List).cast<Map<String, dynamic>>().indexed) {
        final next = withVersion(file, noteId, kept['text'] as String, at: kept['at'] as int, by: kept['by'] as String, label: kept['label'] as String?);
        expect(next, kept['file'], reason: '$noteId, version ${i + 1}');
        file = next ?? file;
      }
      expect(readJson(file), history['read'], reason: noteId);
    }
  });

  test('merges two devices’ files into the page’s file, either way round', () {
    final merges = (web['merges'] as List).cast<Map<String, dynamic>>();
    expect(merges, hasLength(16));
    for (final (i, each) in merges.indexed) {
      final mine = each['mine'] as String?, theirs = each['theirs'] as String?;
      expect(mergeFiles(mine, theirs, 'm'), each['merged'], reason: 'merge $i');
      expect(mergeFiles(theirs, mine, 'm'), each['back'], reason: 'merge $i, back');
      expect(readJson(each['merged'] as String?), each['read'], reason: 'merge $i, read');
    }
  });

  test('writes a long history as the page does, a whole version every fifty', () {
    final versions = [for (var i = 0; i < 130; i += 1) VersionWords(at: i * 1000, by: 'matt', text: 'line $i\nsame\n${i % 7}')];
    expect(writeFile('big', versions), web['many']);
  });

  test('orders handles, hashes and ids as the page’s localeCompare does', () {
    final sorted = (web['sorted'] as List).cast<String>();
    expect(sorted.reversed.toList()..sort(compareAsPage), sorted);
  });
}
