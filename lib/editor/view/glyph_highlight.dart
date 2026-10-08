/// The inline half of the renderer: what every run of markdown looks like, the syntax itself included. Ports
/// `src/app/editor/glyphHighlight.ts`, and with it the two things of CodeMirror's it stands on: the markdown
/// grammar's `styleTags` (@lezer/markdown, markdown.ts and extension.ts) and `syntaxHighlighting`
/// (@codemirror/language, highlight.ts; @lezer/highlight `highlightTree`).
///
/// On the web a node has TAGS (`StrongEmphasis/...: t.strong`, every delimiter `t.processingInstruction`) and
/// `glyphHighlight` gives a class for a tag; the highlighter emits one span for each run with the classes of every
/// tag over it. So inside `**bold**` the asterisks are `strong mark` and the word `strong`: one rule styles the
/// content, one dims the markers, and nothing is hidden. The parser here keeps node names and no tags, so the two
/// tables are folded into one, [_rules]: the class a node's tag has in glyphHighlight.ts, and whether the tag
/// reaches what is inside the node (`/...`) or only the node's own text.
///
/// The fold, for the tags whose class is not the obvious one. A highlight style matches a tag or the nearest of
/// its parents, so: `Escape` is `t.escape`, a `literal`, and takes `tags.literal`'s `codeLiteral`; `Entity` and
/// `Emoji` are `t.character`, a `string`, and take `codeString`, as `LinkTitle` (`t.string`) does; `Comment` and
/// `CommentBlock` take `codeComment`. `Paragraph`, `TableCell` (`t.content`), `TableHeader/...` (`t.heading`) and
/// `Subscript`/`Superscript` (`t.special(t.content)`) have no class: nothing in glyphHighlight.ts names their tags.
///
/// What differs: a fenced block's code is not parsed by its language (docs/STAGE4.md), so the `code*` token
/// classes are never handed out and the block's words are `CodeText`, in the `code` class. The classes are
/// markdown.module.css's (`looks/markdown_look.dart`).
library;

import '../looks/markdown_look.dart';
import '../state/rangeset.dart';
import '../state/state.dart';
import '../syntax/language.dart' show InlineFormatSyntax;
import '../syntax/tree.dart' show SyntaxNode;
import 'decoration.dart';
import 'plugin.dart';
import 'syntax_tree.dart';

/// A node's class, and whether it is inherited by the nodes inside (`/...` in `styleTags`).
typedef _Rule = (String cls, bool inherit);

const Map<String, _Rule> _rules = <String, _Rule>{
  // @lezer/markdown markdown.ts `markdownHighlighting`
  'Blockquote': (MarkdownClass.quote, true), // "Blockquote/...": t.quote
  'HorizontalRule': (MarkdownClass.hr, false), // HorizontalRule: t.contentSeparator
  'ATXHeading1': (MarkdownClass.h1, true), // "ATXHeading1/... SetextHeading1/...": t.heading1
  'SetextHeading1': (MarkdownClass.h1, true),
  'ATXHeading2': (MarkdownClass.h2, true),
  'SetextHeading2': (MarkdownClass.h2, true),
  'ATXHeading3': (MarkdownClass.h3, true),
  'ATXHeading4': (MarkdownClass.h4, true),
  'ATXHeading5': (MarkdownClass.h5, true),
  'ATXHeading6': (MarkdownClass.h6, true),
  'Comment': (MarkdownClass.codeComment, false), // "Comment CommentBlock": t.comment
  'CommentBlock': (MarkdownClass.codeComment, false),
  'Escape': (MarkdownClass.codeLiteral, false), // Escape: t.escape
  'Entity': (MarkdownClass.codeString, false), // Entity: t.character
  'Emphasis': (MarkdownClass.em, true), // "Emphasis/...": t.emphasis
  'StrongEmphasis': (MarkdownClass.strong, true), // "StrongEmphasis/...": t.strong
  'Link': (MarkdownClass.link, true), // "Link/... Image/...": t.link
  'Image': (MarkdownClass.link, true),
  'OrderedList': (MarkdownClass.list, true), // "OrderedList/... BulletList/...": t.list
  'BulletList': (MarkdownClass.list, true),
  'InlineCode': (MarkdownClass.code, false), // "InlineCode CodeText": t.monospace
  'CodeText': (MarkdownClass.code, false),
  'URL': (MarkdownClass.url, false), // "URL Autolink": t.url
  'Autolink': (MarkdownClass.url, false),
  // "HeaderMark HardBreak QuoteMark ListMark LinkMark EmphasisMark CodeMark": t.processingInstruction
  'HeaderMark': (MarkdownClass.mark, false),
  'HardBreak': (MarkdownClass.mark, false),
  'QuoteMark': (MarkdownClass.mark, false),
  'ListMark': (MarkdownClass.mark, false),
  'LinkMark': (MarkdownClass.mark, false),
  'EmphasisMark': (MarkdownClass.mark, false),
  'CodeMark': (MarkdownClass.mark, false),
  'CodeInfo': (MarkdownClass.codeInfo, false), // "CodeInfo LinkLabel": t.labelName
  'LinkLabel': (MarkdownClass.codeInfo, false),
  'LinkTitle': (MarkdownClass.codeString, false), // LinkTitle: t.string
  // @lezer/markdown extension.ts (GFM, subscript, superscript, emoji)
  // "TableDelimiter SubscriptMark SuperscriptMark StrikethroughMark": t.processingInstruction
  'TableDelimiter': (MarkdownClass.mark, false),
  'SubscriptMark': (MarkdownClass.mark, false),
  'SuperscriptMark': (MarkdownClass.mark, false),
  'StrikethroughMark': (MarkdownClass.mark, false),
  'Strikethrough': (MarkdownClass.strike, true), // "Strikethrough/...": t.strikethrough
  'TaskMarker': (MarkdownClass.taskMarker, false), // TaskMarker: t.atom
  'Task': (MarkdownClass.list, false), // Task: t.list
  'Emoji': (MarkdownClass.codeString, false), // Emoji: t.character
};

class _TreeHighlighter extends PluginValue {
  _TreeHighlighter(EditorViewLike view, this.rules) {
    decorations = _build(view);
  }

  final Map<String, _Rule> rules;
  late DecorationSet decorations;

  /// One decoration for each class string, as `TreeHighlighter.markCache` keeps them.
  static final Map<String, Decoration> _marks = <String, Decoration>{};

  @override
  void update(ViewUpdate update) {
    final tree = syntaxTree(update.state);
    if (!identical(tree, syntaxTree(update.startState)) || update.viewportChanged) {
      decorations = _build(update.view);
    }
  }

  DecorationSet _build(EditorViewLike view) {
    final tree = syntaxTree(view.state);
    final builder = RangeSetBuilder<Decoration>();
    for (final range in view.visibleRanges) {
      final from = range.from, to = range.to;
      // @lezer/highlight `HighlightBuilder`: the class of the run being read, and where it started.
      var at = from;
      var cls = '';
      void flush(int upTo) {
        if (upTo > at && cls.isNotEmpty) builder.add(at, upTo, _marks[cls] ??= Decoration.mark(className: cls));
      }

      void startSpan(int pos, String next) {
        if (next == cls) return;
        flush(pos);
        if (pos > at) at = pos;
        cls = next;
      }

      // The class of each open node, and what it hands to the nodes inside it.
      final open = <(String cls, String inherited)>[('', '')];
      tree.iterate(
        from: from,
        to: to,
        enter: (SyntaxNode node) {
          if (node.from >= to || node.to <= from) {
            // Only touches the range: no text of it is inside.
            if (node.parent != null) return false;
          }
          final inherited = open.last.$2;
          final rule = rules[node.name];
          var own = inherited, down = inherited;
          if (rule != null) {
            own = inherited.isEmpty ? rule.$1 : '$inherited ${rule.$1}';
            if (rule.$2) down = own;
          }
          startSpan(node.from < from ? from : node.from, own);
          open.add((own, down));
          return null;
        },
        leave: (SyntaxNode node) {
          open.removeLast();
          if (open.isEmpty) return;
          startSpan(node.to > to ? to : node.to, open.last.$1);
        },
      );
      flush(to);
    }
    return builder.finish();
  }
}

/// `syntaxHighlighting(glyphHighlight)`: the note's runs styled from its parse. `formats` are the switched-on
/// plugins' inline formattings, whose delimiters are markers too (language.ts gives `<Name>Mark` the
/// `processingInstruction` tag).
Extension glyphHighlight([Iterable<InlineFormatSyntax> formats = const <InlineFormatSyntax>[]]) {
  final rules = formats.isEmpty ? _rules : <String, _Rule>{..._rules, for (final format in formats) '${format.name}Mark': (MarkdownClass.mark, false)};
  // CodeMirror's `treeHighlighter` is `Prec.high`.
  return Prec.high(ViewPlugin.define<_TreeHighlighter>((view) => _TreeHighlighter(view, rules), decorations: (value) => value.decorations));
}
