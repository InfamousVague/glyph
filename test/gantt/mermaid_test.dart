import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/gantt/gantt.dart';

/// A Mermaid gantt turned into a ```gantt fence (lib/core/gantt/mermaid.dart), on gantts as people write them: Mermaid's
/// own documentation's, a sprint plan with ids and `after`, one with weekends left out and an odd date format, and
/// one with what the fence cannot say, each said. Each converted fence is read back and worked out, and its days
/// held to the days Mermaid gives the same bars.
GanttModel modelOf(MermaidGantt converted) => ganttModelOf(readGantt(converted.body), today: '2026-01-01');

Map<String, (String, String)> daysOf(GanttModel model) => {for (final item in model.items) item.name: (item.start, item.end)};

void main() {
  test('knows a gantt from any other diagram', () {
    expect(isMermaidGantt('gantt\n  title A'), isTrue);
    expect(isMermaidGantt('%% a note\n\n  gantt'), isTrue);
    expect(isMermaidGantt('flowchart LR\n  A --> B'), isFalse);
  });

  test('Mermaid’s own example: sections, ids, after, lengths, done, active, crit and a milestone', () {
    const code = '''gantt
    title A Gantt Diagram
    dateFormat YYYY-MM-DD
    section Section
        A task          :a1, 2014-01-01, 30d
        Another task    :after a1, 20d
    section Another
        Task in Another :2014-01-12, 12d
        another task    :24d
        Completed task  :done, des1, 2014-01-06,2014-01-08
        Active task     :active, des2, 2014-01-09, 3d
        Critical one    :crit, 2014-01-15, 2d
        Release         :milestone, m1, 2014-01-25, 0d''';
    final converted = mermaidToGantt(code);
    expect(converted.body, '''title: A Gantt Diagram

## Section
- A task [2014-01-01 +30d]
- Another task [+20d] after: A task

## Another
- Task in Another [2014-01-12 +12d]
- another task [+24d] after: Task in Another
- Completed task [2014-01-06 → 2014-01-07] 100%
- Active task [2014-01-09 +3d] #active
- Critical one [2014-01-15 +2d] #crit
- ◆ Release [2014-01-25]''');
    expect(converted.notes, isEmpty, reason: 'nothing was lost');
    final days = daysOf(modelOf(converted));
    expect(days['A task'], ('2014-01-01', '2014-01-30'));
    expect(days['Another task'], ('2014-01-31', '2014-02-19'), reason: 'Mermaid starts it the day A task ends');
    expect(days['another task'], ('2014-01-24', '2014-02-16'), reason: 'after the task above it, as Mermaid starts one with no start');
    expect(days['Completed task'], ('2014-01-06', '2014-01-07'), reason: 'Mermaid’s end is the day after the bar');
    expect(modelOf(converted).byKey['L9']!.done, isTrue);
  });

  test('a sprint plan with weekends left out, ticks a week apart, and several waits', () {
    const code = '''gantt
  title Sprint 14
  dateFormat YYYY-MM-DD
  excludes weekends
  tickInterval 1week
  axisFormat %e %b
  section Backend
  API design      :api, 2026-11-02, 3d
  Endpoints       :ep, after api, 5d
  section Frontend
  Mockups         :mock, 2026-11-02, 2d
  Screens         :scr, after mock api, 4d
  section Release
  QA              :qa, after ep scr, 2d
  Ship it         :milestone, after qa, 0d''';
    final converted = mermaidToGantt(code);
    expect(converted.body.split('\n').take(4), ['title: Sprint 14', 'workdays: true', 'zoom: month', '']);
    expect(converted.body, contains('- Screens [+4d] after: Mockups, API design'));
    expect(converted.body, contains('- QA [+2d] after: Endpoints, Screens'));
    expect(converted.body, contains('- ◆ Ship it after: QA'));
    expect(converted.notes, ['The axis’s format (axisFormat %e %b) is the chart’s own now.']);
    final days = daysOf(modelOf(converted));
    expect(days['API design'], ('2026-11-02', '2026-11-04'));
    expect(days['Endpoints'], ('2026-11-05', '2026-11-11'), reason: 'five working days, the weekend skipped as Mermaid skips it');
    expect(days['Screens'], ('2026-11-05', '2026-11-10'));
    expect(days['QA'], ('2026-11-12', '2026-11-13'));
    expect(days['Ship it'], ('2026-11-16', '2026-11-16'));
  });

  test('another date format, inclusive ends and weeks', () {
    const code = '''gantt
  dateFormat DD/MM/YYYY
  inclusiveEndDates
  Plan     :p, 02/11/2026, 06/11/2026
  Build    :b, after p, 2w''';
    final converted = mermaidToGantt(code);
    expect(converted.body, '- Plan [2026-11-02 → 2026-11-06]\n- Build [+2w] after: Plan');
    expect(converted.notes, isEmpty);
    expect(daysOf(modelOf(converted))['Build'], ('2026-11-07', '2026-11-20'));
  });

  test('says each thing it cannot carry, and keeps a click and a comment as words', () {
    const code = '''%%{init: {"gantt": {"barHeight": 30}}}%%
gantt
  dateFormat YYYY-MM-DDTHH:mm
  excludes 2026-12-25, weekends
  todayMarker off
  weekday monday
  displayMode: compact
  %% the holiday rota
  section Rota
  Cover    :c1, 2026-12-21T09:00, 36h
  Hand over:until c1
  click c1 href "https://example.com"''';
    final converted = mermaidToGantt(code);
    expect(converted.body, contains('workdays: true'));
    expect(converted.body, contains('- Cover [2026-12-21 +2d]'));
    expect(converted.body, contains('%% the holiday rota'));
    expect(converted.body, contains('click c1 href "https://example.com"'));
    expect(converted.notes, [
      'Mermaid’s own settings (%%{init}%%) aren’t part of the chart.',
      'Days left out one at a time (excludes 2026-12-25) can’t be: only weekends can, as workdays: true.',
      'The line at today can’t be turned off.',
      'Which day starts the week (weekday monday) can’t be set: weeks start on a Monday.',
      'Mermaid’s compact rows (displayMode) aren’t: each task has a row.',
      'A length of 36h (Cover) is rounded to whole days.',
      'Running until another task starts (Hand over: until c1) can’t be: it is a day long.',
      'A click on a bar (click …) does nothing here: the line is kept as words.',
      'Times of day (YYYY-MM-DDTHH:mm) aren’t kept: only the days are.',
    ]);
    // The fence reads as it should: the click and the comment are lines the chart draws as nothing.
    final model = modelOf(converted);
    expect(model.problems, isEmpty);
    expect(model.items.map((item) => item.name), ['Cover', 'Hand over']);
  });
}
