/// Liquid: the grammar of @codemirror/lang-liquid (liquid.g.dart) for a template's tags, with its tokenizers
/// (`template_tokens.dart`, and the one for a comment in a tag, ported from the package's `tokens.js`).
library;

import '../lezer/lr.dart';
import 'liquid.g.dart';
import 'template_tokens.dart';

// `parser.terms.js`, which the language package keeps to itself.
const int _interpolationStart = 1, _tagStart = 2, _endTagStart = 3, _text = 180, _endrawTagStart = 4, _rawText = 181, _endcommentTagStart = 5, _commentText = 182, _inlineComment = 6;

/// `inlineComment`: from a `#` in a tag to the end of the line or of the tag.
final ExternalTokenizer _inline = ExternalTokenizer((input, stack) {
  if (input.next != 35 /* # */) return;
  input.advance();
  for (;;) {
    if (input.next == 10 || input.next < 0) break;
    if ((input.next == 37 /* % */ || input.next == 125 /* } */) && input.peek(1) == 125) break;
    input.advance();
  }
  input.acceptToken(_inlineComment);
});

/// `liquidLanguage.parser`, before the page between the tags is handed to HTML.
final LRParser liquidParser = LRParser.deserialize(
  liquidSpec,
  tokenizers: <String, Tokenizer>{
    'base': baseTokenizer(interpolationStart: _interpolationStart, tagStart: _tagStart, endTagStart: _endTagStart, text: _text),
    'raw': rawTokenizer('endraw', _rawText, _endrawTagStart),
    'comment': rawTokenizer('endcomment', _commentText, _endcommentTagStart),
    'inlineComment': _inline,
  },
);
