// A to-do's place reminder (lib/reminders/place_syntax.dart, docs/INTEGRATIONS.md §3): `📍 [Target](geo:…)` read as a
// field like `⏰`, written where a reminder goes (before Tasks' run), left out of the words, drawn as a chip with the
// place's name, and a tap on the chip offering Change place and Remove. Remind me at a place is the sheet the editor
// is given (`placePicker`), offered while the Place reminders plugin is on (`placeRemindersOn`); without either,
// nothing offers it, and a `📍` already written is still read and drawn.

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/task_fields.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/field_chips.dart';
import 'package:ghost_md/editor/items/field_items.dart';
import 'package:ghost_md/editor/items/field_menu.dart';
import 'package:ghost_md/editor/items/task_fields.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/reminders/place_host.dart' show placeRemindersOn;
import 'package:ghost_md/reminders/place_syntax.dart';
import 'package:ghost_md/reminders/tick_item.dart' show itemWords;

const String target = '[Target](geo:35.7002,-81.3084)';
final PlaceMark targetMark = PlaceMark.at(35.7002, -81.3084, name: 'Target');

late EditorView view;

EditorView editor(String doc, {PlacePicker? picker}) {
  view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(more: <Extension>[taskFields(), fieldsToday.of(() => '2026-10-17'), fieldsLocale.of('en-GB'), if (picker != null) placePicker.of(picker)]),
    ),
  );
  addTearDown(view.destroy);
  return view;
}

String line(int n) => view.state.doc.line(n).text;

List<FieldItem> rows() => fieldItems(view, 1, const PlacePage(), onClose: () {}, today: '2026-10-17')!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    useStored(MemoryStored());
    placeRemindersOn.value = true;
  });
  tearDown(() => placeRemindersOn.value = false);

  group('reading', () {
    test('the pin and the link are one field, its value the link as written', () {
      final spans = fieldsIn('- [ ] Buy diapers 📍 $target');
      expect(spans, hasLength(1));
      expect((spans.single.kind, spans.single.key, spans.single.value), (FieldKind.tasks, 'place', target));
      expect(spans.single.from, '- [ ] Buy diapers '.length);
      expect(placeOn('- [ ] Buy diapers 📍 $target'), targetMark);
      expect(placeOn('- [ ] Buy diapers 📍 $target')!.name, 'Target');
    });

    test('with the variation selector, no space, in either case of geo, and the coordinates alone', () {
      expect(placeOn('- [ ] Buy 📍️ $target'), targetMark);
      expect(placeOn('- [ ] Buy 📍$target'), targetMark);
      expect(placeOn('- [ ] Buy 📍 [Target](GEO:35.7002,-81.3084)'), targetMark);
      final bare = placeOn('- [ ] Buy 📍 [35.7002, -81.3084](geo:35.7002,-81.3084)')!;
      expect((bare.tag.place, bare.name), (null, '35.7002, -81.3084'));
      expect(placeOn('- [ ] Buy 📍 [Hickory](geo:35.73,-81.34)')!.tag.rough, isTrue, reason: 'two decimals read back as rough');
    });

    test('not without the pin, off the Earth, or in code', () {
      expect(placeOn('- [ ] Buy diapers $target'), isNull);
      expect(placeOn('- [ ] Buy 📍 [Nowhere](geo:95.0,10.0)'), isNull);
      expect(placeOn('- [ ] Buy `📍 $target`'), isNull);
      expect(placeOn('- [ ] Buy 📍 Target'), isNull);
    });

    test('a person in the place’s name is the place’s words, not an assignee', () {
      final spans = fieldsIn('- [ ] Meet 📍 [Sam @sam’s](geo:35.7002,-81.3084) @jo');
      expect([for (final span in spans) span.key], ['place', 'assignee']);
      expect(fieldsOf('- [ ] Meet 📍 [Sam @sam’s](geo:35.7002,-81.3084) @jo').assignees, ['jo']);
    });

    test('the item’s words leave it out, as Done finds the item by them', () {
      expect(withoutFields('Buy diapers 📍 $target 📅 2026-10-18'), 'Buy diapers');
      expect(itemWords('- [ ] Buy diapers 📍 $target'), 'Buy diapers');
    });
  });

  group('writing', () {
    test('at the end of the words, the link as a place line writes it', () {
      expect(withPlace('- [ ] Buy diapers', targetMark), '- [ ] Buy diapers 📍 $target');
      expect(PlaceMark.at(35.70021, -81.30839, name: 'Target ]x[').written, '📍 [Target x](geo:35.7002,-81.3084)', reason: 'four decimals, and no bracket in the name');
    });

    test('before the run of Tasks’ fields, after a person and a reminder’s place in that run', () {
      expect(withPlace('- [ ] Buy diapers @sam ⏫ 📅 2026-10-18', targetMark), '- [ ] Buy diapers @sam 📍 $target ⏫ 📅 2026-10-18');
      expect(withPlace('- [ ] Buy diapers ⏰ 2026-10-18 09:00 📅 2026-10-18', targetMark), '- [ ] Buy diapers 📍 $target ⏰ 2026-10-18 09:00 📅 2026-10-18');
      // Tasks still reads the due day after it, and a date set later goes after the run.
      expect(fieldsOf('- [ ] Buy diapers @sam 📍 $target ⏫ 📅 2026-10-18').due, '2026-10-18');
      expect(withField('- [ ] Buy diapers 📍 $target', 'due', '2026-10-18'), '- [ ] Buy diapers 📍 $target 📅 2026-10-18');
    });

    test('before the tail: a block link stays the line’s last', () {
      expect(withPlace('- [ ] Buy diapers ^diapers', targetMark), '- [ ] Buy diapers 📍 $target ^diapers');
    });

    test('changed where it is, a second taken off, and taken off with its space', () {
      final costco = PlaceMark.at(35.7301, -81.3399, name: 'Costco');
      expect(withPlace('- [ ] Buy diapers 📍 $target 📅 2026-10-18', costco), '- [ ] Buy diapers 📍 ${costco.link} 📅 2026-10-18');
      expect(withPlace('- [ ] Buy diapers 📍 $target 📍 ${costco.link}', costco), '- [ ] Buy diapers 📍 ${costco.link}');
      expect(withPlace('- [ ] Buy diapers 📍 $target 📅 2026-10-18', null), '- [ ] Buy diapers 📅 2026-10-18');
      expect(withPlace('- [ ] Buy diapers', null), '- [ ] Buy diapers');
    });
  });

  group('the chip', () {
    test('a pin and the place’s name, quiet, opening the place’s page', () {
      final span = fieldsIn('- [ ] Buy diapers 📍 $target').single;
      final look = chipLook(span, today: '2026-10-17', done: false)!;
      expect((look.text, look.icon, look.tone, look.label, look.menu, look.key), ('Target', Lucide.mapPin, 'quiet', 'Remind me at Target', FieldMenu.place, 'place'));
      expect(pageOf(look), const PlacePage());
      expect(chipLook(span, today: '2026-10-17', done: true)!.tone, 'done');
    });

    test('warned: the mark a warning’s, the reason said, the rest as it was', () {
      final look = chipLook(fieldsIn('Buy 📍 $target').single, today: '2026-10-17', done: false)!;
      final warned = warnedPlace(look);
      expect((warned.text, warned.icon, warned.tone, warned.menu), ('Target', Lucide.triangleAlert, 'quiet', FieldMenu.place));
      expect(warned.label, startsWith('Remind me at Target. Ghost.md can’t tell when you arrive'));
    });

    test('drawn in place of the pin and the link, beside the other fields’ chips', () {
      editor('- [ ] Buy diapers @sam 📍 $target 📅 2026-10-18');
      final drawn = <(String, String)>[];
      for (final set in view.decorations) {
        set.between(0, view.state.doc.length, (from, to, value) {
          final widget = value.widget;
          if (widget is FieldWidget) drawn.add((view.state.sliceDoc(from, to), widget.look.label));
          return null;
        });
      }
      expect(drawn, [('@sam', 'Assigned to sam'), ('📍 $target', 'Remind me at Target'), ('📅 2026-10-18', 'Due Sunday 18 October')]);
    });
  });

  group('the page', () {
    test('Remove takes it off; Change place only where the phone watches places', () {
      editor('- [ ] Buy diapers 📍 $target 📅 2026-10-18');
      expect([for (final row in rows()) row.label], ['Remove']);
      rows().single.onPress(Rect.zero);
      expect(line(1), '- [ ] Buy diapers 📅 2026-10-18');
    });

    test('Change place opens the sheet with the line’s place, and writes the one picked', () async {
      final asked = <(int, PlaceMark?)>[];
      final costco = PlaceMark.at(35.7301, -81.3399, name: 'Costco');
      editor('- [ ] Buy diapers 📍 $target', picker: (number, current) async {
        asked.add((number, current));
        return costco;
      });
      expect([for (final row in rows()) row.label], ['Change place', 'Remove']);
      rows().first.onPress(Rect.zero);
      await pumpEventQueue();
      expect(asked, [(1, targetMark)]);
      expect(line(1), '- [ ] Buy diapers 📍 ${costco.link}');
    });

    test('Remind me at a place writes the place picked at the end of the words; put away, nothing', () async {
      PlaceMark? answer = targetMark;
      editor('- [ ] Buy diapers 📅 2026-10-18', picker: (number, current) async => answer);
      expect(await pickLinePlace(view, 1), isTrue);
      expect(line(1), '- [ ] Buy diapers 📍 $target 📅 2026-10-18');
      answer = null;
      expect(await pickLinePlace(view, 1), isFalse);
      expect(line(1), '- [ ] Buy diapers 📍 $target 📅 2026-10-18');
    });

    test('with no sheet, nothing is offered and nothing is picked', () async {
      editor('- [ ] Buy diapers');
      expect(placesOffered(view), isFalse);
      expect(await pickLinePlace(view, 1), isFalse);
    });

    test('with the plugin off, nothing is offered, and a place written is still a chip with Remove', () async {
      placeRemindersOn.value = false;
      var asked = 0;
      editor('- [ ] Buy diapers 📍 $target', picker: (number, current) async {
        asked += 1;
        return targetMark;
      });
      expect(placesOffered(view), isFalse);
      expect(await pickLinePlace(view, 1), isFalse);
      expect(asked, 0);
      expect([for (final row in rows()) row.label], ['Remove']);
      expect(chipLook(fieldsIn(line(1)).single, today: '2026-10-17', done: false)!.text, 'Target');
    });
  });
}
