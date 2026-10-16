import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/reminders/dated_items.dart';
import 'package:ghost_md/reminders/reminder_plan.dart';
import 'package:ghost_md/reminders/reminder_settings.dart';

/// Which reminders the phone holds, decided from the notes (lib/reminders/reminder_plan.dart), against a clock of the
/// test's own: Friday 2 October 2026, 08:00 on the phone.
final DateTime now = DateTime(2026, 10, 2, 8);

Note note(String id, String body, {int updatedAt = 1, bool starred = false, int? archivedAt}) => Note(id: id, body: body, createdAt: 1, updatedAt: updatedAt, starred: starred, archivedAt: archivedAt);

List<String> plan(List<Note> notes, {ReminderSettings settings = const ReminderSettings(), DateTime? at, bool Function(Note)? skip, int most = mostReminders}) => [
      for (final reminder in ReminderPlanner().plan(notes, settings: settings, now: at ?? now, skip: skip, most: most)) '${reminder.at.written} ${reminder.kind.name} ${reminder.words}',
    ];

void main() {
  group('what is reminded', () {
    test('a to-do with a due date, on the day at Settings’ time; one with its own time, then', () {
      final notes = [
        note('a', '# Errands\n\n- [ ] Call the plumber 📅 2026-10-03\n- [ ] Pay the rent ⏰ 2026-10-02 17:30\n- [ ] Buy milk'),
      ];
      expect(plan(notes), ['2026-10-02 17:30 set Pay the rent', '2026-10-03 09:00 due Call the plumber']);
    });

    test('the day before as well, where Settings asks, and at the time Settings sets', () {
      final notes = [note('a', '- [ ] Call the plumber 📅 2026-10-05')];
      expect(plan(notes, settings: const ReminderSettings(hour: 7, minute: 45, dayBefore: true)), ['2026-10-04 07:45 before Call the plumber', '2026-10-05 07:45 due Call the plumber']);
    });

    test('a to-do’s own time stands in for the due day’s', () {
      expect(plan([note('a', '- [ ] Call ⏰ 2026-10-04 12:00 📅 2026-10-05')], settings: const ReminderSettings(dayBefore: true)), ['2026-10-04 12:00 set Call']);
    });

    test('nothing ticked, cancelled, or done on another day', () {
      final notes = [note('a', '- [x] Called 📅 2026-10-03\n- [ ] Dropped ❌ 2026-10-01 📅 2026-10-03\n- [ ] Done another way ✅ 2026-10-01 ⏰ 2026-10-03 10:00')];
      expect(plan(notes), isEmpty);
    });

    test('a plain list item only where it says a time: a due date on it is a date, not a task', () {
      expect(plan([note('a', '- Dentist 📅 2026-10-03\n- Train ⏰ 2026-10-03 06:10')]), ['2026-10-03 06:10 set Train']);
    });

    test('Dataview’s due date reads as the emoji’s', () {
      expect(plan([note('a', '- [ ] File the taxes [due:: 2026-10-03]')]), ['2026-10-03 09:00 due File the taxes']);
    });

    test('a ticket’s due date and its own remind:, not once it is done', () {
      final open = note('t1', '---\ntype: ticket\nstatus: To do\ndue: 2026-10-03\n---\n# Fix the login');
      final timed = note('t2', '---\ntype: ticket\nstatus: In progress\ndue: 2026-10-09\nremind: 2026-10-02 15:00\n---\n# Ship it');
      final done = note('t3', '---\ntype: ticket\nstatus: Done\ndue: 2026-10-03\n---\n# Old one');
      expect(plan([open, timed, done]), ['2026-10-02 15:00 set Ship it', '2026-10-03 09:00 due Fix the login']);
    });

    test('nothing in front matter, fenced code, the archive or the Trash', () {
      final fenced = note('a', '---\nnote: - [ ] not this 📅 2026-10-03\n---\n```\n- [ ] Nor this 📅 2026-10-03\n```\n- [ ] This 📅 2026-10-03');
      final archived = note('b', '- [ ] Archived 📅 2026-10-03', archivedAt: 5);
      final trashed = note('c', '- [ ] Trashed 📅 2026-10-03');
      expect(plan([fenced, archived, trashed], skip: (n) => n.id == 'c'), ['2026-10-03 09:00 due This']);
    });

    test('only what is still to come: a minute that has begun is passed', () {
      final notes = [note('a', '- [ ] Early 📅 2026-10-02\n- [ ] Now ⏰ 2026-10-02 09:00\n- [ ] Soon ⏰ 2026-10-02 09:01')];
      expect(plan(notes, at: DateTime(2026, 10, 2, 9, 0, 30)), ['2026-10-02 09:01 set Soon']);
      expect(plan(notes, at: DateTime(2026, 10, 2, 8, 59, 59)), ['2026-10-02 09:00 due Early', '2026-10-02 09:00 set Now', '2026-10-02 09:01 set Soon']);
    });

    test('the soonest of them, at most as many as asked', () {
      final body = [for (var day = 10; day <= 28; day += 1) '- [ ] Item $day 📅 2026-10-$day'].join('\n');
      final made = plan([note('a', body)], most: 5);
      expect(made, hasLength(5));
      expect(made.first, '2026-10-10 09:00 due Item 10');
      expect(made.last, '2026-10-14 09:00 due Item 14');
    });

    test('nothing at all with reminders off', () {
      expect(plan([note('a', '- [ ] Call 📅 2026-10-03 ⏰ 2026-10-02 10:00')], settings: const ReminderSettings(on: false)), isEmpty);
    });
  });

  group('the same reminder from one pass to the next', () {
    test('keeps its id when lines are written above it, and only the notes that changed are read again', () {
      final planner = ReminderPlanner();
      final a = note('a', '- [ ] Call the plumber 📅 2026-10-03');
      final b = note('b', '- [ ] Pay 📅 2026-10-04');
      final first = planner.plan([a, b], settings: const ReminderSettings(), now: now);
      expect(planner.lastRead, 2);
      final moved = note('a', '# Errands\n\nmore words\n- [ ] Call the plumber 📅 2026-10-03');
      final second = planner.plan([moved, b], settings: const ReminderSettings(), now: now);
      expect(planner.lastRead, 1);
      expect(second.first.id, first.first.id);
      expect(second.first.line, 4);
      expect(planner.plan([moved, b], settings: const ReminderSettings(), now: now), second);
      expect(planner.lastRead, 0);
      // Other settings are another plan: every note read again.
      planner.plan([moved, b], settings: const ReminderSettings(hour: 8), now: now);
      expect(planner.lastRead, 2);
    });

    test('as the phone is handed it: the notification’s words, the line and whether Done is offered', () {
      final made = ReminderPlanner().plan([note('a', '# Errands\n- [ ] Call 📅 2026-10-03\n- Train ⏰ 2026-10-03 06:10')], settings: const ReminderSettings(), now: now);
      final json = jsonDecode(planJson(made)) as Map<String, Object?>;
      final items = (json['items'] as List).cast<Map<String, Object?>>();
      expect(items.map((item) => (item['at'], item['title'], item['text'], item['line'], item['tick'])), [
        ('2026-10-03 06:10', 'Train', 'Errands', 3, false),
        ('2026-10-03 09:00', 'Call', 'Errands · Due today', 2, true),
      ]);
      expect(items.map((item) => item['id']).toSet(), hasLength(2));
    });
  });

  test('a note’s dated items are read once for the note object', () {
    final a = note('a', '- [ ] Call 📅 2026-10-03');
    expect(identical(DatedItems.of(a), DatedItems.of(a)), isTrue);
    expect(DatedItems.of(note('b', 'no dates here')), isEmpty);
  });
}
