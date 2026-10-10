/// Sums: a line that starts with `=` works itself out. Ports `src/app/editor/sums.ts`.
///
///     = 450 + 120 * 2          → 690
///     - = $1,200 / 3           → $400
///
/// The answer is drawn after the line in quiet ink and is never written into the note. The arithmetic is
/// `lib/core/sums.dart`'s, where a query's totals read it too.
///
/// What differs: `.cm-sumAnswer::before { content: "→ " }` is part of the widget's own words.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../core/sums.dart';
import '../editor.dart';
import '../view/line.dart' show EditorRunScope;
import '../view/syntax_tree.dart';

export '../../core/sums.dart' show answer, sumOnLine;

class AnswerWidget extends EditorWidget {
  const AnswerWidget(this.text);

  final String text;

  @override
  bool eq(AnswerWidget other) => other.text == text;

  @override
  bool takesPointer(_) => false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final look = EditorRunScope.maybeOf(context)?.look;
    final size = look?.fontSize ?? t.len('app-body');
    // '.cm-sumAnswer': { marginInlineStart: '0.6em', color: 'var(--app-ink-3, currentColor)',
    //   fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap', userSelect: 'none' }
    final style = (look?.style ?? t.textAt(size)).copyWith(color: t.color('app-ink-3'), fontFeatures: <FontFeature>[...?look?.style.fontFeatures, const FontFeature.tabularFigures()]);
    return Semantics(
      label: 'equals $text',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: 0.6 * size),
          child: Text('→ $text', style: style, softWrap: false, textScaler: TextScaler.noScaling),
        ),
      ),
    );
  }
}

final RegExp _notWords = RegExp(r'Code|FrontMatter|Comment|Math');

/// The answer of each line that is a sum, kept for every line of a document (`LineFact`). A sum is written with
/// an equals sign.
final LineFact<String> _answers = LineFact<String>((text) => text.contains('=') ? sumOnLine(text)?.answer : null);

DecorationSet _decorate(EditorViewLike view) {
  final builder = RangeSetBuilder<Decoration>();
  final doc = view.state.doc;
  final tree = syntaxTree(view.state);
  for (final range in view.visibleRanges) {
    for (final line in _answers.between(doc, doc.lineAt(range.from).number, doc.lineAt(range.to).number)) {
      if (_notWords.hasMatch(tree.resolveInner(line.from, 1).name)) continue;
      builder.add(line.to, line.to, Decoration.widget(widget: AnswerWidget(line.fact), side: 1));
    }
  }
  return builder.finish();
}

class _Sums extends PluginValue {
  _Sums(EditorViewLike view) : decorations = _decorate(view);

  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    if (update.docChanged || update.viewportChanged || !identical(syntaxTree(update.startState), syntaxTree(update.state))) decorations = _decorate(update.view);
  }
}

final Extension _sums = ViewPlugin.define<_Sums>(_Sums.new, decorations: (value) => value.decorations);

/// `= 450 + 120` answered after its line.
Extension sums() => _sums;
