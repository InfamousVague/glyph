// The pack's older modes run from their own JavaScript (lib/editor/code/stream/js_mode.dart): that every one of
// them can be run, that none can take the editor down whatever it is given, and what a block costs.
//
// What each colours is conformance_test.dart's to say; this is about the running.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/code/languages.dart';
import 'package:ghost_md/editor/code/stream/js_mode.dart';
import 'package:ghost_md/editor/code/stream/modes.g.dart';
import 'package:ghost_md/editor/code/work.dart';

void main() {
  final tokens = (jsonDecode(File('test/editor/code/fixtures/tokens.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final samples = <String, String>{for (final sample in tokens) sample['language'] as String: sample['code'] as String};

  test('each of the ${legacyModes.length} languages of the older modes is read, and has a sample that says how', () {
    final unread = <String>[
      for (final (language, _, _, _) in legacyModes)
        if (languageNamed(language) == null) language,
    ];
    expect(unread, isEmpty);
    final unsampled = <String>[
      for (final (language, _, _, _) in legacyModes)
        if (!samples.containsKey(language)) language,
    ];
    expect(unsampled, isEmpty);
  });

  test('every mode file runs, each once, and a block in a language already met costs no loading', () {
    final files = <String>{for (final (_, file, _, _) in legacyModes) file};
    for (final (language, _, _, _) in legacyModes) {
      final code = samples[language]!;
      languageNamed(language)!.start(code).work(code.length, Budget.none());
    }
    expect(JsMode.unloaded, isEmpty);
    // The modes ported by hand never load their file; the rest load theirs and the files those import.
    expect(JsMode.filesRun, lessThanOrEqualTo(modeFiles.length));
    expect(JsMode.filesRun, greaterThan(files.length - 12));
    final before = JsMode.filesRun;
    for (final (language, _, _, _) in legacyModes) {
      final code = samples[language]!;
      languageNamed(language)!.start(code).work(code.length, Budget.none());
    }
    expect(JsMode.filesRun, before);
  });

  test('no mode fails on its own sample', () {
    JsMode.failed = 0;
    CodeStats.reset();
    for (final (language, _, _, _) in legacyModes) {
      final code = samples[language]!;
      languageNamed(language)!.start(code).work(code.length, Budget.none());
      expect(JsMode.failed, 0, reason: '$language: ${JsMode.lastFailure}');
      expect(CodeStats.stuck, 0, reason: language);
    }
  });

  test('whatever is typed into a block, it is read to its end', () {
    // Each language's sample with things put where they should not be, and another language's sample entire.
    const pieces = <String>['"', "'", '/*', '*/', '{', '}', '(', ')', '[', ']', '<', '>', '#', '//', '`', r'$', r'\', '%', '@', ';', '"""', "'''", '<!--', '-->', '{{', '}}', '\t', ' ', 'é', '😀', '\n\n', '=begin', '->', '::', '|', '&', '~', '^'];
    final random = Random(7);
    final all = samples.values.toList();
    JsMode.failed = 0;
    CodeStats.reset();
    var blocks = 0;
    for (final (language, _, _, _) in legacyModes) {
      final reader = languageNamed(language)!;
      final texts = <String>[all[random.nextInt(all.length)], '', '\n', ' ', 'x' * 12000];
      for (var variant = 0; variant < 12; variant++) {
        var text = samples[language]!;
        for (var change = 0; change < 1 + variant * 2; change++) {
          final at = random.nextInt(text.length + 1);
          text = random.nextInt(4) == 0 ? text.substring(0, at) + text.substring(min(text.length, at + random.nextInt(9))) : text.substring(0, at) + pieces[random.nextInt(pieces.length)] + text.substring(at);
        }
        texts.add(text);
      }
      for (final text in texts) {
        final work = reader.start(text)..work(text.length, Budget.none());
        expect(work.done, isTrue, reason: language);
        var last = 0;
        work.spans(0, text.length, (from, to, cls) {
          expect(from >= last && to > from && to <= text.length, isTrue, reason: '$language: a run from $from to $to after $last');
          last = to;
        });
        blocks++;
      }
    }
    // What the web's editor would have stopped at: a mode's own error, or a mode that would not move.
    // ignore: avoid_print
    print('$blocks blocks read to their ends; a mode threw on ${JsMode.failed} lines (the last: ${JsMode.lastFailure}) and stood still ${CodeStats.stuck} times');
    expect(JsMode.unloaded, isEmpty);
  });
}
