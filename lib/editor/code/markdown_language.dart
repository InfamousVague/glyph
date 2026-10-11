/// Markdown inside a fenced block of a note: what `markdown()` of @codemirror/lang-markdown makes of it, which is
/// what the language pack loads for the name. That is CommonMark alone (no strikethrough, no tables, no task
/// boxes: those are GFM, which the note itself is read with and a block of Markdown inside it is not), its HTML
/// read as HTML, and a fence inside it left as plain code, there being no languages given to it.
///
/// It is read by the port's own Markdown parser (`syntax/markdown.dart`, CommonMark as @lezer/markdown has it) and
/// highlighted by the note's own rules (`markdownRules`, view/glyph_highlight.dart), as `highlightTree` reads the
/// web's tree: a node's class on its own words, handed down where the rule says so, and HTML's own runs over an
/// HTML block, a tag and a comment block, with no class from the Markdown round them.
///
/// What differs: a block of Markdown is parsed whole when it is first drawn and whole again when it changes;
/// Markdown parses a line at a glance, and a fence of it in a note is a few lines.
library;

import '../syntax/markdown.dart' as markdown show parser;
import '../syntax/tree.dart' as lezer;
import '../view/glyph_highlight.dart' show markdownRules;
import 'work.dart';

const Set<String> _html = <String>{'HTMLBlock', 'HTMLTag', 'CommentBlock'};

/// Not a class: what keeps an HTML run apart from the runs beside it, as `lezer/highlight.dart` keeps an inner
/// language's.
const String _apart = '\u0001';

class MarkdownCodeLanguage extends CodeLanguage {
  const MarkdownCodeLanguage(this.html) : super('Markdown');

  /// What reads the HTML in it: `html({matchClosingTags: false})`.
  final CodeLanguage html;

  @override
  CodeWork start(String code) {
    CodeStats.started++;
    return _MarkdownWork(this, code);
  }

  @override
  CodeWork resume(CodeWork old, String code) => old is _MarkdownWork && old.code == code ? old : start(code);
}

class _MarkdownWork extends CodeWork {
  _MarkdownWork(this.language, this.code);

  @override
  final MarkdownCodeLanguage language;

  @override
  final String code;

  lezer.Tree? _tree;

  /// The HTML read in it, by where each piece of it starts.
  final Map<int, (String, CodeWork)> _inner = <int, (String, CodeWork)>{};

  @override
  int get parsedTo => _tree == null ? 0 : code.length;

  @override
  bool get done => _tree != null;

  @override
  void work(int upTo, Budget budget) {
    if (_tree != null) return;
    _tree = markdown.parser.parse(code);
    CodeStats.read += code.length;
  }

  @override
  void spans(int from, int to, SpanSink sink, {String inherited = '', Budget? budget}) {
    final tree = _tree;
    if (tree == null || from >= to) return;
    // `HighlightBuilder`: the class of the run being read, and where it started.
    var at = from;
    var cls = '';
    void startSpan(int pos, String next) {
      if (next == cls) return;
      if (pos > at && cls.isNotEmpty && cls != _apart) sink(at, pos, cls);
      if (pos > at) at = pos;
      cls = next;
    }

    void html(lezer.SyntaxNode node, int a, int b, String text, int base) {
      // The piece of the node's HTML from `a` to `b` in the block; `text` is all of the node's, `base` where the
      // piece starts in it.
      if (b <= from || a >= to) return;
      var read = _inner[node.from];
      if (read == null || read.$1 != text) {
        final work = language.html.start(text)..work(text.length, Budget.none());
        read = _inner[node.from] = (text, work);
      }
      final clipFrom = a < from ? from : a, clipTo = b > to ? to : b;
      read.$2.spans(base + clipFrom - a, base + clipTo - a, (f, t, c) {
        startSpan(a + f - base, _apart);
        startSpan(a + f - base, c);
        startSpan(a + t - base, _apart);
      });
    }

    void walk(lezer.SyntaxNode node, String inherited) {
      if (node.from >= to || node.to <= from) return;
      final rule = markdownRules[node.name];
      var own = inherited, down = inherited;
      if (rule != null) {
        own = inherited.isEmpty ? rule.$1 : '$inherited ${rule.$1}';
        if (rule.$2) down = own;
      }
      if (_html.contains(node.name)) {
        // `leftOverSpace`: HTML reads the node less the nodes inside it, as one text.
        final pieces = <int>[];
        var pos = node.from;
        for (var child = node.firstChild; child != null; child = child.nextSibling) {
          if (child.from > pos) {
            pieces
              ..add(pos)
              ..add(child.from);
          }
          pos = child.to;
        }
        if (node.to > pos) {
          pieces
            ..add(pos)
            ..add(node.to);
        }
        final text = StringBuffer();
        for (var i = 0; i < pieces.length; i += 2) {
          text.write(code.substring(pieces[i], pieces[i + 1]));
        }
        final all = text.toString();
        startSpan(node.from < from ? from : node.from, '');
        var piece = 0, base = 0;
        for (var child = node.firstChild; ; child = child.nextSibling) {
          final until = child?.from ?? node.to;
          while (piece < pieces.length && pieces[piece] < until) {
            html(node, pieces[piece], pieces[piece + 1], all, base);
            base += pieces[piece + 1] - pieces[piece];
            startSpan(pieces[piece + 1] > to ? to : pieces[piece + 1], '');
            piece += 2;
          }
          if (child == null) break;
          walk(child, down);
          startSpan(child.to > to ? to : child.to, '');
        }
        return;
      }
      startSpan(node.from < from ? from : node.from, own);
      for (var child = node.firstChild; child != null; child = child.nextSibling) {
        if (child.to <= from) continue;
        if (child.from >= to) break;
        walk(child, down);
        startSpan(child.to > to ? to : child.to, own);
      }
    }

    walk(tree.topNode, inherited);
    if (to > at && cls.isNotEmpty && cls != _apart) sink(at, to, cls);
  }
}
