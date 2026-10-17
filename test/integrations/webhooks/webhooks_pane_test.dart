// Settings › Webhooks (lib/settings/panes/webhooks_pane.dart, docs/INTEGRATIONS.md §1): an outgoing hook added with
// its events, scope and secret, listed with how it went, tested and removed; Local only said; signed out, the incoming
// card says to sign in; signed in, the account's hooks listed, a new one made with a default note picked from the
// notes, its URL shown this once with Copy and the examples, and deleted. Against a service in memory.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/integrations/webhooks/incoming.dart';
import 'package:ghost_md/integrations/webhooks/outgoing.dart';
import 'package:ghost_md/integrations/webhooks/setup.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/integrations/webhooks/webhooks_pane.dart';
import 'package:glacier/glacier.dart';

import '../../settings/support.dart';

List<String> titles(WidgetTester tester) => [for (final section in tester.widgetList<PaneSection>(find.byType(PaneSection, skipOffstage: false))) section.title ?? ''];

Finder row(String label) => find.byWidgetPredicate((w) => w is SettingRow && w.label == label, skipOffstage: false);

String? hintOf(WidgetTester tester, String label) {
  final hint = tester.widget<SettingRow>(row(label)).hint;
  return hint is Text ? hint.data : null;
}

Future<void> tapFound(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await settleSettings(tester);
}

Future<void> type(WidgetTester tester, String key, String text) async {
  final field = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

/// glyph-api's hooks routes, in memory (server/src/hooks.rs).
class HooksService {
  final List<Map<String, Object?>> hooks = [];
  final List<String> calls = [];
  var made = 0;

  Future<FetchResponse> fetch(FetchRequest request) async {
    final path = request.url.path.replaceFirst('/api/v1/', '');
    calls.add('${request.method} $path');
    if (request.method == 'GET' && path == 'hooks') return FetchResponse.json(200, hooks);
    if (request.method == 'POST' && path == 'hooks') {
      made += 1;
      final body = (FetchResponse(200, bytes: request.body).text);
      final note = RegExp(r'"note":"([^"]*)"').firstMatch(body)?.group(1);
      final name = RegExp(r'"name":"([^"]*)"').firstMatch(body)!.group(1);
      final hook = {'id': 'hook$made', 'name': name, 'note': note, 'createdAt': 1792275541000, 'lastUsedAt': null};
      hooks.add(hook);
      return FetchResponse.json(201, {...hook, 'url': 'https://hooks.test/api/hooks/secret$made'});
    }
    if (request.method == 'DELETE' && path.startsWith('hooks/')) {
      hooks.removeWhere((each) => each['id'] == path.substring('hooks/'.length));
      return FetchResponse(204);
    }
    return FetchResponse.json(404, {'error': 'no such route'});
  }
}

void main() {
  setUpAll(loadAppFonts);

  late PreferencesStore prefs;
  late WebhookSender sender;
  late List<FetchRequest> sent;

  setUp(() {
    prefs = PreferencesStore()..startWithoutStorage();
    sent = [];
    final kept = MemoryStored();
    sender = WebhookSender(prefs: prefs, kept: () => kept, on: () => true, wait: (_) async {}, fetch: (request) async {
      sent.add(request);
      return FetchResponse(200);
    });
  });

  tearDown(() => sender.dispose());

  const notes = [
    Note(id: 'g', body: '# Groceries\n\n- milk', createdAt: 1, updatedAt: 1),
    Note(id: 'b', body: '---\nbook: true\n---\n# Trip\n\n- [[Packing]]', createdAt: 1, updatedAt: 1),
  ];

  Future<void> open(WidgetTester tester, {IncomingHooks? incoming}) async {
    await pumpSettings(tester, SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: WebhooksPane(sender: sender, prefs: prefs, incoming: incoming, notes: () async => notes))));
  }

  testWidgets('an outgoing hook is added with its events, a notebook and a secret, listed, tested and removed', (tester) async {
    await open(tester);
    expect(titles(tester), ['Outgoing webhooks', 'New outgoing webhook', 'Incoming webhooks']);
    expect(find.text('Sign in to make one'), findsOneWidget);

    await type(tester, 'webhook-url', 'http://example.com/in');
    await tapFound(tester, find.byKey(const ValueKey('webhook-add')));
    expect(find.text('Only a secure address (https://) is told: your notes go in the body.'), findsOneWidget);

    await type(tester, 'webhook-url', 'https://hooks.zapier.test/catch/1');
    tester.widget<GlacierSwitch>(find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == 'A to-do is ticked', skipOffstage: false)).onCheckedChange!(true);
    await settleSettings(tester);
    await tapFound(tester, find.descendant(of: find.byKey(const ValueKey('webhook-scope-notebook')), matching: find.byType(Pick)));
    expect(row('Trip'), findsOneWidget, reason: 'the notebooks, from the notes');
    await tapFound(tester, find.descendant(of: row('Trip'), matching: find.byType(Pick)));
    await type(tester, 'webhook-secret', 'shh');
    await tapFound(tester, find.byKey(const ValueKey('webhook-add')));

    final hook = sender.setup.outgoing.single;
    expect((hook.url, hook.scope, hook.secret), ('https://hooks.zapier.test/catch/1', const WebhookScope(ScopeKind.notebook, 'b'), 'shh'));
    expect(hook.events, {WebhookEvent.edited, WebhookEvent.todoDone});
    expect(hintOf(tester, 'hooks.zapier.test'), 'note.edited, todo.done · Pages of Trip · signed\nNothing sent yet.');

    await tapFound(tester, find.descendant(of: row('hooks.zapier.test'), matching: find.text('Test')));
    expect(sent.single.headers.keys, contains('X-Ghost-Signature'));
    expect(hintOf(tester, 'hooks.zapier.test'), endsWith('Sent. The URL answered.'));

    await tapFound(tester, find.descendant(of: row('hooks.zapier.test'), matching: find.text('Remove')));
    expect(sender.setup.outgoing, isEmpty);
    expect(find.text('None yet'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('Local only is said, and a hook says nothing is sent', (tester) async {
    sender.add('https://hooks.test/in', events: {WebhookEvent.edited});
    prefs.update((now) => now.copyWith(localOnly: true));
    await open(tester);
    expect(find.byType(SettingsCallout), findsOneWidget);
    expect(hintOf(tester, 'hooks.test'), endsWith('Nothing is sent while Local only is on.'));
    await endSettings(tester);
  });

  testWidgets('incoming: listed, made with a default note picked from the notes, its URL shown once with examples, deleted', (tester) async {
    final service = HooksService()..hooks.add({'id': 'old', 'name': 'Shortcuts', 'note': 'Inbox', 'createdAt': 1, 'lastUsedAt': null});
    var keyed = 0;
    final incoming = IncomingHooks(api: Api(base: 'http://hooks.test/api', fetcher: service.fetch), token: () => 'token', seeToKey: () async => keyed += 1);
    addTearDown(incoming.dispose);
    await open(tester, incoming: incoming);
    expect(titles(tester), ['Outgoing webhooks', 'New outgoing webhook', 'Incoming webhooks', 'New incoming webhook']);
    expect(hintOf(tester, 'Shortcuts'), 'Into Inbox · never used');

    await type(tester, 'webhook-name', 'Zapier');
    await type(tester, 'webhook-note', 'groc');
    await tapFound(tester, find.descendant(of: row('Groceries'), matching: find.byType(Pick)));
    await tapFound(tester, find.byKey(const ValueKey('webhook-make')));
    expect(keyed, 1, reason: 'the account\'s encryption key seen to first');
    expect(service.calls, containsAllInOrder(['GET hooks', 'POST hooks']));
    expect(service.hooks.last['note'], 'Groceries');
    expect(row('https://hooks.test/api/hooks/secret1'), findsOneWidget);
    expect(hintOf(tester, 'https://hooks.test/api/hooks/secret1'), startsWith('Copy it now: it won’t be shown again.'));
    expect(titles(tester), contains('Examples'));
    expect(find.descendant(of: row('curl'), matching: find.textContaining('"note":"Groceries"', skipOffstage: false)), findsOneWidget);
    expect(row('Zapier'), findsWidgets);
    expect(find.descendant(of: row('IFTTT'), matching: find.textContaining('https://hooks.test/api/hooks/secret1', skipOffstage: false)), findsOneWidget);

    await tapFound(tester, find.descendant(of: find.byKey(const ValueKey('webhook-in-old')), matching: find.text('Delete')));
    expect(service.hooks.map((each) => each['id']), ['hook1']);
    expect(find.byKey(const ValueKey('webhook-in-old')), findsNothing);
    await endSettings(tester);
  });

  test('the row says how many go out', () {
    final store = PreferencesStore()..startWithoutStorage();
    expect(webhooksSummary(store.value), 'None going out');
    store.update((now) => withWebhookSetup(now, const WebhookSetup(outgoing: [OutgoingHook(id: 'a', url: 'https://a.test'), OutgoingHook(id: 'b', url: 'https://b.test')])));
    expect(webhooksSummary(store.value), '2 going out');
  });
}
