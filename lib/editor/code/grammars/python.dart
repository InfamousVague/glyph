/// Python: @lezer/python's grammar (python.g.dart) with the parts of it that are code, ported from its
/// `src/tokens.js` (MIT, Marijn Haverbeke and others): where a line's indentation opens and closes a block, where
/// a line break ends a statement, and the pieces of a string.
library;

import '../lezer/lr.dart';
import 'python.g.dart';

typedef _T = PythonTerms;

const int _newline = 10, _carriageReturn = 13, _space = 32, _tab = 9, _hash = 35, _parenOpen = 40, _dot = 46, _braceOpen = 123, _braceClose = 125, _singleQuote = 39, _doubleQuote = 34, _backslash = 92;
const int _letterO = 111, _letterX = 120, _letterN = 78, _letterU = 117, _upperU = 85;

const Set<int> _bracketed = <int>{
  _T.ParenthesizedExpression,
  _T.TupleExpression,
  _T.ComprehensionExpression,
  _T.importList,
  _T.ArgList,
  _T.ParamList,
  _T.ArrayExpression,
  _T.ArrayComprehensionExpression,
  _T.subscript,
  _T.SetExpression,
  _T.SetComprehensionExpression,
  _T.FormatString,
  _T.FormatReplacement,
  _T.nestedFormatReplacement,
  _T.DictionaryExpression,
  _T.DictionaryComprehensionExpression,
  _T.SequencePattern,
  _T.MappingPattern,
  _T.PatternArgList,
  _T.TypeParamList,
};

bool _isLineBreak(int ch) => ch == _newline || ch == _carriageReturn;

bool _isHex(int ch) => ch >= 48 && ch <= 57 || ch >= 65 && ch <= 70 || ch >= 97 && ch <= 102;

/// JavaScript's `/\w/`.
bool _isWord(int ch) => ch >= 48 && ch <= 57 || ch >= 65 && ch <= 90 || ch >= 97 && ch <= 122 || ch == 95;

// Flags used in Context objects
const int _cxBracketed = 1, _cxString = 2, _cxDoubleQuote = 4, _cxLong = 8, _cxRaw = 16, _cxFormat = 32;

/// Where the parse is: inside which brackets and strings, at what indentation.
class _Context {
  _Context(this.parent, this.indent, this.flags) : hash = _hashOf(parent, indent, flags);

  final _Context? parent;
  final int indent;
  final int flags;
  final int hash;

  /// `(parent ? parent.hash + parent.hash << 8 : 0) + indent + (indent << 4) + flags + (flags << 6)`, as
  /// JavaScript works it out: the sum is shifted, and a shift is of thirty-two bits.
  static int _hashOf(_Context? parent, int indent, int flags) {
    final up = parent == null ? 0 : ((parent.hash + parent.hash) << 8).toSigned(32);
    return up + indent + (indent << 4).toSigned(32) + flags + (flags << 6);
  }
}

final _Context _topIndent = _Context(null, 0, 0);

int _countIndent(String space) {
  var depth = 0;
  for (var i = 0; i < space.length; i++) {
    depth += space.codeUnitAt(i) == _tab ? 8 - (depth % 8) : 1;
  }
  return depth;
}

const Map<int, int> _stringFlags = <int, int>{
  _T.stringStart: 0 | _cxString,
  _T.stringStartD: _cxDoubleQuote | _cxString,
  _T.stringStartL: _cxLong | _cxString,
  _T.stringStartLD: _cxLong | _cxDoubleQuote | _cxString,
  _T.stringStartR: _cxRaw | _cxString,
  _T.stringStartRD: _cxRaw | _cxDoubleQuote | _cxString,
  _T.stringStartRL: _cxRaw | _cxLong | _cxString,
  _T.stringStartRLD: _cxRaw | _cxLong | _cxDoubleQuote | _cxString,
  _T.stringStartF: _cxFormat | _cxString,
  _T.stringStartFD: _cxFormat | _cxDoubleQuote | _cxString,
  _T.stringStartFL: _cxFormat | _cxLong | _cxString,
  _T.stringStartFLD: _cxFormat | _cxLong | _cxDoubleQuote | _cxString,
  _T.stringStartFR: _cxFormat | _cxRaw | _cxString,
  _T.stringStartFRD: _cxFormat | _cxRaw | _cxDoubleQuote | _cxString,
  _T.stringStartFRL: _cxFormat | _cxRaw | _cxLong | _cxString,
  _T.stringStartFRLD: _cxFormat | _cxRaw | _cxLong | _cxDoubleQuote | _cxString,
};

final ExternalTokenizer _newlines = ExternalTokenizer((input, stack) {
  final context = stack.context as _Context;
  if (input.next < 0) {
    input.acceptToken(_T.eof);
  } else if ((context.flags & _cxBracketed) != 0) {
    if (_isLineBreak(input.next)) input.acceptToken(_T.newlineBracketed, 1);
  } else {
    final prev = input.peek(-1);
    if ((prev < 0 || _isLineBreak(prev)) && stack.canShift(_T.blankLineStart)) {
      var spaces = 0;
      while (input.next == _space || input.next == _tab) {
        input.advance();
        spaces++;
      }
      if (input.next == _newline || input.next == _carriageReturn || input.next == _hash) input.acceptToken(_T.blankLineStart, -spaces);
    } else if (_isLineBreak(input.next)) {
      input.acceptToken(_T.newline$1, 1);
    }
  }
}, contextual: true);

final ExternalTokenizer _indentation = ExternalTokenizer((input, stack) {
  final context = stack.context as _Context;
  if (context.flags != 0) return;
  final prev = input.peek(-1);
  if (prev == _newline || prev == _carriageReturn) {
    var depth = 0, chars = 0;
    for (;;) {
      if (input.next == _space) {
        depth++;
      } else if (input.next == _tab) {
        depth += 8 - (depth % 8);
      } else {
        break;
      }
      input.advance();
      chars++;
    }
    if (depth != context.indent && input.next != _newline && input.next != _carriageReturn && input.next != _hash) {
      if (depth < context.indent) {
        input.acceptToken(_T.dedent, -chars);
      } else {
        input.acceptToken(_T.indent);
      }
    }
  }
});

final ContextTracker _trackIndent = ContextTracker(
  start: _topIndent,
  reduce: (cx, term, stack, input) {
    final context = cx as _Context;
    if ((context.flags & _cxBracketed) != 0 && _bracketed.contains(term) || (term == _T.String$1 || term == _T.FormatString) && (context.flags & _cxString) != 0) return context.parent;
    return context;
  },
  shift: (cx, term, stack, input) {
    final context = cx as _Context;
    if (term == _T.indent) return _Context(context, _countIndent(input.read(input.pos, stack.pos)), 0);
    if (term == _T.dedent) return context.parent;
    if (term == _T.ParenL || term == _T.BracketL || term == _T.BraceL || term == _T.replacementStart) return _Context(context, 0, _cxBracketed);
    final string = _stringFlags[term];
    if (string != null) return _Context(context, 0, string | (context.flags & _cxBracketed));
    return context;
  },
  hash: (context) => (context as _Context).hash,
);

const String _print = 'print';

final ExternalTokenizer _legacyPrint = ExternalTokenizer((input, stack) {
  for (var i = 0; i < 5; i++) {
    if (input.next != _print.codeUnitAt(i)) return;
    input.advance();
  }
  if (_isWord(input.next)) return;
  for (var off = 0;; off++) {
    final next = input.peek(off);
    if (next == _space || next == _tab) continue;
    if (next != _parenOpen && next != _dot && next != _newline && next != _carriageReturn && next != _hash) input.acceptToken(_T.printKeyword);
    return;
  }
});

final ExternalTokenizer _strings = ExternalTokenizer((input, stack) {
  final flags = (stack.context as _Context).flags;
  final quote = (flags & _cxDoubleQuote) != 0 ? _doubleQuote : _singleQuote;
  final long = (flags & _cxLong) > 0;
  final escapes = (flags & _cxRaw) == 0;
  final format = (flags & _cxFormat) > 0;

  final start = input.pos;
  for (;;) {
    if (input.next < 0) {
      break;
    } else if (format && input.next == _braceOpen) {
      if (input.peek(1) == _braceOpen) {
        input.advance(2);
      } else {
        if (input.pos == start) {
          input.acceptToken(_T.replacementStart, 1);
          return;
        }
        break;
      }
    } else if (escapes && input.next == _backslash) {
      if (input.pos == start) {
        input.advance();
        final escaped = input.next;
        if (escaped >= 0) {
          input.advance();
          _skipEscape(input, escaped);
        }
        input.acceptToken(_T.Escape);
        return;
      }
      break;
    } else if (input.next == _backslash && !escapes && input.peek(1) > -1) {
      // Raw strings still ignore escaped quotes, weirdly.
      input.advance(2);
    } else if (input.next == quote && (!long || input.peek(1) == quote && input.peek(2) == quote)) {
      if (input.pos == start) {
        input.acceptToken(_T.stringEnd, long ? 3 : 1);
        return;
      }
      break;
    } else if (input.next == _newline) {
      if (long) {
        input.advance();
      } else if (input.pos == start) {
        input.acceptToken(_T.stringEnd);
        return;
      }
      break;
    } else {
      input.advance();
    }
  }
  if (input.pos > start) input.acceptToken(_T.stringContent);
});

void _skipEscape(InputStream input, int ch) {
  if (ch == _letterO) {
    for (var i = 0; i < 2 && input.next >= 48 && input.next <= 55; i++) {
      input.advance();
    }
  } else if (ch == _letterX) {
    for (var i = 0; i < 2 && _isHex(input.next); i++) {
      input.advance();
    }
  } else if (ch == _letterU) {
    for (var i = 0; i < 4 && _isHex(input.next); i++) {
      input.advance();
    }
  } else if (ch == _upperU) {
    for (var i = 0; i < 8 && _isHex(input.next); i++) {
      input.advance();
    }
  } else if (ch == _letterN) {
    if (input.next == _braceOpen) {
      input.advance();
      while (input.next >= 0 && input.next != _braceClose && input.next != _singleQuote && input.next != _doubleQuote && input.next != _newline) {
        input.advance();
      }
      if (input.next == _braceClose) input.advance();
    }
  }
}

/// @lezer/python's `parser`.
final LRParser pythonParser = LRParser.deserialize(
  pythonSpec,
  tokenizers: <String, Tokenizer>{'legacyPrint': _legacyPrint, 'indentation': _indentation, 'newlines': _newlines, 'strings': _strings},
  context: _trackIndent,
);
