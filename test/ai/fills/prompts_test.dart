// The fill prompts. A port of src/app/ai/fills/prompts.test.ts, case for case.
//
// The page's first case reads each literal out of prompts.ts's source, as the Rust tests do, and holds the module's
// string to it. Here the page's strings are test/ai/fixtures/fill_prompts_web.json (written from the page's module by
// tool/ai_fixtures.mjs), and each Dart constant is held to its one, byte for byte.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/fills/prompts.dart' as prompts;

const Map<String, String> byName = {
  'FILL_PROMPT': prompts.fillPrompt,
  'FILL_WEB_PROMPT': prompts.fillWebPrompt,
  'FILL_CORE': prompts.fillCore,
  'FILL_ANSWER': prompts.fillAnswer,
  'FILL_NUMBER': prompts.fillNumber,
  'FILL_TITLE': prompts.fillTitle,
  'FILL_SUMMARY': prompts.fillSummary,
  'FILL_ITEMS': prompts.fillItems,
  'FILL_CELL': prompts.fillCell,
  'FILL_TRANSLATE': prompts.fillTranslate,
};

void main() {
  group('the fill prompts', () {
    test('are literals the Rust tests read whole: no \${…} and no backtick inside', () {
      final web = (jsonDecode(File('test/ai/fixtures/fill_prompts_web.json').readAsStringSync()) as Map).cast<String, String>();
      expect(web.keys.toSet(), byName.keys.toSet());
      for (final MapEntry(key: name, value: prompt) in byName.entries) {
        expect(prompt, web[name], reason: name);
        expect(prompt, isNot(contains(r'${')), reason: name);
        expect(prompt, isNot(contains('`')), reason: name);
      }
    });

    test('name UNKNOWN, never “Never invent”, and answer their examples in [1] lines', () {
      const prompt = prompts.fillPrompt;
      expect(prompt, contains('answer exactly: UNKNOWN'));
      expect(prompt, isNot(contains('Never invent')));
      expect(RegExp(r'^\[\d\] ', multiLine: true).allMatches(prompt).length, 8);
      expect(prompt.endsWith('[1] おはようございます (ohayō gozaimasu)'), isTrue);
    });

    test('give every third-rung block its worked example', () {
      for (final name in ['FILL_ANSWER', 'FILL_NUMBER', 'FILL_TITLE', 'FILL_SUMMARY', 'FILL_ITEMS', 'FILL_CELL', 'FILL_TRANSLATE']) {
        expect(byName[name], contains('Example.'), reason: name);
      }
    });

    test('keep the web prompt to what the source returned', () {
      expect(prompts.fillWebPrompt, contains('Answer only from what the source returned.'));
      expect(prompts.fillWebPrompt, contains('answer exactly: UNKNOWN'));
    });
  });
}
