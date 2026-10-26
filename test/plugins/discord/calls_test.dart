// Discord calls on the Discord plugin's page (lib/plugins/discord/calls.dart, calls_section.dart; docs/DISCORD_CALLS.md;
// Matt, 2026-10-26: Discord calls belong to the Discord plugin): Link Discord makes a code after seeing to the account's
// encryption key, shows it with the two steps and the command to copy, and the linked name replaces it once the bot
// has used it; linked, Join Discord calls and Unlink (asked first); the account's calls of kind discord listed, and
// only those; a service with no Discord routes says so; and a pass with the plugin off turns the switch off on the
// service, once.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/discord/calls.dart';
import 'package:ghost_md/plugins/discord/calls_section.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;

import '../../account_ui/support.dart';
import '../../meet/support.dart';

/// The service's Discord routes in memory (server/src/discord.rs), in front of another fetcher for the rest.
class FakeDiscordRoutes {
  Map<String, Object?>? link;
  String? appId;
  bool routes = true;
  int codes = 0;
  final List<String> calls = [];

  /// Every route asked, the service's others too, in order.
  final List<String> seen = [];
  Map<String, Object?>? lastBody;

  /// What `/ghost link` does on the service: the code used, the account linked.
  void linkedBy(String name) => link = {'name': name, 'linkedAt': 1792159200000, 'calls': true};

  Fetcher over(Fetcher rest) => (request) async {
        final path = request.url.path.replaceFirst(RegExp(r'^.*/v1/'), '');
        seen.add('${request.method} $path');
        if (!path.startsWith('discord/')) return rest(request);
        calls.add('${request.method} $path');
        if (!routes) return FetchResponse.json(404, {'error': 'no such route'});
        lastBody = request.body == null || request.body!.isEmpty ? null : jsonDecode(utf8.decode(request.body!)) as Map<String, Object?>;
        return switch ('${request.method} $path') {
          'GET discord/link' => FetchResponse.json(200, {'link': link, 'appId': appId}),
          'POST discord/link-code' => FetchResponse.json(200, {'code': 'K7QM-2XR${++codes}', 'expiresAt': DateTime.now().millisecondsSinceEpoch + 600000}),
          'DELETE discord/link' => () {
              link = null;
              return FetchResponse.json(200, {'link': null});
            }(),
          'PUT discord/calls' => link == null
              ? FetchResponse.json(404, {'error': 'Link your Discord first.'})
              : () {
                  link = {...link!, 'calls': lastBody?['on'] == true};
                  return FetchResponse.json(200, {'link': link});
                }(),
          _ => FetchResponse.json(404, {'error': 'no such route'}),
        };
      };
}

Future<({Device device, FakeDiscordRoutes discord, FakeMeet meet})> made() async {
  final discord = FakeDiscordRoutes();
  final meet = FakeMeet();
  final service = await FakeService.start(seed: seeded);
  final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: discord.over(meet.over(service.fetcher)));
  return (device: device, discord: discord, meet: meet);
}

Map<String, Object?> call(String id, String title, String state, {String kind = 'discord', int startsAt = 1792159200000}) => {
      'id': id,
      'title': title,
      'url': kind == 'discord' ? 'https://discord.com/channels/333333333333333333/444444444444444444' : 'https://meet.google.com/abc-defg-hij',
      'kind': kind,
      'startsAt': startsAt,
      'endsAt': startsAt + 3600000,
      'state': state,
    };

String allText(WidgetTester tester) => [
      for (final widget in tester.widgetList(find.byWidgetPredicate((w) => w is Text || w is RichText)))
        if (widget is Text) widget.data ?? widget.textSpan?.toPlainText() ?? '' else if (widget is RichText) widget.text.toPlainText(),
    ].join(' | ');

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Link Discord: a code with its two steps and the command to copy, then the name once the bot used it', (tester) async {
    final m = await made();
    final clipped = Clipped(tester);
    final meet = m.device.meetIn!;
    final calls = DiscordCalls(account: meet.account, keys: meet.keys, api: meet.api, crypto: meet.crypto);
    addTearDown(calls.dispose);
    await m.device.pump(tester, DiscordCallsSection(services: m.device.services, calls: calls));
    await settle(tester);
    expect(find.byKey(const ValueKey('discord-link')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('discord-link-make')));
      for (var i = 0; i < 20 && m.discord.codes == 0; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await settle(tester);
    expect(m.discord.codes, 1);
    final keyAt = m.discord.seen.indexWhere((s) => s.endsWith('account/key'));
    expect(keyAt, isNonNegative);
    expect(keyAt, lessThan(m.discord.seen.indexOf('POST discord/link-code')), reason: 'the key is seen to before a code, as a call is sealed to it');
    final text = allText(tester);
    expect(text, contains('K7QM-2XR1'));
    expect(text, contains('1. Add Ghost to your Discord server'));
    expect(text, contains('/ghost link K7QM-2XR1'));
    await tapKey(tester, 'discord-code-copy');
    await settle(tester);
    expect(clipped.text, '/ghost link K7QM-2XR1');
    // The bot redeems it; the page's next read shows the name, and the code is gone.
    m.discord.linkedBy('sam_lee');
    await tester.runAsync(calls.refresh);
    await settle(tester);
    expect(allText(tester), contains('Linked as sam_lee'));
    expect(find.byKey(const ValueKey('discord-code')), findsNothing);
    await endSettings(tester);
  });

  testWidgets('linked: Join Discord calls switches it on the service, and Unlink asks first', (tester) async {
    final m = await made();
    m.discord.linkedBy('sam_lee');
    await m.device.pump(tester, DiscordCallsSection(services: m.device.services));
    await settle(tester);
    final toggle = find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == 'Join Discord calls');
    expect(tester.widget<GlacierSwitch>(toggle).checked, isTrue);
    expect(allText(tester), contains('/ghost join'));
    await bringIntoView(tester, toggle);
    await tester.tap(toggle);
    await settle(tester);
    expect(m.discord.calls, contains('PUT discord/calls'));
    expect(m.discord.link!['calls'], isFalse);
    expect(tester.widget<GlacierSwitch>(toggle).checked, isFalse);
    await tapKey(tester, 'discord-unlink');
    await settle(tester);
    expect(allText(tester), contains('Unlink sam_lee?'));
    expect(m.discord.link, isNotNull, reason: 'asked first');
    await tapKey(tester, 'discord-unlink-yes');
    await settle(tester);
    expect(m.discord.link, isNull);
    expect(find.byKey(const ValueKey('discord-link')), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('the account’s Discord calls are listed, and only those; one going on has Leave now', (tester) async {
    final m = await made();
    m.meet.meetings.addAll([call('c1', 'Standup in Ghost HQ', 'in_call', startsAt: DateTime.now().millisecondsSinceEpoch - 60000), call('c2', 'Planning in Ghost HQ', 'done'), call('m1', 'Roadmap review', 'booked', kind: 'meet')]);
    await m.device.meetIn!.refresh();
    await m.device.pump(tester, DiscordCallsSection(services: m.device.services));
    await settle(tester);
    expect(find.byKey(const ValueKey('discord-call-c1')), findsOneWidget);
    expect(find.byKey(const ValueKey('discord-call-c2')), findsOneWidget);
    expect(find.byKey(const ValueKey('discord-call-m1')), findsNothing, reason: 'a Meet is the Google Meet plugin’s');
    expect(allText(tester), contains('In the meeting'));
    await tapKey(tester, 'discord-leave-c1');
    await settle(tester);
    expect(m.meet.calls, contains('DELETE meet/c1'));
    await endSettings(tester);
  });

  testWidgets('Add Ghost to a server opens the invite from the service’s application id, linked or not (Matt, 2026-10-26)', (tester) async {
    final m = await made();
    m.discord.appId = '123456789012345678';
    final opened = <String>[];
    await m.device.pump(tester, DiscordCallsSection(services: m.device.services, onOpenLink: opened.add));
    await settle(tester);
    expect(find.byKey(const ValueKey('discord-invite-row')), findsOneWidget, reason: 'before linking, beside Link Discord');
    await tapKey(tester, 'discord-invite-open');
    await settle(tester);
    expect(opened.single, 'https://discord.com/oauth2/authorize?client_id=123456789012345678&scope=bot%20applications.commands&permissions=1051648');
    m.discord.linkedBy('sam_lee');
    await m.device.pump(tester, DiscordCallsSection(key: const ValueKey('again'), services: m.device.services, onOpenLink: opened.add));
    await settle(tester);
    expect(allText(tester), contains('Linked as sam_lee'));
    expect(find.byKey(const ValueKey('discord-invite-row')), findsOneWidget, reason: 'and once linked, for another server');
    await endSettings(tester);
  });

  testWidgets('with no application id anywhere, Add Ghost to a server says there is no link and offers no button', (tester) async {
    final m = await made();
    await m.device.pump(tester, DiscordCallsSection(services: m.device.services, onOpenLink: (_) {}));
    await settle(tester);
    expect(find.byKey(const ValueKey('discord-invite-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('discord-invite-open')), findsNothing);
    await endSettings(tester);
  });

  testWidgets('a service with no Discord routes says so, and offers nothing', (tester) async {
    final m = await made();
    m.discord.routes = false;
    await m.device.pump(tester, DiscordCallsSection(services: m.device.services));
    await settle(tester);
    expect(allText(tester), contains('Discord calls are not on this service yet'));
    expect(find.byKey(const ValueKey('discord-link')), findsNothing);
    await endSettings(tester);
  });

  test('the invite link asks for the three permissions, with the app this build knows', () {
    expect(discordInviteUrl(''), isNull);
    expect(discordInviteUrl('123456789012345678'), 'https://discord.com/oauth2/authorize?client_id=123456789012345678&scope=bot%20applications.commands&permissions=1051648');
  });

  test('a pass with the plugin off turns the switch off once; with it on, the memory is cleared', () async {
    final routes = FakeDiscordRoutes()..linkedBy('sam_lee');
    final api = Api(base: 'https://ghostmarkdown.test/api', fetcher: routes.over((_) async => FetchResponse.json(404, {'error': 'no such route'})));
    final kept = MemoryStored();
    await discordCallsFollowPlugin(api: api, token: 't', kept: kept, on: () => true);
    expect(routes.calls, isEmpty, reason: 'on: nothing to say');
    await discordCallsFollowPlugin(api: api, token: 't', kept: kept, on: () => false);
    await discordCallsFollowPlugin(api: api, token: 't', kept: kept, on: () => false);
    expect(routes.calls, ['PUT discord/calls'], reason: 'told once');
    expect(routes.link!['calls'], isFalse);
    await discordCallsFollowPlugin(api: api, token: 't', kept: kept, on: () => true);
    routes.link = {...routes.link!, 'calls': true};
    await discordCallsFollowPlugin(api: api, token: 't', kept: kept, on: () => false);
    expect(routes.calls, ['PUT discord/calls', 'PUT discord/calls'], reason: 'off again after it was on: told again');
    // Nothing linked, or no routes: remembered as told, and never asked again.
    final none = FakeDiscordRoutes();
    final quiet = MemoryStored();
    final api2 = Api(base: 'https://ghostmarkdown.test/api', fetcher: none.over((_) async => FetchResponse.json(404, {'error': 'no such route'})));
    await discordCallsFollowPlugin(api: api2, token: 't', kept: quiet, on: () => false);
    await discordCallsFollowPlugin(api: api2, token: 't', kept: quiet, on: () => false);
    expect(none.calls, ['PUT discord/calls']);
  });
}
