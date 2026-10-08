// The phone's write-up (src-tauri/src/write_up.rs, transcript.rs) cuts a long transcript into pieces, gives each
// pass its budget and puts the transcript into the note by the app's own rules, written again in Rust because it
// runs with no app. The fixture beside this file (fixtures/writeUpTwins.fixture.json, the web's own, copied) is read
// by every side, so a rule changed on one and not the others fails on the side that was not changed. A port of
// `src/app/ai/writeUpTwins.test.ts`, case for case.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/summary_text.dart';
import 'package:ghost_md/core/library.dart' show withTranscript, withoutTranscript;
import 'package:ghost_md/format/prompt.dart';

final RegExp _trailingSpace = RegExp(r'\s+$');

/// JavaScript's `trimEnd`.
String trimEnd(String text) => text.replaceFirst(_trailingSpace, '');

void main() {
  final fixture = (jsonDecode(File('test/ai/fixtures/writeUpTwins.fixture.json').readAsStringSync()) as Map).cast<String, Object?>();
  List<Map<String, Object?>> rows(String key) => [for (final row in fixture[key] as List) (row as Map).cast<String, Object?>()];

  group('the write-up’s twins', () {
    test('cut a long transcript into the same pieces', () {
      final pieces = rows('pieces');
      expect(pieces.length, greaterThan(0));
      for (final piece in pieces) {
        final plain = List.filled(piece['times'] as int, piece['unit'] as String).join(piece['joiner'] as String);
        expect([for (final p in transcriptPieces(plain, piece['size'] as int)) p.length], piece['pieces'], reason: piece['name'] as String);
      }
    });

    test('give each pass the same budget', () {
      for (final budget in rows('budgets')) {
        final chars = budget['chars'] as int;
        expect([recordingSummaryBudget(chars), recordingNotesBudget(chars)], [budget['summary'], budget['notes']], reason: '$chars');
      }
    });

    test('put the transcript in the same place and take it out the same way', () {
      for (final section in rows('sections')) {
        final body = section['body'] as String;
        expect(trimEnd(withTranscript(body, '## Transcript\n\n${section['words']}')), trimEnd(section['withTranscript'] as String));
        expect(withoutTranscript(body), section['withoutTranscript']);
      }
    });
  });
}
