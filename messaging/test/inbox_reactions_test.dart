import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/inbox/inbox.dart';
import 'package:ghost_messaging/inbox/signal.dart';
import 'package:ghost_messaging/inbox/telegram.dart';
import 'package:ghost_messaging/ui/inbox_ui.dart';

import 'support/list_harness.dart';

/// Reacting to and replying to a Signal or Telegram message (Matt, 2026-11-17: "Id like to be able to reply to messages
/// as well as react to telegram and signal messages if possible").
class _Net extends InboxNetwork {
  final reacted = <(String, String, bool)>[];
  final replied = <(String, String)>[];
  final sent = <String>[];
  var list = <InboxMessage>[
    InboxMessage(id: '1', text: 'are you coming tonight?', date: DateTime(2026, 11, 17, 9), mine: false, sender: 'Jo', reactions: const [InboxReaction(emoji: '❤️', count: 2, mine: true)]),
    InboxMessage(id: '2', text: 'yes!', date: DateTime(2026, 11, 17, 9, 1), mine: true, replyTo: '1', replyText: 'are you coming tonight?', replySender: 'Jo'),
  ];

  @override
  String get id => 'signal';
  @override
  String get name => 'Signal';
  @override
  InboxState get state => InboxState.ready;
  @override
  String? get error => null;
  @override
  String? get account => null;
  @override
  List<InboxChat> get chats => [InboxChat(network: 'signal', id: 'c1', title: 'Jo', date: DateTime(2026, 11, 17, 9, 1), snippet: 'yes!')];
  @override
  List<InboxMessage> messagesOf(String chatId) => list;
  @override
  Future<void> load(String chatId, {bool older = false}) async {}
  @override
  Future<void> send(String chatId, String text) async => sent.add(text);
  @override
  Future<void> markRead(String chatId) async {}
  @override
  set watching(String? chatId) {}
  @override
  Future<void> start(AppState app) async {}
  @override
  Future<void> signOut() async {}
  @override
  bool get canReact => true;
  @override
  Future<void> react(String chatId, String messageId, String emoji, {bool remove = false}) async => reacted.add((messageId, emoji, remove));
  @override
  bool get canReply => true;
  @override
  Future<void> reply(String chatId, String messageId, String text) async => replied.add((messageId, text));
}

void main() {
  test('Signal\'s reactions, one a person, as kinds: how many each and whether yours is among them', () {
    final r = signalReactions({'aci-jo': '❤️', 'aci-sam': '❤️', 'aci-me': '😂', '': '👍'}, me: 'aci-me');
    expect(r.map((x) => (x.emoji, x.count, x.mine)), [('❤️', 2, false), ('😂', 1, true), ('👍', 1, true)]);
    expect(signalReactions(null), isEmpty);
  });

  test('Telegram\'s reactions: the emoji ones, with their counts and whether this account chose them', () {
    final r = telegramReactions({
      'reactions': {
        'reactions': [
          {'type': {'@type': 'reactionTypeEmoji', 'emoji': '👍'}, 'total_count': 3, 'is_chosen': true},
          {'type': {'@type': 'reactionTypeCustomEmoji', 'custom_emoji_id': '1'}, 'total_count': 1, 'is_chosen': false},
        ],
      },
    });
    expect(r.map((x) => (x.emoji, x.count, x.mine)), [('👍', 3, true)]);
    expect(Telegram().reactionChoices, isNot(contains('😂')), reason: 'Telegram has no 😂; 🤣 stands in');
  });

  testWidgets('a long press reacts, or takes yours off; Reply quotes the message and sends as a reply', (tester) async {
    final sheet = await loadSheet(tester);
    final net = _Net();
    await pumpScreen(tester, sheet, InboxChatScreen(network: net, chatId: 'c1'), AppState());
    await settle(tester);
    // Drawn: the reply's quote, and the reactions with their count.
    expect(find.byType(InboxQuote), findsOneWidget);
    expect(find.text('❤️'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.longPress(find.text('are you coming tonight?').last);
    await settle(tester);
    expect(find.byType(InboxReactionRow), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(InboxReactionRow), matching: find.text('😂')));
    await settle(tester);
    expect(net.reacted.last, ('1', '😂', false));

    // Yours again takes it off.
    await tester.longPress(find.text('are you coming tonight?').last);
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(InboxReactionRow), matching: find.text('❤️')));
    await settle(tester);
    expect(net.reacted.last, ('1', '❤️', true));

    // Reply: the bar says to whom, and the words go as a reply.
    await tester.pump(const Duration(seconds: 6));
    await tester.longPress(find.text('are you coming tonight?').last);
    await settle(tester);
    await tester.tap(find.text('Reply'));
    await settle(tester);
    expect(find.text('Replying to Jo'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'on my way');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(net.replied.single, ('1', 'on my way'));
    expect(net.sent, isEmpty);
    expect(find.text('Replying to Jo'), findsNothing, reason: 'the bar goes once sent');
  });
}
