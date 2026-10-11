// Code in a note, in the editor: the classes on every character of whole notes against what the web editor's own
// parser and highlighter give them (fixtures/documents.json, tool/code_fixtures.mjs), and the work a keystroke
// costs, counted (`CodeStats`), which is the same on a busy machine as on an idle one.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/code/code_highlight.dart';
import 'package:ghost_md/editor/code/work.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

/// The classes glyphHighlight.ts hands out: what the fixtures hold, and so what is read off the view.
const Set<String> highlightClasses = <String>{
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'strong', 'em', 'strike', 'code', 'link', 'url', 'quote', 'list', 'hr', 'codeInfo', 'taskMarker', //
  'codeKeyword', 'codeMacro', 'codeMeta', 'codeString', 'codeComment', 'codeType', 'codeProperty', 'codeName', 'codeLiteral', 'codePunctuation', 'mark',
};

/// The highlighter's classes on each character of the view's note, from every mark over it.
List<Set<String>> classesOf(EditorView view) {
  final doc = view.state.doc;
  final out = <Set<String>>[for (var i = 0; i < doc.length; i++) <String>{}];
  for (final source in view.state.facet(EditorViewLike.decorations)) {
    EditorViewLike.resolveDecorations(source, view).between(0, doc.length, (from, to, value) {
      final name = value is MarkDecoration ? value.spec.className : null;
      if (name == null) return null;
      for (final cls in name.split(' ')) {
        if (!highlightClasses.contains(cls)) continue;
        for (var i = from; i < to; i++) {
          out[i].add(cls);
        }
      }
      return null;
    });
  }
  return out;
}

EditorView viewOf(String doc, {bool whole = true}) {
  final view = EditorView(wholeDocument: whole, state: EditorState.create(doc: doc, extensions: noteExtensions()));
  addTearDown(view.destroy);
  return view;
}

int get tokenised => CodeStats.started + CodeStats.resumed;

void insert(EditorView view, int at, String text) => view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, insert: text)));

void main() {
  // A view asks the painting layer for its caches as it is made.
  TestWidgetsFlutterBinding.ensureInitialized();
  int? apply, slice;
  late int always;
  late Duration pause;
  setUp(() {
    apply = CodeWorkBudget.apply;
    slice = CodeWorkBudget.slice;
    always = CodeWorkBudget.always;
    pause = CodeWorkBudget.pause;
    // Every block read as it is drawn: what is counted and compared is not a matter of the clock.
    CodeWorkBudget.apply = null;
  });
  tearDown(() {
    CodeWorkBudget.apply = apply;
    CodeWorkBudget.slice = slice;
    CodeWorkBudget.always = always;
    CodeWorkBudget.pause = pause;
  });

  group('a whole note has the web\'s classes on every character', () {
    final documents = (jsonDecode(File('test/editor/code/fixtures/documents.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    for (final document in documents) {
      test(document['file'] as String, () {
        final doc = document['doc'] as String;
        final runs = (document['runs'] as List).cast<Object>();
        final theirs = <Set<String>>[for (var i = 0; i < doc.length; i++) <String>{}];
        for (var i = 0; i < runs.length; i += 3) {
          for (var at = runs[i] as int; at < (runs[i + 1] as int); at++) {
            theirs[at].addAll((runs[i + 2] as String).split(' '));
          }
        }
        final mine = classesOf(viewOf(doc));
        final wrong = <String>[];
        for (var i = 0; i < doc.length; i++) {
          if (mine[i].length == theirs[i].length && mine[i].containsAll(theirs[i])) continue;
          // The whole stretch that differs the same way, said once.
          var end = i + 1;
          while (end < doc.length && mine[end].join(' ') == mine[i].join(' ') && theirs[end].join(' ') == theirs[i].join(' ')) {
            end++;
          }
          wrong.add('$i-$end ${jsonEncode(doc.substring(i, end))}: here {${mine[i].join(' ')}}, the web {${theirs[i].join(' ')}}');
          i = end - 1;
        }
        expect(wrong.take(20).join('\n'), '');
      });
    }
  });

  group('what a keystroke costs', () {
    const doc = 'Words before.\n\n```js\nconst a = 1;\nfunction f(x) { return x + a; }\n```\n\nWords between, with <b>a tag</b>.\n\n```python\ndef f(x):\n    return x\n```\n\nWords after.\n';

    test('a letter outside every block reads no block; a caret\'s move is not looked at', () {
      final view = viewOf(doc);
      expect(classesOf(view)[doc.indexOf('const')], <String>{'codeKeyword'});
      CodeStats.reset();
      insert(view, 3, 'x');
      insert(view, view.state.doc.length, 'more');
      expect(tokenised, 0, reason: 'typing in the prose');
      expect(CodeStats.read, 0);
      final before = view.state.facet(EditorViewLike.decorations).map((source) => EditorViewLike.resolveDecorations(source, view)).toList();
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.toString().indexOf('const') + 2)));
      final after = view.state.facet(EditorViewLike.decorations).map((source) => EditorViewLike.resolveDecorations(source, view)).toList();
      expect(tokenised, 0, reason: 'the caret moved into a block');
      expect(after.length, before.length);
      // The very sets the highlighters had: nothing was built again for the caret.
      var kept = 0;
      for (var i = 0; i < after.length; i++) {
        if (identical(after[i], before[i])) kept++;
      }
      expect(kept, greaterThanOrEqualTo(2), reason: 'the note\'s highlighter and the code\'s keep their sets');
      // The line with the tag in it: its HTML is the same few letters, read once and kept.
      insert(view, view.state.doc.toString().indexOf('Words between') + 1, 'y');
      expect(tokenised, 0, reason: 'typing beside a tag whose letters did not change');
    });

    test('a letter in a block reads that block, once, and no other', () {
      final view = viewOf(doc);
      CodeStats.reset();
      insert(view, doc.indexOf('const a') + 6, 'b');
      expect(tokenised, 1);
      expect(classesOf(view)[view.state.doc.toString().indexOf('def')], <String>{'codeKeyword'});
      CodeStats.reset();
      insert(view, view.state.doc.toString().indexOf('return x\n') + 8, 'y');
      expect(tokenised, 1);
      // And again for the next letter: once.
      CodeStats.reset();
      insert(view, view.state.doc.toString().indexOf('def f') + 4, ' ');
      expect(tokenised, 1);
    });

    test('a letter typed outside the blocks on screen makes none of their runs again; one typed in a block, that block\'s', () {
      // The runs of colour a view shows are kept in a set that moves with the note. A change that did not touch
      // a block leaves the block's runs in it: they are shifted, a chunk of the set at a time, and not one of
      // them is made again or looked at.
      const note = 'Before.\n\n```js\nconst a = 1;\nlet b = "x";\n```\n\nA plain line.\n\n```python\ndef f(x):\n    return x + 1\n```\n\nAfter.\n';
      CodeStats.reset();
      final view = viewOf(note);
      final all = CodeStats.drawn;
      expect(all, greaterThan(12), reason: 'both blocks\' runs, made as the view was');
      CodeStats.reset();
      insert(view, 3, 'x');
      insert(view, view.state.doc.toString().indexOf('plain'), 'y');
      insert(view, view.state.doc.toString().indexOf('After'), 'z');
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, to: 2)));
      expect(CodeStats.drawn, 0);
      expect(tokenised, 0);
      expect(classesOf(view), classesOf(viewOf(view.state.doc.toString())), reason: 'and they are where a view made from nothing has them');
      // A letter in the first block: its runs are made again, the second block's are not.
      CodeStats.reset();
      viewOf('```js\nconst ab = 1;\nlet b = "x";\n```\n');
      final one = CodeStats.drawn;
      CodeStats.reset();
      insert(view, view.state.doc.toString().indexOf('const a') + 7, 'b');
      expect(CodeStats.drawn, one);
      expect(one, lessThan(all));
      expect(classesOf(view), classesOf(viewOf(view.state.doc.toString())));
    });

    test('whatever is typed, the runs kept and patched are the runs a view made from nothing has', () {
      // Two hundred changes by chance in a note of fences, tags and plain lines: a letter, a line, a fence's
      // mark or a tag put in, a stretch taken out. After each the view's classes on every character are held to
      // those of a view made of the same note from nothing.
      var text = 'Intro with <b>bold</b> and <i>slant</i>.\n\n```js\nconst a = 1; // one\nlet b = `t\${a}`;\n```\n\n> A quote.\n>\n> ```css\n> a > b { color: red; }\n> ```\n\n<div class="x">\n  <p>html</p>\n</div>\n\n```python\ndef f(x):\n    return x + 1\n```\n\n- item `code` <span>s</span>\n\n```\nplain\n```\n\nEnd.\n';
      const pieces = <String>['x', ' ', '\n', '\n\n', '```', '```js\n', '<b>', '</b>', '<', '>', '"', '/*', '# ', '> ', 'a = 1;', '`', '<!--', '-->'];
      final random = Random(11);
      final view = viewOf(text);
      CodeStats.reset();
      for (var step = 0; step < 200; step++) {
        final at = random.nextInt(text.length + 1);
        if (random.nextInt(4) == 0 && at < text.length) {
          final end = min(text.length, at + 1 + random.nextInt(8));
          view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, to: end)));
          text = text.substring(0, at) + text.substring(end);
        } else {
          final piece = pieces[random.nextInt(pieces.length)];
          insert(view, at, piece);
          text = text.substring(0, at) + piece + text.substring(at);
        }
        expect(view.state.doc.toString(), text);
        final fresh = viewOf(text);
        final here = classesOf(view), there = classesOf(fresh);
        for (var i = 0; i < text.length; i++) {
          if (here[i].length != there[i].length || !here[i].containsAll(there[i])) {
            fail('step $step: at $i (${jsonEncode(text.substring(max(0, i - 20), min(text.length, i + 20)))}) the view has ${here[i]}, a view made from nothing ${there[i]}');
          }
        }
        fresh.destroy();
      }
    });

    test('a fence nothing reads, and one with no language, are never read', () {
      final view = viewOf('```nosuchlanguage\nx = 1\n```\n\n```\nplain\n```\n');
      CodeStats.reset();
      insert(view, view.state.doc.toString().indexOf('x = 1'), 'y');
      insert(view, view.state.doc.toString().indexOf('plain'), 'y');
      expect(tokenised, 0);
      final classes = classesOf(view), text = view.state.doc.toString();
      // No language, or one the pack does not know: the one colour of code. (A language the pack knows and
      // nothing here reads would be in the code's own ink, as the web draws a block whose language is still on
      // its way; there is none a fence can name.)
      expect(classes[text.indexOf('yx = 1')], <String>{'code'});
      expect(classes[text.indexOf('yplain')], <String>{'code'});
    });
  });

  group('a long block', () {
    // Five thousand lines of JavaScript, some 170,000 characters.
    final long = StringBuffer('Before.\n\n```js\n');
    for (var i = 0; i < 5000; i++) {
      long.writeln('const value$i = compute($i, "text $i"); // line $i');
    }
    long.write('```\n\nAfter.\n');
    final doc = long.toString();

    test('is read as far as the screen shows, and a letter typed in it reads on from the letter', () {
      CodeStats.reset();
      final view = viewOf(doc, whole: false);
      // Sixty lines on screen: what is read is those, not the block.
      expect(tokenised, 1);
      expect(CodeStats.read, lessThan(6000), reason: 'the block is ${doc.length} characters');
      final first = doc.indexOf('const value0');
      expect(classesOf(view)[first], <String>{'codeKeyword'});

      CodeStats.reset();
      insert(view, doc.indexOf('const value40 ') + 11, 'x');
      expect(tokenised, 1);
      expect(CodeStats.resumed, 1, reason: 'taken up from a checkpoint before the letter, not from the first line');
      expect(CodeStats.read, lessThan(4000));
      final text = view.state.doc.toString();
      expect(classesOf(view)[text.indexOf('const valuex40')], <String>{'codeKeyword'});
      expect(classesOf(view)[text.indexOf('valuex40')], <String>{'codeName'});

      // A letter in the prose above moves the block and reads none of it.
      CodeStats.reset();
      insert(view, 2, 'x');
      expect(tokenised, 0);
      expect(CodeStats.read, 0);
    });

    test('is read on in slices after it is drawn, and drawn again as the screen gains colour', () async {
      // No reading as it is drawn at all, and every slice as long as it likes: the first slice reads the screen.
      CodeWorkBudget.apply = 0;
      CodeWorkBudget.always = 0;
      CodeWorkBudget.slice = null;
      CodeWorkBudget.pause = Duration.zero;
      final view = viewOf(doc, whole: false);
      final first = doc.indexOf('const value0');
      final lateLine = doc.indexOf('const value50 ');
      expect(classesOf(view)[lateLine], isEmpty, reason: 'not read yet: the code\'s own ink');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(classesOf(view)[first], <String>{'codeKeyword'});
      expect(classesOf(view)[lateLine], <String>{'codeKeyword'});
    });
  });
}
