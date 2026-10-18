// Webhooks as a plugin (lib/integrations/webhooks/plugin.dart; Matt, 2026-10-17: integrations ship as plugins): among
// the plugins that ship, off until switched on, its page a row of Settings once it is; and while it is off, or
// Local only is on, the outgoing hooks hear nothing and the sync pass reads no inbox.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/integrations/webhooks/incoming.dart';
import 'package:ghost_md/integrations/webhooks/outgoing.dart';
import 'package:ghost_md/integrations/webhooks/plugin.dart';
import 'package:ghost_md/integrations/webhooks/setup.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/plugins_pane.dart';
import 'package:ghost_md/settings/settings_sections.dart' show pluginPageSections;

import '../../settings/support.dart';
import '../../support/fake_crypto.dart';
import '../../support/sync_device.dart' show DeviceNotes;

void main() {
  setUpAll(loadAppFonts);

  late Registry registry;
  late Registry before;
  var localOnly = false;

  setUp(() {
    before = plugins;
    localOnly = false;
    usePlugins(registry = createRegistry(builtIn, store: MemorySwitches(), localOnly: () => localOnly));
  });

  tearDown(() => usePlugins(before));

  test('ships with the others, off until switched on, its page and its words in Settings', () {
    expect(builtIn, contains(webhooksPlugin));
    expect((webhooksManifest.id, webhooksManifest.standard), ('webhooks', false));
    expect(webhooksManifest.declares(Permission.network), isTrue);
    expect(webhooksOn(), isFalse);
    expect(registry.enabled(), isNot(contains(webhooksPlugin)));
    registry.setEnabled(webhooksId, true);
    expect(webhooksOn(), isTrue);
    expect(webhooksPlugin.settings?.settings.map((s) => s.name), ['Outgoing webhooks', 'Incoming webhooks']);
    expect(registry.storageKeys(), containsAll(['glyph-webhooks-status', 'glyph-hooks-applied']));
    localOnly = true;
    expect(webhooksOn(), isFalse, reason: 'Local only holds off a plugin that reaches past the phone');
  });

  testWidgets('its card is in Settings › Plugins, to discover; added, its page is a row of Settings of its own', (tester) async {
    await pumpSettings(tester, SingleChildScrollView(child: PluginsPane(registry: registry, onOpen: (id, {setting}) {})), prefs: const Preferences(theme: 'light'));
    expect(find.byWidgetPredicate((w) => w is PaneHero && w.title == 'Webhooks', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('5 of 12 added.', skipOffstage: false), findsOneWidget);
    expect([for (final spec in pluginPageSections()) spec.id], isNot(contains('plugin:webhooks')));
    registry.setEnabled(webhooksId, true);
    await settleSettings(tester);
    final page = pluginPageSections().singleWhere((spec) => spec.id == 'plugin:webhooks');
    expect((page.label, page.parent, page.listed), ('Webhooks', null, true));
    expect(webhooksPlugin.settings!.summary(), 'None going out');
    await endSettings(tester);
  });

  testWidgets('the outgoing hooks hear nothing while the plugin is off, and are told once it is on', (tester) async {
    final prefs = PreferencesStore()..startWithoutStorage();
    final sent = <FetchRequest>[];
    final kept = MemoryStored();
    final sender = WebhookSender(prefs: prefs, kept: () => kept, wait: (_) async {}, fetch: (request) async {
      sent.add(request);
      return FetchResponse(200);
    });
    addTearDown(sender.dispose);
    sender.add('https://hooks.test/in', events: {WebhookEvent.edited});
    const a = Note(id: 'n', body: 'a', createdAt: 1, updatedAt: 1), b = Note(id: 'n', body: 'b', createdAt: 1, updatedAt: 2);
    sender.heard(a, b);
    await tester.pump(quietFor);
    expect(sent, isEmpty);
    registry.setEnabled(webhooksId, true);
    sender.heard(a, b);
    await tester.pump(quietFor);
    expect(sent, hasLength(1));
  });

  test('the sync pass reads no inbox while the plugin is off', () async {
    final calls = <String>[];
    final crypto = FakeCrypto();
    final pair = await crypto.newEncryptionKey();
    final ctx = HookPassContext(
      token: 'token',
      api: Api(base: 'http://hooks.test/api', fetcher: (request) async {
        calls.add('${request.method} ${request.url.path}');
        return FetchResponse.json(200, const []);
      }),
      crypto: crypto,
      pair: () async => pair,
      notes: DeviceNotes(),
      now: () => 1,
      prefs: () => Preferences.defaults,
      kept: MemoryStored(),
    );
    expect(await hooksWhileOn(ctx), 0);
    expect(calls, isEmpty);
    registry.setEnabled(webhooksId, true);
    expect(await hooksWhileOn(ctx), 0);
    expect(calls, ['GET /api/v1/hooks/inbox']);
  });
}
