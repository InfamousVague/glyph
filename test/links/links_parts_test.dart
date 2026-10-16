// The pieces of a note's links that are not drawn (lib/links): its length, its outline read from the editor's own
// lines, Copy link to this line, and Link and its Undo on another note's words.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/links/line_link.dart';
import 'package:ghost_md/links/links_panel.dart';
import 'package:ghost_md/links/outline.dart';
import 'package:ghost_md/links/word_count.dart';

EditorView viewOf(String doc, {int caret = 0}) {
  final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, selection: EditorSelection.single(caret), extensions: noteExtensions()));
  addTearDown(view.destroy);
  return view;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the length of a note', () {
    test('its words, its characters and the minutes to read it, the front matter and addresses left out', () {
      final count = countWords("---\ntitle: Trip\n---\n# Trip\n\nDon't forget [the map](https://example.com/a/very/long/path) and **two** coats.");
      expect(count.words, 8);
      expect(count.characters, "# Trip\n\nDon't forget [the map](https://example.com/a/very/long/path) and **two** coats.".replaceAll('\n', '').length);
      expect(count.minutes, 1);
      expect(countWords('').minutes, 0);
      expect(countWords(List.filled(500, 'word').join(' ')).minutes, 3);
      expect(countWords('Ünïcödé wörds — and 42 numbers', whole: false).words, 5);
    });

    test('said plainly, and kept for the body it was counted from', () {
      expect(lengthWords((words: 1204, characters: 6830, minutes: 6)), '1,204 words, 6,830 characters, about 6 minutes to read');
      expect(lengthWords((words: 1, characters: 4, minutes: 1)), '1 word, 4 characters, a minute to read');
      expect(lengthWords((words: 0, characters: 0, minutes: 0)), 'No words yet');
      const body = '# A\n\nSome words here.';
      expect(identical(noteLength(body), noteLength(body)), isTrue);
    });
  });

  group('the outline', () {
    test('every heading by its level, none in a code block or the front matter', () {
      final doc = Doc.ofString('---\ntitle: x\n---\n# Trip\n\n## Packing\n\n```\n# not a heading\n```\n\n### Shoes ###\n\n#nospace\n\n## Coast');
      expect([for (final heading in outlineOf(doc)) (heading.level, heading.text, heading.line)], [(1, 'Trip', 4), (2, 'Packing', 6), (3, 'Shoes', 12), (2, 'Coast', 16)]);
      expect(outlineOf(Doc.ofString('Just words')), isEmpty);
    });
  });

  group('Copy link to this line', () {
    late List<String?> copied;
    setUp(() {
      copied = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String?);
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    test('names a line that has none, one edit to undo, and copies the link to it', () async {
      const doc = '# Trip\n\nThe ferry leaves at nine.\n\nAfter.';
      final view = viewOf(doc, caret: doc.indexOf('ferry'));
      expect(await copyLineLink(view), 'Copied [[Trip#^ferry-leaves-nine]]');
      expect(copied, ['[[Trip#^ferry-leaves-nine]]']);
      expect(view.state.doc.toString(), '# Trip\n\nThe ferry leaves at nine. ^ferry-leaves-nine\n\nAfter.');
      // Asked again, the name is there: nothing more is written.
      expect(lineLink(view), '[[Trip#^ferry-leaves-nine]]');
      expect(view.state.doc.toString(), contains('nine. ^ferry-leaves-nine\n'));
    });

    test('a heading by its words, an item by its own name, and nothing for a blank line or the front matter', () {
      const doc = '---\ntags: x\n---\n# Trip\n\n## Packing\n\n- [ ] Shoes ^shoes\n\n';
      expect(lineLink(viewOf(doc, caret: doc.indexOf('Packing'))), '[[Trip#Packing]]');
      expect(lineLink(viewOf(doc, caret: doc.indexOf('Shoes'))), '[[Trip#^shoes]]');
      expect(lineLink(viewOf(doc, caret: doc.indexOf('# Trip'))), '[[Trip]]');
      expect(lineLink(viewOf(doc, caret: doc.length)), isNull);
      expect(lineLink(viewOf(doc, caret: 5)), isNull);
    });
  });

  group('a mention linked, and taken back', () {
    test('the words made a link as written, only where they are still the name', () {
      const body = '# Diary\n\nThe launch-week photos.';
      final at = body.indexOf('launch-week');
      final linked = linkMention(body, at, at + 'launch-week'.length, 'Launch week');
      expect(linked, '# Diary\n\nThe [[launch-week]] photos.');
      expect(linkMention('# Diary\n\nSomething else now.', at, at + 11, 'Launch week'), isNull);
      expect(unlinkMention(linked!, at, 'launch-week'), body);
      expect(unlinkMention(body, at, 'launch-week'), isNull);
    });
  });
}
