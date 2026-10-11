// The newer prompts. A port of src/app/ai/prompts.test.ts, case for case, and before it the page's own strings and
// budgets (test/ai/fixtures/kind_prompts_web.json, written from the page's module by tool/ai_fixtures.mjs `kinds`),
// each Dart constant held to its one byte for byte.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/prompts.dart';
import 'package:ghost_md/format/prompt.dart' show systemPrompt;

const Map<String, String> byName = {'FIX_PROMPT': fixPrompt, 'SHAPE_PROMPT': shapePrompt, 'CONTINUE_PROMPT': continuePrompt, 'ASK_PROMPT': askPrompt};

void main() {
  final web = (jsonDecode(File('test/ai/fixtures/kind_prompts_web.json').readAsStringSync()) as Map).cast<String, Object?>();

  group('the page’s own', () {
    test('strings are these, byte for byte, and none is missing', () {
      final strings = (web['strings']! as Map).cast<String, String>();
      expect(strings.keys.toSet(), byName.keys.toSet());
      for (final entry in byName.entries) {
        expect(entry.value, strings[entry.key], reason: entry.key);
      }
    });

    test('prompt for each kind is the one this picks', () {
      final forKind = (web['forKind']! as Map).cast<String, String>();
      expect(forKind.keys.toSet(), {for (final kind in RunKind.values) kind.id});
      for (final kind in RunKind.values) {
        expect(promptForKind(kind), forKind[kind.id], reason: kind.id);
      }
    });

    test('budgets are these, kind by kind and size by size', () {
      final budgets = (web['budgets']! as Map).cast<String, List<Object?>>();
      for (final kind in RunKind.values) {
        for (final pair in budgets[kind.id]!.cast<List<Object?>>()) {
          expect(budgetForKind(kind, pair[0]! as int), pair[1], reason: '${kind.id} at ${pair[0]}');
        }
      }
    });
  });

  group('the newer prompts', () {
    test('each ask for the answer alone, and keep the links as tokens', () {
      for (final prompt in [fixPrompt, shapePrompt, continuePrompt, promptForKind(RunKind.ask)]) {
        expect(prompt, contains('link-1'));
        expect(prompt, contains('nothing else'));
      }
      expect(promptForKind(RunKind.format), systemPrompt);
    });

    test('tell each run that knows the table’s token of the place’s and the video’s too', () {
      for (final prompt in [fixPrompt, shapePrompt, continuePrompt, promptForKind(RunKind.ask)].where((one) => one.contains('![table-1](table)'))) {
        expect(prompt, contains('![place-1](place)'));
        expect(prompt, contains('![video-1](video)'));
      }
    });

    test('give a fix the note again, a continuation a few lines, and an ask as much as an enhancement', () {
      expect(budgetForKind(RunKind.fix, 4000), 1314);
      expect(budgetForKind(RunKind.fix, 10), 128);
      expect(budgetForKind(RunKind.continueWriting, 4000), 398);
      expect(budgetForKind(RunKind.continueWriting, 40000), 512);
      expect(budgetForKind(RunKind.ask, 4000), 2256);
      expect(budgetForKind(RunKind.format, 4000), 2192);
    });

    test('puts the instruction before the note', () {
      expect(askMessage('  shorten it ', '# A\n'), 'Instruction: shorten it\n\nThe note:\n# A\n');
    });
  });
}
