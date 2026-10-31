import 'package:ghost_md/core/query/query.dart';

/// The library the ticket features' tests read: two notebooks of your own (Waitlist, key WAIT; Launch, key GHO) and
/// one of a team's (HelloTrade's Payments, key PAY), with tickets assigned to Matt, to Sam and to nobody, made by
/// hand, by a form, by mail and by the connector. "Today" is Wednesday 28 October 2026; its week ends on Sunday the
/// 1st of November.
const String today = '2026-10-28';

int noon(String day) {
  final parts = day.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2], 12).millisecondsSinceEpoch;
}

QueryNote note(String id, String body, {String created = '2026-10-01', String updated = '2026-10-20'}) => QueryNote(id: id, body: body, createdAt: noon(created), updatedAt: noon(updated));

String ticket(String id, String title, {String status = 'To do', String? assignee, String? due, String? priority, String more = ''}) =>
    '---\ntype: ticket\nid: $id\nstatus: $status\n${assignee == null ? '' : 'assignee: $assignee\n'}${due == null ? '' : 'due: $due\n'}${priority == null ? '' : 'priority: $priority\n'}$more---\n# $title\n';

/// Which notes are a team's, and whose.
const Map<String, String> teamNotes = {'payments': 'HelloTrade', 'pay1': 'HelloTrade', 'pay2': 'HelloTrade', 'pay3': 'HelloTrade'};

String? teamOf(String id) => teamNotes[id];

final List<QueryNote> notes = [
  note('waitlist', '---\nbook: true\nkey: WAIT\nlabel-colours: {bug: amber, signup: teal}\n---\n# Waitlist\n\n- [[Invite emails bounce]]\n- [[Confirm page copy]]\n- [[Referral counter]]\n- [[Spam sign-ups]]\n'),
  note('launch', '---\nbook: true\nkey: GHO\nstatuses: [Ideas, Building, Live]\n---\n# Launch\n\n- [[Pricing page]]\n- [[Press kit]]\n- [[Launch tweet]]\n'),
  note('payments', '---\nbook: true\nkey: PAY\n---\n# Payments\n\n- [[Refund webhook]]\n- [[Card form focus]]\n- [[Payout report]]\n'),
  // Matt's, in his notebooks and his team's.
  note('wait1', ticket('WAIT-1', 'Invite emails bounce', assignee: 'Matt', due: '2026-10-26', priority: 'high', more: 'labels: [bug, email]\ncomponent: Waitlist\n')),
  note('wait2', ticket('WAIT-2', 'Confirm page copy', assignee: '@matt', due: '2026-10-28', more: 'labels: [ui]\n')),
  note('wait3', ticket('WAIT-3', 'Referral counter', assignee: 'Matt', status: 'Done', due: '2026-10-20')),
  note('gho1', ticket('GHO-1', 'Pricing page', assignee: 'matt', status: 'Building', due: '2026-10-30', priority: 'low')),
  note('gho2', ticket('GHO-2', 'Press kit', assignee: 'Matt', status: 'Ideas', due: '2026-11-09')),
  note('gho3', ticket('GHO-3', 'Launch tweet', assignee: 'Matt', status: 'Ideas', priority: 'highest')),
  note('pay1', ticket('PAY-1', 'Refund webhook', assignee: 'Matt', due: '2026-10-29', priority: 'highest', more: 'labels: [bug, backend]\ncomponent: Webhooks\n')),
  note('pay2', ticket('PAY-2', 'Card form focus', assignee: 'Sam', due: '2026-10-27', more: 'labels: [ui]\n')),
  // Waiting in triage: by a form, by mail, by the connector, marked, and with nobody on it.
  note('wait4', ticket('WAIT-4', 'Spam sign-ups', more: 'via: form\nform: "[[Report a problem]]"\n'), created: '2026-10-27'),
  note('pay3', ticket('PAY-3', 'Payout report', more: 'from: "Dana <dana@example.com>"\n'), created: '2026-10-26'),
  note('loose1', ticket('GHO-9', 'Ask about the logo', assignee: 'Sam', more: 'via: connector\n'), created: '2026-10-25'),
  note('loose2', ticket('GHO-10', 'Retry flaky test', assignee: 'Sam', status: 'New'), created: '2026-10-24'),
  note('loose3', ticket('GHO-11', 'Old idea', assignee: 'Sam', more: 'triage: true\n'), created: '2026-10-23'),
  note('looked', ticket('GHO-12', 'Looked at already', more: 'via: form\ntriaged: 2026-10-20\n'), created: '2026-10-22'),
  note('plain', '# Groceries\n\n- [ ] Milk @matt\n'),
];
