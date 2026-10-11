// What the command tests share: a detached "view", which is a state and a dispatch, as the web's tests make one
// with `new EditorView({state})`, and the parser's answers they read back.
import 'package:ghost_md/editor/commands/syntax_tree.dart';
import 'package:ghost_md/editor/state/history.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/syntax/tree.dart';

/// A state that moves on with each transaction dispatched to it.
class TestView implements StateCommandTarget {
  TestView(this.state);

  /// A view over `doc` with the caret at `anchor`, or `anchor` to `head` selected.
  factory TestView.of(String doc, [int anchor = 0, int? head, List<Extension> extensions = const <Extension>[]]) =>
      TestView(EditorState.create(doc: doc, selection: EditorSelection.single(anchor, head), extensions: Extension.list(extensions)));

  @override
  EditorState state;

  /// Every transaction dispatched, in order.
  final List<Transaction> dispatched = <Transaction>[];

  @override
  void dispatch(Dispatchable? tr) {
    if (tr == null) return;
    final Transaction made = switch (tr) {
      Transaction() => tr,
      TransactionSpec() => state.update(tr),
    };
    dispatched.add(made);
    state = made.state;
  }

  /// Runs a command against this view.
  bool run(StateCommand command) => command(this);

  String get text => state.doc.toString();

  /// The main selection's text.
  String get selected => state.sliceDoc(state.selection.main.from, state.selection.main.to);

  int get head => state.selection.main.head;

  bool undo_() => undo(this);
  bool redo_() => redo(this);
}

/// The node names a state's document parses to, in document order.
List<String> nodeNames(Tree tree) {
  final names = <String>[];
  tree.iterate(enter: (node) {
    names.add(node.name);
  });
  return names;
}

/// The nodes around `pos`, innermost first, as the app's parser reads `doc`.
List<String> chainAt(String doc, int pos, [int side = 1]) {
  final state = EditorState.create(doc: doc);
  final chain = <String>[];
  for (SyntaxNode? node = syntaxTree(state).resolveInner(pos, side); node != null; node = node.parent) {
    chain.add(node.name);
  }
  return chain;
}
