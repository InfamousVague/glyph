/// SQL and its dialects: the grammar and the tokenizer of @codemirror/lang-sql 6 (sql.g.dart; MIT, Marijn
/// Haverbeke and others). The grammar is small: nearly all of SQL is in the one tokenizer, which each dialect
/// configures with its words and its ways of quoting.
library;

import '../lezer/lr.dart';
import 'sql.g.dart';

typedef _T = SqlTerms;

bool _isAlpha(int ch) => ch >= 65 && ch <= 90 || ch >= 97 && ch <= 122 || ch >= 48 && ch <= 57;

bool _isHexDigit(int ch) => ch >= 48 && ch <= 57 || ch >= 97 && ch <= 102 || ch >= 65 && ch <= 70;

void _readLiteral(InputStream input, int endQuote, bool backslashEscapes) {
  for (var escaped = false;;) {
    if (input.next < 0) return;
    if (input.next == endQuote && !escaped) {
      input.advance();
      return;
    }
    escaped = backslashEscapes && !escaped && input.next == 92 /* Ch.Backslash */;
    input.advance();
  }
}

void _readDoubleDollarLiteral(InputStream input, String tag) {
  scan:
  for (;;) {
    if (input.next < 0) return;
    if (input.next == 36 /* Ch.Dollar */ ) {
      input.advance();
      for (var i = 0; i < tag.length; i++) {
        if (input.next != tag.codeUnitAt(i)) continue scan;
        input.advance();
      }
      if (input.next == 36 /* Ch.Dollar */ ) {
        input.advance();
        return;
      }
    } else {
      input.advance();
    }
  }
}

void _readPLSQLQuotedLiteral(InputStream input, int openDelim) {
  final matchingDelim = '[{<('.indexOf(String.fromCharCode(openDelim));
  final closeDelim = matchingDelim < 0 ? openDelim : ']}>)'.codeUnitAt(matchingDelim);
  for (;;) {
    if (input.next < 0) return;
    if (input.next == closeDelim && input.peek(1) == 39 /* Ch.SingleQuote */ ) {
      input.advance(2);
      return;
    }
    input.advance();
  }
}

/// Reads a word; with `result`, answers it after what `result` holds.
String? _readWord(InputStream input, [String? result]) {
  final word = result == null ? null : (StringBuffer()..write(result));
  for (;;) {
    if (input.next != 95 /* Ch.Underscore */ && !_isAlpha(input.next)) break;
    word?.writeCharCode(input.next);
    input.advance();
  }
  return word?.toString();
}

void _readWordOrQuoted(InputStream input) {
  if (input.next == 39 /* Ch.SingleQuote */ || input.next == 34 /* Ch.DoubleQuote */ || input.next == 96 /* Ch.Backtick */ ) {
    final quote = input.next;
    input.advance();
    _readLiteral(input, quote, false);
  } else {
    _readWord(input);
  }
}

void _readBits(InputStream input, [int? endQuote]) {
  while (input.next == 48 /* Ch._0 */ || input.next == 49 /* Ch._1 */ ) {
    input.advance();
  }
  if (endQuote != null && input.next == endQuote) input.advance();
}

void _readNumber(InputStream input, bool sawDot) {
  for (;;) {
    if (input.next == 46 /* Ch.Dot */ ) {
      if (sawDot) break;
      sawDot = true;
    } else if (input.next < 48 /* Ch._0 */ || input.next > 57 /* Ch._9 */ ) {
      break;
    }
    input.advance();
  }
  if (input.next == 69 /* Ch.E */ || input.next == 101 /* Ch.e */ ) {
    input.advance();
    if (input.next == 43 /* Ch.Plus */ || input.next == 45 /* Ch.Dash */ ) input.advance();
    while (input.next >= 48 /* Ch._0 */ && input.next <= 57 /* Ch._9 */ ) {
      input.advance();
    }
  }
}

void _eol(InputStream input) {
  while (!(input.next < 0 || input.next == 10 /* Ch.Newline */ )) {
    input.advance();
  }
}

bool _inString(int ch, String str) {
  for (var i = 0; i < str.length; i++) {
    if (str.codeUnitAt(i) == ch) return true;
  }
  return false;
}

const String _space = ' \t\r\n';

/// `keywords(keywords, types, builtin)`: what each of a dialect's words is.
Map<String, int> _words(SqlDialectSpec d) => <String, int>{
  for (final word in d.bools.split(' '))
    if (word.isNotEmpty) word: _T.Bool,
  for (final word in d.nulls.split(' '))
    if (word.isNotEmpty) word: _T.Null,
  for (final word in d.keywords.split(' '))
    if (word.isNotEmpty) word: _T.Keyword,
  for (final word in d.types.split(' '))
    if (word.isNotEmpty) word: _T.Type,
  for (final word in d.builtin.split(' '))
    if (word.isNotEmpty) word: _T.Builtin,
};

/// `tokensFor(d)`.
ExternalTokenizer _tokensFor(SqlDialectSpec d) {
  final words = _words(d);
  return ExternalTokenizer((input, stack) {
    final next = input.next;
    input.advance();
    if (_inString(next, _space)) {
      while (_inString(input.next, _space)) {
        input.advance();
      }
      input.acceptToken(_T.whitespace);
    } else if (next == 36 /* Ch.Dollar */ && d.doubleDollarQuotedStrings) {
      final tag = _readWord(input, '')!;
      if (input.next == 36 /* Ch.Dollar */ ) {
        input.advance();
        _readDoubleDollarLiteral(input, tag);
        input.acceptToken(_T.String$1);
      }
    } else if (next == 39 /* Ch.SingleQuote */ || next == 34 /* Ch.DoubleQuote */ && d.doubleQuotedStrings) {
      _readLiteral(input, next, d.backslashEscapes);
      input.acceptToken(_T.String$1);
    } else if (next == 35 /* Ch.Hash */ && d.hashComments || next == 47 /* Ch.Slash */ && input.next == 47 /* Ch.Slash */ && d.slashComments) {
      _eol(input);
      input.acceptToken(_T.LineComment);
    } else if (next == 45 /* Ch.Dash */ && input.next == 45 /* Ch.Dash */ && (!d.spaceAfterDashes || input.peek(1) == 32 /* Ch.Space */ )) {
      _eol(input);
      input.acceptToken(_T.LineComment);
    } else if (next == 47 /* Ch.Slash */ && input.next == 42 /* Ch.Star */ ) {
      input.advance();
      for (var depth = 1;;) {
        final cur = input.next;
        if (input.next < 0) break;
        input.advance();
        if (cur == 42 /* Ch.Star */ && input.next == 47 /* Ch.Slash */ ) {
          depth--;
          input.advance();
          if (depth == 0) break;
        } else if (cur == 47 /* Ch.Slash */ && input.next == 42 /* Ch.Star */ ) {
          depth++;
          input.advance();
        }
      }
      input.acceptToken(_T.BlockComment);
    } else if ((next == 101 /* Ch.e */ || next == 69 /* Ch.E */ ) && input.next == 39 /* Ch.SingleQuote */ ) {
      input.advance();
      _readLiteral(input, 39 /* Ch.SingleQuote */, true);
      input.acceptToken(_T.String$1);
    } else if ((next == 110 /* Ch.n */ || next == 78 /* Ch.N */ ) && input.next == 39 /* Ch.SingleQuote */ && d.charSetCasts) {
      input.advance();
      _readLiteral(input, 39 /* Ch.SingleQuote */, d.backslashEscapes);
      input.acceptToken(_T.String$1);
    } else if (next == 95 /* Ch.Underscore */ && d.charSetCasts) {
      for (var i = 0;; i++) {
        if (input.next == 39 /* Ch.SingleQuote */ && i > 1) {
          input.advance();
          _readLiteral(input, 39 /* Ch.SingleQuote */, d.backslashEscapes);
          input.acceptToken(_T.String$1);
          break;
        }
        if (!_isAlpha(input.next)) break;
        input.advance();
      }
    } else if (d.plsqlQuotingMechanism && (next == 113 /* Ch.q */ || next == 81 /* Ch.Q */ ) && input.next == 39 /* Ch.SingleQuote */ && input.peek(1) > 0 && !_inString(input.peek(1), _space)) {
      final openDelim = input.peek(1);
      input.advance(2);
      _readPLSQLQuotedLiteral(input, openDelim);
      input.acceptToken(_T.String$1);
    } else if (_inString(next, d.identifierQuotes)) {
      final endQuote = next == 91 /* Ch.BracketL */ ? 93 /* Ch.BracketR */ : next;
      _readLiteral(input, endQuote, false);
      input.acceptToken(_T.QuotedIdentifier);
    } else if (next == 40 /* Ch.ParenL */ ) {
      input.acceptToken(_T.ParenL);
    } else if (next == 41 /* Ch.ParenR */ ) {
      input.acceptToken(_T.ParenR);
    } else if (next == 123 /* Ch.BraceL */ ) {
      input.acceptToken(_T.BraceL);
    } else if (next == 125 /* Ch.BraceR */ ) {
      input.acceptToken(_T.BraceR);
    } else if (next == 91 /* Ch.BracketL */ ) {
      input.acceptToken(_T.BracketL);
    } else if (next == 93 /* Ch.BracketR */ ) {
      input.acceptToken(_T.BracketR);
    } else if (next == 59 /* Ch.Semi */ ) {
      input.acceptToken(_T.Semi);
    } else if (d.unquotedBitLiterals && next == 48 /* Ch._0 */ && input.next == 98 /* Ch.b */ ) {
      input.advance();
      _readBits(input);
      input.acceptToken(_T.Bits);
    } else if ((next == 98 /* Ch.b */ || next == 66 /* Ch.B */ ) && (input.next == 39 /* Ch.SingleQuote */ || input.next == 34 /* Ch.DoubleQuote */ )) {
      final quoteStyle = input.next;
      input.advance();
      if (d.treatBitsAsBytes) {
        _readLiteral(input, quoteStyle, d.backslashEscapes);
        input.acceptToken(_T.Bytes);
      } else {
        _readBits(input, quoteStyle);
        input.acceptToken(_T.Bits);
      }
    } else if (next == 48 /* Ch._0 */ && (input.next == 120 /* Ch.x */ || input.next == 88 /* Ch.X */ ) || (next == 120 /* Ch.x */ || next == 88 /* Ch.X */ ) && input.next == 39 /* Ch.SingleQuote */ ) {
      final quoted = input.next == 39 /* Ch.SingleQuote */;
      input.advance();
      while (_isHexDigit(input.next)) {
        input.advance();
      }
      if (quoted && input.next == 39 /* Ch.SingleQuote */ ) input.advance();
      input.acceptToken(_T.Number);
    } else if (next == 46 /* Ch.Dot */ && input.next >= 48 /* Ch._0 */ && input.next <= 57 /* Ch._9 */ ) {
      _readNumber(input, true);
      input.acceptToken(_T.Number);
    } else if (next == 46 /* Ch.Dot */ ) {
      input.acceptToken(_T.Dot);
    } else if (next >= 48 /* Ch._0 */ && next <= 57 /* Ch._9 */ ) {
      _readNumber(input, false);
      input.acceptToken(_T.Number);
    } else if (_inString(next, d.operatorChars)) {
      while (_inString(input.next, d.operatorChars)) {
        input.advance();
      }
      input.acceptToken(_T.Operator);
    } else if (_inString(next, d.specialVar)) {
      if (input.next == next) input.advance();
      _readWordOrQuoted(input);
      input.acceptToken(_T.SpecialVar);
    } else if (next == 58 /* Ch.Colon */ || next == 44 /* Ch.Comma */ ) {
      input.acceptToken(_T.Punctuation);
    } else if (_isAlpha(next)) {
      final word = _readWord(input, String.fromCharCode(next))!;
      input.acceptToken(input.next == 46 /* Ch.Dot */ || input.peek(-word.length - 1) == 46 /* Ch.Dot */ ? _T.Identifier : words[word.toLowerCase()] ?? _T.Identifier);
    }
  });
}

/// The parser of the dialect the language pack calls `name` (`SQL`, `PostgreSQL`, `MySQL` …).
LRParser sqlParser(String name) => LRParser.deserialize(sqlSpec, tokenizers: <String, Tokenizer>{'tokens': _tokensFor(sqlDialects[name]!)});
