import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/courses.dart';
import 'package:ghost_md/academy/lessons.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/gantt/gantt.dart' show ganttPlugin;
import 'package:ghost_md/plugins/marks_plugin.dart';
import 'package:ghost_md/plugins/more/more_tools.dart' show MoreTools;
import 'package:ghost_md/plugins/places/places_tool.dart' show placesToolPlugin;
import 'package:ghost_md/plugins/projects/suite.dart' show ProjectSuite;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/tickets/tickets.dart' show ticketsPlugin;
import 'package:ghost_md/plugins/planning/planning.dart' show planningPlugin;

/// The Academy's courses (lib/academy/courses.dart; Matt, 2026-11-02: "make it easier to browse the academy lessons
/// sort by plugins features like gantts etc"): every lesson in exactly one, the plugins they stand on, and the lessons
/// of the app's own past the page's (lessons_more.dart), each with a check that takes a person's own words and
/// refuses the words alone.
void main() {
  late Registry registry;
  setUp(() {
    useStored(MemoryStored());
    usePlugins(registry = createRegistry([marksPlugin, ganttPlugin, ticketsPlugin, planningPlugin, placesToolPlugin], store: MemorySwitches()));
  });

  bool passes(String id, String text) => lessonById(id)!.passes(text);

  group('the courses', () {
    test('hold every lesson, each in exactly one, and nothing else', () {
      final filed = [for (final course in courses) ...course.lessonIds];
      expect(filed.toSet(), hasLength(filed.length));
      expect(filed.toSet(), {for (final lesson in academyLessons) lesson.id});
      for (final course in courses) {
        expect(course.all, hasLength(course.lessonIds.length), reason: course.id);
        expect(course.about, isNotEmpty, reason: course.id);
      }
      expect({for (final course in courses) course.id}, hasLength(courses.length));
    });

    test('keep the Markdown shelf to standard Markdown and the page’s Markdown chapters', () {
      for (final course in courses.where((one) => one.shelf == CourseShelf.markdown)) {
        for (final lesson in course.all) {
          expect(['Markdown basics', 'More Markdown'], contains(lesson.chapter), reason: lesson.id);
        }
      }
      expect(courses.first.id, 'basics');
      expect(courses.first.all.every((lesson) => lesson.standard), isTrue);
    });

    test('stand each plugin course on a plugin the app has, and the gantt’s on Gantt and timelines', () {
      expect(courseById('gantt')!.tool, 'gantt');
      expect(academyToolName('gantt'), 'Gantt and timelines');
      expect(academyToolName('marks'), 'Marks');
      for (final course in courses) {
        expect(course.shelf == CourseShelf.plugins, course.tool != null, reason: course.id);
      }
    });

    test('offer a course’s lessons only while its plugin is on, and turn it on for the person', () {
      ProjectSuite.debugAllOn = false;
      MoreTools.debugAllOn = false;
      addTearDown(() {
        ProjectSuite.debugAllOn = true;
        MoreTools.debugAllOn = true;
      });
      final gantt = courseById('gantt')!;
      expect(courseOpen(gantt), isFalse);
      expect([for (final lesson in courseLessonsNow()) lesson.id], isNot(contains('gantt')));
      turnOnAcademyTool('gantt');
      expect(courseOpen(gantt), isTrue);
      expect(registry.isEnabled('gantt'), isTrue);
      expect([for (final lesson in courseLessonsNow()) lesson.id], containsAll(gantt.lessonIds));
      // Planning stands on Tickets, which comes with it.
      turnOnAcademyTool('planning');
      expect(registry.isEnabled('tickets'), isTrue);
      expect(courseOpen(courseById('tickets')!), isTrue);
      // A more tool by its switch, and the Marks plugin by its own.
      expect(courseOpen(courseById('places')!), isFalse);
      turnOnAcademyTool('places');
      expect(courseOpen(courseById('places')!), isTrue);
      registry.setEnabled('marks', false);
      expect(courseOpen(courseById('effects')!), isFalse);
      turnOnAcademyTool('marks');
      expect(courseOpen(courseById('effects')!), isTrue);
    });

    test('list the lessons on offer in the catalog’s order, a course’s in its own', () {
      final now = [for (final lesson in courseLessonsNow()) lesson.id];
      expect(now, [for (final course in courses) ...course.lessonIds]);
      expect(courseLessonsNow(true).every((lesson) => !lesson.standard), isTrue);
    });
  });

  group('the lessons of the app’s own', () {
    test('each has everything a lesson has, and its example passes its check', () {
      expect(moreLessons, isNotEmpty);
      for (final lesson in moreLessons) {
        expect(lesson.title, isNotEmpty, reason: lesson.id);
        expect(lesson.symbol, isNotEmpty, reason: lesson.id);
        expect(lesson.teach.length, greaterThan(30), reason: lesson.id);
        expect(lesson.task, isNotEmpty, reason: lesson.id);
        expect(lesson.hint, isNotEmpty, reason: lesson.id);
        expect(lesson.praise, isNotEmpty, reason: lesson.id);
        expect(lesson.rows, isEmpty, reason: '${lesson.id} teaches no row of the cheat sheet');
        expect(lesson.passes(lesson.example), isTrue, reason: '${lesson.id}: its own example');
        expect(lessons.where((one) => one.id == lesson.id), isEmpty, reason: '${lesson.id} is not one of the page’s');
      }
    });

    test('pass a person’s own words', () {
      expect(passes('gantt', '```gantt\n- Paint the shed [2026-11-07 -> 2026-11-08]\n```'), isTrue);
      expect(passes('gantt', '~~~gantt\nBuild:\n- Pour the base [2026-11-10 +2w]\n~~~'), isTrue);
      expect(passes('ganttAfter', '```gantt\n- Dig [2026-11-02]\n- Pour [+2d] after: Dig\n```'), isTrue);
      expect(passes('ganttQuery', '```query\nfrom: tasks\nshow: timeline\n```'), isTrue);
      expect(passes('estimate', '---\ntype: ticket\nestimate: 4h\n---\n# Copy'), isTrue);
      expect(passes('estimate', '---\ntype: ticket\nstatus: To do\nestimate: 5 points\n---'), isTrue);
      expect(passes('timeLog', '# Login\n\n## Time\n\n- 2026-11-02, 45m, Sam'), isTrue);
      expect(passes('timeLog', '---\ntype: ticket\nspent: 2h\n---\n# Login'), isTrue);
      expect(passes('rules', '```rules\nWhen a ticket is created, set assignee to Sam\n```'), isTrue);
      expect(passes('form', '```form\n- Name\n```'), isTrue);
      expect(passes('form', '```form\n- Email: email, required\n```'), isTrue);
    });

    test('are not passed by the words alone, by a fence still open, or by another mark', () {
      // A fence still being typed is not a chart yet.
      expect(passes('gantt', '```gantt\n- Paint the shed [2026-11-07 +2d]'), isFalse);
      // A task with no days is a line, not a bar.
      expect(passes('gantt', '```gantt\n- Paint the shed\n```'), isFalse);
      expect(passes('gantt', '- Paint the shed [2026-11-07 +2d]'), isFalse);
      expect(passes('ganttAfter', '```gantt\n- Dig [2026-11-02]\n- Pour [2026-11-04]\n```'), isFalse);
      expect(passes('ganttQuery', '```query\nfrom: tasks\nshow: calendar\n```'), isFalse);
      expect(passes('ganttQuery', '```gantt\n- Dig [2026-11-02]\n```'), isFalse);
      // An estimate on a note that is no ticket, or one that is no amount.
      expect(passes('estimate', '---\nestimate: 3\n---\n# Copy'), isFalse);
      expect(passes('estimate', '---\ntype: ticket\nestimate: big\n---'), isFalse);
      expect(passes('timeLog', '## Time\n\n- soon'), isFalse);
      expect(passes('timeLog', '---\ntype: ticket\nspent: 0m\n---'), isFalse);
      // A line the rules do not understand is no rule.
      expect(passes('rules', '```rules\nmake it nice\n```'), isFalse);
      expect(passes('rules', 'When a ticket is created, set assignee to Sam'), isFalse);
      expect(passes('form', '```form\nbutton: Send\n```'), isFalse);
      expect(passes('form', '- Name: short'), isFalse);
    });
  });
}
