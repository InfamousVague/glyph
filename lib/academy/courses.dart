/// Ghost Academy's courses: the lessons filed by the feature they teach, to browse the way a catalog of courses is
/// browsed (Matt, 2026-11-02: "make it easier to browse the academy lessons sort by plugins features like gantts etc
/// redo the academy homepage to be easier to browse like codecademy lessons").
///
/// The web page's seven chapters (lessons.g.dart `chapters`) stay as the lessons' data, read off the page and held to
/// it by test/academy/fixtures/web_lessons.json; a course is a run of lessons by their ids, on one of three shelves:
/// - **Markdown**: what any Markdown app reads, the basics and a little more.
/// - **Ghost**: what Ghost draws of its own, built in: smart lines, to-dos, links, queries.
/// - **Plugins**: a course for each plugin with something to type, the project tools (Tickets, Planning, Gantt and
///   timelines, Boards, Time tracking, Automations, Forms; docs/PM_PLUGINS.md), two of the more tools (Diagrams and
///   math, Places; §10) and the Marks plugin's marks and effects.
///
/// A course on a plugin that is off is still on its shelf, to be found (Matt wants features discovered here, not
/// hidden): it says it needs the plugin and offers the app's own chip to turn it on (lib/plugins/projects/
/// tool_chip.dart `ToolChip`). Its lessons are not on offer until then, as a plugin mark's never were: they are not
/// counted, and Continue passes them by. A project tool is on for the Academy where it is on for the person or in any
/// of their organizations (`ProjectSuite.anywhere`), and turned on here for the person (`ProjectSuite.turnOn`, Tickets
/// with it where it needs it); a more tool and the Marks plugin are the registry's switches.
///
/// Each lesson is in exactly one course, and every lesson is in one (test/academy/courses_test.dart).
library;

import 'dart:async';

import '../art/app_icon.dart' show LucideIcon;
import '../art/lucide.g.dart';
import '../plugins/more/more_tools.dart' show isMoreTool, moreToolOn, moreToolPlugin, withMoreNeeds;
import '../plugins/projects/suite.dart' show isProjectTool, projectPlugin, projectSuite;
import '../plugins/registry.dart' show plugins;
import 'lessons.dart';
import 'looks.dart';

/// The three shelves of the catalog, in its order: the chips across its top.
enum CourseShelf {
  markdown('Markdown'),
  ghost('Ghost'),
  plugins('Plugins');

  const CourseShelf(this.label);
  final String label;
}

/// How far in a course is, as its card says.
enum CourseLevel {
  beginner('Beginner'),
  intermediate('Intermediate'),
  advanced('Advanced');

  const CourseLevel(this.label);
  final String label;
}

/// One course: its lessons by their ids, in the order they are taught.
class Course {
  const Course({required this.id, required this.title, required this.about, required this.shelf, required this.level, required this.look, required this.lessonIds, this.tool, this.hello});

  final String id;
  final String title;

  /// A line on its card and at the head of its page.
  final String about;
  final CourseShelf shelf;
  final CourseLevel level;

  /// Its colour and its sign (looks.dart).
  final ChapterLook look;
  final List<String> lessonIds;

  /// The plugin it stands on, by its id: a project tool, a more tool or `marks`; null for one built in.
  final String? tool;

  /// The clip its hello is (voice.dart), said as it is begun; null for a course with none yet.
  final String? hello;

  /// Every lesson of it, on offer or not.
  List<Lesson> get all => [for (final id in lessonIds) ?lessonById(id)];

  /// Its lessons among [offered], in its order.
  List<Lesson> among(List<Lesson> offered) => [for (final lesson in offered) if (lessonIds.contains(lesson.id)) lesson]..sort((a, b) => lessonIds.indexOf(a.id) - lessonIds.indexOf(b.id));

  /// About two minutes a lesson, as a card says it.
  int minutesFor(int count) => count * 2;

  @override
  String toString() => 'Course($id)';
}

/// The catalog, in its order: the order Continue goes through them, and the order a shelf lists them.
const List<Course> courses = [
  // ---- Markdown -------------------------------------------------------------------------------------------------
  Course(
    id: 'basics',
    title: 'Markdown basics',
    about: 'Headings, bold, lists, links and to-dos: what every Markdown app reads the same way.',
    shelf: CourseShelf.markdown,
    level: CourseLevel.beginner,
    look: ChapterLook(hues: ['indigo', 'blue'], icon: Lucide.heading, tiles: [Lucide.bold, Lucide.italic, Lucide.listChecks, Lucide.link]),
    lessonIds: ['title', 'heading', 'bold', 'italic', 'both', 'struck', 'code', 'link', 'list', 'number', 'todo', 'quote', 'rule', 'fence'],
    hello: 'chapter-basics',
  ),
  Course(
    id: 'more',
    title: 'More Markdown',
    about: 'Tables, pictures, films, footnotes, callouts and emoji, for when a note needs a little more.',
    shelf: CourseShelf.markdown,
    level: CourseLevel.intermediate,
    look: ChapterLook(hues: ['magenta', 'rose'], icon: Lucide.table, tiles: [Lucide.image, Lucide.superscript, Lucide.film, Lucide.messageSquareQuote]),
    lessonIds: ['table', 'picture', 'video', 'raised', 'lowered', 'footnote', 'definition', 'emoji', 'callout'],
  ),
  // ---- Ghost's own ----------------------------------------------------------------------------------------------
  Course(
    id: 'lines',
    title: 'Smart lines',
    about: 'Tags, choices, counters, sums, blanks for the AI and comments: lines whose words the note works with.',
    shelf: CourseShelf.ghost,
    level: CourseLevel.intermediate,
    look: ChapterLook(hues: ['mint', 'cyan'], icon: Lucide.tag, tiles: [Lucide.calculator, Lucide.circleDot, Lucide.messageSquare, Lucide.hash]),
    lessonIds: ['tag', 'choice', 'counter', 'sum', 'blank', 'hiddenLine', 'comment'],
  ),
  Course(
    id: 'todos',
    title: 'To-dos that do more',
    about: 'Due days, priorities and people on a to-do, a heading that counts its boxes, and names for items to point at.',
    shelf: CourseShelf.ghost,
    level: CourseLevel.beginner,
    look: ChapterLook(hues: ['green', 'lime'], icon: Lucide.squareCheckBig, tiles: [Lucide.calendarDays, Lucide.userRound, Lucide.anchor, Lucide.listTodo]),
    lessonIds: ['fields', 'progress', 'anchor', 'itemRef'],
  ),
  Course(
    id: 'links',
    title: 'Links and bookmarks',
    about: 'Another note by its name, and the bookmark a note opens at.',
    shelf: CourseShelf.ghost,
    level: CourseLevel.beginner,
    look: ChapterLook(hues: ['red', 'coral'], icon: Lucide.link2, tiles: [Lucide.bookmark, Lucide.fileText, Lucide.link, Lucide.compass]),
    lessonIds: ['wiki', 'bookmark'],
  ),
  Course(
    id: 'queries',
    title: 'Queries',
    about: 'A block that finds, narrows, groups and adds up what matches in every note, as a list, a table or a month.',
    shelf: CourseShelf.ghost,
    level: CourseLevel.advanced,
    look: ChapterLook(hues: ['purple', 'indigo'], icon: Lucide.database, tiles: [Lucide.search, Lucide.listFilter, Lucide.table, Lucide.chartNoAxesCombined]),
    lessonIds: ['query', 'queryWhere', 'queryShow', 'queryGroup'],
  ),
  // ---- Plugins --------------------------------------------------------------------------------------------------
  Course(
    id: 'gantt',
    title: 'Gantt and timelines',
    about: 'A project written as a list and drawn as bars: days, one task after another, milestones, and your to-dos on a chart.',
    shelf: CourseShelf.plugins,
    level: CourseLevel.intermediate,
    look: ChapterLook(hues: ['orange', 'amber'], icon: Lucide.chartGantt, tiles: [Lucide.calendarDays, Lucide.flag, Lucide.arrowRight, Lucide.hourglass]),
    lessonIds: ['gantt', 'ganttAfter', 'ganttQuery'],
    tool: 'gantt',
  ),
  Course(
    id: 'boards',
    title: 'Boards',
    about: 'Named items laid out as columns, to drag from one to the next.',
    shelf: CourseShelf.plugins,
    level: CourseLevel.intermediate,
    look: ChapterLook(hues: ['lime', 'green'], icon: Lucide.squareKanban, tiles: [Lucide.squareCheckBig, Lucide.anchor, Lucide.layoutGrid, Lucide.gripVertical]),
    lessonIds: ['board', 'boardHeight'],
    tool: 'boards',
  ),
  Course(
    id: 'tickets',
    title: 'Tickets',
    about: 'Notes as tickets, with a status and someone on them, and notebooks that number them.',
    shelf: CourseShelf.plugins,
    level: CourseLevel.intermediate,
    look: ChapterLook(hues: ['blue', 'cyan'], icon: Lucide.ticket, tiles: [Lucide.userRound, Lucide.book, Lucide.hash, Lucide.circleCheck]),
    lessonIds: ['ticket', 'notebookKey'],
    tool: 'tickets',
  ),
  Course(
    id: 'planning',
    title: 'Planning',
    about: 'How big a ticket is and the cycle it is planned in, which burndown and velocity are counted from.',
    shelf: CourseShelf.plugins,
    level: CourseLevel.advanced,
    look: ChapterLook(hues: ['cyan', 'blue'], icon: Lucide.calendarDays, tiles: [Lucide.gauge, Lucide.ticket, Lucide.chartNoAxesCombined, Lucide.flag]),
    lessonIds: ['estimate'],
    tool: 'planning',
  ),
  Course(
    id: 'time',
    title: 'Time tracking',
    about: 'Time spent on a ticket, in lines a person can read, and the total a query adds up.',
    shelf: CourseShelf.plugins,
    level: CourseLevel.intermediate,
    look: ChapterLook(hues: ['yellow', 'amber'], icon: Lucide.hourglass, tiles: [Lucide.clock, Lucide.alarmClock, Lucide.ticket, Lucide.calculator]),
    lessonIds: ['timeLog'],
    tool: 'time-tracking',
  ),
  Course(
    id: 'automations',
    title: 'Automations',
    about: 'Rules a notebook runs by itself: when something happens to a ticket, do something.',
    shelf: CourseShelf.plugins,
    level: CourseLevel.advanced,
    look: ChapterLook(hues: ['purple', 'magenta'], icon: Lucide.workflow, tiles: [Lucide.repeat, Lucide.bell, Lucide.send, Lucide.ticket]),
    lessonIds: ['rules'],
    tool: 'automations',
  ),
  Course(
    id: 'forms',
    title: 'Forms',
    about: 'A note anyone with its link can fill in, each answer filed as a ticket.',
    shelf: CourseShelf.plugins,
    level: CourseLevel.intermediate,
    look: ChapterLook(hues: ['rose', 'magenta'], icon: Lucide.textCursorInput, tiles: [Lucide.mail, Lucide.listChecks, Lucide.send, Lucide.ticket]),
    lessonIds: ['form'],
    tool: 'forms',
  ),
  Course(
    id: 'diagrams',
    title: 'Diagrams and maths',
    about: 'Formulas drawn as maths, and flowcharts drawn from a few lines of words.',
    shelf: CourseShelf.plugins,
    level: CourseLevel.advanced,
    look: ChapterLook(hues: ['indigo', 'purple'], icon: Lucide.sigma, tiles: [Lucide.workflow, Lucide.squareRadical, Lucide.network, Lucide.spline]),
    lessonIds: ['maths', 'diagram'],
    tool: 'diagrams',
  ),
  Course(
    id: 'places',
    title: 'Places',
    about: 'A place on a line of its own, with its map drawn under it.',
    shelf: CourseShelf.plugins,
    level: CourseLevel.beginner,
    look: ChapterLook(hues: ['coral', 'red'], icon: Lucide.mapPinned, tiles: [Lucide.mapPin, Lucide.compass, Lucide.globe, Lucide.locateFixed]),
    lessonIds: ['place'],
    tool: 'places',
  ),
  Course(
    id: 'marks',
    title: 'Marks',
    about: 'Highlights in any colour, spoilers, asides, doubts, redactions, shouts and additions.',
    shelf: CourseShelf.plugins,
    level: CourseLevel.beginner,
    look: ChapterLook(hues: ['amber', 'orange'], icon: Lucide.highlighter, tiles: [Lucide.eyeOff, Lucide.messageCircleQuestionMark, Lucide.megaphone, Lucide.plus]),
    lessonIds: ['spoiler', 'highlight', 'tint', 'aside', 'unsure', 'markNote', 'redact', 'shout', 'added'],
    tool: 'marks',
  ),
  Course(
    id: 'effects',
    title: 'Effects',
    about: 'Five that move: heat, frost, waves, a shimmer and a haunting.',
    shelf: CourseShelf.plugins,
    level: CourseLevel.beginner,
    look: ChapterLook(hues: ['magenta', 'orange'], icon: Lucide.sparkles, tiles: [Lucide.flame, Lucide.snowflake, Lucide.waves, Lucide.ghost]),
    lessonIds: ['heat', 'frost', 'wave', 'shimmer', 'haunt'],
    tool: 'marks',
  ),
];

/// The course of [id]; null for none.
Course? courseById(String id) => courses.where((course) => course.id == id).firstOrNull;

/// The course a lesson is in.
Course courseOf(Lesson lesson) => courses.firstWhere((course) => course.lessonIds.contains(lesson.id));

// ---- the plugins a course stands on -----------------------------------------------------------------------------------

/// Whether the plugin [tool] is on, as the Academy asks it: a project tool for the person or any organization of
/// theirs, a more tool or any other plugin by its registry switch.
bool academyToolOn(String tool) {
  if (isProjectTool(tool)) return projectSuite.anywhere(tool);
  if (isMoreTool(tool)) return moreToolOn(tool);
  return plugins.byId(tool) != null && plugins.isEnabled(tool);
}

/// Whether [course] is open: built in, or its plugin on.
bool courseOpen(Course course) => course.tool == null || academyToolOn(course.tool!);

/// Turns [tool] on for the person: a project tool with what it needs (Tickets for Planning), a more tool with what it
/// stands on, any other plugin by its switch.
void turnOnAcademyTool(String tool) {
  if (isProjectTool(tool)) {
    unawaited(projectSuite.turnOn([tool]));
    return;
  }
  for (final id in isMoreTool(tool) ? withMoreNeeds(tool) : [tool]) {
    plugins.setEnabled(id, true);
  }
}

/// The plugin's name, as the Market says it: "Gantt and timelines", "Diagrams and math", "Marks".
String academyToolName(String tool) => (projectPlugin(tool) ?? moreToolPlugin(tool) ?? plugins.byId(tool))?.manifest.name ?? tool;

/// The plugin's sign, its icon in the Market.
LucideIcon academyToolIcon(String tool) => Lucide.all[(projectPlugin(tool) ?? moreToolPlugin(tool) ?? plugins.byId(tool))?.icon ?? ''] ?? Lucide.puzzle;

/// The lessons on offer now, in the catalog's order: every open course's, without a plugin mark that is off, and
/// without standard Markdown for a person who knows it ([lessonsNow]).
List<Lesson> courseLessonsNow([bool skipStandard = false]) {
  final offered = lessonsNow(skipStandard, academyLessons);
  return [
    for (final course in courses)
      if (courseOpen(course)) ...course.among(offered),
  ];
}
