import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/text.dart';

/// The small things done to a string (lib/core/text.dart), case for case with the web's `core/text.test.ts`.
void main() {
  group('the first letter', () {
    test('is capitalised and nothing after it is touched', () {
      expect(capitalise('milk'), 'Milk');
      expect(capitalise('iPhone case'), 'IPhone case');
      expect(capitalise('the API docs'), 'The API docs');
    });

    test('is lowered for a command read after "Hey Ghost,", and nothing after it is touched', () {
      expect(lowerFirst('Add milk to Shopping'), 'add milk to Shopping');
      expect(lowerFirst('API key'), 'aPI key');
    });

    test('leaves an empty string empty, and a string that has no case as it was', () {
      expect(capitalise(''), '');
      expect(lowerFirst(''), '');
      expect(capitalise('3 eggs'), '3 eggs');
    });
  });

  group('words inside a pattern', () {
    test('match themselves, however much of them is RegExp syntax', () {
      const said = r'C++ (the book) costs $30.00? [maybe] {or} a|b ^ \ *';
      expect(RegExp('^${escapeRegExp(said)}\$').hasMatch(said), isTrue);
      expect(RegExp(escapeRegExp('a.c')).hasMatch('abc'), isFalse);
    });

    test('leaves words with nothing to escape as they were', () {
      expect(escapeRegExp('status'), 'status');
    });
  });
}
