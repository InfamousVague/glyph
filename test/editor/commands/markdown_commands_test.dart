// Enter and Backspace in a list or a quote, held to @codemirror/lang-markdown itself: the fixture is what the real
// commands did under Node, with the app's language, at every caret of 259 documents
// (tool/markdown_command_fixtures.mjs), and the Dart ports must do the same: the same answer, the same changes
// (as CodeMirror writes a change set down), the same selection.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/commands/markdown_commands.dart';
import 'package:ghost_md/editor/state/change.dart';
import 'package:ghost_md/editor/state/selection.dart';
import 'package:ghost_md/editor/state/state.dart';

import 'support.dart';

final Map<String, dynamic> fixture =
    jsonDecode(File('test/editor/commands/fixtures/markdown_commands.json').readAsStringSync()) as Map<String, dynamic>;

final Map<String, Transaction? Function(EditorState)> commands = <String, Transaction? Function(EditorState)>{
  'enter': continueMarkup,
  'enterTight': (state) => continueMarkup(state, nonTightLists: false),
  'backspace': deleteMarkup,
};

EditorState stateOf(String doc, EditorSelection selection) =>
    EditorState.create(doc: doc, selection: selection, extensions: EditorState.allowMultipleSelections.of(true));

/// What a command did, in the fixture's shape: 0, or the changes, the selection's anchors and heads, the main index.
Object shapeOf(String name, Transaction? tr) {
  if (tr == null) return 0;
  expect(tr.scrollIntoView, isTrue);
  expect(tr.annotation(Transaction.userEvent), (fixture['events'] as Map<String, dynamic>)[name]);
  return <Object?>[
    tr.changes.toJson(),
    <int>[for (final r in tr.state.selection.ranges) ...<int>[r.anchor, r.head]],
    tr.state.selection.mainIndex,
  ];
}

/// The document a fixture's answer leaves, for a failure to show words and not a change set.
String docAfter(String doc, Object? result) =>
    result is List ? ChangeSet.fromJson(result[0]).apply(EditorState.create(doc: doc).doc).toString() : doc;

void main() {

  // Missing 9 (docs/PARITY.md): @codemirror/lang-markdown's `pasteURLAsLink`, which the app leaves on
  // (src/app/editor/language.ts `pasteURLAsLink: true`). Read from dist/index.js, since the library's own takes a
  // paste event and a DOM.
  group('an address pasted over a selection', () {
    String? pasted(String doc, int from, int to, String text) {
      final state = EditorState.create(doc: doc, selection: EditorSelection.single(from, to));
      final spec = pasteUrlAsLink(state, text);
      if (spec == null) return null;
      final tr = state.update(spec);
      expect((tr.scrollIntoView, tr.annotation(Transaction.userEvent)), (true, 'input.paste'));
      return tr.state.doc.toString();
    }

    test('makes the selected words a link to it', () {
      expect(pasted('Read the guide first.', 9, 14, 'https://example.com/guide'), 'Read the [guide](https://example.com/guide) first.');
      expect(pasted('Write to Sam.', 9, 12, 'mailto:sam@example.com'), 'Write to [Sam](mailto:sam@example.com).');
      expect(pasted('Chat with Sam.', 10, 13, 'xmpp:sam@example.com'), 'Chat with [Sam](xmpp:sam@example.com).');
      // A bare www is given its scheme.
      expect(pasted('See the site.', 8, 12, 'www.example.com'), 'See the [site](https://www.example.com).');
      // In a list item the words are regular text too.
      expect(pasted('- buy bread\n', 6, 11, 'http://bakery.example'), '- buy [bread](http://bakery.example)\n');
    });

    test('is left to the editor with nothing selected, or words that are no address', () {
      expect(pasted('Read the guide first.', 9, 9, 'https://example.com'), isNull);
      expect(pasted('Read the guide first.', 9, 14, 'example.com'), isNull);
      expect(pasted('Read the guide first.', 9, 14, 'see https://example.com'), isNull);
      expect(pasted('Read the guide first.', 9, 14, ''), isNull);
    });

    test('is left to the editor where the selection is not regular text, or starts or ends something part way', () {
      // Inside code, and inside a link's own words.
      expect(pasted('Run `make guide` now.', 10, 15, 'https://example.com'), isNull);
      expect(pasted('Read [the guide](https://a.example) first.', 10, 15, 'https://example.com'), isNull);
      // From before an emphasis into it, and out of one.
      expect(pasted('Read *the guide* first.', 2, 9, 'https://example.com'), isNull);
      expect(pasted('Read *the guide* first.', 10, 20, 'https://example.com'), isNull);
      // Across two paragraphs.
      expect(pasted('One.\n\nTwo.', 0, 10, 'https://example.com'), isNull);
    });
  });
  final docs = (fixture['docs'] as List<dynamic>).cast<Map<String, dynamic>>();

  test('Markdown is the active language where lang-markdown says it is', () {
    var checked = 0;
    for (final entry in docs) {
      final doc = entry['doc'] as String, active = entry['active'] as String;
      final state = EditorState.create(doc: doc);
      for (var pos = 0; pos <= doc.length; pos++) {
        final got = (markdownActiveAt(state, pos, -1) ? 1 : 0) + (markdownActiveAt(state, pos, 1) ? 2 : 0);
        expect('$got', active[pos], reason: '${jsonEncode(doc)} at $pos');
        checked++;
      }
    }
    expect(checked, greaterThan(5000));
  });

  for (final name in commands.keys) {
    test('$name does what the library does at every caret', () {
      var checked = 0, handled = 0;
      for (final entry in docs) {
        final doc = entry['doc'] as String;
        final expected = entry[name] as List<dynamic>;
        for (var pos = 0; pos <= doc.length; pos++) {
          final tr = commands[name]!(stateOf(doc, EditorSelection.single(pos)));
          final got = shapeOf(name, tr);
          if (jsonEncode(got) != jsonEncode(expected[pos])) {
            fail(
              '$name in ${jsonEncode(doc)} at $pos:\n'
              '  the library: ${jsonEncode(expected[pos])} -> ${jsonEncode(docAfter(doc, expected[pos]))}\n'
              '  the port:    ${jsonEncode(got)} -> ${jsonEncode(tr?.state.doc.toString() ?? doc)}',
            );
          }
          checked++;
          if (tr != null) handled++;
        }
      }
      expect(checked, greaterThan(5000));
      expect(handled, greaterThan(500));
    });
  }

  test('several carets, and ranges, as the library takes them', () {
    final multi = (fixture['multi'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (final c in multi) {
      final doc = c['doc'] as String, name = c['command'] as String;
      final selection = EditorSelection.create(<SelectionRange>[
        for (final r in c['ranges'] as List<dynamic>) EditorSelection.range(r[0] as int, r[1] as int),
      ], c['main'] as int);
      final got = shapeOf(name, commands[name]!(stateOf(doc, selection)));
      expect(jsonEncode(got), jsonEncode(c['result']), reason: '$name in ${jsonEncode(doc)} with ${c['ranges']}');
    }
    expect(multi.length, 48);
  });

  group('as commands', () {
    test('Enter continues a list and Backspace takes a marker whole, each one dispatch', () {
      final view = TestView.of('- milk', 6);
      expect(view.run(insertNewlineContinueMarkup), isTrue);
      expect(view.text, '- milk\n- ');
      expect(view.head, 9);
      expect(view.run(deleteMarkupBackward), isTrue);
      expect(view.text, '- milk\n  ');
      expect(view.run(deleteMarkupBackward), isTrue);
      expect(view.text, '- milk\n');
      expect(view.dispatched.length, 3);
    });

    test('both answer false, and dispatch nothing, in plain words', () {
      final view = TestView.of('plain words', 5);
      expect(view.run(insertNewlineContinueMarkup), isFalse);
      expect(view.run(deleteMarkupBackward), isFalse);
      expect(view.dispatched, isEmpty);
      expect(<String>[for (final b in markdownKeymap) b.key], <String>['Enter', 'Backspace']);
    });
  });
}
