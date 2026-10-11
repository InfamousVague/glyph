/// C and C++: @lezer/cpp's grammar (cpp.g.dart) with the parts of it that are code, ported from its
/// `src/tokens.js` (MIT, Marijn Haverbeke and others). The language pack reads C with the C++ grammar too.
library;

import '../lezer/lr.dart';
import 'cpp.g.dart';

typedef _T = CppTerms;

const int _upperR = 82, _upperL = 76, _u = 117, _upperU = 85, _a = 97, _z = 122, _upperA = 65, _upperZ = 90, _underscore = 95, _zero = 48, _quote = 34, _parenL = 40, _parenR = 41, _space = 32, _greaterThan = 62;

final ExternalTokenizer _rawString = ExternalTokenizer((input, stack) {
  // Raw string literals can start with: R, LR, uR, UR, u8R
  if (input.next == _upperL || input.next == _upperU) {
    input.advance();
  } else if (input.next == _u) {
    input.advance();
    if (input.next == _zero + 8) input.advance();
  }
  if (input.next != _upperR) return;
  input.advance();
  if (input.next != _quote) return;
  input.advance();

  final marker = <int>[];
  while (input.next != _parenL) {
    if (input.next == _space || input.next <= 13 || input.next == _parenR) return;
    marker.add(input.next);
    input.advance();
  }
  input.advance();

  for (;;) {
    if (input.next < 0) return input.acceptToken(_T.RawString);
    if (input.next == _parenR) {
      var match = true;
      for (var i = 0; match && i < marker.length; i++) {
        if (input.peek(i + 1) != marker[i]) match = false;
      }
      if (match && input.peek(marker.length + 1) == _quote) return input.acceptToken(_T.RawString, 2 + marker.length);
    }
    input.advance();
  }
});

final ExternalTokenizer _fallback = ExternalTokenizer((input, stack) {
  if (input.next == _greaterThan) {
    // Provide a template-args-closing token when the next characters are ">>", in which case the regular tokenizer
    // will only see a bit shift op.
    if (input.peek(1) == _greaterThan) input.acceptToken(_T.templateArgsEndFallback, 1);
  } else {
    // Notice all-uppercase identifiers
    var sawLetter = false, i = 0;
    for (;; i++) {
      if (input.next >= _upperA && input.next <= _upperZ) {
        sawLetter = true;
      } else if (input.next >= _a && input.next <= _z) {
        return;
      } else if (input.next != _underscore && !(input.next >= _zero && input.next <= _zero + 9)) {
        break;
      }
      input.advance();
    }
    if (sawLetter && i > 1) input.acceptToken(_T.MacroName);
  }
}, extend: true);

/// @lezer/cpp's `parser`.
final LRParser cppParser = LRParser.deserialize(cppSpec, tokenizers: <String, Tokenizer>{'rawString': _rawString, 'fallback': _fallback});
