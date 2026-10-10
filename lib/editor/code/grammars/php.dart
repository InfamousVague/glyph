/// PHP: @lezer/php's grammar (php.g.dart) with the parts of it that are code, ported from its `src/tokens.js`
/// (MIT, Marijn Haverbeke and others): its keywords, which are words whatever their case, casts, heredocs, and the
/// pieces of a string with variables in it. What is outside `<?php … ?>` is HTML's: `../nesting.dart`.
library;

import '../lezer/lr.dart';
import 'php.g.dart';

typedef _T = PhpTerms;

const Map<String, int> _keywordMap = <String, int>{
  'abstract': _T.abstract_,
  'and': _T.and,
  'array': _T.array,
  'as': _T.as_,
  'true': _T.Boolean,
  'false': _T.Boolean,
  'break': _T.break_,
  'case': _T.case_,
  'catch': _T.catch_,
  'clone': _T.clone,
  'const': _T.const_,
  'continue': _T.continue_,
  'declare': _T.declare,
  'default': _T.default_,
  'do': _T.do_,
  'echo': _T.echo,
  'else': _T.else_,
  'elseif': _T.elseif,
  'enddeclare': _T.enddeclare,
  'endfor': _T.endfor,
  'endforeach': _T.endforeach,
  'endif': _T.endif,
  'endswitch': _T.endswitch,
  'endwhile': _T.endwhile,
  'enum': _T.enum_,
  'extends': _T.extends_,
  'final': _T.final_,
  'finally': _T.finally_,
  'fn': _T.fn,
  'for': _T.for_,
  'foreach': _T.foreach,
  'from': _T.from,
  'function': _T.function,
  'global': _T.global,
  'goto': _T.goto,
  'if': _T.if_,
  'implements': _T.implements_,
  'include': _T.include,
  'include_once': _T.include_once,
  'instanceof': _T.instanceof,
  'insteadof': _T.insteadof,
  'interface': _T.interface_,
  'list': _T.list,
  'match': _T.match,
  'namespace': _T.namespace,
  'new': _T.new_,
  'null': _T.null_,
  'or': _T.or,
  'print': _T.print,
  'readonly': _T.readonly,
  'require': _T.require,
  'require_once': _T.require_once,
  'return': _T.return_,
  'switch': _T.switch_,
  'throw': _T.throw_,
  'trait': _T.trait,
  'try': _T.try_,
  'unset': _T.unset,
  'use': _T.use,
  'var': _T.var_,
  'public': _T.Visibility,
  'private': _T.Visibility,
  'protected': _T.Visibility,
  'while': _T.while_,
  'xor': _T.xor,
  'yield': _T.yield_,
};

int _keywords(String name, Stack stack) => _keywordMap[name.toLowerCase()] ?? -1;

bool _isSpace(int ch) => ch == 9 || ch == 10 || ch == 13 || ch == 32;

bool _isASCIILetter(int ch) => ch >= 97 && ch <= 122 || ch >= 65 && ch <= 90;

bool _isIdentifierStart(int ch) => ch == 95 || ch >= 0x80 || _isASCIILetter(ch);

bool _isHex(int ch) => ch >= 48 && ch <= 55 || ch >= 97 && ch <= 102 || ch >= 65 && ch <= 70; /* 0-9, a-f, A-F */

const Set<String> _castTypes = <String>{'int', 'integer', 'bool', 'boolean', 'float', 'double', 'real', 'string', 'array', 'object', 'unset'};

final ExternalTokenizer _expression = ExternalTokenizer((input, stack) {
  if (input.next == 40 /* '(' */ ) {
    input.advance();
    var peek = 0;
    while (_isSpace(input.peek(peek))) {
      peek++;
    }
    final name = StringBuffer();
    for (;;) {
      final next = input.peek(peek);
      if (!_isASCIILetter(next)) break;
      name.writeCharCode(next);
      peek++;
    }
    while (_isSpace(input.peek(peek))) {
      peek++;
    }
    if (input.peek(peek) == 41 /* ')' */ && _castTypes.contains(name.toString().toLowerCase())) input.acceptToken(_T.castOpen);
  } else if (input.next == 60 /* '<' */ && input.peek(1) == 60 && input.peek(2) == 60) {
    for (var i = 0; i < 3; i++) {
      input.advance();
    }
    while (input.next == 32 /* ' ' */ || input.next == 9 /* '\t' */ ) {
      input.advance();
    }
    final quoted = input.next == 39; /* "'" */
    if (quoted) input.advance();
    if (!_isIdentifierStart(input.next)) return;
    final tag = <int>[input.next];
    for (;;) {
      input.advance();
      if (!_isIdentifierStart(input.next) && !(input.next >= 48 && input.next <= 55) /* 0-9 */ ) break;
      tag.add(input.next);
    }
    if (quoted) {
      if (input.next != 39) return;
      input.advance();
    }
    if (input.next != 10 /* '\n' */ && input.next != 13 /* '\r' */ ) return;
    for (;;) {
      final lineStart = input.next == 10 || input.next == 13;
      input.advance();
      if (input.next < 0) return;
      if (lineStart) {
        while (input.next == 32 /* ' ' */ || input.next == 9 /* '\t' */ ) {
          input.advance();
        }
        var match = true;
        for (var i = 0; i < tag.length; i++) {
          if (input.next != tag[i]) {
            match = false;
            break;
          }
          input.advance();
        }
        if (match) return input.acceptToken(_T.HeredocString);
      }
    }
  }
});

final ExternalTokenizer _eofToken = ExternalTokenizer((input, stack) {
  if (input.next < 0) input.acceptToken(_T.eof);
});

final ExternalTokenizer _semicolon = ExternalTokenizer((input, stack) {
  if (input.next == 63 /* '?' */ && stack.canShift(_T.automaticSemicolon) && input.peek(1) == 62 /* '>' */ ) input.acceptToken(_T.automaticSemicolon);
});

int _scanEscape(InputStream input) {
  final after = input.peek(1);
  if (after == 110 /* 'n' */ ||
      after == 114 /* 'r' */ ||
      after == 116 /* 't' */ ||
      after == 118 /* 'v' */ ||
      after == 101 /* 'e' */ ||
      after == 102 /* 'f' */ ||
      after == 92 /* '\\' */ ||
      after == 36 /* '"' */ ||
      after == 34 /* '$' */ ||
      after == 123 /* '{' */ ) {
    return 2;
  }

  if (after >= 48 && after <= 55 /* '0'-'7' */ ) {
    var size = 2;
    for (;;) {
      if (size >= 5) break;
      final next = input.peek(size);
      if (!(next >= 48 && next <= 55)) break;
      size++;
    }
    return size;
  }

  if (after == 120 /* 'x' */ && _isHex(input.peek(2))) {
    return _isHex(input.peek(3)) ? 4 : 3;
  }

  if (after == 117 /* 'u' */ && input.peek(2) == 123 /* '{' */ ) {
    for (var size = 3;; size++) {
      final next = input.peek(size);
      if (next == 125 /* '}' */ ) return size == 2 ? 0 : size + 1;
      if (!_isHex(next)) break;
    }
  }

  return 0;
}

final ExternalTokenizer _interpolated = ExternalTokenizer((input, stack) {
  var content = false;
  for (;; content = true) {
    if (input.next == 34 /* '"' */ ||
        input.next < 0 ||
        input.next == 36 /* '$' */ && (_isIdentifierStart(input.peek(1)) || input.peek(1) == 123 /* '{' */ ) ||
        input.next == 123 /* '{' */ && input.peek(1) == 36 /* '$' */ ) {
      break;
    } else if (input.next == 92 /* '\\' */ ) {
      final escaped = _scanEscape(input);
      if (escaped != 0) {
        if (content) {
          break;
        } else {
          return input.acceptToken(_T.EscapeSequence, escaped);
        }
      }
    } else if (!content &&
        (input.next == 91 /* '[' */ ||
            input.next == 45 /* '-' */ && input.peek(1) == 62 /* '>' */ && _isIdentifierStart(input.peek(2)) ||
            input.next == 63 /* '?' */ && input.peek(1) == 45 && input.peek(2) == 62 && _isIdentifierStart(input.peek(3))) &&
        stack.canShift(_T.afterInterpolation)) {
      break;
    }
    input.advance();
  }
  if (content) input.acceptToken(_T.interpolatedStringContent);
});

/// @lezer/php's `parser`, at the top rule @codemirror/lang-php reads a file by: a template, HTML with PHP in it.
final LRParser phpParser = LRParser.deserialize(
  phpSpec,
  tokenizers: <String, Tokenizer>{'expression': _expression, 'interpolated': _interpolated, 'semicolon': _semicolon, 'eofToken': _eofToken},
  specializers: <String, int Function(String value, Stack stack)>{'keywords': _keywords},
);
