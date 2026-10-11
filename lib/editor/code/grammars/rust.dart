/// Rust: @lezer/rust's grammar (rust.g.dart) with the parts of it that are code, ported from its `src/tokens.js`
/// (MIT, Marijn Haverbeke and others).
library;

import '../lezer/lr.dart';
import 'rust.g.dart';

typedef _T = RustTerms;

const int _b = 98, _e = 101, _f = 102, _r = 114, _upperE = 69, _zero = 48, _dot = 46, _plus = 43, _minus = 45, _hash = 35, _quote = 34, _pipe = 124, _lessThan = 60, _greaterThan = 62;

bool _isNum(int ch) => ch >= 48 && ch <= 57;
bool _isNumOrUnderscore(int ch) => _isNum(ch) || ch == 95;

/// JavaScript's `/\w/`.
bool _isWord(int ch) => ch >= 48 && ch <= 57 || ch >= 65 && ch <= 90 || ch >= 97 && ch <= 122 || ch == 95;

final ExternalTokenizer _literalTokens = ExternalTokenizer((input, stack) {
  if (_isNum(input.next)) {
    var isFloat = false;
    do {
      input.advance();
    } while (_isNumOrUnderscore(input.next));
    if (input.next == _dot) {
      isFloat = true;
      input.advance();
      if (_isNum(input.next)) {
        do {
          input.advance();
        } while (_isNumOrUnderscore(input.next));
      } else if (input.next == _dot || input.next > 0x7f || _isWord(input.next)) {
        return;
      }
    }
    if (input.next == _e || input.next == _upperE) {
      isFloat = true;
      input.advance();
      if (input.next == _plus || input.next == _minus) input.advance();
      if (!_isNumOrUnderscore(input.next)) return;
      do {
        input.advance();
      } while (_isNumOrUnderscore(input.next));
    }
    if (input.next == _f) {
      final after = input.peek(1);
      if (after == _zero + 3 && input.peek(2) == _zero + 2 || after == _zero + 6 && input.peek(2) == _zero + 4) {
        input.advance(3);
        isFloat = true;
      } else {
        return;
      }
    }
    if (isFloat) input.acceptToken(_T.Float);
  } else if (input.next == _b || input.next == _r) {
    if (input.next == _b) input.advance();
    if (input.next != _r) return;
    input.advance();
    var count = 0;
    while (input.next == _hash) {
      count++;
      input.advance();
    }
    if (input.next != _quote) return;
    input.advance();
    content:
    for (;;) {
      if (input.next < 0) return;
      final isQuote = input.next == _quote;
      input.advance();
      if (isQuote) {
        for (var i = 0; i < count; i++) {
          if (input.next != _hash) continue content;
          input.advance();
        }
        input.acceptToken(_T.RawString);
        return;
      }
    }
  }
});

final ExternalTokenizer _closureParam = ExternalTokenizer((input, stack) {
  if (input.next == _pipe) input.acceptToken(_T.closureParamDelim, 1);
});

final ExternalTokenizer _tpDelim = ExternalTokenizer((input, stack) {
  if (input.next == _lessThan) {
    input.acceptToken(_T.tpOpen, 1);
  } else if (input.next == _greaterThan) {
    input.acceptToken(_T.tpClose, 1);
  }
});

/// @lezer/rust's `parser`.
final LRParser rustParser = LRParser.deserialize(rustSpec, tokenizers: <String, Tokenizer>{'closureParam': _closureParam, 'tpDelim': _tpDelim, 'literalTokens': _literalTokens});
