import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/playground.dart';
import 'package:ghost_md/editor/editor_widget.dart';

import 'support.dart';

/// `academy/Playground.test.tsx`, case for case. The field under a lesson belongs to the phone's keyboard, not to the
/// screen. A keyboard composes a word and commits it on space; a field whose value is written back while it composes
/// gets the letters committed twice (Matt: "when doing the ## and then hitting space on the academy it shows an
/// extra # and the lesson isn't passed"). So the Playground writes into the field only when the app changed the text
/// (Show me, a new lesson) and never with what was typed.
///
/// Where the page's test counted writes to the textarea's `value`, these count what the field's controller tells its
/// listeners, and look at the keyboard's composing range, which is the thing a write would have thrown away.
void main() {
  setUpAll(loadAppFonts);
  setUp(freshDevice);

  /// The playground alone, holding what it is given: [value] is put down again only when a test says so.
  Future<void> show(WidgetTester tester, {required String value, ValueChanged<String>? onChange, String placeholder = '# Weekend trip'}) =>
      pumpApp(tester, home: Align(alignment: Alignment.topCenter, child: SizedBox(width: 345, child: Playground(value: value, onChange: onChange ?? (_) {}, placeholder: placeholder))));

  TextEditingController controller(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText)).controller;

  /// The field, with every write into it counted from now on.
  List<String> watched(WidgetTester tester) {
    final seen = <String>[];
    final field = controller(tester);
    field.addListener(() => seen.add(field.text));
    return seen;
  }

  group('the Academy’s live page', () {
    testWidgets('hands on what is typed and never writes it back into the field', (tester) async {
      final heard = <String>[];
      await show(tester, value: '', onChange: heard.add);
      // Typed the way a keyboard types: straight into the field, still composing, which the screen then hears.
      await tester.showKeyboard(find.byType(EditableText));
      tester.testTextInput.updateEditingValue(const TextEditingValue(text: '##', selection: TextSelection.collapsed(offset: 2), composing: TextRange(start: 0, end: 2)));
      await tester.pump();
      expect(heard.last, '##');
      final seen = watched(tester);
      // The screen passes the text back down as it would after the change.
      await show(tester, value: '##', onChange: heard.add);
      expect(seen, isEmpty);
      expect(controller(tester).text, '##');
      // The keyboard's word is still its own to commit.
      expect(controller(tester).value.composing, const TextRange(start: 0, end: 2));
      await away(tester);
    });

    testWidgets('writes the text in when the app changes it: Show me, or a new lesson', (tester) async {
      await show(tester, value: '');
      await tester.enterText(find.byType(EditableText), 'weekend');
      await show(tester, value: 'weekend');
      final seen = watched(tester);
      await show(tester, value: '# Weekend trip');
      expect(seen, ['# Weekend trip']);
      expect(controller(tester).text, '# Weekend trip');
      await show(tester, value: '', placeholder: '## The budget');
      expect(controller(tester).text, '');
      // The empty field says the new lesson's example.
      expect(find.text('## The budget'), findsOneWidget);
      await away(tester);
    });

    testWidgets('draws nothing typed as a line saying where it will appear', (tester) async {
      await show(tester, value: '   ');
      expect(find.textContaining('Whatever you type appears here'), findsOneWidget);
      expect(find.byType(Editor), findsNothing);
      await away(tester);
    });
  });

  group('the note the live page shows', () {
    testWidgets('is the note’s own editor, read-only, redrawn as the words change', (tester) async {
      await show(tester, value: 'the **big** tent');
      final view = tester.widget<Editor>(find.byType(Editor)).view;
      expect(view.state.doc.toString(), 'the **big** tent');
      expect(view.state.readOnly, isTrue);
      await show(tester, value: 'the **big** tent\n- [ ] pegs');
      // The same editor, with the words as they are now.
      expect(identical(tester.widget<Editor>(find.byType(Editor)).view, view), isTrue);
      expect(view.state.doc.toString(), 'the **big** tent\n- [ ] pegs');
      await away(tester);
    });

    testWidgets('takes a tap on a choice, and sends the change back for the field above', (tester) async {
      const before = 'Where do we stay?\n- ( ) Tent\n- (x) Cabin';
      final heard = <String>[];
      await show(tester, value: before, onChange: heard.add);
      await settle(tester, 4);
      final view = tester.widget<Editor>(find.byType(Editor)).view;
      // The first choice's box: the three characters `( )` of the second line.
      final at = before.indexOf('( )');
      final from = view.coordsAtPos(at, 1)!, to = view.coordsAtPos(at + 3, -1)!;
      await tester.tapAt(Offset((from.left + to.right) / 2, (from.top + from.bottom) / 2));
      await settle(tester, 4);
      expect(heard, ['Where do we stay?\n- (x) Tent\n- ( ) Cabin']);
      // The screen puts the change in the field, which is the app changing the text.
      await show(tester, value: heard.last, onChange: heard.add);
      expect(controller(tester).text, 'Where do we stay?\n- (x) Tent\n- ( ) Cabin');
      await away(tester);
    });

    testWidgets('takes a tap on a to-do’s box too', (tester) async {
      const before = '- [ ] ring the site';
      final heard = <String>[];
      await show(tester, value: before, onChange: heard.add);
      await settle(tester, 4);
      final view = tester.widget<Editor>(find.byType(Editor)).view;
      final from = view.coordsAtPos(2, 1)!, to = view.coordsAtPos(5, -1)!;
      await tester.tapAt(Offset((from.left + to.right) / 2, (from.top + from.bottom) / 2));
      await settle(tester, 4);
      expect(heard, ['- [x] ring the site']);
      await away(tester);
    });
  });
}
