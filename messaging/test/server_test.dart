import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/ui/conversations.dart';
import 'package:ghost_messaging/ui/servers/server_mock.dart';
import 'package:ghost_messaging/ui/servers/server_parts.dart';
import 'package:ghost_messaging/ui/servers/server_sidebar.dart';
import 'package:ghost_messaging/ui/shell.dart';

import 'support/list_harness.dart';

/// Servers (lib/ui/servers; Matt, 2026-11-17: "Let's go with the workspace view for servers but it should takeover the
/// normal sidebar when i enter a server with a back button at the top"). Pictures of the made-up server on a phone and
/// on an unfolded Fold go to test/shots/ with --update-goldens.
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
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('ghost_messaging/sms'), (_) async => null));

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

  Future<void> enter(WidgetTester tester, Size size) async {
    final sheet = await loadSheet(tester);
    await pumpScreen(tester, sheet, const AppShell(), AppState()..setTheme('dark'), size: size);
    await settle(tester);
    tester.state<AppShellState>(find.byType(AppShell)).go('new');
    await settle(tester);
    await tester.tap(find.text('Add a server (preview)'));
    await settle(tester);
  }

  testWidgets('on a wide window the server takes the list\'s place, its first channel beside it; back is the conversations', (tester) async {
    await enter(tester, const Size(1240, 900));
    expect(find.byType(ServerSidebar), findsOneWidget);
    expect(find.text('Unreads'), findsOneWidget);
    expect(find.byType(ChannelView), findsOneWidget, reason: 'the first text channel, beside the list');
    expect(find.text('News from the admins'), findsOneWidget);
    if (autoUpdateGoldenFiles) await expectLater(find.byType(AppShell), matchesGoldenFile('shots/server-fold.png'));

    await tester.tap(find.text('game-night').first);
    await settle(tester);
    expect(find.text('Plans for Friday'), findsOneWidget, reason: 'the channel chosen, in the pane');
    expect(tester.widget<ChannelTile>(find.ancestor(of: find.text('game-night').first, matching: find.byType(ChannelTile))).selected, isTrue);

    // The server's menu: arranging opens in the pane, and moves a channel.
    await tester.tap(find.text('Night Owls').first);
    await settle(tester);
    await tester.tap(find.text('Arrange channels and spaces'));
    await settle(tester);
    expect(find.byType(ChannelOrganizer), findsOneWidget);
    await tester.tap(find.text('photos').last);
    await settle(tester);
    await tester.tap(find.text('Move to Spaces'));
    await settle(tester);
    expect(find.byType(ServerSidebar), findsOneWidget, reason: 'the server stays in the list\'s place');

    await tester.tap(find.byKey(const ValueKey('server-back')));
    await settle(tester);
    expect(find.byType(ServerSidebar), findsNothing);
    expect(find.byType(ChannelOrganizer), findsNothing, reason: 'its pages go with it');
    expect(find.byType(ConversationsScreen), findsOneWidget);
  });

  testWidgets('on a phone the server is the list; a channel opens over it, and back comes to the server', (tester) async {
    await enter(tester, const Size(412, 892));
    expect(find.byType(ServerSidebar), findsOneWidget);
    expect(find.byType(ChannelView), findsNothing, reason: 'nothing opens by itself on a phone');
    expect(tester.takeException(), isNull);
    if (autoUpdateGoldenFiles) await expectLater(find.byType(AppShell), matchesGoldenFile('shots/server-phone.png'));

    await tester.tap(find.text('general').first);
    await settle(tester);
    expect(find.text('#general'), findsOneWidget);
    if (autoUpdateGoldenFiles) await expectLater(find.byType(AppShell), matchesGoldenFile('shots/server-phone-channel.png'));
    await tester.tap(find.bySemanticsLabel('Back').last);
    await settle(tester);
    expect(find.byType(ChannelView), findsNothing);
    expect(find.byType(ServerSidebar), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('server-back')));
    await settle(tester);
    expect(find.byType(ServerSidebar), findsNothing);
  });
}
