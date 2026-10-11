import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/placeholder.dart';

/// CodeMirror's `placeholder`: a widget at the document's start while it is empty, and nothing once it has a letter
/// (lib/editor/placeholder.dart).
void main() {
  List<PlaceholderWidget> shown(EditorState state) {
    final found = <PlaceholderWidget>[];
    for (final source in state.facet(EditorViewLike.decorations)) {
      if (source is! DecorationSet) continue;
      final cursor = source.iter();
      while (cursor.value != null) {
        final widget = cursor.value!.spec.widget;
        if (widget is PlaceholderWidget) {
          expect(cursor.from, 0);
          found.add(widget);
        }
        cursor.next();
      }
    }
    return found;
  }

  test('an empty document shows the words, and one with a letter does not', () {
    var state = EditorState.create(doc: '', extensions: placeholder('Write something.'));
    expect(shown(state).single.words, 'Write something.');
    state = state.update(TransactionSpec(changes: ChangeSpec(from: 0, insert: 'a'))).state;
    expect(shown(state), isEmpty);
    state = state.update(TransactionSpec(changes: ChangeSpec(from: 0, to: 1))).state;
    expect(shown(state), hasLength(1));
  });

  test('the words take no press, so a tap on them is a tap on the empty line', () {
    expect(const PlaceholderWidget('a').eq(const PlaceholderWidget('a')), isTrue);
    expect(const PlaceholderWidget('a').eq(const PlaceholderWidget('b')), isFalse);
  });
}
