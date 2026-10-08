/// What goes in a note's open first heading, said in it: `A name`, quiet, at the heading's own size, after its
/// marks, gone at the first letter. Ports `src/app/editor/openHeading.ts`.
///
/// Only the note's first line of words, the one that names it: an empty `## ` further down is a heading being
/// written, and says nothing. Nothing is written into the note: the words are a widget, and not in the file.
///
/// And a reading note's lead line ([leadLine], `look: reading`): the first paragraph after its title set a step
/// larger, in the second ink, with a little less leading, as a magazine sets its standfirst. While the line under
/// the title is empty and nothing below it has words, that line says `A line that says what it is about.`.
///
/// What differs: the hint's size is the heading's class resolved through the view's own look (`.h1` of
/// markdown.module.css), where the page puts the class on the hint's `<span>`.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../editor.dart';
import '../looks/look.dart';
import '../looks/markdown_look.dart';
import '../looks/sheets.dart';
import '../view/editor_view.dart';
import '../view/extended.dart' show frontMatter;
import '../view/line.dart' show EditorRunScope;
import 'inline_box.dart';

/// The hint in an open first heading.
const String openHeadingHint = 'A name';

/// The hint on a reading note's empty lead line.
const String leadHint = 'A line that says what it is about.';

const List<String> _headingSize = <String>[MarkdownClass.h1, MarkdownClass.h1, MarkdownClass.h2, MarkdownClass.h3, MarkdownClass.h4, MarkdownClass.h5, MarkdownClass.h6];

/// The note's first line of words: the first line after its front matter with anything on it.
Line? firstWordsLine(EditorState state) {
  final front = frontMatter(state.doc);
  for (var n = front != null ? front.to + 1 : 1; n <= state.doc.lines; n += 1) {
    final line = state.doc.line(n);
    if (line.text.trim().isNotEmpty) return line;
  }
  return null;
}

final RegExp _open = RegExp(r'^ {0,3}(#{1,6})\s*$');

/// The first line of words when it is a heading with no words (`# `, `##`), and its level; else null.
({Line line, int level})? openFirstHeading(EditorState state) {
  final line = firstWordsLine(state);
  final open = line == null ? null : _open.firstMatch(line.text);
  return line != null && open != null ? (line: line, level: open.group(1)!.length) : null;
}

/// Whether the caret is on the line that names the note: its first line of words, with no words of its own yet.
/// A blank note's line 1, or an open first heading (`# `).
bool onNamingLine(EditorState state) {
  final main = state.selection.main;
  if (!main.empty) return false;
  final line = state.doc.lineAt(main.head);
  if (line.text.trim().isNotEmpty && !_open.hasMatch(line.text)) return false;
  final front = frontMatter(state.doc);
  if (front != null && line.number <= front.to) return false;
  final words = firstWordsLine(state);
  return words == null || words.number >= line.number;
}

class HintWidget extends EditorWidget {
  const HintWidget(this.words, this.size);

  final String words;

  String get openWords => words;

  /// The heading's size class, or empty for the line's own.
  final String size;

  @override
  bool eq(HintWidget other) => other.words == words && other.size == size;

  // Never in the way of a tap on the line.
  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = EditorRunScope.maybeOf(context);
    final view = EditorViewScope.maybeOf(context);
    final look = view is EditorView ? view.look : null;
    var run = scope?.look;
    if (size.isNotEmpty && look != null && scope != null) run = look.run(scope.line, <LookElement>[LookElement(size)]);
    // '.cm-openHint': { color: 'var(--glacier-text-subtle)', pointerEvents: 'none', userSelect: 'none' }
    final style = (run?.style ?? t.textAt(t.len('app-body'))).copyWith(color: t.color('glacier-text-subtle'));
    final words = Text(openWords, softWrap: false, textScaler: TextScaler.noScaling, style: style);
    if (run == null) return ExcludeSemantics(child: words);
    // An inline span gives its line its leading, not its letters' own box, which in a heading's tight leading
    // stands over the line's top: the hint takes the room the heading's words would, and no more.
    final face = FaceMetrics.of(style);
    return ExcludeSemantics(
      child: InlineBox(above: run.above, below: run.below, child: Dropped(top: run.above - face.ascent * run.fontSize, child: words)),
    );
  }
}

DecorationSet _hints(EditorState state) {
  final open = openFirstHeading(state);
  if (open == null) return Decoration.none;
  final size = open.level < _headingSize.length ? _headingSize[open.level] : MarkdownClass.h1;
  return Decoration.set(<Range<Decoration>>[Decoration.widget(widget: HintWidget(openHeadingHint, size), side: 1).range(open.line.to)]);
}

class _Docs extends PluginValue {
  _Docs(EditorViewLike view, this.make) : decorations = make(view.state);

  final DecorationSet Function(EditorState state) make;
  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    if (update.docChanged) decorations = make(update.state);
  }
}

final Extension _openHeading = ViewPlugin.define<_Docs>((view) => _Docs(view, _hints), decorations: (value) => value.decorations);

/// `A name` in an open first heading.
Extension openHeading() => _openHeading;

/// A line a lead paragraph cannot be: a heading, a list, a quote, a fence, a table, a rule or a picture.
final RegExp _notProse = RegExp(r'^\s*(#{1,6}(\s|$)|[-*+]\s|\d+[.)]\s|>|```|~~~|\||(-{3,}|\*{3,}|_{3,})\s*$|!\[)');
final RegExp _title = RegExp(r'^ {0,3}#{1,6}(\s|$)');

/// The lead: the first paragraph after the note's first line of words when that is a heading, as the lines it
/// covers; and the line under the title that says what goes there, when that line is empty and nothing below it
/// has words.
({List<Line> lines, Line? hint}) leadOf(EditorState state) {
  final title = firstWordsLine(state);
  if (title == null || !_title.hasMatch(title.text)) return (lines: const <Line>[], hint: null);
  var n = title.number + 1;
  while (n <= state.doc.lines && state.doc.line(n).text.trim().isEmpty) {
    n += 1;
  }
  if (n > state.doc.lines) {
    // Nothing under the title yet: the line under it, where the caret goes after Enter, says what goes there.
    return (lines: const <Line>[], hint: title.number < state.doc.lines ? state.doc.line(title.number + 1) : null);
  }
  final lines = <Line>[];
  for (; n <= state.doc.lines; n += 1) {
    final line = state.doc.line(n);
    if (line.text.trim().isEmpty || _notProse.hasMatch(line.text)) break;
    lines.add(line);
  }
  return (lines: lines, hint: null);
}

final Decoration _leadMark = Decoration.line(className: 'cm-lead');

DecorationSet _leads(EditorState state) {
  final lead = leadOf(state);
  final hint = lead.hint;
  if (hint != null) return Decoration.set(<Range<Decoration>>[_leadMark.range(hint.from), Decoration.widget(widget: const HintWidget(leadHint, ''), side: 1).range(hint.from)], true);
  return Decoration.set(<Range<Decoration>>[for (final line in lead.lines) _leadMark.range(line.from)]);
}

final LookSheet _leadTheme = LookSheet('editor/openHeading.ts', <LookRule>[
  // A step up from the words, the kit's xl over its lg, in the second ink.
  // '.cm-line.cm-lead': { fontSize: 'calc(var(--app-body) * 1.2)', lineHeight: '1.4',
  //   color: 'var(--app-ink-2, var(--glacier-text))' }
  LookRule('cm-lead', classes: 3, (p, e) {
    p
      ..fontSize = e.body * 1.2
      ..lineHeight = 1.4
      ..color = e.t.color('app-ink-2');
  }),
]);

final Extension _leadLine = Extension.list(<Extension>[
  ViewPlugin.define<_Docs>((view) => _Docs(view, _leads), decorations: (value) => value.decorations),
  baseTheme(_leadTheme),
]);

/// A reading note's lead line under its title, and what it says while it is empty.
Extension leadLine() => _leadLine;
