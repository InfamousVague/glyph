/// What a screen reader is told of the note (docs/PARITY.md, Missing 12): each line of the editor as a node of the
/// phone's accessibility tree, with its words as they are drawn, where the page's `contenteditable` was read by
/// the WebView itself. The editor drew its text and said nothing.
///
/// A LINE is one node, called by its words as drawn (the marks a formatted note hides are not read out; a chip or
/// a picture in the line is its own widget's to name). On top of that:
///
/// - **a heading** is a header, at its level (`#` one to `######` six);
/// - **a to-do** has a checked state, and activating it ticks or clears the box, as a tap on the box does;
/// - **a link** in the line is a node of its own inside the line's, a link called by its words, where the line
///   laid it out, and activating it opens it where the editor was given a way ([semanticsOpenLink]);
/// - **the line the caret is on**, while the editor has the keyboard, is the text field: focused, its value the
///   line's words, the selection reported in them, and the reader's own controls answered - set the selection,
///   move the caret by a character or by a word, with or without extending the selection - by the editor's own
///   commands, so they stop where the keys stop;
/// - **any other line** activated takes the caret to its end and the keyboard with it, which is how a reader
///   gets into the note to type. It is read as its words and no more: only the caret's line is called an edit
///   box, so a long note is not a hundred of them.
///
/// An empty line with no caret says nothing. A line that is all a drawn block (a board, a table, a picture) is
/// its block's to describe.
///
/// IT COSTS NOTHING WITH NO SCREEN READER ON. Flutter asks a render object to describe itself only while the
/// phone has asked for the tree (`SemanticsBinding.instance.semanticsEnabled`): [describeLine] and
/// [assembleLine] are never called otherwise, and the one thing the line does for them on its own, marking itself
/// when its selection changes, returns at once when nobody is listening (`RenderObject.markNeedsSemanticsUpdate`).
///
/// What is not here, said so the README can: cut, copy and paste as the reader's own actions (the note's menu has
/// them), a reader's "set text", and the words of a line as separate nodes for each mark (bold is not announced).
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';

import '../commands/commands.dart';
import '../commands/task_toggle.dart';
import '../looks/markdown_look.dart' show MarkdownClass;
import '../state/selection.dart';
import '../state/state.dart';
import '../view/editor_view.dart';
import '../view/line.dart';
import '../view/plugin.dart';
import '../view/projection.dart' show widgetPlaceholder;
import '../view/syntax_tree.dart';

/// Opens a link a screen reader activated: given by whoever wires the editor (the note's desk gives the app's own
/// way of opening an address). Without one a link is still announced as a link.
final Facet<void Function(String url), void Function(String url)?> semanticsOpenLink = Facet.define<void Function(String url), void Function(String url)?>(
  combine: (values) => values.isEmpty ? null : values.first,
);

/// The heading level a line's classes say, or 0. The page's fourth class stands for levels four to six, so the
/// level is read from the line's own marks.
int headingLevelOf(String className, String source) {
  final classes = className.split(' ');
  if (!classes.any((name) => name == MarkdownClass.lineH1 || name == MarkdownClass.lineH2 || name == MarkdownClass.lineH3 || name == MarkdownClass.lineH4)) return 0;
  final hashes = RegExp(r'^\s{0,3}(#{1,6})(\s|$)').firstMatch(source)?.group(1)?.length;
  if (hashes != null) return hashes;
  if (classes.contains(MarkdownClass.lineH1)) return 1;
  if (classes.contains(MarkdownClass.lineH2)) return 2;
  if (classes.contains(MarkdownClass.lineH3)) return 3;
  return 4;
}

/// The line's words as a reader hears them: what is drawn, a widget in the line as a space (it names itself).
String wordsOf(RenderEditorLine line) => line.spec.projection.display.replaceAll(widgetPlaceholder, ' ');

EditorView? _viewOf(RenderEditorLine line) {
  final host = line.host;
  return host is EditorView ? host : null;
}

/// The links on the line: where each one stands, in document positions, its address, and the words it is called
/// by (a `[word](address)`'s word; an address alone is called by itself).
List<({int from, int to, String url, String words})> linksOn(EditorState state, int from, int to) {
  final found = <({int from, int to, String url, String words})>[];
  syntaxTree(state).iterate(
    from: from,
    to: to,
    enter: (node) {
      if (node.name != 'Link' && node.name != 'Autolink' && node.name != 'URL') return null;
      if (node.from < from || node.to > to) return null;
      if (node.name == 'URL') {
        // A bare address in the words (an autolink's is inside its node, and was taken there).
        final url = state.sliceDoc(node.from, node.to);
        if (found.isEmpty || found.last.to <= node.from) found.add((from: node.from, to: node.to, url: url, words: url));
        return false;
      }
      final text = state.sliceDoc(node.from, node.to);
      if (node.name == 'Autolink') {
        final url = text.replaceAll(RegExp(r'^<|>$'), '');
        found.add((from: node.from, to: node.to, url: url, words: url));
        return false;
      }
      final link = RegExp(r'^\[([^\]]*)\]\(\s*<?([^)\s>]*)').firstMatch(text);
      if (link == null || link.group(2)!.isEmpty) return false;
      final words = link.group(1)!.trim();
      found.add((from: node.from, to: node.to, url: link.group(2)!, words: words.isEmpty ? link.group(2)! : words));
      return false;
    },
  );
  return found;
}

/// What [line] says of itself. Called by the line only while a screen reader is listening.
void describeLine(RenderEditorLine line, SemanticsConfiguration config) {
  final view = _viewOf(line);
  final projection = line.spec.projection;
  final words = wordsOf(line);
  final state = view?.state;
  final main = state?.selection.main;
  final editable = state != null && state.facet(EditorViewLike.editable) && !state.readOnly;
  final caretHere = view != null && main != null && editable && view.hasFocus && main.head >= line.from && main.head <= line.to;
  if (words.trim().isEmpty && !caretHere) return;

  config
    ..isSemanticBoundary = true
    // A widget in the line (a chip, a count, a picture) is a node of its own inside the line's, called by what it
    // says of itself. Left to merge, whatever of them had no press of its own was folded into the line's node,
    // its name run on after the line's words and nothing left to find it by.
    ..explicitChildNodes = true
    ..textDirection = TextDirection.ltr;

  final level = headingLevelOf(projection.className, projection.source);
  if (level > 0) {
    config
      ..isHeader = true
      ..headingLevel = level;
  }

  final box = state == null ? null : _boxOn(state, line.from, line.to);
  if (box != null) config.isChecked = box.done;

  if (caretHere) {
    int shown(int pos) => projection.toDisplay((pos - line.from).clamp(0, projection.length), 1).clamp(0, words.length);
    config
      ..isTextField = true
      ..isMultiline = true
      ..isFocused = true
      ..value = words
      ..textSelection = TextSelection(baseOffset: shown(main.anchor), extentOffset: shown(main.head))
      ..onSetSelection = (selection) {
        int doc(int at) => line.from + projection.toDoc(at.clamp(0, projection.display.length), -1);
        view.dispatch(TransactionSpec(selection: EditorSelection.single(doc(selection.baseOffset), doc(selection.extentOffset)), userEvent: 'select'));
      }
      ..onMoveCursorForwardByCharacter = ((extend) => extend ? selectCharForward(view) : cursorCharForward(view))
      ..onMoveCursorBackwardByCharacter = ((extend) => extend ? selectCharBackward(view) : cursorCharBackward(view))
      ..onMoveCursorForwardByWord = ((extend) => extend ? selectGroupForward(view) : cursorGroupForward(view))
      ..onMoveCursorBackwardByWord = ((extend) => extend ? selectGroupBackward(view) : cursorGroupBackward(view));
  } else {
    config.label = words.trim();
  }

  if (view != null && editable) {
    if (box != null && !caretHere) {
      // A to-do read out: activating it is the tap on its box.
      config.onTap = () => view.dispatch(toggleBox(view.state, boxAt(view.state, box.from) ?? box));
      config.onLongPress = () => _enter(view, line);
    } else if (!caretHere) {
      config.onTap = () => _enter(view, line);
    }
  }
}

({int from, int to, bool done})? _boxOn(EditorState state, int from, int to) {
  final text = state.sliceDoc(from, to);
  final at = RegExp(r'^\s*(?:>\s*)*(?:[-*+]|\d+[.)])\s+\[').firstMatch(text);
  return at == null ? null : boxAt(state, from + at.end);
}

/// The caret to the end of [line], and the keyboard: how a reader gets into the note.
void _enter(EditorView view, RenderEditorLine line) {
  view.dispatch(TransactionSpec(selection: EditorSelection.single(line.to.clamp(0, view.state.doc.length)), userEvent: 'select'));
  view.focus();
}

/// The line's node put together: its own, and one inside it for each link it shows. [links] are kept by the line
/// between calls, as a paragraph keeps the nodes of its spans. Called by the line only while a screen reader is
/// listening.
void assembleLine(RenderEditorLine line, SemanticsNode node, SemanticsConfiguration config, Iterable<SemanticsNode> children, List<SemanticsNode> links) {
  final view = _viewOf(line);
  final made = <SemanticsNode>[...children];
  var used = 0;
  if (view != null && config.isSemanticBoundary) {
    final state = view.state;
    final open = state.facet(semanticsOpenLink);
    for (final link in linksOn(state, line.from, line.to)) {
      final rects = line.rectsForRange(link.from - line.from, link.to - line.from);
      if (rects.isEmpty) continue;
      var box = rects.first;
      for (final rect in rects.skip(1)) {
        box = box.expandToInclude(rect);
      }
      final said = SemanticsConfiguration()
        ..isLink = true
        ..textDirection = TextDirection.ltr
        ..label = link.words;
      final uri = Uri.tryParse(link.url);
      if (uri != null && uri.hasScheme) said.linkUrl = uri;
      if (open != null) said.onTap = () => open(link.url);
      if (used == links.length) links.add(SemanticsNode());
      final child = links[used++]
        ..rect = box
        ..updateWith(config: said);
      made.add(child);
    }
  }
  if (used < links.length) links.removeRange(used, links.length);
  node.updateWith(config: config, childrenInInversePaintOrder: made);
}
