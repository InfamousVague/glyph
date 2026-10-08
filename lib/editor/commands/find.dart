/// Find and replace in a note: the matches, which one is current, and the edits. A port of `src/app/editor/find.ts`.
/// The bar that drives it is the find piece's (docs/STAGE4.md, K), opened from the note's settings sheet or from a
/// selection's press-and-hold menu.
///
/// Plain text, case forgiven: the words are a note's, not code, and a person looking for "friday" means "Friday"
/// too. Every match is marked in the note, the current one printed in reverse like a selection; replacing all is
/// one change, so one undo takes it back.
///
/// What differs:
/// - the field is the state alone: the web's `provide`s the marks (`cm-findMatch`, `cm-findCurrent`) and comes with
///   their theme, which are the view's to draw from [findOf]; [findExtension] is the field;
/// - the web's commands take the view and dispatch, then `reveal` the current match with
///   `EditorView.scrollIntoView(match.from, {y: 'center'})`. These take the state and answer the transactions in the
///   order to dispatch them; the scroll is the view's, to make after them from [currentMatch]: [search] and [step]
///   answer one transaction (step null with no matches), [replaceOne] two (the change, then the search again past
///   what was written), [replaceAll] one and how many, [endSearch] one.
library;

import '../state/change.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/text.dart';

/// One place the query is (`Match`).
class FindMatch {
  const FindMatch(this.from, this.to);

  final int from;
  final int to;

  @override
  bool operator ==(Object other) => other is FindMatch && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'FindMatch($from-$to)';
}

/// What is searched for, where it is, and which match is current (`FindState`).
class FindState {
  const FindState({required this.query, required this.matches, required this.current});

  final String query;
  final List<FindMatch> matches;

  /// The current match's index, or -1 when there is none.
  final int current;

  FindState _with({List<FindMatch>? matches, int? current}) =>
      FindState(query: query, matches: matches ?? this.matches, current: current ?? this.current);
}

const FindState _empty = FindState(query: '', matches: <FindMatch>[], current: -1);

/// Sets what is searched for; `near` picks the first match at or after that position as current.
final StateEffectType<({String query, int? near})> setFind = StateEffect.define<({String query, int? near})>();

/// Makes match `index` current.
final StateEffectType<int> _pick = StateEffect.define<int>();

/// Every place `query` is in `doc` (a `String` or a [Doc]), case forgiven, never overlapping.
List<FindMatch> matchesIn(Object doc, String query) {
  if (query.isEmpty) return const <FindMatch>[];
  final text = (doc is String ? doc : (doc as Doc).toString()).toLowerCase();
  final needle = query.toLowerCase();
  final out = <FindMatch>[];
  for (var at = text.indexOf(needle); at >= 0; at = at + needle.length > text.length ? -1 : text.indexOf(needle, at + needle.length)) {
    out.add(FindMatch(at, at + needle.length));
  }
  return out;
}

int _nearest(List<FindMatch> matches, int pos) {
  if (matches.isEmpty) return -1;
  final index = matches.indexWhere((m) => m.to > pos);
  return index >= 0 ? index : 0;
}

final StateField<FindState> _findState = StateField.define<FindState>(
  create: (_) => _empty,
  update: (value, tr) {
    var next = value;
    for (final effect in tr.effects) {
      final set = setFind.cast(effect);
      if (set != null) {
        final matches = matchesIn(tr.state.doc, set.value.query);
        next = FindState(query: set.value.query, matches: matches, current: _nearest(matches, set.value.near ?? 0));
      } else if (effect.isOf(_pick)) {
        final index = effect.value as int, length = next.matches.length;
        next = next._with(current: length > 0 ? ((index % length) + length) % length : -1);
      }
    }
    if (tr.docChanged && next.query.isNotEmpty && identical(next, value)) {
      // The words changed under the search: found again, current kept as near where it was.
      final was = next.current >= 0 && next.current < next.matches.length ? next.matches[next.current] : null;
      final matches = matchesIn(tr.state.doc, next.query);
      next = next._with(matches: matches, current: _nearest(matches, was != null ? tr.changes.mapPos(was.from) : 0));
    }
    return next;
  },
);

/// The search's field, for an editor that can be searched.
Extension findExtension() => _findState;

/// The search as it stands; empty in a state without [findExtension].
FindState findOf(EditorState state) => state.fieldOrNull(_findState) ?? _empty;

/// The current match, which the view brings into view (centred) after a search, a step or a replacement; null
/// when there is none.
FindMatch? currentMatch(EditorState state) {
  final find = findOf(state);
  return find.current >= 0 && find.current < find.matches.length ? find.matches[find.current] : null;
}

/// Searches for `query`, current at or after the caret.
Transaction search(EditorState state, String query) =>
    state.update(TransactionSpec(effects: setFind.of((query: query, near: state.selection.main.from))));

/// The next match (or the previous, with `by` -1), wrapping round. Null when there are no matches.
Transaction? step(EditorState state, int by) {
  final find = findOf(state);
  if (find.matches.isEmpty) return null;
  return state.update(TransactionSpec(effects: _pick.of(find.current + by)));
}

/// Replaces the current match and moves on to the next: the change, then the search again from past what was
/// written, so its own words are not found and replaced again. Empty when there is no current match.
List<Transaction> replaceOne(EditorState state, String replacement) {
  final match = currentMatch(state);
  if (match == null) return const <Transaction>[];
  final query = findOf(state).query;
  final after = match.from + replacement.length;
  final change = state.update(
    TransactionSpec(changes: ChangeSpec(from: match.from, to: match.to, insert: replacement), userEvent: 'input.replace'),
  );
  return <Transaction>[change, change.state.update(TransactionSpec(effects: setFind.of((query: query, near: after))))];
}

/// Replaces every match in one change, so one undo takes it all back. Answers how many were replaced, and the
/// transaction (null for none).
({Transaction? tr, int count}) replaceAll(EditorState state, String replacement) {
  final matches = findOf(state).matches;
  if (matches.isEmpty) return (tr: null, count: 0);
  final tr = state.update(
    TransactionSpec(
      changes: <ChangeSpec>[for (final m in matches) ChangeSpec(from: m.from, to: m.to, insert: replacement)],
      userEvent: 'input.replace.all',
    ),
  );
  return (tr: tr, count: matches.length);
}

/// Ends the search: no marks, and the caret on what was current, so the note picks up where the search left it.
Transaction endSearch(EditorState state) {
  final match = currentMatch(state);
  return state.update(
    TransactionSpec(
      effects: setFind.of((query: '', near: null)),
      selection: match != null ? EditorSelection.single(match.from, match.to) : null,
    ),
  );
}
