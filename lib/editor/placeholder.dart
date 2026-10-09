/// CodeMirror's `placeholder(words)` (@codemirror/view, placeholder.ts): words drawn where the first line would be
/// while the document is empty, in `.cm-placeholder { color: var(--glacier-text-subtle) }` (Editor.tsx's theme).
/// They are a widget after the caret's place, so the caret stands before them, and they take no press: a tap on
/// them is a tap on the empty line.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import 'editor.dart';
import 'view/line.dart' show EditorRunScope;

class PlaceholderWidget extends EditorWidget {
  const PlaceholderWidget(this.words);

  final String words;

  @override
  bool eq(PlaceholderWidget other) => other.words == words;

  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) {
    final style = EditorRunScope.maybeOf(context)?.look.style ?? DefaultTextStyle.of(context).style;
    return ExcludeSemantics(child: Text(words, softWrap: false, style: style.copyWith(color: context.tokens.color('glacier-text-subtle'))));
  }
}

/// The words an empty document shows (`placeholder` in Editor.tsx).
Extension placeholder(String words) => EditorViewLike.decorations.compute(
      <Object>[docDependency],
      (state) => state.doc.length > 0 ? Decoration.none : Decoration.set(<Range<Decoration>>[Decoration.widget(widget: PlaceholderWidget(words), side: 1).range(0)]),
    );
