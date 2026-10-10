// The port's reader of JavaScript (lib/editor/code/stream/js) against JavaScript: tool/code_modes.mjs wrote small
// programs in the JavaScript CodeMirror's older modes are written in, each with its syntax tree and with what
// Node made of it (fixtures/js.json). Here each tree is run and must give Node's answer.
//
// The modes themselves are the larger test of it (conformance_test.dart: a hundred and ten languages' samples,
// token for token); these say which turn of the language went wrong when one of those does.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/code/stream/js/js.dart';

/// A value as `JSON.stringify` writes it: `undefined` and a function are `null` in a list and left out of an
/// object, a number that is not one is `null`.
Object? plain(Object? value) {
  if (value is JsArray) return <Object?>[for (final item in value.list) plain(item)];
  if (value is JsCallable || identical(value, undefined)) return null;
  if (value is JsObject) {
    return <String, Object?>{
      for (final key in value.ownKeys())
        if (!identical(value.get(key), undefined) && value.get(key) is! JsCallable) key: plain(value.get(key)),
    };
  }
  if (value is double) {
    if (value.isNaN || value.isInfinite) return null;
    if (value == value.truncateToDouble() && value.abs() < 1e15) return value.toInt();
  }
  return value;
}

void main() {
  final programs = (jsonDecode(File('test/editor/code/fixtures/js.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

  for (final program in programs) {
    test('JavaScript: ${program['name']}', () {
      final exports = runModule(program['tree'] as Map<String, dynamic>, (file) => throw StateError('no module $file'));
      expect(jsonEncode(plain(exports['answer'])), jsonEncode(program['answer']));
    });
  }

  test('a loop that would not end is stopped, and says so', () {
    // `export const answer = (function () { for (;;) {} })()`, its tree written by hand.
    final forever = <String, dynamic>{
      'type': 'Program',
      'body': <dynamic>[
        <String, dynamic>{
          'type': 'ExpressionStatement',
          'expression': <String, dynamic>{
            'type': 'CallExpression',
            'callee': <String, dynamic>{
              'type': 'FunctionExpression',
              'id': null,
              'params': <dynamic>[],
              'body': <String, dynamic>{
                'type': 'BlockStatement',
                'body': <dynamic>[
                  <String, dynamic>{'type': 'ForStatement', 'init': null, 'test': null, 'update': null, 'body': <String, dynamic>{'type': 'BlockStatement', 'body': <dynamic>[]}},
                ],
              },
            },
            'arguments': <dynamic>[],
          },
        },
      ],
    };
    refuel(1000);
    expect(() => runModule(forever, (file) => throw StateError('no module $file')), throwsA(isA<JsThrow>()));
    refuel();
  });
}
