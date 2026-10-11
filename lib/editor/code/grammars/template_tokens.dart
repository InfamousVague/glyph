/// The tokenizers Liquid's and Jinja's grammars share (@codemirror/lang-liquid 6, @codemirror/lang-jinja 6; MIT,
/// Marijn Haverbeke and others): the text between a template's tags, and the text of a `raw` or a `comment`
/// block up to the tag that ends it. The two packages carry the same code, a few lines apart; here it is once,
/// with what differs handed in.
library;

import '../lezer/lr.dart';

bool _wordChar(int code) => code >= 65 && code <= 90 || code >= 97 && code <= 122;

/// `base`: text up to `{{`, `{%` or the line's end, or the token one of those starts. `{#` starts a comment where
/// `commentTagStart` is given (Jinja); a `{%` before `end…` is `endTagStart` where that is given (Liquid).
ExternalTokenizer baseTokenizer({required int interpolationStart, required int tagStart, required int text, int? commentTagStart, int? endTagStart}) => ExternalTokenizer((input, stack) {
  final start = input.pos;
  for (;;) {
    final next = input.next;
    if (next < 0) break;
    if (next == 123 /* { */) {
      final after = input.peek(1);
      if (after == 123 /* { */) {
        if (input.pos > start) break;
        input.acceptToken(interpolationStart, 2);
        return;
      } else if (commentTagStart != null && after == 35 /* # */) {
        if (input.pos > start) break;
        input.acceptToken(commentTagStart, 2);
        return;
      } else if (after == 37 /* % */) {
        if (input.pos > start) break;
        var scan = 2, size = 2;
        for (;;) {
          final next = input.peek(scan);
          if (next == 32 || next == 10) {
            ++scan;
          } else if (next == 35 /* # */) {
            ++scan;
            for (;;) {
              final comment = input.peek(scan);
              if (comment < 0 || comment == 10) break;
              scan++;
            }
          } else if (next == 45 /* - */ && size == 2) {
            size = ++scan;
          } else {
            final end = endTagStart != null && next == 101 /* e */ && input.peek(scan + 1) == 110 /* n */ && input.peek(scan + 2) == 100 /* d */;
            input.acceptToken(end ? endTagStart : tagStart, size);
            return;
          }
        }
      }
    }
    input.advance();
    if (next == 10) break;
  }
  if (input.pos > start) input.acceptToken(text);
});

/// `rawTokenizer(endTag, text, tagStart)`: text up to the `{% endTag` that ends the block, a line at a time.
ExternalTokenizer rawTokenizer(String endTag, int text, int tagStart) => ExternalTokenizer((input, stack) {
  final start = input.pos;
  for (;;) {
    final next = input.next;
    if (next == 123 /* { */ && input.peek(1) == 37 /* % */) {
      var scan = 2;
      for (;; scan++) {
        final ch = input.peek(scan);
        if (ch != 32 && ch != 10) break;
      }
      final word = StringBuffer();
      for (;; scan++) {
        final next = input.peek(scan);
        if (!_wordChar(next)) break;
        word.writeCharCode(next);
      }
      if (word.toString() == endTag) {
        if (input.pos > start) break;
        input.acceptToken(tagStart, 2);
        break;
      }
    } else if (next < 0) {
      break;
    }
    input.advance();
    if (next == 10) break;
  }
  if (input.pos > start) input.acceptToken(text);
});
