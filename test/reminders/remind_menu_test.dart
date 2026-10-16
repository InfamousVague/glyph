// A to-do's Remind me (lib/editor/items/field_items.dart, lib/reminders/remind_choices.dart): the times on offer
// counted from a clock of the test's own, the one the line has lit, the phone's calendar and clock for Pick a time,
// Remove, and the reminder's chip on the line. Offered only where the phone reminds: the editor is given its picker.

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/field_chips.dart';
import 'package:ghost_md/editor/items/field_items.dart';
import 'package:ghost_md/editor/items/field_menu.dart';
import 'package:ghost_md/editor/items/task_fields.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/core/task_fields.dart' show fieldsIn;
import 'package:ghost_md/reminders/remind_choices.dart';
import 'package:ghost_md/reminders/reminder_settings.dart';
import 'package:ghost_md/reminders/reminder_syntax.dart';

import '../support/fake_reminders.dart';

/// Thursday 1 October 2026, 10:07 on the phone.
final DateTime now = DateTime(2026, 10, 1, 10, 7);

late EditorView view;

EditorView editor(String doc, {ReminderPicker? picker}) {
  view = EditorView(
    wholeDocument: true,
    state: EditorState.create(
      doc: doc,
      extensions: noteExtensions(more: <Extension>[taskFields(), fieldsToday.of(() => '2026-10-01'), fieldsNow.of(() => now), fieldsLocale.of('en-GB'), if (picker != null) reminderPicker.of(picker)]),
    ),
  );
  addTearDown(view.destroy);
  return view;
}

String line(int n) => view.state.doc.line(n).text;

List<FieldItem> rows() => fieldItems(view, 1, const RemindPage(), onClose: () {}, today: '2026-10-01')!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    useStored(MemoryStored());
    forgetReminderSettings();
  });
  tearDown(forgetReminderSettings);

  group('the times on offer', () {
    test('an hour on to the next five minutes, this evening, and tomorrow at Settings’ time', () {
      expect(remindChoices(now, const ReminderSettings()), const [
        RemindChoice('hour', 'In an hour', 'Remind me at 11:10', ReminderTime('2026-10-01', 11, 10)),
        RemindChoice('evening', 'This evening', 'Remind me this evening at 18:00', ReminderTime('2026-10-01', 18, 0)),
        RemindChoice('tomorrow', 'Tomorrow, 9:00', 'Remind me tomorrow at 9:00', ReminderTime('2026-10-02', 9, 0)),
      ]);
    });

    test('no evening once it is nearly here; an hour on past midnight is tomorrow', () {
      expect([for (final choice in remindChoices(DateTime(2026, 10, 1, 17, 30), const ReminderSettings(hour: 8, minute: 30))) choice.label], ['In an hour', 'Tomorrow, 8:30']);
      expect(remindChoices(DateTime(2026, 10, 1, 23, 40), const ReminderSettings()).first.at, const ReminderTime('2026-10-02', 0, 40));
    });
  });

  group('the page', () {
    test('writes the time pressed as plain words on the line, lights it, and takes it off', () {
      editor('- [ ] Call the plumber 📅 2026-10-03', picker: (at, current) async => null);
      expect([for (final row in rows()) row.label], ['In an hour', 'This evening', 'Tomorrow, 9:00', 'Pick a time']);
      rows().firstWhere((row) => row.label == 'This evening').onPress(Rect.zero);
      expect(line(1), '- [ ] Call the plumber ⏰ 2026-10-01 18:00 📅 2026-10-03');
      expect(rows().firstWhere((row) => row.label == 'This evening').lit, isTrue);
      expect([for (final row in rows()) row.label].last, 'Remove');
      rows().firstWhere((row) => row.name == 'Remove the reminder').onPress(Rect.zero);
      expect(line(1), '- [ ] Call the plumber 📅 2026-10-03');
    });

    test('Pick a time opens the phone’s calendar and clock, and writes what was picked', () async {
      final phone = FakeReminders()..picks = (hour: 7, minute: 45);
      final days = <String?>[];
      editor('- [ ] Pay the rent', picker: phoneReminderPicker(phone, (at, current) async {
        days.add(current);
        return '2026-10-05';
      }, clock: () => now));
      rows().firstWhere((row) => row.label == 'Pick a time').onPress(Rect.zero);
      await pumpEventQueue();
      expect(days, ['2026-10-01']);
      expect(phone.pickedFrom, [(9, 0)]);
      expect(line(1), '- [ ] Pay the rent ⏰ 2026-10-05 07:45');
    });

    test('with no calendar, a time already gone today is tomorrow’s', () async {
      final phone = FakeReminders()..picks = (hour: 8, minute: 0);
      final pick = phoneReminderPicker(phone, null, clock: () => now);
      expect(await pick(Offset.zero, null), const ReminderTime('2026-10-02', 8, 0));
      phone.picks = (hour: 21, minute: 0);
      expect(await pick(Offset.zero, null), const ReminderTime('2026-10-01', 21, 0));
    });
  });

  group('the chip', () {
    test('says the day as a due day does, and the time', () {
      final span = fieldsIn('Call ⏰ 2026-10-02 09:00').single;
      final look = chipLook(span, today: '2026-10-01', done: false, locale: 'en-GB')!;
      expect((look.text, look.label, look.menu, look.tone), ('Tomorrow 9:00', 'Reminder Friday 2 October at 9:00', FieldMenu.remind, 'quiet'));
      expect(pageOf(look), const RemindPage());
      expect(chipLook(span, today: '2026-10-01', done: true, locale: 'en-GB')!.tone, 'done');
    });
  });
}
