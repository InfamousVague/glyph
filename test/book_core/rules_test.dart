// A notebook's rules for its tickets (lib/book/rules.dart; Matt, 2026-10-31, "Rules / automations"): each sentence
// read and written back the same, the lines that are no rule said with why, and which rules a change or the clock
// sets off.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/rules.dart';
import 'package:ghost_md/core/properties.dart';

const String fence = '''
# When a ticket ships, the team hears.
When status becomes Done, post to Slack #eng "{id} {title} shipped"
When a ticket is created, set assignee to Sam
When a ticket is assigned, notify the assignee
When due passes and priority is High, notify me "{id} is overdue"
When blocked for 3 days, post to Discord #triage "{id} has been stuck"
When label bug is added, set priority to High, then run the Claude rule "Triage a bug"
When status becomes "Research and design", make a note from "Review checklist" in Kiln called "Review {id}"
When status changes and assignee is not Sam, ask Claude "Say what changed"
When the moon is full, howl
''';

String ticket({String status = 'To do', String? assignee, String? due, String? priority, String labels = ''}) => [
      '---',
      'type: ticket',
      'id: HT-12',
      'status: $status',
      if (assignee != null) 'assignee: $assignee',
      if (due != null) 'due: $due',
      if (priority != null) 'priority: $priority',
      if (labels.isNotEmpty) 'labels: [$labels]',
      '---',
      '# Fix the login',
      '',
    ].join('\n');

void main() {
  group('reading', () {
    final set = rulesOf(fence);

    test('every sentence is a rule but the one it cannot read, which is said with why', () {
      expect(set.rules, hasLength(8));
      expect(set.problems, hasLength(1));
      expect(set.problems.single.text, 'When the moon is full, howl');
      expect(set.problems.single.why, contains('the moon is full'));
    });

    test('each trigger, test and action as written', () {
      final r = set.rules;
      expect(r[0].when, const RuleWhen(RuleTrigger.status, value: 'Done'));
      expect(r[0].actions.single, const RuleAction(RuleVerb.post, {'to': 'slack', 'channel': 'eng', 'text': '{id} {title} shipped'}));
      expect(r[1].when.trigger, RuleTrigger.created);
      expect(r[1].actions.single, const RuleAction(RuleVerb.set, {'field': 'assignee', 'value': 'Sam'}));
      expect(r[2].when, const RuleWhen(RuleTrigger.assigned));
      expect(r[2].actions.single, const RuleAction(RuleVerb.notify, {'person': 'assignee'}));
      expect(r[3].when.trigger, RuleTrigger.duePasses);
      expect(r[3].conditions.single, const RuleCondition('priority', 'High'));
      expect(r[3].actions.single, const RuleAction(RuleVerb.notify, {'person': 'me', 'text': '{id} is overdue'}));
      expect(r[4].when, const RuleWhen(RuleTrigger.blocked, days: 3));
      expect(r[4].actions.single.plugin, 'discord');
      expect(r[5].when, const RuleWhen(RuleTrigger.labelAdded, value: 'bug'));
      expect(r[5].actions, [const RuleAction(RuleVerb.set, {'field': 'priority', 'value': 'High'}), const RuleAction(RuleVerb.claude, {'rule': 'Triage a bug'})]);
      expect(r[6].when, const RuleWhen(RuleTrigger.status, value: 'Research and design'));
      expect(r[6].actions.single, const RuleAction(RuleVerb.make, {'template': 'Review checklist', 'in': 'Kiln', 'title': 'Review {id}'}));
      expect(r[7].when, const RuleWhen(RuleTrigger.status));
      expect(r[7].conditions.single, const RuleCondition('assignee', 'Sam', not: true));
      expect(r[7].actions.single, const RuleAction(RuleVerb.claude, {'prompt': 'Say what changed'}));
    });

    test('other ways of saying it read the same', () {
      expect(ruleOf('- when the status changes to Done, post it to slack').rule!.text, 'When status becomes Done, post to Slack');
      expect(ruleOf('When it is overdue, tell @sam').rule!.text, 'When due passes, notify sam');
      expect(ruleOf('When a label is added, clear assignee').rule!.text, 'When a label is added, set assignee to nothing');
      expect(ruleOf('When blocked for more than 1 day, notify me').rule!.text, 'When blocked for 1 day, notify me');
      expect(ruleOf('When assigned to @Priya, new note from template Onboarding').rule!.text, 'When a ticket is assigned to Priya, make a note from "Onboarding"');
      expect(ruleOf('When created and type = bug; set status to Triage').rule, isNull, reason: 'the comma before what it does is needed');
      expect(ruleOf('When created and type = bug, set status to Triage; notify me').rule!.actions, hasLength(2));
    });

    test('what is wrong is said in a sentence', () {
      expect(ruleOf('If done, post to Slack').why, 'A rule starts with “When”.');
      expect(ruleOf('When status becomes Done').why, contains('after a comma'));
      expect(ruleOf('When status becomes Done, dance').why, contains('dance'));
      expect(ruleOf('When created and the sky, notify me').why, contains('the sky'));
    });
  });

  group('writing', () {
    test('a rule written and read again is the same rule, word for word', () {
      for (final rule in rulesOf(fence).rules) {
        final again = ruleOf(rule.text).rule;
        expect(again, isNotNull, reason: rule.text);
        expect(again!.text, rule.text);
        expect(again.when, rule.when);
        expect(again.conditions, rule.conditions);
        expect(again.actions, rule.actions);
      }
    });

    test('a value that would read otherwise is quoted, and its quotes kept', () {
      const rule = TicketRule(when: RuleWhen(RuleTrigger.status, value: 'Done, really'), actions: [RuleAction(RuleVerb.post, {'to': 'slack', 'text': 'Say "hi"'})]);
      expect(rule.text, r'When status becomes "Done, really", post to Slack "Say \"hi\""');
      expect(ruleOf(rule.text).rule!.actions.single['text'], 'Say "hi"');
      expect(ruleOf(rule.text).rule!.when.value, 'Done, really');
    });

    test('the id is the words: the same on every device, another for other words', () {
      final a = ruleOf('When status becomes Done, notify me').rule!;
      expect(a.id, ruleOf('when status becomes Done, notify me').rule!.id);
      expect(a.id, isNot(ruleOf('When status becomes Done, notify Sam').rule!.id));
      expect(a.id, hasLength(8));
    });

    test('the fence in the index, made, written over, and taken out', () {
      const notebook = '---\nkey: HT\n---\n# Help desk\n\n- [[HT-1 Fix it]]\n';
      final made = withRulesText(notebook, 'When a ticket is created, notify me');
      expect(made, '---\nkey: HT\n---\n# Help desk\n\n- [[HT-1 Fix it]]\n\n```rules\nWhen a ticket is created, notify me\n```\n');
      expect(rulesIn(made).rules.single.when.trigger, RuleTrigger.created);
      final changed = withRulesText(made, 'When due passes, notify me');
      expect(rulesIn(changed).rules.single.when.trigger, RuleTrigger.duePasses);
      expect(changed.indexOf('```rules'), made.indexOf('```rules'));
      expect(withRulesText(changed, ''), '---\nkey: HT\n---\n# Help desk\n\n- [[HT-1 Fix it]]\n');
    });

    test('the builder writes each rule over its own line, keeping comments and lines it cannot read', () {
      final notebook = '# Desk\n\n```rules\n$fence```\n';
      final read = rulesIn(notebook);
      final rules = [...read.rules]..removeAt(1);
      rules[0] = rules[0].copyWith(actions: const [RuleAction(RuleVerb.notify, {'person': 'me'})]);
      rules.add(const TicketRule(when: RuleWhen(RuleTrigger.created), actions: [RuleAction(RuleVerb.set, {'field': 'priority', 'value': 'Low'})]));
      final written = withRules(notebook, rules, read: read);
      final lines = rulesFenceOf(written)!.text.split('\n');
      expect(lines.first, '# When a ticket ships, the team hears.');
      expect(lines[1], 'When status becomes Done, notify me');
      expect(lines, isNot(contains('When a ticket is created, set assignee to Sam')));
      expect(lines, contains('When the moon is full, howl'));
      expect(lines.last, 'When a ticket is created, set priority to Low');
    });
  });

  group('what sets a rule off', () {
    final rules = rulesOf(fence).rules;
    List<String> fired(String? before, String after) {
      final was = before == null ? null : ticketOf(before);
      return [for (final f in firedByChange(rules, before: before, after: after, was: was, now: ticketOf(after)!)) '${rules.indexOf(f.rule)} ${f.cause}'];
    }

    test('a status it moves to, once, and not a status it stays in', () {
      expect(fired(ticket(), ticket(status: 'Done')), ['0 status:done', '7 status:done']);
      expect(fired(ticket(status: 'Done'), ticket(status: 'Done')), isEmpty);
      expect(fired(ticket(status: 'done'), ticket(status: 'Done')), isEmpty, reason: 'any case');
      expect(fired(ticket(status: 'Done', assignee: 'Sam'), ticket(assignee: 'Sam')), isEmpty, reason: 'its test: not Sam');
    });

    test('a ticket made, with what it was made with', () {
      expect(fired(null, ticket(assignee: 'Priya')), ['1 created', '2 assigned:priya', '7 status:to do']);
    });

    test('an assignee given or changed, not taken off', () {
      expect(fired(ticket(), ticket(assignee: '@Sam')), ['2 assigned:sam']);
      expect(fired(ticket(assignee: 'Sam'), ticket()), isEmpty);
    });

    test('a label added, not one it had', () {
      expect(fired(ticket(labels: 'ui'), ticket(labels: 'ui, bug')), ['5 label:bug']);
      expect(fired(ticket(labels: 'bug'), ticket(labels: 'bug, ui')), isEmpty);
    });

    test('the clock: a due day passed while not done, a block that has lasted', () {
      const day = 86400000;
      final overdue = ticket(due: '2026-10-29', priority: 'High');
      expect([for (final f in firedByClock(rules, body: overdue, ticket: ticketOf(overdue)!, today: '2026-10-30', now: 0)) f.cause], ['due:2026-10-29']);
      expect(firedByClock(rules, body: overdue, ticket: ticketOf(overdue)!, today: '2026-10-29', now: 0), isEmpty, reason: 'due today has not passed');
      final low = ticket(due: '2026-10-29', priority: 'Low');
      expect(firedByClock(rules, body: low, ticket: ticketOf(low)!, today: '2026-10-30', now: 0), isEmpty, reason: 'its test');
      final done = ticket(status: 'Done', due: '2026-10-29', priority: 'High');
      expect(firedByClock(rules, body: done, ticket: ticketOf(done)!, today: '2026-10-30', now: 0), isEmpty);
      final plain = ticket();
      expect([for (final f in firedByClock(rules, body: plain, ticket: ticketOf(plain)!, today: '2026-10-30', blockedSince: 10, now: 10 + 3 * day)) f.cause], ['blocked:10']);
      expect(firedByClock(rules, body: plain, ticket: ticketOf(plain)!, today: '2026-10-30', blockedSince: 10, now: 3 * day), isEmpty);
    });

    test('blocked: waiting on a ticket not done, or a status called Blocked, and not done itself', () {
      expect(isBlockedTicket(ticketOf(ticket())!, waiting: true), isTrue);
      expect(isBlockedTicket(ticketOf(ticket(status: 'Blocked'))!, waiting: false), isTrue);
      expect(isBlockedTicket(ticketOf(ticket())!, waiting: false), isFalse);
      expect(isBlockedTicket(ticketOf(ticket(status: 'Done'))!, waiting: true), isFalse);
    });

    test('a ticket’s words in braces', () {
      expect(filledIn('{id} {title} is {status}, {assignee}{nothing}', body: ticket(assignee: 'Sam'), title: 'Fix the login'), 'HT-12 Fix the login is To do, Sam');
    });
  });

  test('the notebook’s GitHub repos and what a merge does', () {
    expect(githubReposOf('---\ngithub: ghost/app\n---\n'), ['ghost/app']);
    expect(githubReposOf('---\ngithub: [ghost/app, ghost/site, nonsense]\n---\n'), ['ghost/app', 'ghost/site']);
    expect(onMergeOf('---\ngithub: ghost/app\n---\n'), 'done');
    expect(onMergeOf('---\non-merge: off\n---\n'), isNull);
    expect(onMergeOf('---\non-merge: In review\n---\n'), 'In review');
  });
}
