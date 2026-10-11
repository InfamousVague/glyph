/// CSS: @lezer/css's grammar (css.g.dart) with the parts of it that are code, ported from its `src/tokens.js`
/// (MIT, Marijn Haverbeke and others).
library;

import '../lezer/lr.dart';
import 'css.g.dart';

typedef _T = CssTerms;

/* Hand-written tokenizers for CSS tokens that can't be expressed by Lezer's built-in tokenizer. */

const List<int> _space = <int>[9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288];
const int _colon = 58, _parenL = 40, _underscore = 95, _bracketL = 91, _dash = 45, _period = 46, _hash = 35, _percent = 37, _ampersand = 38, _backslash = 92, _newline = 10, _asterisk = 42;

bool _isAlpha(int ch) => ch >= 65 && ch <= 90 || ch >= 97 && ch <= 122 || ch >= 161;

bool _isDigit(int ch) => ch >= 48 && ch <= 57;

bool _isHex(int ch) => _isDigit(ch) || ch >= 97 && ch <= 102 || ch >= 65 && ch <= 70;

void Function(InputStream input, Stack stack) _identifierTokens(int id, int varName, int callee) => (input, stack) {
  for (var inside = false, dashes = 0, i = 0;; i++) {
    final next = input.next;
    if (_isAlpha(next) || next == _dash || next == _underscore || (inside && _isDigit(next))) {
      if (!inside && (next != _dash || i > 0)) inside = true;
      if (dashes == i && next == _dash) dashes++;
      input.advance();
    } else if (next == _backslash && input.peek(1) != _newline) {
      input.advance();
      if (_isHex(input.next)) {
        do {
          input.advance();
        } while (_isHex(input.next));
        if (input.next == 32) input.advance();
      } else if (input.next > -1) {
        input.advance();
      }
      inside = true;
    } else {
      if (inside) input.acceptToken(dashes == 2 && stack.canShift(_T.VariableName) ? varName : next == _parenL ? callee : id);
      break;
    }
  }
};

final ExternalTokenizer _identifiers = ExternalTokenizer(_identifierTokens(_T.identifier, _T.VariableName, _T.callee), contextual: true);
final ExternalTokenizer _queryIdentifiers = ExternalTokenizer(_identifierTokens(_T.queryIdentifier, _T.queryVariableName, _T.QueryCallee), contextual: true);

final ExternalTokenizer _descendant = ExternalTokenizer((input, stack) {
  if (_space.contains(input.peek(-1))) {
    final next = input.next;
    if (_isAlpha(next) ||
        next == _underscore ||
        next == _hash ||
        next == _period ||
        next == _asterisk ||
        next == _bracketL ||
        next == _colon && _isAlpha(input.peek(1)) ||
        next == _dash ||
        next == _ampersand) {
      input.acceptToken(_T.descendantOp);
    }
  }
});

final ExternalTokenizer _unitToken = ExternalTokenizer((input, stack) {
  if (!_space.contains(input.peek(-1))) {
    final next = input.next;
    if (next == _percent) {
      input.advance();
      input.acceptToken(_T.Unit);
    }
    if (_isAlpha(next)) {
      do {
        input.advance();
      } while (_isAlpha(input.next) || _isDigit(input.next));
      input.acceptToken(_T.Unit);
    }
  }
});

/// @lezer/css's `parser`: a stylesheet.
final LRParser cssParser = LRParser.deserialize(
  cssSpec,
  tokenizers: <String, Tokenizer>{'descendant': _descendant, 'unitToken': _unitToken, 'identifiers': _identifiers, 'queryIdentifiers': _queryIdentifiers},
);

/// The declarations of a `style="…"` attribute (`parser.configure({top: 'Styles'})`, @codemirror/lang-html).
final LRParser cssStylesParser = cssParser.configure(top: 'Styles');
