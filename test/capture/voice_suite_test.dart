/// Every recording in the voice suite, from its script: the recorder's rules against what each test says should
/// happen, played through the live reader as the recorder runs it (`lib/capture/live_route.dart`). A port of
/// `src/app/capture/voiceSuite.test.ts`, case for case, with one group more: every case's outcome held against what
/// the web's own `voiceSuite.ts` left for it (`fixtures/voice_suite_web.json`, written by `tool/voice_fixtures.mjs`).
///
/// With GLYPH_VOICE set, the same tests again from what Whisper heard in the audio files, as on the web.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/markdown.dart';
import 'package:ghost_md/capture/spoken/extras.dart';
import 'package:ghost_md/capture/spoken/inline.dart';
import 'package:ghost_md/capture/voice_suite.dart';
import 'package:ghost_md/plugins/marks.dart';

final Suite suite = Suite.fromJson(jsonDecode(File('test/capture/fixtures/suite.json').readAsStringSync()) as Map<String, Object?>);
final Map<String, Object?> web = jsonDecode(File('test/capture/fixtures/voice_suite_web.json').readAsStringSync()) as Map<String, Object?>;

/// The Marks plugin's cues, as the web test takes them from `MARKS`.
List<SpokenFormat> marksFormats() => [
  for (final format in marks)
    if (format.cue != null && format.cue!.isNotEmpty) SpokenFormat(word: format.cue!, delimiter: format.delimiter),
];

void main() {
  setUpAll(() {
    // The Marks plugin is on by default, so its cues can be said.
    setSpokenFormats(marksFormats());
  });

  tearDownAll(() {
    setSpokenFormats(const []);
    setLinkTitles(const []);
  });

  group('the voice suite, from the scripts', () {
    for (final test_ in suite.tests) {
      // A test held back is skipped, with why (voice-tests/suite.json `skip`).
      test('${test_.file}: ${test_.tests}${test_.skip != null ? ' (skipped: ${test_.skip})' : ''}', () {
        final outcome = runTest(test_, suite.fixtures, scriptHeard(test_.lines));
        expect(problems(test_, outcome), isEmpty);
      }, skip: test_.skip != null && test_.skip!.isNotEmpty ? test_.skip : null);
    }
  });

  final voice = Platform.environment['GLYPH_VOICE'];
  final heardDir = voice != null && voice.isNotEmpty
      ? '${Platform.environment['GLYPH_VOICE_DIR'] ?? '${Platform.environment['HOME']}/Desktop/glyph-voice-tests'}/.heard'
      : null;

  if (heardDir != null) {
    group('the voice suite, from the audio', () {
      for (final test_ in suite.tests) {
        final file = File('$heardDir/${test_.file}.json');
        // A test whose script changed since its recording is left until the recording is made again (`rerecord`).
        if (!file.existsSync() || test_.skip != null || test_.rerecord != null) continue;
        test('${test_.file}: ${test_.tests}', () {
          final heard = Heard.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, Object?>);
          final outcome = runTest(test_, suite.fixtures, heard);
          final wrong = problems(test_, outcome, heard: true);
          expect(wrong, isEmpty, reason: 'heard: ${heard.segments.map((s) => '[${s.startMs}-${s.endMs}] ${s.text}').join(' | ')}');
        });
      }
    });
  }

  // Not in the web's file: the same scripts, with what each leaves held against what the web's own run left.
  group('the voice suite, held against the web’s own run', () {
    final cases = (web['cases']! as List<Object?>).cast<Map<String, Object?>>();

    // The web's run counted a spoken "tomorrow" from the day it was made on: so does this one, whenever it is run.
    setUp(() => spokenToday = () => web['today']! as String);
    tearDown(resetSpokenToday);

    test('says the Marks’ cues the web says', () {
      expect([
        for (final format in marksFormats()) {'word': format.word, 'delimiter': format.delimiter},
      ], web['formats']);
    });

    test('has the web’s cases, in the web’s order', () {
      expect(suite.tests.map((t) => t.id).toList(), cases.map((c) => c['id']).toList());
    });

    for (var i = 0; i < suite.tests.length; i += 1) {
      final test_ = suite.tests[i];
      test('${test_.id} leaves what the web leaves', () {
        final theirs = cases[i];
        expect(theirs['id'], test_.id);
        final heard = scriptHeard(test_.lines);
        final heardThere = theirs['heard']! as Map<String, Object?>;
        expect([
          for (final s in heard.segments) {'text': s.text, 'startMs': s.startMs, 'endMs': s.endMs},
        ], heardThere['segments']);
        expect(heard.audioMs, heardThere['audioMs']);
        final outcome = runTest(test_, suite.fixtures, heard);
        final there = theirs['outcome']! as Map<String, Object?>;
        final mine = outcome.toJson();
        for (final key in there.keys) {
          expect(mine[key], there[key], reason: '${test_.id}: outcome.$key');
        }
        expect(mine.keys.toList(), there.keys.toList());
        // The order of the notes, which a map's equality does not look at.
        expect(outcome.notes.keys.toList(), (there['notes']! as Map<String, Object?>).keys.toList());
        final wrong = problems(test_, outcome);
        expect(wrong, theirs['problems']);
        expect(wrong.isEmpty, theirs['pass']);
      });
    }
  });

  /*
   * The scripts are timed as src-tauri/src/whisper/stream.rs commits speech - 300 ms of the quiet after a phrase kept,
   * two seconds of quiet dropped for all but 300 ms - and capture/markdown.dart's paragraph gap is set against the same
   * arithmetic. Change either side and every script is re-timed; these say what the timing is, so it cannot move unseen.
   */
  group('a script, timed as the phone commits it', () {
    int gapAfter(num pause) {
      final segments = scriptHeard([('Grocery run.', pause), ('Oat milk and eggs.', 0)]).segments;
      return segments[1].startMs - segments[0].endMs;
    }

    test('shows a pause as no gap, or 1.7 s for each two seconds of quiet past the 300 ms kept', () {
      expect(gapAfter(0), 0);
      expect(gapAfter(1), 0);
      expect(gapAfter(2.3), 1700);
      expect(gapAfter(4), 1700);
      expect(gapAfter(4.5), 3400);
    });

    test('keeps each phrase until 300 ms into the quiet after it, and times it by its words', () {
      final heard = scriptHeard([('Grocery run.', 2)]);
      // Two words at a third of a second each, never under half a second, after the 300 ms of quiet the take opens with.
      expect(heard.segments, [const Segment(text: 'Grocery run.', startMs: 0, endMs: 300 + 660 + 300)]);
      expect(heard.audioMs, 300 + 660 + 2000);
    });

    test('breaks a paragraph at a pause of two and a half seconds, and not at one of a second', () {
      List<String> paragraphs(num pause) => toParagraphs(scriptHeard([('Grocery run.', pause), ('Oat milk and eggs.', 0)]).segments);
      expect(paragraphs(2.5), ['Grocery run.', 'Oat milk and eggs.']);
      expect(paragraphs(1), ['Grocery run. Oat milk and eggs.']);
    });
  });

  group('comparing what was heard', () {
    test('takes a number said in words and one written in digits as the same', () {
      expect(heardForm('We agreed on four thousand for the kitchen.'), 'We agreed on 4000 for the kitchen.');
      expect(heardForm('We agreed on 4,000 for the kitchen.'), 'We agreed on 4000 for the kitchen.');
      expect(heardForm('The gate code is four four one seven.'), 'The gate code is 4417.');
      expect(heardForm('Calculate: four hundred fifty plus one hundred twenty'), 'Calculate: 450 plus 120');
      expect(heardForm('Someone said it'), 'Someone said it');
    });

    test('forgives a misheard word, and nothing about the marks', () {
      expect(sameShape('# Groceries\n\n- Book the ferry #travel', '# Groceries\n\n- Book the fairy #travel'), true);
      expect(sameShape('- [ ] Buy ice', '- [ ] By ice'), true);
      expect(sameShape('- [ ] Buy ice', '- Buy ice'), false);
      expect(sameShape('The deadline is **Friday**.', 'The deadline is Friday.'), false);
      // A redaction's at signs are part of a line's shape too (plugins/marks, back 2026-09-26).
      expect(sameShape('the gate code is @@4417@@', 'the gate code is 4417'), false);
      expect(sameShape('the gate code is @@4417@@', 'the gate code is @@4417@@'), true);
      expect(sameShape('# Weekend trip\n\nWe leave.', '# We can trip\n\nWe leave.'), true);
      expect(sameShape('# Weekend trip\n\nWe leave.', '# Something else entirely\n\nWe leave.'), false);
      expect(sameShape('One line.', 'One line.\n\nAnother.'), false);
    });
  });
}
