import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/ticket_watchers.dart';
import 'package:ghost_md/book/tickets.dart';
import 'package:ghost_md/core/properties.dart';

/// Who watches a ticket (lib/book/ticket_watchers.dart; Matt, 2026-10-31): the `watchers:` list read and written as
/// plain front matter, Watch and Unwatch, and who a change makes a watcher - the creator, a new assignee, whoever
/// comments, whoever is newly mentioned - never twice, and never a name still being typed.
const String ticket = '---\ntype: ticket\nid: GHO-12\nstatus: To do\n---\n# Fix the login loop\n\nIt loops.\n';

void main() {
  group('the list', () {
    test('is read with or without at signs and quotes, each person once in any case', () {
      expect(watchersOf('---\ntype: ticket\nwatchers: ["@matt", "@sam"]\n---\n'), ['matt', 'sam']);
      expect(watchersOf('---\ntype: ticket\nwatchers: matt, @Sam, sam, "Priya Shah"\n---\n'), ['matt', 'Sam'], reason: 'a name with a space is no handle');
      expect(watchersOf(ticket), isEmpty);
      expect(watches('---\nwatchers: ["@Matt"]\n---\n', 'matt'), isTrue);
      expect(watches('---\nwatchers: ["@Matt"]\n---\n', '@MATT'), isTrue);
      expect(watches('---\nwatchers: ["@Matt"]\n---\n', 'sam'), isFalse);
    });

    test('Watch writes it across, quoted, as plain YAML; Unwatch takes a person off, and the key with the last', () {
      final watched = withWatcher(ticket, 'matt', true);
      expect(watched, contains('watchers: ["@matt"]\n'));
      final both = withWatcher(watched, '@sam', true);
      expect(both, contains('watchers: ["@matt", "@sam"]\n'));
      expect(withWatcher(both, 'SAM', true), both, reason: 'already watching');
      expect(withWatcher(both, 'Sam', false), contains('watchers: ["@matt"]\n'));
      expect(withWatcher(withWatcher(both, 'sam', false), 'matt', false), ticket, reason: 'the key goes with the last watcher');
      expect(withWatcher(ticket, 'Priya Shah', true), ticket);
      expect(ticketOf(both)?.id, 'GHO-12', reason: 'the rest of the ticket as it was');
    });
  });

  group('auto-watch', () {
    test('the creator, when a note becomes a ticket', () {
      expect(autoWatchers('# Fix it\n', ticket, me: 'matt'), ['matt']);
      expect(autoWatchers(ticket, '$ticket\nMore.', me: 'matt'), isEmpty, reason: 'editing a ticket is not making it');
      expect(autoWatchers('# Fix it\n', ticket, me: null), isEmpty);
    });

    test('a new assignee once picked, not while it is being typed in the front matter', () {
      final assigned = withProperty(ticket, 'assignee', 'sam');
      expect(autoWatchers(ticket, assigned, me: 'matt'), ['sam']);
      final caret = assigned.indexOf('assignee: sam') + 'assignee: sa'.length;
      expect(autoWatchers(ticket, assigned, me: 'matt', caret: caret), isEmpty);
      expect(autoWatchers(withWatcher(ticket, 'sam', true), withWatcher(assigned, 'sam', true), me: 'matt'), isEmpty, reason: 'watching already');
      expect(autoWatchers(withProperty(ticket, 'assignee', 'Priya Shah'), withProperty(ticket, 'assignee', 'Priya Shah'), me: 'matt'), isEmpty);
    });

    test('whoever comments, and whoever is newly mentioned, a name finished', () {
      const fence = '\n```comments\nc1 ana 2026-10-31T09:00:00Z\nLooks like the cookie.\n```\n';
      expect(autoWatchers(ticket, '${ticket.trimRight()}[^c1]\n$fence', me: 'matt'), ['ana']);
      final reply = '${ticket.trimRight()}[^c1]\n${fence.replaceFirst('```\n', '  zed 2026-10-31T09:05:00Z\n  Agreed.\n```\n').replaceFirst('```comments', '```comments')}';
      expect(autoWatchers('${ticket.trimRight()}[^c1]\n$fence', reply, me: 'matt'), ['zed']);
      final mentioned = '${ticket}Ask @sam about it.\n';
      expect(autoWatchers(ticket, mentioned, me: 'matt'), ['sam']);
      expect(autoWatchers(ticket, mentioned, me: 'matt', caret: mentioned.indexOf('@sam') + 4), isEmpty, reason: '`@sam` with the caret after it may still be `@samuel`');
      expect(autoWatchers(mentioned, '${mentioned}And again @sam.\n', me: 'matt'), ['sam'], reason: 'a second mention is a new one');
      expect(autoWatchers(mentioned, mentioned.replaceFirst('Ask', 'Please ask'), me: 'matt'), isEmpty, reason: 'the same mention standing still adds nobody, so an unwatch holds');
    });

    test('withAutoWatch writes them into the list, or answers null', () {
      final made = withAutoWatch('# Fix it\n', '${ticket}Ask @sam.\n', me: 'matt');
      expect(made, contains('watchers: ["@matt", "@sam"]\n'));
      expect(withAutoWatch(ticket, '$ticket ', me: 'matt'), isNull);
    });
  });

  test('a ticket made outside the editor names its creator as its first watcher', () {
    ticketCreator.value = 'matt';
    addTearDown(() => ticketCreator.value = null);
    expect(newTicketBody('Fix the login loop', id: 'GHO-13', statuses: defaultStatuses), contains('watchers: ["@matt"]\n'));
    ticketCreator.value = null;
    expect(newTicketBody('Fix the login loop', id: 'GHO-13', statuses: defaultStatuses), isNot(contains('watchers')));
  });
}
