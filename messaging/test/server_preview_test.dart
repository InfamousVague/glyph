import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/ui/servers/server_layouts.dart';
import 'package:ghost_messaging/ui/servers/server_mock.dart';
import 'package:ghost_messaging/ui/servers/server_parts.dart';
import 'package:ghost_messaging/ui/servers/server_preview.dart';
import 'package:glacier/glacier.dart';

import 'support/list_harness.dart';

/// The server preview (lib/ui/servers; Matt, 2026-11-17: "propose 5 different layouts ... add a mocked sever ... with a
/// button to toggle between the 5 different designs ... consider user lists, server settings, moving channels and
/// spaces around"). Pictures of each layout on a phone and on an unfolded Fold go to test/shots/ with --update-goldens.
Future<void> _fonts() async {
  Future<void> family(String name, String file) async {
    final loader = FontLoader(name)..addFont(File(file).readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
    await loader.load();
  }

  await family('Inter Variable', 'assets/fonts/InterVariable-latin.ttf');
  await family('JetBrains Mono Variable', 'assets/fonts/JetBrainsMonoVariable-latin.ttf');
  await family('Ghost Emoji Noto', 'assets/emoji/NotoColor.ttf');
}

void main() {
  setUpAll(_fonts);

  test('channels move within a category and to another; categories move; people change role', () {
    final s = sampleServer();
    final talk = s.categories[1], voice = s.categories[2];
    final games = s.channel('games')!;
    s.move(games, talk, 0);
    expect(talk.channels.first.id, 'games');
    s.move(games, voice, voice.channels.length);
    expect(voice.channels.last.id, 'games');
    expect(talk.channels.any((c) => c.id == 'games'), isFalse);
    s.shiftCategory(voice, -2);
    expect(s.categories.first.id, 'voice');
    final priya = s.member('priya')!;
    s.setRole(priya, MockRole.moderator);
    expect(priya.role, MockRole.moderator);
    expect(s.liveSpaces.map((c) => c.id), ['lounge', 'gaming']);
  });

  for (final (name, size) in const [('phone', Size(412, 892)), ('fold', Size(1240, 900))]) {
    testWidgets('each of the five layouts draws the server on a $name', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (_) async => null);
      final sheet = await loadSheet(tester);
      final app = AppState()..setTheme('dark');
      await pumpScreen(tester, sheet, const ServerPreviewScreen(), app, size: size);
      await settle(tester);
      for (final l in ServerLayout.values) {
        await tester.tap(find.byKey(ValueKey('server-layout-${l.name}')));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: '${l.label} on a $name');
        expect(find.textContaining(l.after), findsOneWidget, reason: 'the bar says what ${l.label} is like');
        expect(find.textContaining('general'), findsWidgets, reason: '${l.label} lists the channels');
        if (autoUpdateGoldenFiles) await expectLater(find.byType(ServerPreviewScreen), matchesGoldenFile('shots/server-${l.name}-$name.png'));
      }
    });
  }

  testWidgets('a channel opens beside the list on a wide window; settings arrange the channels', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (_) async => null);
    final sheet = await loadSheet(tester);
    final server = sampleServer();
    await pumpScreen(tester, sheet, ServerPreviewScreen(server: server), AppState(), size: const Size(1240, 900));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('server-layout-rail')));
    await settle(tester);
    await tester.tap(find.text('game-night').first);
    await settle(tester);
    expect(find.byType(ChannelView), findsOneWidget);
    expect(find.text('Plans for Friday'), findsOneWidget, reason: 'its topic, in the channel opened beside the list');
    // The server's menu, its settings, and arranging.
    await tester.tap(find.text('Night Owls').first);
    await settle(tester);
    await tester.tap(find.text('Arrange channels and spaces'));
    await settle(tester);
    expect(find.byType(ChannelOrganizer), findsOneWidget);
    await tester.tap(find.text('photos').last);
    await settle(tester);
    await tester.tap(find.text('Move to Spaces'));
    await settle(tester);
    expect(server.categories[2].channels.last.name, 'photos');
    expect(find.byType(GlacierSwitch), findsNothing);
  });
}
