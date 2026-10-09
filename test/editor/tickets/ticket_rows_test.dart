// What a ticket's panel shows (lib/editor/tickets/ticket_rows.dart; docs/DESIGN.md §157): the rows a ticket has, the
// keys left to the quiet line, a day in words, a due day passed, and another ticket as a property links it.
// `src/app/editor/ticketRows.test.ts`, case for case.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/editor/tickets/ticket_rows.dart';

const String front = '---\ntype: ticket\nid: GHO-12\nstatus: In progress\nestimate: 3\nlabels: []\ntitle: "Login"\nlook: reading\nauthors: Matt\n---';

void main() {
  group('the rows', () {
    test('are Status, Assignee, Priority and Due always, then each of the rest a ticket has, in the panel’s order', () {
      expect(panelRows(front), <String>['status', 'assignee', 'priority', 'due', 'estimate']);
      // An empty list is not a value: Labels waits behind More.
      expect(hiddenRows(front), <String>['start', 'blocked-by', 'parent', 'labels']);
      expect(panelRows(front, true), <String>['status', 'assignee', 'priority', 'due', 'start', 'estimate', 'blocked-by', 'parent', 'labels']);
    });

    test('leave the keys a ticket does not have to the quiet line, not its type, its id or its look', () {
      expect(otherKeys(front), <String>['title', 'authors']);
      expect(otherKeys('---\ntype: ticket\n---'), isEmpty);
    });
  });

  group('a day', () {
    String say(String iso) => dayLabel(iso, '2026-10-01', 'en-GB');

    group('in the phone’s own words, where no locale is named (core/locale_dates.dart)', () {
      tearDown(() => toldLocale = null);
      String own(String iso) => dayLabel(iso, '2026-10-01');

      test('an American phone has the month first', () {
        toldLocale = DateLocale.enUS;
        expect((own('2026-10-01'), own('2026-10-03'), own('2027-01-04'), own('soon')), ('Today', 'Sat, Oct 3', 'Mon, Jan 4, 2027', 'soon'));
      });

      test('a British phone has the day first', () {
        toldLocale = DateLocale.enGB;
        expect((own('2026-10-01'), own('2026-10-03'), own('2027-01-04'), own('soon')), ('Today', 'Sat, 3 Oct', 'Mon, 4 Jan 2027', 'soon'));
      });
    });

    test('is said as today, tomorrow or yesterday, else its weekday and date, with the year only when it is another', () {
      expect(say('2026-10-01'), 'Today');
      expect(say('2026-10-02'), 'Tomorrow');
      expect(say('2026-09-30'), 'Yesterday');
      expect(say('2026-10-03'), 'Sat 3 Oct');
      expect(say('2027-01-04'), 'Mon, 4 Jan 2027');
      // A day written by hand that is not one is said as it was written.
      expect(say('soon'), 'soon');
    });

    test('is overdue once it has passed with the ticket not done, and due today on the day', () {
      expect(dueState('2026-09-30', '2026-10-01', StatusCategory.doing), 'overdue');
      expect(dueState('2026-10-01', '2026-10-01', StatusCategory.todo), 'today');
      expect(dueState('2026-10-03', '2026-10-01', StatusCategory.todo), isNull);
      expect(dueState('2026-09-30', '2026-10-01', StatusCategory.done), isNull);
      expect(dueState(null, '2026-10-01', StatusCategory.todo), isNull);
    });
  });

  group('a link to another ticket', () {
    test('is its key where it has one, else its title', () {
      expect(linkTo(const TicketChoice(key: 'GHO-9', title: 'Fix the cookie', status: 'To do', category: StatusCategory.todo)), '[[GHO-9]]');
      expect(linkTo(const TicketChoice(key: null, title: 'Fix the cookie', status: null, category: StatusCategory.todo)), '[[Fix the cookie]]');
    });

    test('is written as nothing, one quoted value, or a list across', () {
      expect(linksValue(const <String>[]), isNull);
      expect(linksValue(const <String>['[[GHO-9]]']), '[[GHO-9]]');
      expect(linksValue(const <String>['[[GHO-9]]', '[[GHO-10]]']), <String>['[[GHO-9]]', '[[GHO-10]]']);
    });
  });
}
