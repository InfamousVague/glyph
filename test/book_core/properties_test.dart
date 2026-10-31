import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/core/properties.dart';

/// A ticket is front matter, and front matter is read in one place (lib/core/front_matter.dart): these are the blocks
/// a properties panel, a ticket's numbering and a query must all read the same way, and the values that must come
/// back from YAML as they went in. Case for case with the web's `core/properties.test.ts`.
final String ticket = [
  '---',
  'type: ticket',
  'id: GHO-12',
  'status: In progress',
  'assignee: Sam',
  'priority: high',
  'due: 2026-10-03',
  'estimate: 3',
  'blocked-by: "[[GHO-9]]"',
  '---',
  '# Fix the login loop',
  '',
  'It loops.',
].join('\n');

Property p(String key, String value, int line) => Property(key: key, value: value, line: line);

void main() {
  group('a note’s properties', () {
    test('are every key in its front matter, in order, the quotes off, with the line each is on', () {
      expect(propertiesOf(ticket), [
        p('type', 'ticket', 1),
        p('id', 'GHO-12', 2),
        p('status', 'In progress', 3),
        p('assignee', 'Sam', 4),
        p('priority', 'high', 5),
        p('due', '2026-10-03', 6),
        p('estimate', '3', 7),
        p('blocked-by', '[[GHO-9]]', 8),
      ]);
    });

    test('keep a key as written, an empty value, a value with colons, and skip blank lines', () {
      expect(propertiesOf('---\nTitle: "A: B"\n\nempty:\nurl: https://a.b/c\nspaced  :   x  \n---\n'), [
        p('Title', 'A: B', 1),
        p('empty', '', 3),
        p('url', 'https://a.b/c', 4),
        p('spaced', 'x', 5),
      ]);
    });

    test('take a value’s quotes off as YAML does, as frontMatterValue does', () {
      const body = '---\na: \'It\'\'s\'\nb: "say \\"hi\\""\nc: \'"quoted"\'\n---\n';
      expect([for (final each in propertiesOf(body)) each.value], ["It's", 'say "hi"', '"quoted"']);
      for (final Property(:key, :value) in propertiesOf(body)) {
        expect(frontMatterValue(body, key), value);
      }
    });

    test('read the block a `+++` fence opens too', () {
      expect(propertiesOf('+++\nid: GHO-1\n+++\nWords'), [p('id', 'GHO-1', 1)]);
    });

    test('leave out an indented key, which belongs to the one above it', () {
      expect([for (final each in propertiesOf('---\nmeta:\n  inner: 1\nafter: 2\n---\n')) each.key], ['meta', 'after']);
    });

    test('are none where the note has no front matter, as frontMatterEnd decides it', () {
      for (final body in ['', '# Note\n\ntype: ticket', '---\ntype: ticket\nwords here\n---\n', '---\ntype: ticket\n', 'Words\n---\ntype: ticket\n---', '---\n- a\n---\n']) {
        expect(frontMatterEnd(body.split('\n')), 0, reason: body);
        expect(propertiesOf(body), isEmpty, reason: body);
      }
    });

    test('read a list written as lines under its key, as Obsidian writes one (2026-10-31), the key with an empty value', () {
      const body = '---\ntags:\n  - a\n  - b\ntype: ticket\n---\n';
      expect(frontMatterEnd(body.split('\n')), 6);
      expect(propertiesOf(body), [p('tags', '', 1), p('type', 'ticket', 4)]);
    });
  });

  group('a value read as a list', () {
    test('reads a flow list, its items unquoted', () {
      expect(propertyList('["[[GHO-9]]", "[[GHO-10]]"]'), ['[[GHO-9]]', '[[GHO-10]]']);
      expect(propertyList('[bug, ui]'), ['bug', 'ui']);
      expect(propertyList("['a, b', c]"), ['a, b', 'c']);
      expect(propertyList('[[[GHO-9]], [[GHO-10]]]'), ['[[GHO-9]]', '[[GHO-10]]']);
      expect(propertyList('[]'), isEmpty);
      expect(propertyList('[ , a ,, ]'), ['a']);
    });

    test('reads names with commas, as authors are written', () {
      expect(propertyList('Matt, Claude'), ['Matt', 'Claude']);
      expect(propertyList('Backlog, To do, Won’t do, Won\'t fix'), ['Backlog', 'To do', 'Won’t do', "Won't fix"]);
      expect(propertyList('one'), ['one']);
    });

    test('reads note links alone as links, never as a list in a list', () {
      expect(propertyList('[[GHO-9]]'), ['[[GHO-9]]']);
      expect(propertyList('[[GHO-9]], [[GHO-10|the loop]]'), ['[[GHO-9]]', '[[GHO-10|the loop]]']);
    });

    test('keeps a comma inside quotes or brackets in its item', () {
      expect(propertyList('"Smith, J", [[A, B]]'), ['Smith, J', '[[A, B]]']);
    });

    test('is empty for nothing', () {
      expect(propertyList(''), isEmpty);
      expect(propertyList('   '), isEmpty);
      expect(propertyList(null), isEmpty);
    });
  });

  group('what a link property points at', () {
    test('is each note link’s title, its heading or words after it not part of it', () {
      expect(linkTargets('[[GHO-9]]'), ['GHO-9']);
      expect(linkTargets('["[[GHO-9]]", "[[GHO-10|the loop]]", "[[Plan#Risks]]"]'), ['GHO-9', 'GHO-10', 'Plan']);
    });

    test('is an item without brackets as it is, so a hand-written key still points', () {
      expect(linkTargets('GHO-9, GHO-10'), ['GHO-9', 'GHO-10']);
      expect(linkTargets('[GHO-9]'), ['GHO-9']);
    });

    test('is nothing for nothing', () {
      expect(linkTargets(''), isEmpty);
      expect(linkTargets(null), isEmpty);
      expect(linkTargets('[[ ]]'), isEmpty);
    });
  });

  group('a value written', () {
    test('is left as it is where YAML reads it as words', () {
      for (final value in ['In progress', 'GHO-12', '2026-10-03', '3', "Won't do", 'C# notes', 'a:b', 'https://a.b/c', 'x - y', 'true', '50%']) {
        expect(yamlValue(value), value, reason: value);
      }
    });

    test('is quoted where YAML would misread it', () {
      for (final value in ['[[GHO-9]]', '[a]', '{a}', '#bug', '@sam', '`code`', 'a: b', 'ends:', 'a #comment', '- item', '-', '? x', ': x', '!tag', '&a', '*a', '|', '>', '%x', ',a', ' padded', 'padded ', '']) {
        expect(yamlValue(value), '"$value"', reason: value);
      }
    });

    test('is quoted in single quotes where the words have a double quote or a backslash, a single one doubled', () {
      expect(yamlValue('"quoted"'), '\'"quoted"\'');
      expect(yamlValue('say "hi": now'), '\'say "hi": now\'');
      expect(yamlValue(r'C:\notes: x'), r"'C:\notes: x'");
      expect(yamlValue('"It\'s"'), '\'"It\'\'s"\'');
      expect(yamlValue("'single'"), '"\'single\'"');
    });

    test('is one line', () {
      expect(yamlValue('two\nlines'), 'two lines');
      expect(yamlValue('a:\n b'), '"a: b"');
    });

    test('as a list is written across, each item quoted where it must be', () {
      expect(yamlList(['bug', 'ui']), '[bug, ui]');
      expect(yamlList(['[[GHO-9]]', '[[GHO-10]]']), '["[[GHO-9]]", "[[GHO-10]]"]');
      expect(yamlList(['a, b', 'c]', '{d}', '#e', 'f g']), '["a, b", "c]", "{d}", "#e", f g]');
      expect(yamlList([]), '[]');
    });

    test('comes back as it went, through the reader', () {
      for (final value in ['[[GHO-9]]', 'say "hi": now', "It's", '"It\'s"', r'C:\notes', '@sam', 'a #b', ' padded ', 'In progress']) {
        final body = withProperty('# A', 'x', value);
        expect(frontMatterValue(body, 'x'), value, reason: value);
        expect(propertiesOf(body).first.value, value, reason: value);
      }
      for (final list in [
        ['[[GHO-9]]', '[[GHO-10]]'],
        ['a, b', 'c'],
        ['bug'],
        ['"q"', "it's"],
      ]) {
        expect(propertyList(frontMatterValue(withProperty('# A', 'x', list), 'x')), list);
      }
    });
  });

  group('a property written into a note', () {
    test('replaces the key where it is, in any case, and keeps the rest', () {
      expect(withProperty(ticket, 'status', 'Done'), ticket.replaceFirst('status: In progress', 'status: Done'));
      expect(withProperty('---\nStatus: To do\ntitle: "A"\n---\nWords', 'status', 'Done'), '---\nstatus: Done\ntitle: "A"\n---\nWords');
    });

    test('adds a key last, and makes front matter where there is none', () {
      expect(withProperty('---\ntype: ticket\n---\n# A', 'labels', ['bug', 'ui']), '---\ntype: ticket\nlabels: [bug, ui]\n---\n# A');
      expect(withProperty('# A\n', 'blocked-by', '[[GHO-9]]'), '---\nblocked-by: "[[GHO-9]]"\n---\n# A\n');
    });

    test('takes a key off for null or an empty list, and front matter that held nothing else with it', () {
      expect(withProperty('---\ntype: ticket\ndue: 2026-10-03\n---\n# A', 'due', null), '---\ntype: ticket\n---\n# A');
      expect(withProperty('---\nlabels: [bug]\n---\n# A', 'labels', [' ', '']), '# A');
      expect(withProperty('# A', 'due', null), '# A');
    });

    test('writes an empty value as two quotes, which reads back as nothing', () {
      final body = withProperty('# A', 'assignee', '');
      expect(body, '---\nassignee: ""\n---\n# A');
      expect(frontMatterValue(body, 'assignee'), '');
    });

    test('leaves the note as it was for a key front matter cannot hold', () {
      for (final key in ['', 'two words', 'a:b', '#tag', 'é']) {
        expect(isPropertyKey(key), isFalse, reason: key);
        expect(withProperty('# A', key, 'x'), '# A', reason: key);
      }
      for (final key in ['due', 'blocked-by', 'a.b', 'x_1']) {
        expect(isPropertyKey(key), isTrue, reason: key);
      }
    });

    test('leaves front matter the list still reads as front matter', () {
      var body = '---\ntitle: "Fix it"\n---\n# Fix it';
      body = withProperty(body, 'blocked-by', ['[[GHO-9]]', '[[GHO-10]]']);
      body = withProperty(body, 'labels', ['bug']);
      body = withProperty(body, 'assignee', '@sam');
      expect(frontMatterEnd(body.split('\n')), 6);
      expect(body, '---\ntitle: "Fix it"\nblocked-by: ["[[GHO-9]]", "[[GHO-10]]"]\nlabels: [bug]\nassignee: "@sam"\n---\n# Fix it');
    });
  });

  group('a ticket', () {
    test('is a note whose type is ticket, in any case', () {
      expect(isTicket(ticket), isTrue);
      expect(isTicket('---\ntype: Ticket\n---\n'), isTrue);
      expect(isTicket('---\ntype: "ticket"\n---\n'), isTrue);
      expect(isTicket('---\ntype: note\n---\n'), isFalse);
      expect(isTicket('# Ticket\n\ntype: ticket'), isFalse);
      expect(isTicket(''), isFalse);
    });

    test('is read whole: its id, its status and where it stands, its person, priority, days, estimate and links', () {
      expect(ticketOf(ticket)!.toJson(), {
        'id': 'GHO-12',
        'status': 'In progress',
        'category': 'doing',
        'assignee': 'Sam',
        'priority': 'high',
        'due': '2026-10-03',
        'start': null,
        'estimate': 3,
        'blockedBy': ['GHO-9'],
        'parent': null,
        'labels': <String>[],
      });
    });

    test('reads what a person may write by hand the way they meant it', () {
      final body = ['---', 'type: ticket', 'id: gho-7', 'assignee: "@sam"', 'priority: ⏫', 'due: Friday', 'start: 2026-10-01', 'estimate: 2.5 days', 'blocked-by: ["[[GHO-5]]", "[[GHO-6|the cache]]"]', 'parent: "[[GHO-1]]"', 'labels: ["#bug", ui]', '---', ''].join('\n');
      expect(
        ticketOf(body),
        const Ticket(
          id: 'GHO-7',
          status: null,
          category: StatusCategory.todo,
          assignee: 'sam',
          priority: 'high',
          due: null,
          start: '2026-10-01',
          estimate: 2.5,
          blockedBy: ['GHO-5', 'GHO-6'],
          parent: 'GHO-1',
          labels: ['bug', 'ui'],
        ),
      );
    });

    test('reads nothing it cannot use as nothing', () {
      // `urgent` is a ticket's priority since 2026-10-31 (Matt: `priority: urgent|high|medium|low`), so the one that
      // reads as nothing is a word that is none.
      final read = ticketOf('---\ntype: ticket\nid: twelve\nassignee:\npriority: whenever\nestimate: some\n---\n')!;
      expect([read.id, read.assignee, read.priority, read.estimate, read.blockedBy, read.parent], [null, null, null, null, <String>[], null]);
    });

    test('places its status in its notebook’s workflow', () {
      const body = '---\ntype: ticket\nstatus: Live\n---\n';
      expect(ticketOf(body)?.category, StatusCategory.todo);
      expect(ticketOf(body, ['Ideas', 'Building', 'Live'])?.category, StatusCategory.done);
    });

    test('is no ticket for a note that is not one', () {
      expect(ticketOf('---\nid: GHO-1\n---\n'), isNull);
    });

    test('has its properties named once, for a panel and a query to share', () {
      expect([for (final each in ticketProperties) '${each.key}:${each.kind.name}'], [
        'type:text',
        'id:id',
        'status:status',
        'assignee:person',
        'priority:priority',
        'due:date',
        'start:date',
        'estimate:number',
        'blocked-by:links',
        'parent:link',
        'labels:list',
        'component:text',
        'cycle:link',
        'milestone:link',
      ]);
      expect(ticketProperties.firstWhere((each) => each.key == 'blocked-by').label, 'Blocked by');
      expect(propertyKind('Due'), PropertyKind.date);
      expect(propertyKind(' assignee '), PropertyKind.person);
      expect(propertyKind('title'), PropertyKind.text);
    });
  });

  group('statuses', () {
    test('are the default workflow where a notebook names none', () {
      expect(defaultStatuses, ['Backlog', 'To do', 'In progress', 'In review', 'Done']);
      expect(statusesOf(null), defaultStatuses);
      expect(statusesOf('---\nbook: true\n---\n# Book'), defaultStatuses);
      expect(statusesOf('---\nbook: true\nstatuses: []\n---\n'), defaultStatuses);
    });

    test('are a notebook’s own, as a flow list or with commas, each once', () {
      expect(statusesOf('---\nbook: true\nstatuses: [Ideas, Building, Live]\n---\n'), ['Ideas', 'Building', 'Live']);
      expect(statusesOf('---\nbook: true\nstatuses: To do, Doing, Done, done\n---\n'), ['To do', 'Doing', 'Done']);
    });

    test('stand where their words say: done, under way, or not started', () {
      for (final status in ['Done', 'done', 'DONE', 'Closed', 'Resolved', 'Complete', "Won't do", 'Won’t do', 'Wont fix', "won't-fix", 'Cancelled', 'Canceled', 'Duplicate', 'Shipped', 'All done', 'Done this week']) {
        expect(statusCategory(status), StatusCategory.done, reason: status);
      }
      for (final status in ['In progress', 'in-progress', 'In review', 'In QA', 'In design', 'Doing', 'Review', 'Blocked', 'WIP']) {
        expect(statusCategory(status), StatusCategory.doing, reason: status);
      }
      for (final status in ['Backlog', 'To do', 'To-Do', 'todo', 'Open', 'New', 'Ready', '', null, 'Inbox']) {
        expect(statusCategory(status), StatusCategory.todo, reason: '$status');
      }
    });

    test('stand by their place in a workflow where their words say nothing: first not started, last done, between under way', () {
      const workflow = ['Ideas', 'Building', 'Polishing', 'Live'];
      expect(statusCategory('Ideas', workflow), StatusCategory.todo);
      expect(statusCategory('building', workflow), StatusCategory.doing);
      expect(statusCategory('Polishing', workflow), StatusCategory.doing);
      expect(statusCategory('Live', workflow), StatusCategory.done);
      expect(statusCategory('Live'), StatusCategory.todo);
      expect(statusCategory('Elsewhere', workflow), StatusCategory.todo);
      expect(statusCategory('Only', ['Only']), StatusCategory.todo);
      // What the words say wins over the place: a workflow that ends in Backlog does not finish there.
      expect(statusCategory('Backlog', ['Doing', 'Backlog']), StatusCategory.todo);
    });
  });

  group('issue keys', () {
    test('are a notebook’s key, a dash and a number, as Jira writes them', () {
      for (final key in ['GHO-1', 'GHO-12', 'AB-999999', 'A1-3', 'ABCDEFGHIJ-1']) {
        expect(issueKey.hasMatch(key), isTrue, reason: key);
      }
      for (final key in ['GHO-0', 'GHO-012', 'G-1', '1GH-1', 'GHO-1234567', 'ABCDEFGHIJK-1', 'GHO12', 'GHO-', 'gho-12', 'GHO_12']) {
        expect(issueKey.hasMatch(key), isFalse, reason: key);
      }
      for (final key in ['GH', 'GHO', 'A1', 'ABCDEFGHIJ']) {
        expect(projectKey.hasMatch(key), isTrue, reason: key);
      }
      for (final key in ['G', '1G', 'GHO-', 'ABCDEFGHIJK', 'gho']) {
        expect(projectKey.hasMatch(key), isFalse, reason: key);
      }
    });

    test('are read in any case, as a link’s title matches, and give their number', () {
      expect(issueKeyOf(' gho-12 '), 'GHO-12');
      expect(issueKeyOf('GHO-12 the loop'), isNull);
      expect(issueKeyOf(null), isNull);
      expect(isIssueKey('Gho-3'), isTrue);
      expect(isIssueKey('Fix it'), isFalse);
      expect(issueNumber('GHO-12'), 12);
      expect(issueNumber('gho-9'), 9);
      expect(issueNumber('GHO'), isNull);
    });

    test('take a notebook’s key from its key property, upper-cased, where it is one', () {
      expect(notebookKey('---\nbook: true\nkey: GHO\n---\n'), 'GHO');
      expect(notebookKey('---\nbook: true\nkey: gho\n---\n'), 'GHO');
      expect(notebookKey('---\nbook: true\nkey: "ops2"\n---\n'), 'OPS2');
      for (final said in ['G', '12', 'GHO-1', 'TOO-LONG-KEY', 'two words', '']) {
        expect(notebookKey('---\nbook: true\nkey: $said\n---\n'), isNull, reason: said);
      }
      expect(notebookKey('---\nbook: true\n---\n'), isNull);
      expect(notebookKey('# key: GHO'), isNull);
    });

    test('give a ticket its id from its id property', () {
      expect(ticketIdOf(ticket), 'GHO-12');
      expect(ticketIdOf('---\nid: gho-3\n---\n'), 'GHO-3');
      expect(ticketIdOf('---\nid: 20260930\n---\n'), isNull);
      expect(ticketIdOf('# GHO-3'), isNull);
    });
  });

  group('the next id', () {
    test('is one more than the highest the notes give the key, in an id or anywhere in their words', () {
      const notes = ['---\ntype: ticket\nid: GHO-3\n---\n', '---\ntype: ticket\nid: GHO-12\n---\nBlocked by [[GHO-9]]', 'see gho-14 in passing'];
      expect(nextIssueId('GHO', notes), 'GHO-15');
      expect(nextIssueId('gho', notes.sublist(0, 2)), 'GHO-13');
    });

    test('never fills a gap, so a number once given is not given again', () {
      expect(nextIssueId('GHO', ['id: GHO-1', 'id: GHO-7']), 'GHO-8');
    });

    test('is the first where nothing names the key, and counts no other key’s numbers', () {
      expect(nextIssueId('GHO', []), 'GHO-1');
      expect(nextIssueId('GHO', ['XGHO-40 and GHO_2 and GHOST-5 and AGHO-9', 'GHO-1234567']), 'GHO-1');
      expect(nextIssueId('OPS', ['GHO-40']), 'OPS-1');
    });

    test('is nothing for a key that is not one, or past the last number a key can have', () {
      expect(nextIssueId('G', []), isNull);
      expect(nextIssueId('GHO-1', []), isNull);
      expect(nextIssueId('GHO', ['GHO-999999']), isNull);
      expect(nextIssueId('GHO', ['GHO-999998']), 'GHO-999999');
    });
  });

  group('a number a value starts with', () {
    // Not a web case: `Number.parseFloat` is the page's own, and [parseFloat] stands in for it.
    test('is read as the page reads it', () {
      expect(parseFloat('3'), 3);
      expect(parseFloat('2.5 days'), 2.5);
      expect(parseFloat('  -4.'), -4);
      expect(parseFloat('.5x'), 0.5);
      expect(parseFloat('1e3'), 1000);
      expect(parseFloat('+7,5'), 7);
      expect(parseFloat('about 3'), isNull);
      expect(parseFloat(''), isNull);
      expect(parseFloat('Infinity'), double.infinity);
    });
  });
}
