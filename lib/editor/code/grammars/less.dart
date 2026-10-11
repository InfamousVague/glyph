/// LESS: the grammar and the tokenizers of @codemirror/lang-less 6 (less.g.dart; MIT, Marijn Haverbeke and
/// others).
library;

import '../lezer/lr.dart';
import 'less.g.dart';

typedef _T = LessTerms;

const List<int> _space = <int>[9, 10, 11, 12, 13, 32, 133, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288];

bool _isAlpha(int ch) => ch >= 65 && ch <= 90 || ch >= 97 && ch <= 122 || ch >= 161;

bool _isDigit(int ch) => ch >= 48 && ch <= 57;

final ExternalTokenizer _argList = ExternalTokenizer((input, stack) {
  if (input.next == 40 /* Ch.parenL */ ) {
    final prev = input.peek(-1);
    if (_isAlpha(prev) || _isDigit(prev) || prev == 95 /* Ch.underscore */ || prev == 45 /* Ch.dash */ ) input.acceptToken(_T.openArgList, 1);
  }
});

final ExternalTokenizer _descendant = ExternalTokenizer((input, stack) {
  if (_space.contains(input.peek(-1))) {
    final next = input.next;
    if (_isAlpha(next) || next == 95 /* Ch.underscore */ || next == 35 /* Ch.hash */ || next == 46 /* Ch.period */ || next == 91 /* Ch.bracketL */ || next == 58 /* Ch.colon */ || next == 45 /* Ch.dash */ ) {
      input.acceptToken(_T.descendantOp);
    }
  }
});

final ExternalTokenizer _unitToken = ExternalTokenizer((input, stack) {
  if (!_space.contains(input.peek(-1))) {
    final next = input.next;
    if (next == 37 /* Ch.percent */ ) {
      input.advance();
      input.acceptToken(_T.Unit);
    }
    if (_isAlpha(next)) {
      do {
        input.advance();
      } while (_isAlpha(input.next));
      input.acceptToken(_T.Unit);
    }
  }
});

/// `lessLanguage.parser`.
final LRParser lessParser = LRParser.deserialize(lessSpec, tokenizers: <String, Tokenizer>{'descendant': _descendant, 'unitToken': _unitToken, 'argList': _argList});
