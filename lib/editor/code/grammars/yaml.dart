/// YAML: @lezer/yaml's grammar (yaml.g.dart) with the parts of it that are code, ported from its `src/tokens.js`
/// (MIT, Marijn Haverbeke and others): where a block starts and ends by its column, and the scalars.
library;

import '../lezer/lr.dart';
import 'yaml.g.dart';

typedef _T = YamlTerms;

const int _typeTop = 0; // Top document level
const int _typeSeq = 1; // Block sequence
const int _typeMap = 2; // Block mapping
const int _typeFlow = 3; // Inside flow content
const int _typeLit = 4; // Block literal with explicit indentation

class _Context {
  _Context(this.parent, this.depth, this.type) : hash = (parent == null ? 0 : ((parent.hash + parent.hash) << 8).toSigned(32)) + depth + (depth << 4).toSigned(32) + type;

  final _Context? parent;
  final int depth;
  final int type;

  /// As JavaScript works it out: the parent's twice over is what is shifted, and a shift is of thirty-two bits.
  final int hash;

  static final _Context top = _Context(null, -1, _typeTop);
}

int _findColumn(InputStream input, int pos) {
  for (var col = 0, p = pos - input.pos - 1;; p--, col++) {
    final ch = input.peek(p);
    if (_isBreakSpace(ch) || ch == -1) return col;
  }
}

bool _isNonBreakSpace(int ch) => ch == 32 || ch == 9;

bool _isBreakSpace(int ch) => ch == 10 || ch == 13;

bool _isSpace(int ch) => _isNonBreakSpace(ch) || _isBreakSpace(ch);

bool _isSep(int ch) => ch < 0 || _isSpace(ch);

final RegExp _indentDigit = RegExp('[1-9]');

final ContextTracker _indentation = ContextTracker(
  start: _Context.top,
  reduce: (cx, term, stack, input) {
    final context = cx as _Context;
    return context.type == _typeFlow && (term == _T.FlowSequence || term == _T.FlowMapping) ? context.parent : context;
  },
  shift: (cx, term, stack, input) {
    final context = cx as _Context;
    if (term == _T.sequenceStartMark) return _Context(context, _findColumn(input, input.pos), _typeSeq);
    if (term == _T.mapStartMark || term == _T.explicitMapStartMark) return _Context(context, _findColumn(input, input.pos), _typeMap);
    if (term == _T.blockEnd) return context.parent;
    if (term == _T.BracketL || term == _T.BraceL) return _Context(context, 0, _typeFlow);
    if (term == _T.BlockLiteralContent && context.type == _typeLit) return context.parent;
    if (term == _T.BlockLiteralHeader) {
      final indent = _indentDigit.firstMatch(input.read(input.pos, stack.pos));
      if (indent != null) return _Context(context, context.depth + int.parse(indent.group(0)!), _typeLit);
    }
    return context;
  },
  hash: (context) => (context as _Context).hash,
);

bool _three(InputStream input, int ch, [int off = 0]) => input.peek(off) == ch && input.peek(off + 1) == ch && input.peek(off + 2) == ch && _isSep(input.peek(off + 3));

final ExternalTokenizer _newlines = ExternalTokenizer((input, stack) {
  if (input.next == -1 && stack.canShift(_T.eof)) return input.acceptToken(_T.eof);
  final context = stack.context as _Context;
  final prev = input.peek(-1);
  if ((_isBreakSpace(prev) || prev < 0) && context.type != _typeFlow) {
    if (_three(input, 45 /* '-' */ )) {
      if (stack.canShift(_T.blockEnd)) {
        input.acceptToken(_T.blockEnd);
      } else {
        return input.acceptToken(_T.DirectiveEnd, 3);
      }
    }
    if (_three(input, 46 /* '.' */ )) {
      if (stack.canShift(_T.blockEnd)) {
        input.acceptToken(_T.blockEnd);
      } else {
        return input.acceptToken(_T.DocEnd, 3);
      }
    }
    var depth = 0;
    while (input.next == 32 /* ' ' */ ) {
      depth++;
      input.advance();
    }
    if ((depth < context.depth || depth == context.depth && context.type == _typeSeq && (input.next != 45 /* '-' */ || !_isSep(input.peek(1)))) &&
        // Not blank
        input.next != -1 &&
        !_isBreakSpace(input.next) &&
        input.next != 35 /* '#' */ ) {
      input.acceptToken(_T.blockEnd, -depth);
    }
  }
}, contextual: true);

final ExternalTokenizer _blockMark = ExternalTokenizer((input, stack) {
  final context = stack.context as _Context;
  if (context.type == _typeFlow) {
    if (input.next == 63 /* '?' */ ) {
      input.advance();
      if (_isSep(input.next)) input.acceptToken(_T.flowMapMark);
    }
    return;
  }
  if (input.next == 45 /* '-' */ ) {
    input.advance();
    if (_isSep(input.next)) input.acceptToken(context.type == _typeSeq && context.depth == _findColumn(input, input.pos - 1) ? _T.sequenceContinueMark : _T.sequenceStartMark);
  } else if (input.next == 63 /* '?' */ ) {
    input.advance();
    if (_isSep(input.next)) input.acceptToken(context.type == _typeMap && context.depth == _findColumn(input, input.pos - 1) ? _T.explicitMapContinueMark : _T.explicitMapStartMark);
  } else {
    final start = input.pos;
    // Scan over a potential key to see if it is followed by a colon.
    for (;;) {
      if (_isNonBreakSpace(input.next)) {
        if (input.pos == start) return;
        input.advance();
      } else if (input.next == 33 /* '!' */ ) {
        _readTag(input);
      } else if (input.next == 38 /* '&' */ ) {
        _readAnchor(input);
      } else if (input.next == 42 /* '*' */ ) {
        _readAnchor(input);
        break;
      } else if (input.next == 39 /* "'" */ || input.next == 34 /* '"' */ ) {
        if (_readQuoted(input, true)) break;
        return;
      } else if (input.next == 91 /* '[' */ || input.next == 123 /* '{' */ ) {
        if (!_scanBrackets(input)) return;
        break;
      } else {
        _readPlain(input, true, false, 0);
        break;
      }
    }
    while (_isNonBreakSpace(input.next)) {
      input.advance();
    }
    if (input.next == 58 /* ':' */ ) {
      if (input.pos == start && stack.canShift(_T.Colon)) return;
      final after = input.peek(1);
      if (_isSep(after)) input.acceptTokenTo(context.type == _typeMap && context.depth == _findColumn(input, start) ? _T.mapContinueMark : _T.mapStartMark, start);
    }
  }
}, contextual: true);

bool _uriChar(int ch) => ch > 32 && ch < 127 && ch != 34 && ch != 37 && ch != 44 && ch != 60 && ch != 62 && ch != 92 && ch != 94 && ch != 96 && ch != 123 && ch != 124 && ch != 125;

bool _hexChar(int ch) => ch >= 48 && ch <= 57 || ch >= 97 && ch <= 102 || ch >= 65 && ch <= 70;

bool _readUriChar(InputStream input, bool quoted) {
  if (input.next == 37 /* '%' */ ) {
    input.advance();
    if (_hexChar(input.next)) input.advance();
    if (_hexChar(input.next)) input.advance();
    return true;
  } else if (_uriChar(input.next) || quoted && input.next == 44 /* ',' */ ) {
    input.advance();
    return true;
  }
  return false;
}

void _readTag(InputStream input) {
  input.advance(); // !
  if (input.next == 60 /* '<' */ ) {
    input.advance();
    for (;;) {
      if (!_readUriChar(input, true)) {
        if (input.next == 62 /* '>' */ ) input.advance();
        break;
      }
    }
  } else {
    while (_readUriChar(input, false)) {}
  }
}

void _readAnchor(InputStream input) {
  input.advance();
  while (!_isSep(input.next) && _charTag(input.next) != _f) {
    input.advance();
  }
}

bool _readQuoted(InputStream input, bool scan) {
  final quote = input.next, start = input.pos;
  var lineBreak = false;
  input.advance();
  for (;;) {
    final ch = input.next;
    if (ch < 0) break;
    input.advance();
    if (ch == quote) {
      if (ch == 39 /* "'" */ ) {
        if (input.next == 39) {
          input.advance();
        } else {
          break;
        }
      } else {
        break;
      }
    } else if (ch == 92 /* "\\" */ && quote == 34 /* '"' */ ) {
      if (input.next >= 0) input.advance();
    } else if (_isBreakSpace(ch)) {
      if (scan) return false;
      lineBreak = true;
    } else if (scan && input.pos >= start + 1024) {
      return false;
    }
  }
  return !lineBreak;
}

bool _scanBrackets(InputStream input) {
  final stack = <int>[], end = input.pos + 1024;
  for (;;) {
    if (input.next == 91 /* '[' */ || input.next == 123 /* '{' */ ) {
      stack.add(input.next);
      input.advance();
    } else if (input.next == 39 /* "'" */ || input.next == 34 /* '"' */ ) {
      if (!_readQuoted(input, true)) return false;
    } else if (input.next == 93 /* ']' */ || input.next == 125 /* '}' */ ) {
      if (stack.isEmpty || stack.last != input.next - 2) return false;
      stack.removeLast();
      input.advance();
      if (stack.isEmpty) return true;
    } else if (input.next < 0 || input.pos > end || _isBreakSpace(input.next)) {
      return false;
    } else {
      input.advance();
    }
  }
}

// "Safe char" info for char codes 33 to 125. s: safe, i: indicator, f: flow indicator
const String _charTable = 'iiisiiissisfissssssssssssisssiiissssssssssssssssssssssssssfsfssissssssssssssssssssssssssssfif';

const int _u = 117, _s = 115, _f = 102;

/// `u` unsafe, `s` safe, `i` an indicator, `f` a flow indicator.
int _charTag(int ch) {
  if (ch < 33) return _u;
  if (ch > 125) return _s;
  return _charTable.codeUnitAt(ch - 33);
}

bool _isSafe(int ch, bool inFlow) {
  final tag = _charTag(ch);
  return tag != _u && !(inFlow && tag == _f);
}

bool _readPlain(InputStream input, bool scan, bool inFlow, int indent) {
  if (_charTag(input.next) == _s || (input.next == 63 /* '?' */ || input.next == 58 /* ':' */ || input.next == 45 /* '-' */ ) && _isSafe(input.peek(1), inFlow)) {
    input.advance();
  } else {
    return false;
  }
  final start = input.pos;
  for (;;) {
    var next = input.next, off = 0, lineIndent = indent + 1;
    while (_isSpace(next)) {
      if (_isBreakSpace(next)) {
        if (scan) return false;
        lineIndent = 0;
      } else {
        lineIndent++;
      }
      next = input.peek(++off);
    }
    final safe =
        next >= 0 &&
        (next == 58 /* ':' */
            ? _isSafe(input.peek(off + 1), inFlow)
            : next == 35 /* '#' */
            ? input.peek(off - 1) != 32 /* ' ' */
            : _isSafe(next, inFlow));
    if (!safe || !inFlow && lineIndent <= indent || lineIndent == 0 && !inFlow && (_three(input, 45, off) || _three(input, 46, off))) break;
    if (scan && _charTag(next) == _f) return false;
    for (var i = off; i >= 0; i--) {
      input.advance();
    }
    if (scan && input.pos > start + 1024) return false;
  }
  return true;
}

final ExternalTokenizer _literals = ExternalTokenizer((input, stack) {
  final context = stack.context as _Context;
  if (input.next == 33 /* '!' */ ) {
    _readTag(input);
    input.acceptToken(_T.Tag);
  } else if (input.next == 38 /* '&' */ || input.next == 42 /* '*' */ ) {
    final token = input.next == 38 ? _T.Anchor : _T.Alias;
    _readAnchor(input);
    input.acceptToken(token);
  } else if (input.next == 39 /* "'" */ || input.next == 34 /* '"' */ ) {
    _readQuoted(input, false);
    input.acceptToken(_T.QuotedLiteral);
  } else if (_readPlain(input, false, context.type == _typeFlow, context.depth)) {
    input.acceptToken(_T.Literal);
  }
});

final ExternalTokenizer _blockLiteral = ExternalTokenizer((input, stack) {
  final context = stack.context as _Context;
  var indent = context.type == _typeLit ? context.depth : -1, upto = input.pos;
  scan:
  for (;;) {
    var depth = 0, next = input.next;
    while (next == 32 /* ' ' */ ) {
      next = input.peek(++depth);
    }
    if (depth == 0 && (_three(input, 45, depth) || _three(input, 46, depth))) break;
    if (!_isBreakSpace(next)) {
      if (indent < 0) indent = context.depth + 1 > depth ? context.depth + 1 : depth;
      if (depth < indent) break;
    }
    for (;;) {
      if (input.next < 0) break scan;
      final isBreak = _isBreakSpace(input.next);
      input.advance();
      if (isBreak) continue scan;
      upto = input.pos;
    }
  }
  input.acceptTokenTo(_T.BlockLiteralContent, upto);
});

/// @lezer/yaml's `parser`.
final LRParser yamlParser = LRParser.deserialize(
  yamlSpec,
  tokenizers: <String, Tokenizer>{'newlines': _newlines, 'blockMark': _blockMark, 'literals': _literals, 'blockLiteral': _blockLiteral},
  context: _indentation,
);
