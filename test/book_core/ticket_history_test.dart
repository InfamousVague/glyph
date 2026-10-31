import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/ticket_history.dart';
import 'package:ghost_md/core/versions_file.dart';

/// A ticket's history (lib/book/ticket_history.dart; Matt, 2026-10-31): from a sequence of versions, each one's
/// front matter beside the one before, put down to whoever kept it; the timeline's words; each pair read once.
String ticket(String front) => '---\ntype: ticket\nid: GHO-12\n$front---\n# Fix the login loop\n';

const int hour = 3600000;

/// A team note's versions as its file keeps them: written, then read back, so the hashes are the file's own.
List<Version> versions(List<(int at, String by, String text)> kept) => readFile(writeFile('n1', [for (final (at, by, text) in kept) VersionWords(at: at, by: by, text: text)]))!.versions;

void main() {
  final kept = versions([
    (1 * hour, 'matt', '# Fix the login loop\n'),
    (2 * hour, 'matt', ticket('status: To do\npriority: high\n')),
    (3 * hour, 'matt', ticket('status: To do\npriority: high\nassignee: sam\n')),
    (4 * hour, 'sam', '${ticket('status: In progress\npriority: high\nassignee: sam\ndue: 2026-11-06\n')}\nLooking at it.\n'),
    (5 * hour, 'sam', '${ticket('status: In review\npriority: high\nassignee: sam\ndue: 2026-11-07\nlabels: [bug, auth]\nestimate: 3\n')}\nLooking at it.\n'),
    (6 * hour, 'ana', '${ticket('status: In review\npriority: low\nassignee: sam\ndue: 2026-11-07\nlabels: [bug]\n')}\nLooking at it, and more words.\n'),
  ]);

  test('is every change to the six keys, oldest first, with who and when, from the version that made it a ticket', () {
    final changes = historyOf(kept);
    expect([for (final c in changes) (c.at ~/ hour, c.by, c.key, c.from, c.to)], [
      (2, 'matt', 'type', null, 'ticket'),
      (3, 'matt', 'assignee', null, 'sam'),
      (4, 'sam', 'status', 'To do', 'In progress'),
      (4, 'sam', 'due', null, '2026-11-06'),
      (5, 'sam', 'status', 'In progress', 'In review'),
      (5, 'sam', 'due', '2026-11-06', '2026-11-07'),
      (5, 'sam', 'labels', null, 'bug, auth'),
      (5, 'sam', 'estimate', null, '3'),
      (6, 'ana', 'priority', 'high', 'low'),
      (6, 'ana', 'labels', 'bug, auth', 'bug'),
      (6, 'ana', 'estimate', '3', null),
    ]);
    expect(changes.first.created, isTrue);
  });

  test('a version that changed only the words, or a note that is no ticket, says nothing', () {
    expect(changesBetween(ticket('status: To do\n'), '${ticket('status: To do\n')}More.\n', at: 1, by: 'sam'), isEmpty);
    expect(changesBetween('# A\n', '# B\n', at: 1, by: 'sam'), isEmpty);
  });

  test('says each change in the timeline’s words, the reader as You', () {
    final changes = historyOf(kept);
    expect([for (final c in changes) changeWords(c, me: 'matt')], [
      'You created it',
      'You assigned it to sam',
      'sam moved it To do → In progress',
      'sam set the due date to 2026-11-06',
      'sam moved it In progress → In review',
      'sam moved the due date to 2026-11-07',
      'sam added the labels bug, auth',
      'sam estimated it at 3',
      'ana set the priority to Low',
      'ana took off the label auth',
      'ana took the estimate off',
    ]);
  });

  test('reads each pair of versions once: a file that grew is read for its new version alone', () async {
    var file = kept;
    final history = TicketTimeline((_) async => file);
    expect(await history.of('n1'), hasLength(11));
    expect(history.read, 6);
    expect(await history.of('n1'), hasLength(11));
    expect(history.read, 6, reason: 'nothing read again');
    file = versions([
      for (final v in kept) (v.at, v.by, v.text),
      (7 * hour, 'sam', '${ticket('status: Done\npriority: low\nassignee: sam\ndue: 2026-11-07\nlabels: [bug]\n')}\nLooking at it, and more words.\n'),
    ]);
    final grown = await history.of('n1');
    expect(history.read, 7);
    expect(changeWords(grown.last), 'sam moved it In review → Done');
  });

  test('the app’s history is what ticketHistory answers, and none before it is registered', () async {
    registerTicketHistory(null);
    expect(await ticketHistory('n1'), isEmpty);
    registerTicketHistory(TicketTimeline((id) async => id == 'n1' ? kept : const []));
    addTearDown(() => registerTicketHistory(null));
    expect((await ticketHistory('n1')).map((c) => c.key).where((k) => k == 'status'), hasLength(2));
    expect(await ticketHistory('n2'), isEmpty);
  });
}
