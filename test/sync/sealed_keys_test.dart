// The keys and connections kept the same on every device of the account (lib/sync/sealed_keys.dart, the items in
// lib/sync/connections.dart; Matt, 2026-10-26: "make it so things like the Claude tokens and other stuff is kept in
// sync across all instances of ghost logged in to my account"). Devices here are whole sync engines over the service
// in memory, with their own settings, secure store, plugin storage and switches, and the settings' real pass; the
// notes, the feed and the organizations are stand-ins that do nothing, as they have nothing to do with the keys.
//
// What is proved: a key set on one device is on the next after a sync, and one taken away is taken away; two changes
// of one key are settled by which was made later, not which was sent later; the switch off sends nothing and keeps
// what each device has; an older build carries the entries untouched; nothing secret is in what is sent, nor in what
// a device keeps in the clear; Slack is not written on an iPhone while Claude's key is; and Claude turned on and its key
// put in on the Fold make the Mac able to write up a meeting another device handed on.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/account/keystore.dart';
import 'package:ghost_md/account/session.dart';
import 'package:ghost_md/ai/summary_claude.dart' show MeetingClaude;
import 'package:ghost_md/ai/summary_handoff.dart';
import 'package:ghost_md/claude/claude_settings.dart';
import 'package:ghost_md/core/kept_workspaces.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/orgs/org_keys.dart';
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/plugins/claude/claude.dart' show claudePlugin;
import 'package:ghost_md/plugins/discord/discord.dart' show discordChannels, discordMeetingChannel, discordPlugin, postsMeetingsToDiscord;
import 'package:ghost_md/plugins/discord/manifest.dart' as discord show discordWebhookPrefix, manifest;
import 'package:ghost_md/plugins/github/github.dart' show githubPlugin;
import 'package:ghost_md/plugins/github/manifest.dart' as github show manifest, tokenSecret;
import 'package:ghost_md/plugins/lovart/lovart.dart' show lovartPlugin;
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart show accessKeySecret, manifest, secretKeySecret;
import 'package:ghost_md/plugins/meetings/meetings.dart' show googleMeetPlugin, zoomPlugin;
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/slack/channels.dart' show channels;
import 'package:ghost_md/plugins/slack/manifest.dart' as slack show manifest, webhookPrefix;
import 'package:ghost_md/plugins/slack/meetings.dart' show meetingChannel, postsMeetings;
import 'package:ghost_md/plugins/slack/slack.dart' show slackPlugin;
import 'package:ghost_md/plugins/types.dart' show PluginHost;
import 'package:ghost_md/sync/connections.dart';
import 'package:ghost_md/sync/engine.dart';
import 'package:ghost_md/sync/feed.dart';
import 'package:ghost_md/sync/notes.dart';
import 'package:ghost_md/sync/prefs.dart';
import 'package:ghost_md/sync/sealed_keys.dart';

import 'support.dart';

/// The account as a device holds it: signed in, with the account key.
class _Account extends ChangeNotifier implements SyncAccount {
  _Account(this.session, this.key);

  @override
  Session? session;
  final SealKey key;

  @override
  Future<SealKey?> accountKey() async => key;

  @override
  Future<void> resume() async {}

  @override
  Future<void> signOut() async {
    session = null;
    notifyListeners();
  }

  @override
  Future<void> deleteAccount(String password) async {}
}

const String claudeKey = 'sk-ant-api03-FOLD-ONLY-0123456789abcdef';
const String otherKey = 'sk-ant-api03-MAC-CHOSEN-fedcba9876543210';
const String webhook = 'https://hooks.slack.com/services/T000/B000/XXXXXXXXXXXXXXXXXXXXXXXX';
const String githubToken = 'ghp_0123456789abcdefABCDEF0123456789abcd';
const String lovartAccess = 'ak-LOVART-0123456789abcdef';
const String lovartSecret = 'sk-LOVART-fedcba9876543210';
const String discordWebhook = 'https://discord.com/api/webhooks/123456789012345678/aB3_-aB3_-aB3_-aB3_-aB3_-aB3_-aB3_-aB3_-aB3_-aB3_-aB3_-aB3_-aB3_-x';

/// One device: its settings, its secure stores, its plugins' storage and switches, its sync engine.
class KeysDevice {
  KeysDevice(this.service, this.id, {this.platform, bool keys = true}) {
    prefs.startWithoutStorage();
    ground = PluginGround(stored: () => kept, secrets: MemorySecureStore());
    slackHost = createHost(slack.manifest, ground: ground);
    githubHost = createHost(github.manifest, ground: ground);
    lovartHost = createHost(lovart.manifest, ground: ground);
    discordHost = createHost(discord.manifest, ground: ground);
    registry = createRegistry([claudePlugin, slackPlugin, githubPlugin, lovartPlugin, discordPlugin, googleMeetPlugin, zoomPlugin], store: MemorySwitches());
    claude = ClaudeSettings(claudeStore);
    sealed = keys
        ? SealedKeys(
            items: (named) => connectionItems(named, claude: claude, slackHost: slackHost, discordHost: discordHost, githubHost: githubHost, lovartHost: lovartHost, registry: () => registry, platform: platform),
            prefs: prefs,
            device: () => id,
            heard: connectionChanges(claude: claude, registry: () => registry),
            on: on,
            kept: kept,
            now: () => clock,
          )
        : null;
    final account = _Account(Session(token: service.signedIn(), handle: 'matt', accountId: 7), service.accountKey);
    final api = apiOf(service, (request) {
      if (request.method == 'PUT' && request.url.path.endsWith('/prefs')) sent.add(utf8.decode(request.body ?? Uint8List(0)));
      return service.fetcher(request);
    });
    final workspaces = WorkspaceStore(storage: KeptWorkspaceStorage(prefs: prefs, stored: kept));
    engine = SyncEngine(
      account: account,
      api: api,
      crypto: service.crypto,
      keys: MemoryKeyStore(),
      prefs: prefs,
      notes: DeviceNotes(),
      files: DeviceFiles(),
      feed: NotificationFeed(account: account, crypto: service.crypto, kept: kept),
      orgs: Orgs(account: account, api: api, workspaces: workspaces, kept: kept),
      orgKeys: OrgKeys(crypto: service.crypto, api: api),
      kept: kept,
      now: () => clock,
      sealedKeys: sealed,
      notesPass: (_) async => Outcome(),
      feedPass: (_) async => true,
      orgsPass: (_) async => null,
    );
  }

  final FakeService service;
  final String id;
  final TargetPlatform? platform;
  final MemoryStored kept = MemoryStored();
  final PreferencesStore prefs = PreferencesStore();
  final MemorySecureStore claudeStore = MemorySecureStore();
  final ValueNotifier<bool> on = ValueNotifier<bool>(true);
  final List<String> sent = [];
  late final PluginGround ground;
  late final PluginHost slackHost;
  late final PluginHost githubHost;
  late final PluginHost lovartHost;
  late final PluginHost discordHost;
  late final Registry registry;
  late final ClaudeSettings claude;
  late final SealedKeys? sealed;
  late final SyncEngine engine;
  int clock = 1000;

  Future<void> sync() => engine.syncNow();

  KeysContext get context => KeysContext(key: service.accountKey, crypto: service.crypto, accountId: 7);

  Future<void> addChannel(String channelId, String name, String url) async {
    await slackHost.secrets.write('${slack.webhookPrefix}$channelId', url);
    slackHost.storage.set('glyph-slack-channels', [
      ...?(slackHost.storage.get<Object?>('glyph-slack-channels', null) as List?),
      {'id': channelId, 'name': name},
    ]);
  }

  Future<void> forgetChannel(String channelId) async {
    await slackHost.secrets.write('${slack.webhookPrefix}$channelId', null);
    final left = [
      for (final each in (slackHost.storage.get<Object?>('glyph-slack-channels', const <Object?>[]) as List))
        if ((each as Map)['id'] != channelId) each,
    ];
    if (left.isEmpty) {
      slackHost.storage.remove('glyph-slack-channels');
    } else {
      slackHost.storage.set('glyph-slack-channels', left);
    }
  }

  Future<String?> webhookOf(String channelId) => slackHost.secrets.read('${slack.webhookPrefix}$channelId');

  /// A Discord channel, as lib/plugins/discord/channels.dart keeps one.
  Future<void> addDiscordChannel(String channelId, String name, String url) async {
    await discordHost.secrets.write('${discord.discordWebhookPrefix}$channelId', url);
    discordHost.storage.set('glyph-discord-channels', [
      ...?(discordHost.storage.get<Object?>('glyph-discord-channels', null) as List?),
      {'id': channelId, 'name': name},
    ]);
  }

  Future<String?> discordWebhookOf(String channelId) => discordHost.secrets.read('${discord.discordWebhookPrefix}$channelId');

  /// Everything this device keeps in the clear: its storage, and its settings as the store would write them.
  String inTheClear() => [for (final key in kept.allKeys) kept.getItem(key), jsonEncode(prefs.value.toJson())].join('\n');
}

void main() {
  late FakeService service;

  setUp(() async {
    service = await FakeService.start(seed: testAccount);
    syncedPrefsAsOlderBuild = null;
  });

  tearDown(() {
    syncedPrefsAsOlderBuild = null;
    usePluginGround(PluginGround());
    usePlugins(createRegistry(const []));
  });

  test('a key, a channel and a token set on one device are on the next after a sync, where its own code reads them', () async {
    final fold = KeysDevice(service, 'fold-1');
    final mac = KeysDevice(service, 'mac-1');
    await fold.claude.load();
    await fold.claude.setKey(claudeKey);
    await fold.claude.setModel('claude-opus-5-5');
    await fold.claude.spend.setOn(true);
    await fold.claude.spend.setLimit(25);
    await fold.addChannel('abc123', '#launch', webhook);
    fold.slackHost.storage.set('glyph-slack-meetings', {'channel': 'abc123', 'on': true, 'share': true});
    fold.registry.setEnabled('slack', true);
    await fold.githubHost.secrets.write(github.tokenSecret, githubToken);
    await fold.sync();

    await mac.claude.load();
    expect(mac.claude.hasKey, isFalse);
    await mac.sync();
    expect((mac.claude.key, mac.claude.model), (claudeKey, 'claude-opus-5-5'));
    expect((mac.claude.spend.on, mac.claude.spend.limit), (true, 25.0));
    expect(await mac.claudeStore.read(claudeKeyName), claudeKey, reason: 'in the secure store, where the code reads it');
    expect(await mac.webhookOf('abc123'), webhook);
    expect(await mac.githubHost.secrets.read(github.tokenSecret), githubToken);
    expect(mac.registry.switchedOn('slack'), isTrue);

    // The Slack plugin's own code, on the Mac: the channel, and meetings posted from whichever device writes one up.
    usePluginGround(mac.ground);
    usePlugins(mac.registry);
    expect([for (final c in channels()) c.name], ['#launch']);
    expect(meetingChannel()?.id, 'abc123');
    expect(postsMeetings(), isTrue);

    // Nothing more to say on either side: no write.
    mac.sent.clear();
    fold.sent.clear();
    await mac.sync();
    await fold.sync();
    expect([...mac.sent, ...fold.sent], isEmpty);
  });

  test('a spending limit set before this build travels, and a count never does', () async {
    final fold = KeysDevice(service, 'fold-1');
    final mac = KeysDevice(service, 'mac-1');
    // As a build from before kept it: the limit inside the month's count, nothing on its own.
    await fold.claudeStore.write('anthropic-spend', jsonEncode({'on': true, 'limit': 50, 'warn': false, 'month': '2026-10', 'spent': 12.5, 'requests': 40, 'warned': false}));
    await fold.claude.load();
    await fold.sync();
    await mac.claude.load();
    await mac.sync();
    expect((mac.claude.spend.on, mac.claude.spend.limit, mac.claude.spend.warn), (true, 50.0, false));
    expect(mac.claude.spend.requests, 0, reason: 'each device counts its own');
    // A device that only ever counted, and never set a limit, sends no defaults over it.
    final tablet = KeysDevice(service, 'tab-1');
    await tablet.claudeStore.write('anthropic-spend', jsonEncode({'on': false, 'limit': 10, 'warn': true, 'month': '2026-10', 'spent': 1, 'requests': 2, 'warned': false}));
    await tablet.claude.load();
    tablet.clock = 9000;
    await tablet.sync();
    await tablet.sync();
    await mac.sync();
    expect((mac.claude.spend.on, mac.claude.spend.limit), (true, 50.0));
    expect((tablet.claude.spend.on, tablet.claude.spend.limit), (true, 50.0));
  });

  test('a key taken away on one device is taken away on the others, and stays away', () async {
    final fold = KeysDevice(service, 'fold-1');
    final mac = KeysDevice(service, 'mac-1');
    await fold.claude.load();
    await fold.claude.setKey(claudeKey);
    await fold.addChannel('abc123', '#launch', webhook);
    await fold.sync();
    await mac.sync();
    expect(await mac.webhookOf('abc123'), webhook);

    mac.clock = 2000;
    await mac.claude.setKey(null);
    await mac.forgetChannel('abc123');
    await mac.sync();
    final entries = sealedEntriesOf(mac.prefs.value);
    expect(SealedEntry.fromJson(entries[claudeKeyName])?.gone, isTrue, reason: 'a tombstone, not nothing');
    expect(SealedEntry.fromJson(entries['${slack.webhookPrefix}abc123'])?.gone, isTrue);

    fold.clock = 3000;
    await fold.sync();
    await fold.claude.load();
    expect(fold.claude.hasKey, isFalse);
    expect(await fold.claudeStore.read(claudeKeyName), isNull);
    expect(await fold.webhookOf('abc123'), isNull);
    expect(fold.slackHost.storage.get<Object?>('glyph-slack-channels', null), isNull);

    // A third device signing in later does not bring the key back from nowhere.
    final tablet = KeysDevice(service, 'tab-1');
    await tablet.sync();
    await fold.sync();
    expect(fold.claude.hasKey, isFalse);
  });

  test('two changes of one key: the one made later stands on both, whichever was sent first', () async {
    final fold = KeysDevice(service, 'fold-1');
    final mac = KeysDevice(service, 'mac-1');
    await fold.claude.load();
    await mac.claude.load();
    await fold.sync();
    await mac.sync();

    // The Fold's change is made first, offline: sealed into its settings at 1500, not sent.
    fold.clock = 1500;
    await fold.claude.setKey(claudeKey);
    expect(await fold.sealed!.gather(fold.context), 1);
    // The Mac's is made later and sent first.
    mac.clock = 2000;
    await mac.claude.setKey(otherKey);
    await mac.sync();
    // The Fold comes back: what it sends loses to what was made after it.
    fold.clock = 3000;
    await fold.sync();
    await mac.sync();
    expect((fold.claude.key, mac.claude.key), (otherKey, otherKey));

    // And the other way round: the later change sent last stands too.
    fold.clock = 4000;
    await fold.claude.setKey(claudeKey);
    await fold.sync();
    await mac.sync();
    expect((fold.claude.key, mac.claude.key), (claudeKey, claudeKey));
  });

  test('a tie goes the same way on both devices', () {
    final a = SealedEntry(at: 5, by: 'fold-1', sealed: 'A').toJson();
    final b = SealedEntry(at: 5, by: 'mac-1', sealed: 'B').toJson();
    const base = <String, Object?>{};
    expect(mergedSealedKeys(base, {'k': a}, {'k': b})['k'], b);
    expect(mergedSealedKeys(base, {'k': b}, {'k': a})['k'], b);
    // A name only one side changed is that side's, and nothing is ever dropped.
    expect(mergedSealedKeys({'k': a}, {'k': a, 'j': b}, {'k': b}), {'k': b, 'j': b});
  });

  test('with the switch off a device sends nothing, takes nothing, and keeps the key it has', () async {
    final fold = KeysDevice(service, 'fold-1');
    final mac = KeysDevice(service, 'mac-1');
    await mac.claude.load();
    await mac.claude.setKey(otherKey);
    await mac.sync();
    fold.on.value = false;
    await fold.claude.load();
    await fold.claude.setKey(claudeKey);
    await fold.sync();
    expect(fold.claude.key, claudeKey, reason: 'the Mac’s key was not taken');
    expect(sealedEntriesOf(fold.prefs.value).keys, isNot(contains(contains('fold'))));
    for (final body in fold.sent) {
      expect(body, isNot(contains(claudeKey)));
    }
    final account = await service.crypto.open(service.accountKey, service.prefs!.blob, 'prefs') as Map;
    final entry = SealedEntry.fromJson((account[sealedKeysKey] as Map)[claudeKeyName])!;
    expect(entry.by, 'mac-1', reason: 'what the account holds is still the Mac’s alone');

    await mac.sync();
    expect(mac.claude.key, otherKey);

    // Turned on again: what arrived meanwhile is taken.
    fold.on.value = true;
    await fold.sync();
    expect(fold.claude.key, otherKey);
  });

  test('an older build carries the entries untouched, through changes of its own', () async {
    final fold = KeysDevice(service, 'fold-1');
    await fold.claude.load();
    await fold.claude.setKey(claudeKey);
    await fold.addChannel('abc123', '#launch', webhook);
    await fold.sync();
    final written = (await service.crypto.open(service.accountKey, service.prefs!.blob, 'prefs') as Map)[sealedKeysKey];
    expect(written, isA<Map>());

    // A build from before: it syncs every setting it knows but these, and has no keys of its own to gather.
    final old = KeysDevice(service, 'old-1', keys: false);
    syncedPrefsAsOlderBuild = [for (final key in syncedPrefs) if (key != sealedKeysKey) key];
    await old.sync();
    old.prefs.update((now) => now.copyWith(theme: 'ember'));
    old.clock = 5000;
    await old.sync();
    syncedPrefsAsOlderBuild = null;
    expect(old.sent, isNotEmpty, reason: 'the older build wrote');
    final after = await service.crypto.open(service.accountKey, service.prefs!.blob, 'prefs') as Map;
    expect(after['theme'], 'ember');
    expect(jsonEncode(after[sealedKeysKey]), jsonEncode(written), reason: 'carried as it came');

    // And a device of this build still gets the key from it.
    final mac = KeysDevice(service, 'mac-1');
    await mac.sync();
    expect((mac.claude.key, await mac.webhookOf('abc123')), (claudeKey, webhook));
  });

  test('a device whose first sync meets settings with no keys in them sends its own after', () async {
    // An older build wrote the account's settings first, with no keys in them.
    final old = KeysDevice(service, 'old-1', keys: false);
    syncedPrefsAsOlderBuild = [for (final key in syncedPrefs) if (key != sealedKeysKey) key];
    old.prefs.update((now) => now.copyWith(theme: 'ember'));
    await old.sync();
    syncedPrefsAsOlderBuild = null;

    final fold = KeysDevice(service, 'fold-1');
    await fold.claude.load();
    await fold.claude.setKey(claudeKey);
    await fold.sync();
    expect(fold.prefs.value.theme, 'ember', reason: 'the account’s settings, taken on a first sync');
    fold.clock = 2000;
    await fold.sync();
    final mac = KeysDevice(service, 'mac-1');
    await mac.sync();
    expect(mac.claude.key, claudeKey);
  });

  test('Lovart’s two keys and its switch, set on one device, are on the next after a sync, sealed (Matt, 2026-10-26: "Yes please sync lovart too")', () async {
    final fold = KeysDevice(service, 'fold-1');
    final mac = KeysDevice(service, 'mac-1');
    await fold.lovartHost.secrets.write(lovart.accessKeySecret, lovartAccess);
    await fold.lovartHost.secrets.write(lovart.secretKeySecret, lovartSecret);
    fold.registry.setEnabled('lovart', true);
    // This device's own: its project and its meetings' switch stay with it.
    fold.lovartHost.storage.set('glyph-lovart-project', 'proj-fold');
    await fold.sync();

    expect(mac.registry.switchedOn('lovart'), isFalse);
    await mac.sync();
    expect(await mac.lovartHost.secrets.read(lovart.accessKeySecret), lovartAccess);
    expect(await mac.lovartHost.secrets.read(lovart.secretKeySecret), lovartSecret);
    expect(mac.registry.switchedOn('lovart'), isTrue);
    expect(mac.lovartHost.storage.get<Object?>('glyph-lovart-project', null), isNull);

    // Sealed: neither key is in what was sent, as written or as base64.
    String b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');
    for (final body in fold.sent) {
      for (final secret in [lovartAccess, lovartSecret]) {
        expect(body, isNot(contains(secret)));
        expect(body, isNot(contains(b64(secret))));
      }
    }

    // Forgotten on the Mac, forgotten on the Fold.
    await mac.lovartHost.secrets.write(lovart.accessKeySecret, null);
    await mac.lovartHost.secrets.write(lovart.secretKeySecret, null);
    await mac.sync();
    await fold.sync();
    expect(await fold.lovartHost.secrets.read(lovart.accessKeySecret), isNull);
    expect(await fold.lovartHost.secrets.read(lovart.secretKeySecret), isNull);
  });

  test('nothing secret is in what is sent, nor in the settings opened, nor in what a device keeps in the clear', () async {
    final fold = KeysDevice(service, 'fold-1');
    final mac = KeysDevice(service, 'mac-1');
    await fold.claude.load();
    await fold.claude.setKey(claudeKey);
    await fold.addChannel('abc123', '#launch', webhook);
    await fold.githubHost.secrets.write(github.tokenSecret, githubToken);
    await fold.sync();
    await mac.sync();
    expect(mac.claude.key, claudeKey, reason: 'it did travel');

    final secrets = [claudeKey, webhook, githubToken, 'FOLD-ONLY', 'XXXXXXXXXXXXXXXXXXXXXXXX'];
    String b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');
    expect(fold.sent, isNotEmpty);
    for (final body in fold.sent) {
      for (final secret in secrets) {
        expect(body, isNot(contains(secret)));
        expect(body, isNot(contains(b64(secret))));
      }
    }
    // Opened with the account key, as the service never can: the settings hold each value sealed again, by name.
    final opened = jsonEncode(await service.crypto.open(service.accountKey, service.prefs!.blob, 'prefs'));
    for (final secret in secrets) {
      expect(opened, isNot(contains(secret)));
    }
    expect(opened, contains(claudeKeyName));
    // And neither device keeps one in its ordinary storage or its settings.
    for (final device in [fold, mac]) {
      final clear = device.inTheClear();
      for (final secret in secrets) {
        expect(clear, isNot(contains(secret)));
      }
    }
  });

  test('on an iPhone Claude’s key arrives and Slack’s channels do not, and they are carried untouched', () async {
    final fold = KeysDevice(service, 'fold-1');
    await fold.claude.load();
    await fold.claude.setKey(claudeKey);
    await fold.addChannel('abc123', '#launch', webhook);
    await fold.sync();
    final before = jsonEncode(sealedEntriesOf(fold.prefs.value));

    final iphone = KeysDevice(service, 'iphone-1', platform: TargetPlatform.iOS);
    await iphone.sync();
    expect(iphone.claude.key, claudeKey);
    expect(await iphone.webhookOf('abc123'), isNull);
    expect(iphone.slackHost.storage.get<Object?>('glyph-slack-channels', null), isNull);
    iphone.clock = 9000;
    await iphone.claude.setModel('claude-haiku-5-5');
    await iphone.sync();
    await fold.sync();
    expect(fold.claude.model, 'claude-haiku-5-5');
    final after = sealedEntriesOf(fold.prefs.value);
    expect(jsonEncode(after['${slack.webhookPrefix}abc123']), jsonEncode((jsonDecode(before) as Map)['${slack.webhookPrefix}abc123']));
  });

  test('a Discord channel, where meetings post and the switch follow the account sealed, and a channel forgotten goes everywhere', () async {
    final fold = KeysDevice(service, 'fold-1');
    final mac = KeysDevice(service, 'mac-1');
    await fold.addDiscordChannel('d1', '#launch', discordWebhook);
    fold.discordHost.storage.set('glyph-discord-meetings', {'channel': 'd1', 'on': true, 'share': true});
    fold.registry.setEnabled('discord', true);
    await fold.sync();
    // Nothing of the webhook in what was sent, nor kept readable: sealed on its own.
    expect(fold.sent.join(), isNot(contains('discord.com/api/webhooks')));
    expect(fold.inTheClear(), isNot(contains(discordWebhook)));
    expect(sealedEntriesOf(fold.prefs.value).keys, containsAll(['${discord.discordWebhookPrefix}d1', 'glyph-discord-channels', 'glyph-discord-meetings', 'plugin:discord']));

    await mac.sync();
    expect(await mac.discordWebhookOf('d1'), discordWebhook);
    expect(mac.registry.switchedOn('discord'), isTrue);
    // The Discord plugin's own code, on the Mac.
    usePluginGround(mac.ground);
    usePlugins(mac.registry);
    expect([for (final c in discordChannels()) c.name], ['#launch']);
    expect(discordMeetingChannel()?.id, 'd1');
    expect(postsMeetingsToDiscord(), isTrue);

    // Forgotten on the Mac: gone from the Fold at its next sync, webhook first.
    mac.clock = 2000;
    await mac.discordHost.secrets.write('${discord.discordWebhookPrefix}d1', null);
    mac.discordHost.storage.remove('glyph-discord-channels');
    await mac.sync();
    fold.clock = 3000;
    await fold.sync();
    expect(await fold.discordWebhookOf('d1'), isNull);
    expect(fold.discordHost.storage.get<Object?>('glyph-discord-channels', null), isNull);
  });

  test('on an iPhone Discord’s channels do not arrive either, and are carried untouched', () async {
    final fold = KeysDevice(service, 'fold-1');
    await fold.addDiscordChannel('d1', '#launch', discordWebhook);
    await fold.sync();
    final before = sealedEntriesOf(fold.prefs.value)['${discord.discordWebhookPrefix}d1'];
    final iphone = KeysDevice(service, 'iphone-1', platform: TargetPlatform.iOS);
    await iphone.sync();
    expect(await iphone.discordWebhookOf('d1'), isNull);
    expect(iphone.discordHost.storage.get<Object?>('glyph-discord-channels', null), isNull);
    iphone.clock = 9000;
    await iphone.sync();
    await fold.sync();
    expect(jsonEncode(sealedEntriesOf(fold.prefs.value)['${discord.discordWebhookPrefix}d1']), jsonEncode(before));
  });

  // Matt, 2026-10-26: "Make sure the Google Meet and the Zoom plugins are two different plugins": which kinds Ghost
  // joins is the account's, so each switch travels as the others do.
  test('the Google Meet and Zoom switches follow the account, each its own, and one never moved sends nothing', () async {
    final fold = KeysDevice(service, 'fold-1');
    final mac = KeysDevice(service, 'mac-1');
    expect((fold.registry.switchedOn('google-meet'), fold.registry.switchedOn('zoom')), (true, true), reason: 'both ship on');
    fold.registry.setEnabled('zoom', false);
    await fold.sync();
    final entries = sealedEntriesOf(fold.prefs.value).keys;
    expect(entries, contains('plugin:zoom'));
    expect(entries, isNot(contains('plugin:google-meet')), reason: 'a switch never moved is not sent');
    await mac.sync();
    expect((mac.registry.switchedOn('google-meet'), mac.registry.switchedOn('zoom')), (true, false));
    // On again on the Mac, and Google Meet off: the Fold has both.
    mac.clock = 2000;
    mac.registry.setEnabled('zoom', true);
    mac.registry.setEnabled('google-meet', false);
    await mac.sync();
    fold.clock = 3000;
    await fold.sync();
    expect((fold.registry.switchedOn('google-meet'), fold.registry.switchedOn('zoom')), (false, true));
  });

  test('signing out takes the entries out of the settings here, and keeps the keys', () async {
    final fold = KeysDevice(service, 'fold-1');
    await fold.claude.load();
    await fold.claude.setKey(claudeKey);
    await fold.sync();
    expect(sealedEntriesOf(fold.prefs.value), isNotEmpty);
    await fold.engine.signOutHere();
    expect(sealedEntriesOf(fold.prefs.value), isEmpty);
    expect(fold.kept.getItem('glyph-sync-7-keys'), isNull);
    expect(fold.claude.key, claudeKey);
  });

  test('Claude turned on and its key put in on the Fold make the Mac able to write up a meeting handed on', () async {
    final fold = KeysDevice(service, 'fold-1');
    final mac = KeysDevice(service, 'mac-1');
    await mac.claude.load();
    await fold.claude.load();
    // The Mac had Claude turned off, and no key; that went to the Fold too.
    mac.registry.setEnabled('claude', false);
    await mac.sync();
    await fold.sync();
    expect(fold.registry.switchedOn('claude'), isFalse);

    final claude = MeetingClaude(settings: mac.claude, switchedOn: () => mac.registry.switchedOn('claude'), localOnly: () => false);
    final queue = _Queue(claude);
    const transcript = Note(id: 'standup', body: '# Engineering standup\n\n## Transcript\n\nWe shipped the build.\n', createdAt: 0, updatedAt: 0);
    // A meeting another device (an iPhone, which writes nothing up) has waiting for a summary.
    mac.prefs.update((now) => withHandoff(now, 'standup', Handoff(from: 'iphone-1', fromName: 'phone', at: 0), now: 0));
    final handoff = SummaryHandoff(
      device: () => const SummaryDevice(id: 'mac-1', name: 'Mac'),
      preferences: () => mac.prefs.value,
      setPreferences: mac.prefs.update,
      syncNow: () async {},
      getNote: (id) async => id == 'standup' ? transcript : null,
      notes: () => const [],
      warn: (_) {},
    )..attach(queue);
    // What the app's handoff hears (lib/root/voice_wiring.dart): the settings, and Claude's settings and switch.
    final stop = handoff.start(Listenable.merge([mac.prefs, mac.claude, mac.registry]), settle: const Duration(milliseconds: 1));
    await handoff.look();
    expect(queue.handed, isEmpty, reason: 'nothing to write it with');

    fold.clock = 2000;
    fold.registry.setEnabled('claude', true);
    await fold.claude.setKey(claudeKey);
    await fold.sync();
    // The Mac's settings take the Fold's entries with its switch off, so nothing is written into its stores yet, and
    // the settings changing alone finds nothing to write the summary with.
    mac.on.value = false;
    mac.clock = 3000;
    await mac.sync();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(mac.claude.hasKey, isFalse);
    expect(queue.handed, isEmpty);
    // Turned on: the key and the switch are written in, the settings unchanged, and the handoff hears Claude's.
    mac.on.value = true;
    expect(await mac.sealed!.apply(mac.context), greaterThanOrEqualTo(2));
    expect((mac.registry.switchedOn('claude'), mac.claude.hasKey), (true, true));
    expect((claude.chosen, claude.enabled), (true, true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(queue.handed, ['standup'], reason: 'looked again once the key arrived, and took it on');
    stop();
  });
}

/// The summary queue as the handoff asks it: able where Claude is chosen and free to run, as
/// ai/summaries.dart's `canWriteUpMeetings` answers on a Mac with no summary model.
class _Queue implements HandoffQueue {
  _Queue(this.claude);

  final MeetingClaude claude;
  final List<String> handed = [];

  @override
  bool hasJob(String id) => handed.contains(id);

  @override
  Future<bool> canWriteUpMeetings() async {
    await claude.load();
    return claude.chosen && claude.enabled && !claude.limited;
  }

  @override
  void handOn(String id) => handed.add(id);

  @override
  void handedOff(String id) {}
}
