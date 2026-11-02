// Lessons of the app's own, past the web page's sixty-one (lessons.g.dart): one for each plugin with something to type
// that had no lesson yet (Matt, 2026-11-02: "make it easier to browse the academy lessons sort by plugins features like
// gantts etc"). Written here, not read off the page, so they are not in test/academy/fixtures/web_lessons.json; their
// checks are lessons.dart's `_checks` like every other, over the app's own readers, and test/academy/lessons_test.dart
// holds them. Their `chapter` is the web chapter nearest them, kept as data; the Academy files them by course
// (courses.dart). None has a voice yet (voice.dart): the Academy says nothing for them until tool/academy_voice.py has
// made one.
part of 'lessons.dart';

/// The lessons that are not the web page's, in the order their courses teach them.
final List<Lesson> moreLessons = List<Lesson>.unmodifiable(<Lesson>[
  // ---- Gantt and timelines -----------------------------------------------------------------------------------------
  Lesson._(
    id: 'gantt',
    chapter: 'Tickets and queries',
    symbol: '```gantt',
    rows: <String>[],
    title: 'A Gantt chart',
    teach: 'A block marked gantt is a project written as a list, and the chart is drawn from it: each task a line, its days in square brackets. A day, an arrow and another day is both of them and the days between; a day and +5d is five days from it. Drag a bar on the chart and the brackets are written for you.',
    example: '```gantt\n## Build\n- Design the page [2026-11-02 → 2026-11-06] @sam\n- Write the copy [2026-11-04 +3d]\n```',
    task: 'Make a Gantt chart with a task or two.',
    praise: 'That is a Gantt chart.',
    hint: 'Three backticks and gantt, a line like - Design [2026-11-02 +3d], then three backticks. -> works as the arrow too.',
  ),
  Lesson._(
    id: 'ganttAfter',
    chapter: 'Tickets and queries',
    symbol: 'after:',
    rows: <String>[],
    title: 'One thing after another',
    teach: 'after: and a task’s name make a task wait on it, with a line drawn from one bar to the next, and [+4d] starts it the working day after what it waits on ends, so moving one moves the rest. A name that starts with ◆ (or <>) is a milestone: a day, not a bar.',
    example: '```gantt\n- Design the page [2026-11-02 +5d]\n- Build it [+4d] after: Design the page\n- ◆ Launch [2026-11-16] after: Build it\n```',
    task: 'Make one task wait on another.',
    praise: 'That one waits its turn.',
    hint: 'In a gantt block, after a task’s days: after: and the name of the task before it.',
  ),
  Lesson._(
    id: 'ganttQuery',
    chapter: 'Tickets and queries',
    symbol: 'show: gantt',
    rows: <String>[],
    title: 'Your to-dos as a Gantt chart',
    teach: 'A query can draw what it finds as a chart too: show: gantt lays every dated to-do or ticket out as a bar, and show: timeline puts them along a line of days. Both keep up as the notes change.',
    example: '```query\nfrom: tasks\nwhere: due >= today\nshow: gantt\n```',
    task: 'Show a query as a gantt or a timeline.',
    praise: 'Every dated thing, on the chart.',
    hint: 'Inside a query fence, a line like show: gantt, or show: timeline.',
  ),
  // ---- Planning ----------------------------------------------------------------------------------------------------
  Lesson._(
    id: 'estimate',
    chapter: 'Tickets and queries',
    symbol: 'estimate:',
    rows: <String>[],
    title: 'An estimate and a cycle',
    teach: 'A ticket’s front matter can say how big it is, estimate: 3 for points or 4h for hours, and the cycle it is planned in, cycle: and its name, like 2026-C45 for the fortnight starting in week 45. Burndown and velocity are counted from them, and a query adds estimates up with total: estimate.',
    example: '---\ntype: ticket\nstatus: To do\nestimate: 3\ncycle: 2026-C45\n---\n# Write the pricing copy',
    task: 'Give a ticket an estimate.',
    praise: 'Sized, and ready to plan.',
    hint: 'In a ticket’s front matter, under type: ticket, a line like estimate: 3.',
  ),
  // ---- Time tracking -----------------------------------------------------------------------------------------------
  Lesson._(
    id: 'timeLog',
    chapter: 'Tickets and queries',
    symbol: '## Time',
    rows: <String>[],
    title: 'Time on a ticket',
    teach: 'Time spent on a ticket is lines under a ## Time heading at its foot: the day, how long, and who. A ticket’s timer writes one each time it stops and adds it to spent: in the front matter, which a query can total.',
    example: '---\ntype: ticket\nstatus: Doing\nspent: 1h 20m\n---\n# Fix the login\n\n## Time\n\n- 2026-11-02 · 1h 20m · Sam',
    task: 'Log some time on a ticket.',
    praise: 'Time logged.',
    hint: 'A ## Time heading, then a line like - 2026-11-02 · 45m · Sam. A comma or a bar between the parts works too.',
  ),
  // ---- Automations -------------------------------------------------------------------------------------------------
  Lesson._(
    id: 'rules',
    chapter: 'Tickets and queries',
    symbol: '```rules',
    rows: <String>[],
    title: 'A rule',
    teach: 'A block marked rules, in a ticket notebook’s index, holds its automations: a sentence a line, when something happens, do something. A rule can set a field, notify someone or post to a channel, and a line it does not understand is kept as it is and said so.',
    example: '```rules\nWhen status becomes Done, notify the assignee\nWhen a ticket is created, set priority to Normal\n```',
    task: 'Write a rule.',
    praise: 'That rule will run by itself.',
    hint: 'Three backticks and rules, a line like When a ticket is created, set assignee to Sam, then three backticks.',
  ),
  // ---- Forms -------------------------------------------------------------------------------------------------------
  Lesson._(
    id: 'form',
    chapter: 'Tickets and queries',
    symbol: '```form',
    rows: <String>[],
    title: 'A form',
    teach: 'A block marked form makes the note a form anyone with its link can fill in, each answer arriving as a ticket. A field is a line: a dash, its label, a colon and what it takes, short, long, email, file, or choice with the options in brackets, and required where it must be filled.',
    example: '```form\nbutton: Send\n- Your name: short, required\n- What happened: long\n- How bad: choice (Annoying | Blocking)\n```',
    task: 'Make a form with a field or two.',
    praise: 'That is a form.',
    hint: 'Three backticks and form, a line like - Your name: short, then three backticks.',
  ),
]);
