/// Claude's suggested edits, drawn in the note (docs/CLAUDE_LIVE.md, "Suggest mode"): what it would put in is
/// underlined in the author's colour, what it would take out struck through and dimmed, a replacement both, the old
/// words first. The marks round them and the author's note are hidden off the caret's lines and shown as typed on
/// them, as the other marks are. A tap on one offers Keep and Revert after it; a line over the note says how many
/// there are, with Keep all and Revert all. Reading them is critic.dart's.
///
/// The note is the whole truth (docs/CLAUDE_LIVE.md): a suggestion is its words, not a mark beside them, so Keep
/// and Revert are ordinary edits, one undo each, and the note reads the same anywhere (another markdown app shows
/// the CriticMarkup itself). Keep writes the new words without the marks; Revert the old ones.
///
/// Where this differs from the AI's own changes (lib/editor/ai/ai_changes.dart), whose pills these are:
/// - The pills are not after every change, which would be a row of them down a note Claude went through: they come
///   on a tap, after the suggestion tapped, and go with a tap elsewhere or any edit.
/// - A tap off the caret's lines is the suggestion's alone, so the caret stays where it was and the marks stay
///   hidden; on the caret's line, where the marks are shown to be edited, the caret goes where the finger went too.
/// - A read-only note (a notebook's own words) draws them all and offers nothing: no pills, and the line over it
///   only says how many there are.
library;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../ai/ai_changes.dart' show AiPill;
import '../editor.dart';
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../media/inline_box.dart';
import '../view/editor_view.dart' show EditorView;
import '../view/lines.dart' show selectedLines;
import '../view/line.dart' show EditorRunScope;
import 'critic.dart';

export 'critic.dart';

/// The colour a suggestion wears when nothing says whose it is: a workspace hue (lib/core/workspaces.dart), the
/// green of an insertion in most tracked changes.
const String suggestionHue = 'moss';

/// Which workspace hue an author's suggestions wear (`ink`, `moss`, …); null for [suggestionHue].
typedef SuggestionHue = String? Function(String? author);

/// The suggestion whose Keep and Revert are showing, by where it starts; [_none] for none.
final StateEffectType<int> _openAt = StateEffect.define<int>(map: (at, changes) => at == _none ? _none : changes.mapPos(at));

const int _none = -1;

final StateField<int> _open = StateField.define<int>(
  create: (_) => _none,
  update: (value, tr) {
    for (final effect in tr.effects) {
      final told = _openAt.cast(effect);
      if (told != null) return told.value;
    }
    // Any edit puts them away: what they were offered for has changed, or gone.
    return tr.docChanged ? _none : value;
  },
);

/// Where the suggestion whose Keep and Revert are showing starts, for a test or a screen that asks; null for none.
int? openSuggestion(EditorState state) {
  final at = state.fieldOrNull(_open) ?? _none;
  return at == _none ? null : at;
}

/// Shows Keep and Revert after the suggestion starting at `from`, or with null puts them away.
void openSuggestionAt(StateCommandTarget view, int? from) {
  if (openSuggestion(view.state) == from) return;
  view.dispatch(TransactionSpec(effects: _openAt.of(from ?? _none)));
}

// ---- the words -----------------------------------------------------------------------------------------------------

final Decoration _hidden = Decoration.replace();
final Decoration _mark = Decoration.mark(className: 'cm-suggestMark');
final Decoration _gone = Decoration.mark(className: 'cm-suggestGone');
final Map<String, Decoration> _added = <String, Decoration>{};
Decoration _addedIn(String hue) => _added[hue] ??= Decoration.mark(className: 'cm-suggestAdd', attributes: <String, String>{'data-hue': hue});

DecorationSet _decorate(EditorViewLike view, SuggestionHue? hueOf) {
  final state = view.state;
  final all = suggestionsOf(state.doc);
  if (all.isEmpty) return Decoration.none;
  // While the note is being written, the lines the caret or a selection touches keep their marks, as typed.
  final active = view.hasFocus && !state.readOnly ? selectedLines(state) : const <int>{};
  final open = state.readOnly ? null : openSuggestion(state);
  final doc = state.doc;
  final ranges = <Range<Decoration>>[];
  for (final one in all) {
    for (final mark in one.marks) {
      ranges.add((active.contains(doc.lineAt(mark.from).number) ? _mark : _hidden).range(mark.from, mark.to));
    }
    if (one.oldTo > one.oldFrom) ranges.add(_gone.range(one.oldFrom, one.oldTo));
    if (one.newTo > one.newFrom) ranges.add(_addedIn(hueOf?.call(one.author) ?? suggestionHue).range(one.newFrom, one.newTo));
    if (open == one.from) ranges.add(Decoration.widget(widget: SuggestionPillsWidget(one.from), side: 1).range(one.to));
  }
  return Decoration.set(ranges, true);
}

class _Suggestions extends PluginValue {
  _Suggestions(EditorViewLike view, this.hueOf) : decorations = _decorate(view, hueOf);

  final SuggestionHue? hueOf;
  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    if (update.docChanged ||
        update.selectionSet ||
        update.focusChanged ||
        update.startState.readOnly != update.state.readOnly ||
        openSuggestion(update.startState) != openSuggestion(update.state)) {
      decorations = _decorate(update.view, hueOf);
    }
  }
}

/// A press on a suggestion: off the caret's lines it opens its Keep and Revert and is its alone, so the caret stays
/// put; on them it opens them and the caret goes there too. Anywhere else it puts them away.
bool _pressed(PointerDownEvent event, EditorViewLike view) {
  final state = view.state;
  if (state.readOnly) return false;
  final pos = view.posAtCoords(event.position);
  final one = pos == null ? null : suggestionAt(state.doc, pos);
  if (one == null) {
    if (openSuggestion(state) != null) openSuggestionAt(view, null);
    return false;
  }
  final onCaretLine = view.hasFocus && selectedLines(state).contains(state.doc.lineAt(pos!).number);
  if (openSuggestion(state) == one.from) return false;
  openSuggestionAt(view, one.from);
  return !onCaretLine;
}

// ---- Keep and Revert, after a suggestion ---------------------------------------------------------------------------

/// Keep and Revert, after the suggestion starting at [from].
class SuggestionPillsWidget extends EditorWidget {
  const SuggestionPillsWidget(this.from);

  final int from;

  @override
  bool eq(SuggestionPillsWidget other) => other.from == from;

  @override
  Widget build(BuildContext context) => SuggestionPills(from);
}

/// `.cm-suggestPills`: the AI's pair of pills (`.cm-aiPills`), for one suggestion.
class SuggestionPills extends StatelessWidget {
  const SuggestionPills(this.from, {super.key});

  final int from;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    final scope = EditorRunScope.maybeOf(context);
    final body = t.len('app-body');
    final around = scope?.look.style ?? t.textAt(body, color: t.color('app-ink'));
    final em = scope?.look.fontSize ?? body;
    // As '.cm-aiPills': { display: 'inline-flex', gap: '0.35em', marginInlineStart: '0.6em',
    //   verticalAlign: '0.15em', whiteSpace: 'nowrap' }
    return Semantics(
      container: true,
      label: 'This suggestion',
      child: InlineRaise(
        by: em * 0.15,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: layoutUnit(em * 0.6)),
          child: Row(
            key: const ValueKey<String>('cm-suggestPills'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AiPill(word: 'Keep', keep: true, around: around, em: em, onPress: view == null ? null : () => settleSuggestion(view, from, keep: true)),
              SizedBox(width: layoutUnit(em * 0.35)),
              AiPill(word: 'Revert', keep: false, around: around, em: em, onPress: view == null ? null : () => settleSuggestion(view, from, keep: false)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- the line over the note ----------------------------------------------------------------------------------------

/// What the line over the note says: "Claude suggested 2 changes", or "2 suggested changes" where they name no one
/// author.
String suggestedWords(List<Suggestion> all) {
  final count = all.length == 1 ? '1 change' : '${all.length} changes';
  final author = soleAuthor(all);
  return author == null ? (all.length == 1 ? '1 suggested change' : '${all.length} suggested changes') : '$author suggested $count';
}

/// The line over the note while it holds suggestions: how many, and Keep all and Revert all where it can be edited.
class SuggestionBarWidget extends EditorWidget {
  const SuggestionBarWidget(this.words, this.actions);

  final String words;

  /// Whether Keep all and Revert all are offered: the note can be edited.
  final bool actions;

  @override
  bool eq(SuggestionBarWidget other) => other.words == words && other.actions == actions;

  @override
  double get estimatedHeight => 34;

  @override
  Widget build(BuildContext context) => SuggestionBar(words: words, actions: actions);
}

/// `.cm-suggestBar`: a quiet line in the note's face, a step smaller, a rule under it.
class SuggestionBar extends StatelessWidget {
  const SuggestionBar({super.key, required this.words, required this.actions});

  final String words;
  final bool actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final view = EditorViewScope.maybeOf(context);
    final look = view is EditorView ? view.look : null;
    final base = look?.line(LookElement(null)).base;
    final size = base?.fontSize ?? t.len('app-body');
    final around = base?.style ?? t.textAt(size, color: t.color('app-ink'));
    final em = size * 0.86;
    final said = around.copyWith(fontSize: em, color: t.color('app-ink-3'), decoration: TextDecoration.none, height: 1.4);
    return Semantics(
      container: true,
      label: words,
      child: Padding(
        key: const ValueKey<String>('cm-suggestBar'),
        padding: EdgeInsets.only(bottom: layoutUnit(size * 0.5)),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('app-rule')))),
          child: Padding(
            padding: EdgeInsets.only(bottom: layoutUnit(size * 0.4)),
            child: Wrap(
              spacing: layoutUnit(em * 0.5),
              runSpacing: layoutUnit(em * 0.3),
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                ExcludeSemantics(child: Text(words, key: const ValueKey<String>('cm-suggestBarWords'), style: said, textScaler: TextScaler.noScaling)),
                if (actions && view != null) ...<Widget>[
                  AiPill(word: 'Keep all', keep: true, around: around, em: size, onPress: () => settleAllSuggestions(view, keep: true)),
                  AiPill(word: 'Revert all', keep: false, around: around, em: size, onPress: () => settleAllSuggestions(view, keep: false)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

DecorationSet _bar(EditorState state) {
  final all = suggestionsOf(state.doc);
  if (all.isEmpty) return Decoration.none;
  return Decoration.set(<Range<Decoration>>[
    Decoration.widget(widget: SuggestionBarWidget(suggestedWords(all), !state.readOnly), block: true, side: -1).range(0),
  ]);
}

// ---- the looks -----------------------------------------------------------------------------------------------------

Tokens _hued(Tokens t, String? hue) => t.child(attrs: <String, String>{'hue': hue ?? suggestionHue});

final LookSheet _theme = LookSheet('editor/suggestions', <LookRule>[
  // What would go in: in the author's colour, underlined, over a faint wash of it.
  // '.cm-suggestAdd': { color: 'color-mix(in oklch, var(--app-space) 70%, var(--app-ink))',
  //   textDecoration: 'underline', backgroundColor: 'color-mix(in oklch, var(--app-space) 12%, transparent)' }
  LookRule('cm-suggestAdd', classes: 2, (p, e) {
    final hue = _hued(e.t, p.element?.attrs['data-hue']);
    final ink = hue.colorOf('color-mix(in oklch, var(--app-space) 70%, var(--app-ink))', current: p.color);
    final wash = hue.colorOf('color-mix(in oklch, var(--app-space) 12%, transparent)', current: p.color);
    p
      ..color = ink
      ..underline = true
      ..lineThrough = false
      ..background = (_) => wash;
  }),
  // A replacement's `{~~old~>new~~}` is a strikethrough's to the parser, whose span is inside this one: the new
  // words are not struck.
  // '.cm-suggestAdd *': { textDecoration: 'inherit' }
  LookRule.under('cm-suggestAdd', classes: 92, (p, e) => p.lineThrough = false),
  // What would go: struck through and dimmed, as the AI's gone words are.
  // '.cm-suggestGone': { color: 'var(--app-ink-4)', textDecoration: 'line-through',
  //   textDecorationColor: 'color-mix(in oklch, var(--app-ink) 45%, transparent)' }
  LookRule('cm-suggestGone', classes: 2, (p, e) {
    p
      ..color = e.t.color('app-ink-4')
      ..lineThrough = true;
  }),
  // The marks and the author's note, on the caret's line: quiet, as a mark is.
  // '.cm-suggestMark, .cm-suggestMark *': { color: 'var(--app-ink-4)', textDecoration: 'none' }
  for (final under in const <bool>[false, true])
    LookRule('cm-suggestMark', classes: under ? 92 : 2, under: under, (p, e) {
      p
        ..color = e.t.color('app-ink-4')
        ..underline = false
        ..lineThrough = false;
    }),
]);

/// Suggested edits in CriticMarkup, drawn with Keep and Revert. `hueOf` says which workspace hue an author's
/// insertions wear; none, or a null answer, is [suggestionHue].
Extension suggestions({SuggestionHue? hueOf}) => Extension.list(<Extension>[
  _open,
  ViewPlugin.define<_Suggestions>(
    (view) => _Suggestions(view, hueOf),
    decorations: (value) => value.decorations,
    eventHandlers: const EditorEventHandlers(mouseDown: _pressed),
  ),
  // A block over the note must come from the state (view/blocks.dart).
  EditorViewLike.decorations.compute(<Object>[docDependency, EditorState.readOnlyFacet], _bar),
  baseTheme(_theme),
]);
