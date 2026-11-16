import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/inbox/bluesky.dart';
import 'package:ghost_messaging/inbox/inbox.dart';
import 'package:ghost_messaging/inbox/telegram.dart';
import 'package:ghost_messaging/main.dart' show InkOverrides, ghostTypography;
import 'package:ghost_messaging/ui/common.dart' show IconTap;
import 'package:ghost_messaging/ui/composer_box.dart';
import 'package:ghost_messaging/ui/conversations.dart';
import 'package:ghost_messaging/ui/inbox_ui.dart';
import 'package:ghost_messaging/ui/me.dart' show NetworkMark;
import 'package:ghost_messaging/ui/settings.dart';
import 'package:glacier/glacier.dart';

import 'support/list_harness.dart';

/// A network signed in, held in memory: what the screens of the inbox (lib/ui/inbox_ui.dart) draw from.
class FakeNetwork extends InboxNetwork {
  FakeNetwork(this.id, this.name, this._chats, this._messages);
  @override
  final String id;
  @override
  final String name;
  final List<InboxChat> _chats;
  final Map<String, List<InboxMessage>> _messages;
  final sent = <(String, String)>[];
  final read = <String>[];
  String? watched;

  @override
  InboxState get state => InboxState.ready;
  @override
  String? get error => null;
  @override
  String? get account => '@matt';
  @override
  List<InboxChat> get chats => _chats;
  @override
  bool get canSendFiles => true;
  final wanted = <int>[];
  @override
  void wantFile(int fileId) => wanted.add(fileId);
  @override
  List<InboxMessage> messagesOf(String chatId) => _messages[chatId] ?? const [];
  @override
  Future<void> load(String chatId, {bool older = false}) async {}
  @override
  Future<void> send(String chatId, String text) async {
    sent.add((chatId, text));
    _messages[chatId] = [...messagesOf(chatId), InboxMessage(id: 'n${sent.length}', text: text, date: DateTime.now(), mine: true)];
    notifyListeners();
  }

  @override
  Future<void> markRead(String chatId) async => read.add(chatId);
  @override
  set watching(String? chatId) => watched = chatId;
  @override
  Future<void> start(AppState app) async {}
  @override
  Future<void> signOut() async {}
}

Future<void> _shoot(WidgetTester tester, TokenSheet sheet, Widget screen, String name, {required bool dark}) async {
  final state = AppState()..setTheme(dark ? 'dark' : 'light');
  tester.view.physicalSize = const Size(412, 892) * 2.0;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(
    state: state,
    child: WidgetsApp(
      color: const Color(0xFF4F5BD5),
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(RouteSettings s, WidgetBuilder b) => PageRouteBuilder<T>(settings: s, pageBuilder: (c, _, _) => b(c)),
      builder: (context, child) => GlacierTheme(
        sheet: sheet,
        attrs: {'platform': 'mobile', 'theme': state.theme},
        typography: ghostTypography('noto'),
        child: InkOverrides(child: GlacierToastProvider(child: child!)),
      ),
      home: KeyedSubtree(key: ValueKey('$name-$dark'), child: screen),
    ),
  ));
  await settle(tester);
  await _again(tester, name, dark: dark);
}

Future<void> _again(WidgetTester tester, String name, {required bool dark}) async {
  await settle(tester);
  // Written with --update-goldens, as screens_test.dart's are; a plain run builds every screen and fails on an exception.
  if (autoUpdateGoldenFiles) await expectLater(find.byType(WidgetsApp), matchesGoldenFile('shots/$name-${dark ? 'dark' : 'light'}.png'));
}

Future<void> _fonts() async {
  for (final (name, file) in [('Inter Variable', 'assets/fonts/InterVariable-latin.ttf'), ('Ghost Emoji Noto', 'assets/emoji/NotoColor.ttf')]) {
    await (FontLoader(name)..addFont(File(file).readAsBytes().then((b) => ByteData.view(Uint8List.fromList(b).buffer)))).load();
  }
}

void main() {
  setUpAll(_fonts);
  late FakeNetwork telegram;
  final now = DateTime.now();

  setUp(() {
    ListPhone([
      ListPhone.conversation(1, '+15551230001', 'Sounds good, see you at 7!', name: 'Maya Chen', minutes: 4),
      ListPhone.conversation(2, '+15551230005', 'Call me when you land', name: 'Dad', minutes: 300),
    ]).install();
    telegram = FakeNetwork('telegram', 'Telegram', [
      InboxChat(network: 'telegram', id: '10', title: 'Jo Park', date: now.subtract(const Duration(minutes: 2)), snippet: 'are you coming tonight?', unread: 2),
      InboxChat(network: 'telegram', id: '20', title: 'Weekend crew', date: now.subtract(const Duration(hours: 3)), snippet: 'tent is packed', group: true),
      InboxChat(network: 'telegram', id: '30', title: 'Sam Rivera', date: now.subtract(const Duration(days: 2)), snippet: 'thanks!', lastFromMe: true),
    ], {
      '10': [
        InboxMessage(id: '1', text: 'hey! long time', date: now.subtract(const Duration(minutes: 30)), mine: false),
        InboxMessage(id: '2', text: 'I know, how have you been?', date: now.subtract(const Duration(minutes: 28)), mine: true),
        InboxMessage(id: '3', text: 'good! there\'s a thing at the park later', date: now.subtract(const Duration(minutes: 3)), mine: false),
        InboxMessage(id: '4', text: 'are you coming tonight?', date: now.subtract(const Duration(minutes: 2)), mine: false),
        InboxMessage(id: '5', text: 'the park', date: now.subtract(const Duration(minutes: 1)), mine: false, media: const [InboxMedia(kind: 'photo', fileId: 42, width: 800, height: 600)]),
        InboxMessage(id: '6', text: '', date: now.subtract(const Duration(seconds: 30)), mine: false, media: const [InboxMedia(kind: 'file', fileId: 43, name: 'tickets.pdf', size: 245760)]),
      ],
    });
    Inbox.instance = Inbox.of([telegram, FakeNetwork('bluesky', 'Bluesky', const [], const {})]);
  });

  tearDown(() => Inbox.instance = null);

  testWidgets('a signed-in network\'s chats are among the texts, newest first, marked with its logo; one opens, is read, and is answered', (tester) async {
    final sheet = await loadSheet(tester);
    for (final dark in [false, true]) {
      // Mixed into Messages (Matt, 2026-11-15: "Id like the telegram chats to be mixed into the normal text messages
      // (same with bluesky) just add a telegram icon in thr corner of the bubble"): no tab of their own.
      await _shoot(tester, sheet, const ConversationsScreen(), '16-inbox-list', dark: dark);
      expect(find.bySemanticsLabel(RegExp('^Telegram')), findsNothing);
      expect(find.text('Jo Park'), findsOneWidget);
      expect(find.text('Maya Chen'), findsWidgets);
      final rows = find.byType(InboxChatRow);
      expect(rows, findsWidgets);
      final badges = find.descendant(of: rows.first, matching: find.byType(NetworkMark));
      expect(badges, findsOneWidget, reason: 'Telegram\'s logo on the corner of the face');
      // The newest first: Jo Park (two minutes ago) above Weekend crew (three hours).
      expect(tester.getTopLeft(find.text('Jo Park')).dy, lessThan(tester.getTopLeft(find.text('Weekend crew')).dy));

      await tester.tap(find.text('Jo Park'));
      await settle(tester);
      expect(telegram.watched, '10');
      expect(telegram.read, contains('10'));
      expect(find.text('are you coming tonight?'), findsOneWidget);
      await _again(tester, '16-inbox-chat', dark: dark);

      await tester.enterText(find.byType(EditableText).last, 'on my way');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(telegram.sent.last, ('10', 'on my way'));
      expect(find.text('on my way'), findsWidgets);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester);
    }
  });

  // Matt, 2026-11-15: "Also use the same composer for telegram and if possible proxy the archive and delete messages
  // too, if we can't actually delete telegram messages add them to a ignore or archive list".
  testWidgets('a chat slid is archived and pinned (in Ghost\'s own lists where the network keeps none); its page has the same composer, and a message is deleted', (tester) async {
    final sheet = await loadSheet(tester);
    telegram.listStore = AppState();
    await _shoot(tester, sheet, const ConversationsScreen(), '16-inbox-list-archive', dark: false);
    // Slid left to Archive and let go, as a conversation of texts is (Matt, 2026-11-15: "Don't use a press and hold
    // menu on telegram chats use the same slide solution normal messages use").
    final left = await tester.startGesture(tester.getCenter(find.text('Weekend crew')));
    await left.moveBy(const Offset(-30, 0));
    await left.moveBy(const Offset(-80, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await left.up();
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Weekend crew'), findsNothing);
    expect(telegram.archivedChats.map((c) => c.title), ['Weekend crew']);
    // Slid right, pinned: at the top, above the newest text.
    final right = await tester.startGesture(tester.getCenter(find.text('Sam Rivera')));
    await right.moveBy(const Offset(30, 0));
    await right.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await right.up();
    await settle(tester);
    expect(telegram.localList('pinned'), {'30'});
    expect(tester.getTopLeft(find.text('Sam Rivera')).dy, lessThan(tester.getTopLeft(find.text('Jo Park')).dy));

    await tester.tap(find.text('Jo Park'));
    await settle(tester);
    expect(find.byType(ComposerBox), findsOneWidget);
    // Laid out as a conversation of texts is (Matt, 2026-11-15: "The compose window should also use the exact same
    // layout as messages"): + at its start, the microphone at its end while it is empty.
    expect(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Add an attachment'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Record a voice message'), findsOneWidget);
    // A picture is asked for as it is drawn; a file is its name and size.
    expect(telegram.wanted, contains(42));
    expect(find.text('tickets.pdf'), findsOneWidget);
    expect(find.text('240 KB'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'hi');
    await settle(tester);
    expect(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Send' && w.onPressed != null), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, '');
    await settle(tester);
    await tester.longPress(find.text('hey! long time'));
    await settle(tester);
    expect(find.text('Delete for everyone'), findsNothing, reason: 'this network says nothing can be');
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('hey! long time'), findsNothing);
    expect(find.text('I know, how have you been?'), findsOneWidget);
  });

  // Matt, 2026-11-15: "proxy telegram codes through to the codes tab as well".
  test('a sign-in code from Telegram\'s own account or a bot is a code; a friend\'s is not', () {
    final now = DateTime.now();
    InboxChat chat(String text, {bool service = true, bool mine = false}) => InboxChat(network: 'telegram', id: '1', title: 'Telegram', date: now, snippet: text, service: service, lastFromMe: mine);
    expect(inboxCode(chat('Login code: 48213. Do not give this code to anyone')), '48213');
    expect(inboxCode(chat('Login code: 48213', service: false)), isNull, reason: 'a person\'s chat');
    expect(inboxCode(chat('Login code: 48213', mine: true)), isNull);
    expect(inboxCode(chat('Welcome to Telegram')), isNull);
  });

  testWidgets('signing in: Bluesky\'s page, and Telegram\'s steps', (tester) async {
    final sheet = await loadSheet(tester);
    for (final dark in [false, true]) {
      await _shoot(tester, sheet, BlueskySignInScreen(network: Bluesky(entryway: 'http://127.0.0.1:9', plc: 'http://127.0.0.1:9')), '16-inbox-bluesky-sign-in', dark: dark);
      expect(find.textContaining('Allow access to your direct messages'), findsOneWidget);

      final unavailable = Telegram(apiId: 0, apiHash: '');
      await _shoot(tester, sheet, TelegramSignInScreen(network: unavailable), '16-inbox-telegram-unavailable', dark: dark);
      expect(find.textContaining('isn\'t in this build'), findsOneWidget);
    }
  });

  testWidgets('Bluesky is coming soon: no tab, no sign-in, and never started', (tester) async {
    Inbox.instance = null;
    final own = Inbox.instance;
    final bluesky = own.named('bluesky')!;
    expect(bluesky.soon, isTrue);
    expect(own.ready, isNot(contains(bluesky)));
    final sheet = await loadSheet(tester);
    addInboxSettings();
    addTearDown(() => SettingsSources.remove(inboxSettingsSections));
    for (final dark in [false, true]) {
      await _shoot(tester, sheet, const SettingsSectionScreen('inbox-bluesky'), '16-inbox-bluesky-soon', dark: dark);
      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
    }
  });

  testWidgets('each network has a section of Settings', (tester) async {
    final sections = inboxSettingsSections();
    expect(sections.map((s) => s.label), ['Telegram', 'Bluesky']);
    final sheet = await loadSheet(tester);
    addInboxSettings();
    addTearDown(() => SettingsSources.remove(inboxSettingsSections));
    for (final dark in [false, true]) {
      await _shoot(tester, sheet, const SettingsSectionScreen('inbox-telegram'), '16-inbox-settings', dark: dark);
      expect(find.text('@matt'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    }
  });
}
