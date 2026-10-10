// The port's highlighter against the web editor's own, on the same code: every sample of test/editor/code/samples
// was parsed by the parser @codemirror/language-data loads for its language and highlighted by @lezer/highlight
// with the classes of src/app/editor/glyphHighlight.ts (tool/code_fixtures.mjs wrote what came out, into
// fixtures/tokens.json); here each is read by the port's reader for that language and must come out the same,
// run for run: the same characters in the same classes, joined and parted in the same places.
//
// A language the pack knows and the port does not read is said here by name, so the list is one a test holds.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/code/languages.dart';
import 'package:ghost_md/editor/code/work.dart';

List<Object> runsOf(CodeLanguage language, String code) {
  final work = language.start(code)..work(code.length, Budget.none());
  final out = <Object>[];
  work.spans(0, code.length, (from, to, cls) {
    out
      ..add(from)
      ..add(to)
      ..add(cls);
  });
  return out;
}

void main() {
  final tokens = (jsonDecode(File('test/editor/code/fixtures/tokens.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final names = (jsonDecode(File('test/editor/code/fixtures/names.json').readAsStringSync()) as Map).cast<String, String?>();

  test('a fence\'s info string names the language the web names: ${names.length} things people write', () {
    final wrong = <String>[
      for (final entry in names.entries)
        if (languageNameOf(entry.key) != entry.value) '"${entry.key}": ${languageNameOf(entry.key)}, the web ${entry.value}',
    ];
    expect(wrong, isEmpty);
    // The ones worth saying aloud: an extension is not a name, a short name wants room either side, and a
    // longer name is found anywhere.
    expect(languageNameOf('js'), 'JavaScript');
    expect(languageNameOf('py'), isNull);
    expect(languageNameOf('rs'), isNull);
    expect(languageNameOf('md'), isNull);
    expect(languageNameOf('python title="x.py"'), 'Python');
    expect(languageNameOf('plaintext'), 'LaTeX');
    expect(languageNameOf('ts-node'), 'JavaScript');
    expect(languageNameOf(''), isNull);
  });

  final unread = <String>[];
  for (final sample in tokens) {
    final name = sample['language'] as String;
    final language = languageNamed(name);
    if (language == null) {
      unread.add(name);
      continue;
    }
    test('${sample['file']}: $name, ${(sample['runs'] as List).length ~/ 3} runs', () {
      final code = sample['code'] as String;
      final mine = runsOf(language, code);
      final theirs = (sample['runs'] as List).cast<Object>();
      List<String> show(List<Object> runs) => <String>[
        for (var i = 0; i < runs.length; i += 3) '${runs[i]}-${runs[i + 1]} ${runs[i + 2]} ${jsonEncode(code.substring(runs[i] as int, runs[i + 1] as int))}',
      ];
      final here = show(mine), there = show(theirs);
      final a = here.toSet(), b = there.toSet();
      final onlyHere = here.where((line) => !b.contains(line)).toList(), onlyThere = there.where((line) => !a.contains(line)).toList();
      if (onlyHere.isNotEmpty || onlyThere.isNotEmpty) {
        fail('${onlyHere.length} runs only here, ${onlyThere.length} only on the web, of ${there.length}\nHERE:\n${onlyHere.take(10).join('\n')}\nWEB:\n${onlyThere.take(10).join('\n')}');
      }
      expect(here, there, reason: 'the same runs in another order');
    });
  }

  test('the languages with a sample that the port does not read', () {
    expect(unread, <String>[
      'Markdown',
      'SCSS',
      'LESS',
      'Dockerfile',
      'PowerShell',
      'Perl',
      'R',
      'Haskell',
      'Clojure',
      'LaTeX',
      'Nginx',
      'ProtoBuf',
      'Erlang',
      'Groovy',
      'Pascal',
      'Julia',
      'F#',
      'OCaml',
      'CMake',
      'HTTP',
      'VB.NET',
      'Sass',
      'WebAssembly',
    ]);
  });
}
