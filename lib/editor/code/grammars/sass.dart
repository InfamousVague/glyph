/// SCSS and Sass: @lezer/sass's grammar (sass.g.dart) with the parts of it that are code, ported from its
/// `src/tokens.js` (MIT, Marijn Haverbeke and others). One grammar reads both: Sass, written by its indentation,
/// is the dialect `indented` of it (`sass({indented: true})`, @codemirror/lang-sass).
library;

import '../lezer/lr.dart';
import 'sass.g.dart';

typedef _T = SassTerms;

/* Hand-written tokenizers for CSS tokens that can't be expressed by Lezer's built-in tokenizer. */

const List<int> _space = <int>[9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288];
const int _colon = 58, _parenL = 40, _underscore = 95, _bracketL = 91, _dash = 45, _period = 46, _hash = 35, _percent = 37, _braceL = 123, _braceR = 125, _slash = 47, _asterisk = 42;
const int _newlineChar = 10, _equals = 61, _plus = 43, _and = 38;

bool _isAlpha(int ch) => ch >= 65 && ch <= 90 || ch >= 97 && ch <= 122 || ch >= 161;

bool _isDigit(int ch) => ch >= 48 && ch <= 57;

bool _startOfComment(InputStream input) {
  if (input.next != _slash) return false;
  final next = input.peek(1);
  return next == _slash || next == _asterisk;
}

final ExternalTokenizer _spaces = ExternalTokenizer((input, stack) {
  if (stack.dialectEnabled(_T.Dialect_indented)) {
    if (input.next < 0 && stack.canShift(_T.eof)) {
      input.acceptToken(_T.eof);
      return;
    }
    final prev = input.peek(-1);
    if ((prev == _newlineChar || prev < 0) && stack.canShift(_T.blankLineStart)) {
      var spaces = 0;
      while (input.next != _newlineChar && _space.contains(input.next)) {
        input.advance();
        spaces++;
      }
      if (input.next == _newlineChar || _startOfComment(input)) {
        input.acceptToken(_T.blankLineStart, -spaces);
      } else if (spaces != 0) {
        input.acceptToken(_T.whitespace);
      }
    } else if (input.next == _newlineChar) {
      input.acceptToken(_T.newline, 1);
    } else if (_space.contains(input.next)) {
      input.advance();
      while (input.next != _newlineChar && _space.contains(input.next)) {
        input.advance();
      }
      input.acceptToken(_T.whitespace);
    }
  } else {
    var length = 0;
    while (_space.contains(input.next)) {
      input.advance();
      length++;
    }
    if (length != 0) input.acceptToken(_T.whitespace);
  }
}, contextual: true);

final ExternalTokenizer _comments = ExternalTokenizer((input, stack) {
  if (!_startOfComment(input)) return;
  input.advance();
  if (stack.dialectEnabled(_T.Dialect_indented)) {
    var indentedComment = -1;
    for (var off = 1;; off++) {
      final prev = input.peek(-off - 1);
      if (prev == _newlineChar || prev < 0) {
        indentedComment = off + 1;
        break;
      } else if (!_space.contains(prev)) {
        break;
      }
    }
    if (indentedComment > -1) {
      // Weird indented-style comment
      final block = input.next == _asterisk;
      var end = 0;
      input.advance();
      while (input.next >= 0) {
        if (input.next == _newlineChar) {
          input.advance();
          var indented = 0;
          while (input.next != _newlineChar && _space.contains(input.next)) {
            indented++;
            input.advance();
          }
          if (indented < indentedComment) {
            end = -indented - 1;
            break;
          }
        } else if (block && input.next == _asterisk && input.peek(1) == _slash) {
          end = 2;
          break;
        } else {
          input.advance();
        }
      }
      input.acceptToken(block ? _T.Comment : _T.LineComment, end);
      return;
    }
  }
  if (input.next == _slash) {
    while (input.next != _newlineChar && input.next >= 0) {
      input.advance();
    }
    input.acceptToken(_T.LineComment);
  } else {
    input.advance();
    while (input.next >= 0) {
      final next = input.next;
      input.advance();
      if (next == _asterisk && input.next == _slash) {
        input.advance();
        break;
      }
    }
    input.acceptToken(_T.Comment);
  }
});

final ExternalTokenizer _indentedMixins = ExternalTokenizer((input, stack) {
  if ((input.next == _plus || input.next == _equals) && stack.dialectEnabled(_T.Dialect_indented)) {
    input.acceptToken(input.next == _equals ? _T.IndentedMixin : _T.IndentedInclude, 1);
  }
});

final ExternalTokenizer _indentation = ExternalTokenizer((input, stack) {
  if (!stack.dialectEnabled(_T.Dialect_indented)) return;
  final cDepth = (stack.context as _IndentLevel).depth;
  if (input.next < 0 && cDepth != 0) {
    input.acceptToken(_T.dedent);
    return;
  }
  final prev = input.peek(-1);
  if (prev == _newlineChar) {
    var depth = 0;
    while (input.next != _newlineChar && _space.contains(input.next)) {
      input.advance();
      depth++;
    }
    if (depth != cDepth && input.next != _newlineChar && !_startOfComment(input)) {
      if (depth < cDepth) {
        input.acceptToken(_T.dedent, -depth);
      } else {
        input.acceptToken(_T.indent);
      }
    }
  }
});

final ExternalTokenizer _identifiers = ExternalTokenizer((input, stack) {
  for (var inside = false, dashes = 0, i = 0;; i++) {
    final next = input.next;
    if (_isAlpha(next) || next == _dash || next == _underscore || (inside && _isDigit(next))) {
      if (!inside && (next != _dash || i > 0)) inside = true;
      if (dashes == i && next == _dash) dashes++;
      input.advance();
    } else if (next == _hash && input.peek(1) == _braceL) {
      input.acceptToken(_T.InterpolationStart, 2);
      break;
    } else {
      if (inside) {
        input.acceptToken(
          dashes == 2 && stack.canShift(_T.VariableName)
              ? _T.VariableName
              : stack.canShift(_T.queryIdentifier)
              ? _T.queryIdentifier
              : next == _parenL
              ? _T.callee
              : _T.identifier,
        );
      }
      break;
    }
  }
});

final ExternalTokenizer _interpolationEnd = ExternalTokenizer((input, stack) {
  if (input.next == _braceR) {
    input.advance();
    while (_isAlpha(input.next) || input.next == _dash || input.next == _underscore || _isDigit(input.next)) {
      input.advance();
    }
    if (input.next == _hash && input.peek(1) == _braceL) {
      input.acceptToken(_T.InterpolationContinue, 2);
    } else {
      input.acceptToken(_T.InterpolationEnd);
    }
  }
});

final ExternalTokenizer _descendant = ExternalTokenizer((input, stack) {
  if (_space.contains(input.peek(-1))) {
    final next = input.next;
    if (_isAlpha(next) ||
        next == _underscore ||
        next == _hash ||
        next == _period ||
        next == _bracketL ||
        next == _colon && _isAlpha(input.peek(1)) ||
        next == _dash ||
        next == _and ||
        next == _asterisk) {
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

class _IndentLevel {
  _IndentLevel(this.parent, this.depth) : hash = (parent == null ? 0 : ((parent.hash + parent.hash) << 8).toSigned(32)) + depth + (depth << 4).toSigned(32);

  final _IndentLevel? parent;
  final int depth;

  /// As JavaScript works it out: the parent's twice over is what is shifted, and a shift is of thirty-two bits.
  final int hash;
}

final _IndentLevel _topIndent = _IndentLevel(null, 0);

final ContextTracker _trackIndent = ContextTracker(
  start: _topIndent,
  shift: (cx, term, stack, input) {
    final context = cx as _IndentLevel;
    if (term == _T.indent) return _IndentLevel(context, stack.pos - input.pos);
    if (term == _T.dedent) return context.parent;
    return context;
  },
  hash: (context) => (context as _IndentLevel).hash,
);

/// @lezer/sass's `parser`: SCSS.
final LRParser scssParser = LRParser.deserialize(
  sassSpec,
  tokenizers: <String, Tokenizer>{
    'indentation': _indentation,
    'descendant': _descendant,
    'interpolationEnd': _interpolationEnd,
    'unitToken': _unitToken,
    'identifiers': _identifiers,
    'spaces': _spaces,
    'comments': _comments,
    'indentedMixins': _indentedMixins,
  },
  context: _trackIndent,
);

/// `indentedSassLanguage`: Sass, written by its indentation.
final LRParser sassParser = scssParser.configure(dialect: 'indented');
