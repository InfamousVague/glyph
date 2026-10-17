// What an outgoing webhook says (lib/integrations/webhooks/payload.dart, docs/INTEGRATIONS.md §1): the body's shape,
// its signature, the lines a change added or changed, a to-do ticked, and which event a change is to a hook.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/integrations/webhooks/payload.dart';
import 'package:ghost_md/integrations/webhooks/setup.dart';

void main() {
  test('the body is the contract\'s: the event, the time to the second in UTC, and the note', () {
    final body = payloadOf(
      event: WebhookEvent.edited,
      at: DateTime.utc(2026, 10, 17, 18, 0, 0, 412),
      id: 'n1',
      body: '# Baby\n\n- [x] Buy a crib',
      workspace: 'Family',
      changed: const ['- [x] Buy a crib'],
    );
    expect(jsonDecode(body), {
      'event': 'note.edited',
      'at': '2026-10-17T18:00:00Z',
      'note': {'id': 'n1', 'title': 'Baby', 'workspace': 'Family', 'url': 'ghostmd://note/n1', 'body': '# Baby\n\n- [x] Buy a crib', 'changed': ['- [x] Buy a crib']},
    });
    expect((jsonDecode(payloadOf(event: WebhookEvent.created, at: DateTime.utc(2026), id: 'n2', body: 'Hi', changed: const ['Hi'])) as Map)['note']['workspace'], isNull);
  });

  test('the signature is sha256= and the hex HMAC-SHA256 of the body\'s very bytes', () {
    // The standard's own example (Wikipedia's HMAC page, key "key").
    expect(signatureOf('key', utf8.encode('The quick brown fox jumps over the lazy dog')), 'sha256=f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8');
    expect(signatureHeader, 'X-Ghost-Signature');
  });

  test('changed is the lines added or changed, in order, and nothing for lines only taken out', () {
    expect(changedLines('a\nb\nc', 'a\nb\nc'), isEmpty);
    expect(changedLines('', '# New\n\nfirst words'), ['# New', 'first words']);
    expect(changedLines('# List\n- one\n- two', '# List\n- one\n- one and a half\n- two\n- three'), ['- one and a half', '- three']);
    expect(changedLines('# List\n- [ ] Buy a crib\n- [ ] Paint', '# List\n- [x] Buy a crib\n- [ ] Paint'), ['- [x] Buy a crib']);
    expect(changedLines('a\nb\nc', 'a\nc'), isEmpty);
    // A line moved reads as changed where it left the order.
    expect(changedLines('a\nb\nc', 'c\na\nb'), ['c']);
    // Blank lines are not news.
    expect(changedLines('a', 'a\n\n\nb'), ['b']);
  });

  test('a to-do ticked is one the words before had open', () {
    const before = '- [ ] Buy a crib\n- [ ] Paint\n1. [ ] Call';
    expect(ticked(before, ['- [x] Buy a crib', '- [x] Something new', '1. [X] Call', '- [ ] Paint']), ['- [x] Buy a crib', '1. [X] Call']);
  });

  test('which event a change is: made, ticked or edited, as the hook asked', () {
    final made = changeOf(null, '# New');
    final edited = changeOf('# A\nold', '# A\nnew');
    final done = changeOf('- [ ] Crib', '- [x] Crib');
    final nothing = changeOf('a\nb', 'a');
    final all = WebhookEvent.values.toSet();
    expect((eventFor(all, made), eventFor({WebhookEvent.edited}, made)), (WebhookEvent.created, null));
    expect((eventFor(all, edited), eventFor({WebhookEvent.todoDone}, edited)), (WebhookEvent.edited, null));
    expect((eventFor(all, done), eventFor({WebhookEvent.edited}, done)), (WebhookEvent.todoDone, WebhookEvent.edited));
    expect(eventFor(all, nothing), isNull);
  });

  test('a URL is a secure address, or a plain one on this computer', () {
    expect(webhookUrl('https://hooks.zapier.com/hooks/catch/1/abc/').url, 'https://hooks.zapier.com/hooks/catch/1/abc/');
    expect(webhookUrl('http://localhost:8080/in').url, 'http://localhost:8080/in');
    expect(webhookUrl('http://example.com/in').problem, contains('secure'));
    expect(webhookUrl('ftp://example.com').problem, isNotNull);
    expect(webhookUrl('not a url').problem, isNotNull);
    expect(webhookUrl('').problem, 'Paste the URL to tell.');
  });

  test('the setup round-trips, and carries what a newer build keeps beside it', () {
    final setup = WebhookSetup.fromJson({
      'outgoing': [
        {'id': 'h1', 'url': 'https://x.test/h', 'events': ['note.created', 'todo.done', 'something.new'], 'scope': {'kind': 'tag', 'value': '#Work'}, 'secret': 's'},
        {'url': 'no id'},
      ],
      'incoming': {'later': true},
    });
    expect(setup.outgoing.single.events, {WebhookEvent.created, WebhookEvent.todoDone});
    expect(setup.outgoing.single.scope, const WebhookScope(ScopeKind.tag, 'work'));
    expect(setup.toJson()['incoming'], {'later': true});
    expect(WebhookSetup.fromJson(setup.toJson()), setup);
  });
}
