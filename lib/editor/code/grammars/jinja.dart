/// Jinja: the grammar of @codemirror/lang-jinja (jinja.g.dart) for a template's tags, with its tokenizers
/// (`template_tokens.dart`).
library;

import '../lezer/lr.dart';
import 'jinja.g.dart';
import 'template_tokens.dart';

// `parser.terms.js`, which the language package keeps to itself.
const int _interpolationStart = 1, _commentTagStart = 2, _tagStart = 3, _text = 155, _endrawTagStart = 4, _rawText = 156;

/// `jinjaLanguage.parser`, before the page between the tags is handed to HTML.
final LRParser jinjaParser = LRParser.deserialize(
  jinjaSpec,
  tokenizers: <String, Tokenizer>{
    'base': baseTokenizer(interpolationStart: _interpolationStart, commentTagStart: _commentTagStart, tagStart: _tagStart, text: _text),
    'raw': rawTokenizer('endraw', _rawText, _endrawTagStart),
  },
);
