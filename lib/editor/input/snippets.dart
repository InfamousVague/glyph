/// Snippets as they are typed (Matt, 2026-10-27: "build ... snippets"; lib/core/snippets.dart says what a snippet
/// is): a trigger, `;sig`, followed by a space, Enter or Tab becomes the snippet's words, as one step that Undo takes
/// back to the trigger as it was typed.
///
/// - **A space** reaches the editor as typed text, from a phone's keyboard and a Mac's alike (ime.dart), so it is
///   caught by a transaction filter: the transaction that types it is swapped for one that writes the snippet over
///   the trigger and the space after it. Keyboards commit a word with its space in one change (Gboard's "sig" for
///   "sig "), so what is asked is that the change ends with a space at the caret, not that it is a space alone.
/// - **Enter and Tab** are keys (keymap.dart), bound above everything else. Enter writes the snippet and then what
///   Enter would have done there (a list goes on), in the one step. Tab only writes the snippet: it is the key that
///   says "expand", and a tab after the words is never what was meant.
/// - **Where the words place the caret** (`{cursor}`), the key that called the snippet is taken by it: the caret
///   goes where the person is to write, and a space or a new line there would be in the way.
///
/// Not inside code (a fence, an indented block, a code span), where `;sig` is what it says, and not in the note's
/// front matter, whose lines are YAML. Not while the keyboard is still composing: only what it commits.
///
/// The snippets are asked for each time a trigger may have been typed ([snippetExpansion]'s `snippets`), so a snippet
/// added in Settings works in a note already open, and no other editor is made for it.
library;

import '../../core/preferences.dart' show Snippet;
import '../../core/snippets.dart';
import '../commands/commands.dart' show KeyBinding, insertNewlineAndIndent;
import '../commands/markdown_commands.dart' show insertNewlineContinueMarkup;
import '../commands/syntax_tree.dart';
import '../state/change.dart';
import '../state/history.dart' show isolateHistory;
import '../state/selection.dart';
import '../state/state.dart';
import '../syntax/tree.dart' show SyntaxNode;
import '../view/extended.dart' show frontMatter;
import 'keymap.dart' show editorKeymap;

/// Code, where a trigger is only what it says.
const Set<String> _code = <String>{'FencedCode', 'CodeBlock', 'InlineCode', 'CodeText', 'CodeMark', 'CodeInfo'};

/// The user event a snippet's step is written with: CodeMirror's for a completion taken.
const String snippetEvent = 'input.complete';

/// Whether [at] is somewhere a trigger is only words: code, or the front matter.
bool _onlyWords(EditorState state, int at) {
  final front = frontMatter(state.doc);
  if (front != null) {
    final line = state.doc.lineAt(at).number;
    if (line >= front.from && line <= front.to) return true;
  }
  for (SyntaxNode? node = syntaxTree(state).resolveInner(at, 1); node != null; node = node.parent) {
    if (_code.contains(node.name)) return true;
  }
  return false;
}

/// The trigger that ends just before [at] in [state], and its snippet; null where there is none, or where it is only
/// words.
({int from, int to, Snippet snippet})? snippetTriggerAt(EditorState state, int at, List<Snippet> snippets) {
  if (snippets.isEmpty) return null;
  final line = state.doc.lineAt(at);
  final found = triggerBefore(line.text.substring(0, at - line.from), snippets);
  if (found == null) return null;
  final from = line.from + found.from;
  if (_onlyWords(state, from)) return null;
  return (from: from, to: at, snippet: found.snippet);
}

/// What writing [found]'s snippet over its trigger makes, at [now]: the change, in [state]'s document; where the words
/// end after it; and where the caret goes, or null where the words place no caret.
({ChangeSet changes, int end, int? caret}) _written(EditorState state, ({int from, int to, Snippet snippet}) found, DateTime now) {
  final made = expandSnippet(found.snippet.text, now);
  final changes = ChangeSet.of(ChangeSpec(from: found.from, to: found.to, insert: made.text), state.doc.length);
  return (changes: changes, end: found.from + made.text.length, caret: placesCaret(found.snippet) ? found.from + made.caret : null);
}

/// The step that writes a snippet: its own in the history on both sides, so Undo takes it back to the trigger and no
/// typing after it joins it.
TransactionSpec _step(ChangeSet changes, int caret) => TransactionSpec(
      changes: changes,
      selection: EditorSelection.single(caret),
      userEvent: snippetEvent,
      annotations: isolateHistory.of('full'),
      scrollIntoView: true,
    );

/// Whether what a transaction put in ends with a space where the caret is: a keyboard's space, alone or committing
/// the word before it.
bool _endsWithSpaceAtCaret(Transaction tr) {
  final head = tr.newSelection.main;
  if (!head.empty) return false;
  var ends = false;
  tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) {
    final text = inserted.toString();
    if (toB == head.head && text.endsWith(' ')) ends = true;
  });
  return ends;
}

/// A transaction that typed a space after a trigger, as the one that writes the snippet there instead; the
/// transaction itself otherwise.
Object snippetOnSpace(Transaction tr, List<Snippet> snippets, DateTime now) {
  if (!tr.docChanged || !tr.isUserEvent('input.type') || tr.isUserEvent('input.type.compose') || snippets.isEmpty) return tr;
  if (!_endsWithSpaceAtCaret(tr)) return tr;
  // The line's words read first, so the new state (and its tree) is only made where a trigger is there at all.
  final space = tr.newSelection.main.head;
  final line = tr.newDoc.lineAt(space);
  if (space - 1 < line.from || triggerBefore(line.text.substring(0, space - 1 - line.from), snippets) == null) return tr;
  final after = tr.state;
  final found = snippetTriggerAt(after, space - 1, snippets);
  if (found == null) return tr;
  final written = _written(after, found, now);
  final changes = tr.changes.compose(written.changes);
  // The space stays after the words, unless the words say where the caret goes.
  final caret = written.caret;
  if (caret != null) {
    final dropSpace = ChangeSet.of(ChangeSpec(from: written.end, to: written.end + 1), written.changes.newLength);
    return _step(changes.compose(dropSpace), caret);
  }
  return _step(changes, written.end + 1);
}

/// Tab after a trigger: the snippet, and nothing else.
bool _expandOnTab(StateCommandTarget target, List<Snippet> snippets, DateTime now) {
  final state = target.state;
  final main = state.selection.main;
  if (!main.empty || state.readOnly) return false;
  final found = snippetTriggerAt(state, main.head, snippets);
  if (found == null) return false;
  final written = _written(state, found, now);
  target.dispatch(state.update(_step(written.changes, written.caret ?? written.end)));
  return true;
}

/// Enter after a trigger: the snippet, then what Enter does at its end (a list goes on), as one step.
bool _expandOnEnter(StateCommandTarget target, List<Snippet> snippets, DateTime now) {
  final state = target.state;
  final main = state.selection.main;
  if (!main.empty || state.readOnly) return false;
  final found = snippetTriggerAt(state, main.head, snippets);
  if (found == null) return false;
  final written = _written(state, found, now);
  if (written.caret != null) {
    target.dispatch(state.update(_step(written.changes, written.caret!)));
    return true;
  }
  final first = state.update(TransactionSpec(changes: written.changes, selection: EditorSelection.single(written.end)));
  Transaction? enter;
  final there = StateCommandTarget(first.state, (tr) => enter = tr);
  if (!insertNewlineContinueMarkup(there)) insertNewlineAndIndent(there);
  final made = enter;
  if (made == null) {
    target.dispatch(state.update(_step(written.changes, written.end)));
  } else {
    target.dispatch(state.update(_step(written.changes.compose(made.changes), made.newSelection.main.head)));
  }
  return true;
}

/// Snippets in a note: [snippets] is asked each time a trigger may have been typed (the preferences' list, in the
/// app), and [clock] for the moment `{date}` and `{time}` are; the device's own when left out.
Extension snippetExpansion(List<Snippet> Function() snippets, {DateTime Function()? clock}) {
  DateTime now() => (clock ?? DateTime.now)();
  return Extension.list(<Extension>[
    EditorState.transactionFilter.of((tr) => snippetOnSpace(tr, snippets(), now())),
    Prec.highest(editorKeymap.of(<KeyBinding>[
      KeyBinding(key: 'Enter', run: (target) => _expandOnEnter(target, snippets(), now())),
      KeyBinding(key: 'Tab', run: (target) => _expandOnTab(target, snippets(), now())),
    ])),
  ]);
}
