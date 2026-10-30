// A day mentioned is a reminder (lib/mentions/mention_reminders.dart, lib/reminders/reminder_plan.dart; Matt,
// 2026-10-30: "add all 12"): on the day at Settings' time, for the writer, or for the person beside it, against a
// clock of the test's own: Friday 30 October 2026, 08:00.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/mentions/mention_reminders.dart';
import 'package:ghost_md/reminders/reminder_plan.dart';
import 'package:ghost_md/reminders/reminder_settings.dart';

final DateTime now = DateTime(2026, 10, 30, 8);

Note note(String id, String body) => Note(id: id, body: body, createdAt: 1, updatedAt: 1);

List<String> plan(List<Note> notes, {MentionWho? who, ReminderSettings settings = const ReminderSettings()}) => [
      for (final reminder in ReminderPlanner().plan(notes, settings: settings, now: now, who: who)) '${reminder.at.written} ${reminder.kind.name} ${reminder.words}',
    ];

/// Matt, in a team whose note is `team`, having written the day 2026-11-03 himself.
final MentionWho matt = MentionWho(me: 'matt', team: (id) => id == 'team', wrote: (id, day) => id == 'team' && day == '2026-11-03', key: 'matt');

void main() {
  test('a day mentioned in a note of your own reminds you on it, at Settings’ time; one passed does not', () {
    final notes = [note('mine', '# Plan\n\nCall the venue @2026-11-06\nBook it by @2026-10-29\nAsk @sam @2026-11-04')];
    expect(plan(notes), ['2026-11-04 09:00 mention Ask @sam @2026-11-04', '2026-11-06 09:00 mention Call the venue @2026-11-06']);
    expect(plan(notes, settings: const ReminderSettings(hour: 7, minute: 30)).first, '2026-11-04 07:30 mention Ask @sam @2026-11-04');
  });

  test('the reminder says what the line says, the note and why', () {
    final made = ReminderPlanner().plan([note('mine', '# Plan\nCall the venue @2026-11-06')], settings: const ReminderSettings(), now: now).single;
    expect((made.title, made.text, made.line, made.tick), ('Call the venue @2026-11-06', 'Plan · Mentioned for today', 2, false));
  });

  test('in a team’s note: beside a person it is theirs, on its own it is the writer’s', () {
    final notes = [note('team', '# Launch\n@matt @2026-11-02 the copy\n@sam @2026-11-05 the venue\nFreeze @2026-11-03\nShip @2026-11-07')];
    expect(plan(notes, who: matt), ['2026-11-02 09:00 mention @matt @2026-11-02 the copy', '2026-11-03 09:00 mention Freeze @2026-11-03']);
    final sam = MentionWho(me: 'sam', team: (id) => true, wrote: (id, day) => false, key: 'sam');
    expect(plan(notes, who: sam), ['2026-11-05 09:00 mention @sam @2026-11-05 the venue']);
  });

  test('a to-do with a due day is reminded by it, not again by a day mentioned on its line', () {
    final notes = [note('mine', '- [ ] Ship @2026-11-04 📅 2026-11-06')];
    expect(plan(notes), ['2026-11-06 09:00 due Ship @2026-11-04']);
  });

  test('nothing in code or the front matter, and nothing while reminders are off', () {
    final notes = [note('mine', '---\nwhen: @2026-11-04\n---\n```\n@2026-11-05\n```\n`@2026-11-06`')];
    expect(plan(notes), isEmpty);
    expect(plan([note('mine', 'Call @2026-11-06')], settings: const ReminderSettings(on: false)), isEmpty);
  });

  test('read again when who is asking changes', () {
    final planner = ReminderPlanner();
    final notes = [note('team', '@sam @2026-11-05 the venue')];
    expect(planner.plan(notes, settings: const ReminderSettings(), now: now, who: matt), isEmpty);
    final sam = MentionWho(me: 'sam', team: (id) => true, key: 'sam');
    expect(planner.plan(notes, settings: const ReminderSettings(), now: now, who: sam), hasLength(1));
  });
}
