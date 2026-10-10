/// The AI's changes, drawn in the note: what it added washed behind, what it took away struck through where it
/// stood, and a pair of words, Keep and Revert, after each run of changes. The drawing half of
/// `src/app/editor/aiChanges.ts`, and the whole extension, [aiChanges]; the state half is lib/ai/ai_changes.dart
/// (the fields, the effects, Keep and Revert themselves), which this file hands on.
///
/// Matt chose auto-apply with marks over a preview: the model's lines go into the note as they finish
/// (ai/land.dart), and the note itself is always the text as it now reads. So the marks are decorations over that
/// text, never text in it: a mark over the added words, a widget of the old ones (a block above the line for whole
/// lines, inline before the words that came for words within one), and one pair of pills at the end of the last
/// line of each group of neighbouring changes from one run.
///
/// What differs:
/// - The theme's rules are drawn by the widgets themselves, each rule cited where it is drawn, as
///   lib/editor/items/suggestions.dart does for the suggestion pill these are cousins of; `.cm-aiAdded` alone is a
///   stylesheet rule, a wash behind the run and every mark inside it, with square corners where the page rounds
///   them by 3px. `cursor`, `user-select` and the tap highlight have no counterpart.
/// - Words taken out of the middle of a line are a box to each word ([goneWords]: the word and the gap after it),
///   one after the other at the place they stood, so they wrap with the line between words as the page's one span
///   does. A word longer than the line is not broken inside, where the page's would be.
/// - A press on a pill is the pill's alone (`takesPointer`), where the page stopped a pointer, a mouse and a touch
///   press each its own way.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../ai/ai_changes.dart';
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../media/inline_box.dart';
import '../view/editor_view.dart' show EditorView;
import '../view/line.dart' show EditorRunScope;

export '../../ai/ai_changes.dart';

final RegExp _leadingSpace = RegExp(r'^\s+');
final RegExp _wordAndGap = RegExp(r'\S+\s*');
final RegExp _gap = RegExp(r'\s');

/// The words a rewrite took out of a line, in the pieces the line may break between: each word with the gap after
/// it, which is struck with it (`span.textContent = this.text.replace(/^\s+/, '')`, an inline span, which wraps
/// where its words do). The gap is written as spaces that are not let go at a box's end, so the strike runs on
/// across it as it does on the page.
List<String> goneWords(String removed) {
  final text = removed.replaceFirst(_leadingSpace, '');
  final pieces = <String>[for (final piece in _wordAndGap.allMatches(text)) piece.group(0)!.replaceAll(_gap, '\u00A0')];
  return pieces.isEmpty ? <String>[text] : pieces;
}

/// The line a struck-through word is drawn with: `text-decoration: line-through` in `color-mix(in oklch,
/// var(--app-ink, currentColor) 45%, transparent)`.
TextStyle _struck(Tokens t, TextStyle around) => around.copyWith(
      // color: 'var(--app-ink-4, currentColor)'
      color: t.color('app-ink-4'),
      decoration: TextDecoration.lineThrough,
      decorationColor: t.colorOf('color-mix(in oklch, var(--app-ink, currentColor) 45%, transparent)', current: t.color('app-ink-4')),
    );

/// The words that went, struck through: a block above the line for whole lines, or inline before the words that
/// came (`GoneWidget`).
class GoneWidget extends EditorWidget {
  const GoneWidget(this.text, this.block, {this.first = true, this.last = true});

  final String text;
  final bool block;

  /// Within a line, whether this is the first and the last of the pieces the words were drawn in ([goneWords]):
  /// the first says what they are, the last keeps the span's margin from the words that came.
  final bool first;
  final bool last;

  @override
  bool eq(GoneWidget other) => other.text == text && other.block == block && other.first == first && other.last == last;

  @override
  double get estimatedHeight => block ? 26.0 * (text.split('\n').length) : -1;

  @override
  Widget build(BuildContext context) => block ? _GoneBlock(text) : _GoneWords(text, first: first, last: last);
}

/// `.cm-aiGone`: the words a rewrite took out of a line, before the ones that came.
class _GoneWords extends StatelessWidget {
  const _GoneWords(this.text, {required this.first, required this.last});

  final String text;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = EditorRunScope.maybeOf(context);
    final body = t.len('app-body');
    final around = scope?.look.style ?? t.textAt(body, color: t.color('app-ink'));
    final em = scope?.look.fontSize ?? body;
    // '.cm-aiGone': { color: 'var(--app-ink-4, currentColor)', textDecoration: 'line-through',
    //   textDecorationColor: 'color-mix(in oklch, var(--app-ink, currentColor) 45%, transparent)',
    //   marginInlineEnd: '0.3em' }
    final words = ExcludeSemantics(
      child: Padding(
        padding: EdgeInsetsDirectional.only(end: last ? layoutUnit(em * 0.3) : 0),
        // span.textContent = this.text.replace(/^\s+/, '')
        child: InlineWords(first ? text.replaceFirst(_leadingSpace, '') : text, key: const ValueKey<String>('cm-aiGone'), style: _struck(t, around)),
      ),
    );
    // Said once, where the words begin: the pieces after the first are the same span's.
    return first ? Semantics(label: 'Words the AI took out', child: words) : words;
  }
}

/// `.cm-aiGoneBlock`: whole lines the AI took out, above the line they stood before.
class _GoneBlock extends StatelessWidget {
  const _GoneBlock(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    // The face, the size and the leading of the editor it is in (`.cm-scroller`: the note's own face at
    // `--app-body`, `line-height: 1.6`), which a block beside the lines inherits as they do.
    final base = view is EditorView ? view.look?.line(LookElement(null)).base : null;
    final size = base?.fontSize ?? t.len('app-body');
    final around = base?.style ?? t.textAt(size, color: t.color('app-ink'));
    final style = _struck(t, around).copyWith(height: 1.6, leadingDistribution: TextLeadingDistribution.even);
    // '.cm-aiGoneBlock': { color: 'var(--app-ink-4, currentColor)', textDecoration: 'line-through',
    //   textDecorationColor: 'color-mix(in oklch, var(--app-ink, currentColor) 45%, transparent)',
    //   whiteSpace: 'pre-wrap', padding: '0 0 0.1em' }
    return Semantics(
      label: 'Words the AI took out',
      child: ExcludeSemantics(
        child: Padding(
          key: const ValueKey<String>('cm-aiGoneBlock'),
          padding: EdgeInsets.only(bottom: layoutUnit(size * 0.1)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final line in text.split('\n'))
                // '.cm-aiGoneLine': { minHeight: '1em' }; row.textContent = line || ' '
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: size),
                  child: Text(line.isEmpty ? ' ' : line, key: const ValueKey<String>('cm-aiGoneLine'), style: style, softWrap: true),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keep and Revert, at the end of a run of changes (`PillsWidget`).
class PillsWidget extends EditorWidget {
  const PillsWidget(this.ids);

  final List<String> ids;

  @override
  bool eq(PillsWidget other) => other.ids.join(',') == ids.join(',');

  @override
  Widget build(BuildContext context) => AiPills(ids);
}

/// `.cm-aiPills`: the two words, a step smaller than the line and out of its way.
class AiPills extends StatelessWidget {
  const AiPills(this.ids, {super.key});

  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    final scope = EditorRunScope.maybeOf(context);
    final body = t.len('app-body');
    final around = scope?.look.style ?? t.textAt(body, color: t.color('app-ink'));
    final em = scope?.look.fontSize ?? body;
    // '.cm-aiPills': { display: 'inline-flex', gap: '0.35em', marginInlineStart: '0.6em', verticalAlign: '0.15em',
    //   whiteSpace: 'nowrap' }
    return Semantics(
      container: true,
      label: 'This change from the AI',
      child: InlineRaise(
        by: em * 0.15,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: layoutUnit(em * 0.6)),
          child: Row(
            key: const ValueKey<String>('cm-aiPills'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AiPill(word: 'Keep', keep: true, around: around, em: em, onPress: view == null ? null : () => keepChanges(view, ids)),
              SizedBox(width: layoutUnit(em * 0.35)),
              AiPill(word: 'Revert', keep: false, around: around, em: em, onPress: view == null ? null : () => revertChanges(view, ids)),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.cm-aiPill`: one outlined word.
class AiPill extends StatefulWidget {
  const AiPill({super.key, required this.word, required this.keep, required this.around, required this.em, required this.onPress});

  final String word;

  /// `data-act="keep"`: the darker of the two.
  final bool keep;

  /// The style of the line it stands in, and that line's size.
  final TextStyle around;
  final double em;
  final VoidCallback? onPress;

  @override
  State<AiPill> createState() => _AiPillState();
}

class _AiPillState extends State<AiPill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // '.cm-aiPill': { appearance: 'none', display: 'inline-block', padding: '0 0.6em',
    //   border: '1px solid color-mix(in oklch, currentColor 45%, transparent)', borderRadius: '999px',
    //   background: 'transparent', color: 'var(--app-ink-3, currentColor)', font: 'inherit', fontSize: '0.68em',
    //   lineHeight: '1.7' }
    // '.cm-aiPill[data-act="keep"]': { color: 'var(--app-ink, currentColor)',
    //   borderColor: 'color-mix(in oklch, currentColor 70%, transparent)' }
    // '.cm-aiPill:active': { background: 'color-mix(in oklch, currentColor 12%, transparent)' }
    final size = widget.em * 0.68;
    final color = widget.keep ? t.color('app-ink') : t.color('app-ink-3');
    final edge = t.colorOf('color-mix(in oklch, currentColor ${widget.keep ? 70 : 45}%, transparent)', current: color);
    final ground = _pressed ? t.colorOf('color-mix(in oklch, currentColor 12%, transparent)', current: color) : null;
    final style = widget.around.copyWith(fontSize: size, color: color, decoration: TextDecoration.none);
    final pad = layoutUnit(size * 0.6);
    return Semantics(
      button: true,
      label: widget.word,
      onTap: widget.onPress,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onPress,
          child: DecoratedBox(
            key: ValueKey<String>('cm-aiPill-${widget.word.toLowerCase()}'),
            decoration: ShapeDecoration(color: ground, shape: StadiumBorder(side: BorderSide(color: edge))),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad + 1, vertical: 1),
              child: InlineWords(widget.word, style: style, lineHeight: size * 1.7),
            ),
          ),
        ),
      ),
    );
  }
}

final Decoration _added = Decoration.mark(className: 'cm-aiAdded');

DecorationSet _decorate(EditorState state) {
  final changes = state.field(aiChangesField);
  if (changes.isEmpty) return Decoration.none;
  final doc = state.doc;
  final ranges = <Range<Decoration>>[];
  for (final change in changes) {
    if (change.removed.isNotEmpty) {
      if (change.block) {
        ranges.add(Decoration.widget(widget: GoneWidget(change.removed, true), block: true, side: -1).range(doc.lineAt(change.from < doc.length ? change.from : doc.length).from));
      } else {
        // One piece to a word, in the order they stood (ranges at one place keep the order they are given in): the
        // line breaks between them as it does between its own words.
        final words = goneWords(change.removed);
        for (var i = 0; i < words.length; i++) {
          ranges.add(Decoration.widget(widget: GoneWidget(words[i], false, first: i == 0, last: i == words.length - 1), side: -1).range(change.from));
        }
      }
    }
    if (change.to > change.from) ranges.add(_added.range(change.from, change.to));
  }
  for (final group in groupChanges(doc, changes)) {
    ranges.add(Decoration.widget(widget: PillsWidget(group.ids), side: 1).range(doc.lineAt(group.to < doc.length ? group.to : doc.length).to));
  }
  return Decoration.set(ranges, true);
}

final LookSheet _theme = LookSheet('editor/aiChanges.ts', <LookRule>[
  // Added words: a wash of the page's ink behind them, faint enough to read through.
  // '.cm-aiAdded': { backgroundColor: 'color-mix(in oklch, var(--app-ink, currentColor) 11%, transparent)',
  //   borderRadius: '3px', boxDecorationBreak: 'clone' }
  // The wash is the run's own ground, which reaches the marks inside it (a heading's, a list's) as the span's
  // background lies behind its children; its corners are square.
  LookRule('cm-aiAdded', classes: 2, (p, e) {
    final wash = e.t.colorOf('color-mix(in oklch, var(--app-ink, currentColor) 11%, transparent)', current: p.color);
    p.background = (_) => wash;
  }),
]);

/// What [aiChanges] is told (`AiChangesOptions.onMarks`): the marks every time they change, for the note to keep
/// them with it (ai/marks.dart).
typedef OnAiMarks = void Function(List<AiChange> changes);

/// The AI's changes in an editor: the two fields, what is drawn over them, and the note told when its marks change
/// (`aiChanges`).
Extension aiChanges({OnAiMarks? onMarks}) => Extension.list(<Extension>[
      aiChangesState(),
      EditorViewLike.decorations.compute(<Object>[aiChangesField], _decorate),
      baseTheme(_theme),
      if (onMarks != null)
        EditorViewLike.updateListener.of((update) {
          final now = changedMarks(update.startState, update.state);
          if (now != null) onMarks(now);
        }),
    ]);
