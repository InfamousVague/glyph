// What the press-and-hold menu does with a to-do's fields (lib/editor/items/field_menu.dart):
// `src/app/editor/fieldMenu.test.ts`, case for case.
//
// What is asked differently: `pickDay` opens whatever the `dayPicker` facet says, where the page made a hidden
// `<input type="date">` and called its `showPicker`. So the two cases of "a day picked" hold the same ends - the
// picker is opened once, on the day the field has, and the day chosen is handed back; nothing is handed back for
// none - through a picker of the test's own. "Keeps one picker at a time" is the app's calendar's to keep, and is
// left out; that no picker means nothing is opened is added in its place.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/field_menu.dart';
import 'package:ghost_md/editor/view/editor_view.dart';

EditorView open(String doc, {bool readOnly = false, List<Extension> more = const <Extension>[]}) {
  final view = EditorView(wholeDocument: true, state: EditorState.create(doc: doc, extensions: Extension.list(<Extension>[history(), EditorState.readOnlyFacet.of(readOnly), ...more])));
  addTearDown(view.destroy);
  return view;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what the menu offers', () {
    test('offers today, tomorrow and next week’s Monday', () {
      expect(dayChoices('2026-10-01'), const <DayChoice>[DayChoice('today', 'Today', '2026-10-01'), DayChoice('tomorrow', 'Tomorrow', '2026-10-02'), DayChoice('next-week', 'Next week', '2026-10-05')]);
      expect(dayChoices('2026-10-04').last.day, '2026-10-05');
    });

    test('offers fields on a list item, and on nothing else', () {
      expect(takesFields('- [ ] Fix it'), isTrue);
      expect(takesFields('2. Step'), isTrue);
      expect(takesFields('- Bullet'), isTrue);
      expect(takesFields('Just words'), isFalse);
      expect(takesFields('# Heading'), isFalse);
    });

    test('knows the people a note names, each once, and none in code', () {
      expect(peopleIn('- [ ] One @sam\n- [ ] Two @Sam @matt\nSee `@jo` and @@@kim@@\n- [ ] Three @sam-ortiz'), <String>['sam', 'matt', 'sam-ortiz']);
    });
  });

  group('the edits', () {
    test('sets, changes and takes off a field as one edit each', () {
      final on = open('Top\n- [ ] Fix the login loop ^login-loop');
      expect(setLineField(on, 2, 'due', '2026-10-03'), isTrue);
      expect(on.state.doc.line(2).text, '- [ ] Fix the login loop 📅 2026-10-03 ^login-loop');
      expect(setLineField(on, 2, 'priority', 'high'), isTrue);
      expect(on.state.doc.line(2).text, '- [ ] Fix the login loop ⏫ 📅 2026-10-03 ^login-loop');
      expect(lineFields(on, 2)?.due, '2026-10-03');
      expect(lineFields(on, 2)?.priority, 'high');
      undo(on);
      expect(on.state.doc.line(2).text, '- [ ] Fix the login loop 📅 2026-10-03 ^login-loop');
      expect(setLineField(on, 2, 'due', null), isTrue);
      expect(on.state.doc.line(2).text, '- [ ] Fix the login loop ^login-loop');
    });

    test('changes only what differs, so the caret elsewhere on the line stays put', () {
      final on = open('- [ ] Fix it 📅 2026-10-03');
      on.dispatch(TransactionSpec(selection: EditorSelection.single(8)));
      setLineField(on, 1, 'due', '2026-10-09');
      expect(on.state.doc.toString(), '- [ ] Fix it 📅 2026-10-09');
      expect(on.state.selection.main.head, 8);
    });

    test('puts people on and takes them off', () {
      final on = open('- [ ] Fix it ⏫');
      setLinePerson(on, 1, 'Sam', true);
      expect(on.state.doc.toString(), '- [ ] Fix it @Sam ⏫');
      expect(setLinePerson(on, 1, 'sam', true), isFalse);
      setLinePerson(on, 1, 'sam', false);
      expect(on.state.doc.toString(), '- [ ] Fix it ⏫');
    });

    test('leaves the at sign where a new person goes, with the caret after it', () {
      final on = open('- [ ] Fix it #bug ⏫ 📅 2026-10-03');
      expect(startPerson(on, 1), isTrue);
      expect(on.state.doc.toString(), '- [ ] Fix it #bug @ ⏫ 📅 2026-10-03');
      expect(on.state.selection.main.head, '- [ ] Fix it #bug @'.length);
    });

    test('writes nothing on a page that cannot be edited, or a line that is not there', () {
      final on = open('- [ ] Fix it', readOnly: true);
      expect(setLineField(on, 1, 'due', '2026-10-03'), isFalse);
      expect(startPerson(on, 1), isFalse);
      final other = open('- [ ] Fix it');
      expect(setLineField(other, 4, 'due', '2026-10-03'), isFalse);
      expect(setLineField(other, 1, 'due', 'Friday'), isFalse);
      expect(lineFields(other, 9), isNull);
    });
  });

  group('a day picked', () {
    test('opens the phone’s own picker on its day, and hands back the day chosen', () async {
      final shown = <(Offset, String?)>[];
      final on = open(
        '- [ ] Fix it',
        more: <Extension>[
          dayPicker.of((at, current) async {
            shown.add((at, current));
            return '2026-10-09';
          }),
        ],
      );
      final picked = <String>[];
      await pickDay(on, const Offset(10, 20), '2026-10-03', picked.add);
      expect(shown, <(Offset, String?)>[(const Offset(10, 20), '2026-10-03')]);
      expect(picked, <String>['2026-10-09']);
    });

    test('keeps one picker at a time, and hands back nothing for a cleared field', () async {
      final shown = <String?>[];
      final on = open(
        '- [ ] Fix it',
        more: <Extension>[
          dayPicker.of((at, current) async {
            shown.add(current);
            return null;
          }),
        ],
      );
      final picked = <String>[];
      await pickDay(on, Offset.zero, null, picked.add);
      // Words that are not a day are no day to open on.
      await pickDay(on, Offset.zero, 'Friday', picked.add);
      expect(shown, <String?>[null, null]);
      expect(picked, isEmpty);
      // With no picker, nothing is opened and nothing handed back.
      await pickDay(open('- [ ] Fix it'), Offset.zero, null, picked.add);
      expect(picked, isEmpty);
    });
  });
}
