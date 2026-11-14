import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/plugins/codes.dart';
import 'package:ghost_messaging/plugins/list.dart';
import 'package:ghost_messaging/plugins/plugin.dart';
import 'package:ghost_messaging/plugins/registry.dart';
import 'package:ghost_messaging/plugins/spam.dart';
import 'package:ghost_messaging/plugins/ui.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/ui/conversations.dart';

import 'support/list_harness.dart';

/// Spam filter (lib/plugins/spam.dart; Matt, 2026-11-14: "filtering out spam messages"): which texts the rules call
/// spam and why, that a contact's never is, that it is off until chosen, and the Spam section in the list with "Not
/// spam" that sticks.
MessageFacts _facts(String text, {List<String> from = const ['+15550001111'], bool contact = false, int thread = 7, bool? outgoing}) => MessageFacts(thread: thread, senders: from, text: text, contact: contact, outgoing: outgoing);

List<String> _signs(String text, {List<String> from = const ['+15550001111']}) => [for (final s in judgeSpam(_facts(text, from: from)).signs) s.id];

Finder _chip(String label) => find.descendant(of: find.byType(SectionTabs), matching: find.text(label));

const _prize = 'Congratulations! You\'ve won a \$1,000 gift card. Claim now: http://prize.example/win';
const _locked = 'Your account has been locked. Verify your identity at https://secure-login.example';
const _parcel = 'Your package could not be delivered. Reschedule here: bit.ly/3xYz';

void main() {
  group('the rules', () {
    test('each sign is found where it is, and one sign alone is not spam', () {
      expect(_signs(_prize), ['link', 'prize']);
      expect(_signs(_locked), ['link', 'pressure']);
      expect(_signs(_parcel), ['link', 'delivery']);
      expect(_signs('You\'re pre-approved for a \$5,000 loan! Act now'), ['pressure', 'money']);
      expect(_signs('Deals inside: www.shop.example/sale', from: ['promo@deals.example']), ['link', 'email']);
      expect(_signs('Unable to deliver your parcel: customs fee unpaid'), ['pressure', 'delivery']);
      for (final text in [_prize, _locked, _parcel]) {
        expect(judgeSpam(_facts(text)).spam, isTrue, reason: text);
      }

      // One sign, or none: an ordinary text from a shop, a bank, a courier, a person.
      for (final text in [
        'Your order has shipped. Track it: https://shop.example/t/123',
        'Unusual activity on your card. Reply YES if this was you.',
        'You\'re pre-approved for a \$5,000 loan! Reply YES',
        'Your package is on hold at the depot until Friday',
        'Your package was delivered',
        'See you at 7',
        'Hi, is this Anna?',
      ]) {
        final verdict = judgeSpam(_facts(text));
        expect(verdict.signs.length, lessThan(2), reason: text);
        expect(verdict.spam, isFalse, reason: text);
      }
    });

    test('a phrase is a word of its own, and an email address in a text is not a link', () {
      expect(_signs('Your phone was unlocked, thanks for choosing us'), isEmpty);
      expect(_signs('The surprised look on his face was priceless'), isEmpty);
      expect(_signs('Write to me at maya@example.com'), isEmpty);
      expect(_signs('Our community.center opens at 9'), isEmpty);
      expect(_signs('Details at example.com/today'), ['link']);
    });

    test('why it is spam is said in words, the signs in the order the rules are listed', () {
      expect(judgeSpam(_facts(_prize)).why, 'a link, prize wording');
      expect(judgeSpam(_facts('URGENT: your parcel is held. Pay the customs fee now: https://post.example/pay')).why, 'a link, pressure to act, a delivery problem');
    });

    test('a text with a sign-in code in it needs three signs, not two', () {
      const code = 'Your code is 482913. If this wasn\'t you, secure your account immediately: https://bank.example/help';
      final verdict = judgeSpam(_facts(code));
      expect(verdict.signs.map((s) => s.id), ['link', 'pressure']);
      expect(verdict.needed, 3);
      expect(verdict.spam, isFalse);
    });

    test('every rule says what it is, for Settings and for the row', () {
      expect(spamRules.map((r) => r.id).toSet(), hasLength(spamRules.length));
      for (final rule in spamRules) {
        expect(rule.name, isNotEmpty);
        expect(rule.says, isNotEmpty);
        expect(rule.about, endsWith('.'));
      }
    });
  });

  group('the plugin', () {
    const plugin = SpamPlugin();
    final registry = PluginRegistry(const [plugin]);
    MemoryStore on() => MemoryStore({'plugin_spam': 'on'});

    test('is off until it is chosen, and is one of the plugins the app ships with', () {
      expect(plugin.onByDefault, isFalse);
      expect(registry.isOn(plugin, MemoryStore()), isFalse);
      expect(registry.classify(_facts(_prize), MemoryStore()).isEmpty, isTrue);
      expect(registry.sections(MemoryStore()), isEmpty);
      expect(shippedPlugins.whereType<SpamPlugin>(), hasLength(1));
    });

    test('a spam text is tagged with why; a contact\'s and the person\'s own never are', () {
      final store = on();
      expect(registry.classify(_facts(_prize), store).detail('spam'), 'a link, prize wording');
      expect(registry.classify(_facts(_prize, contact: true), store).isEmpty, isTrue);
      expect(registry.classify(_facts(_prize, outgoing: true), store).isEmpty, isTrue);
      expect(registry.classify(_facts('See you at 7'), store).isEmpty, isTrue);
    });

    test('its section takes what is tagged, its row says why and has "Not spam"', () async {
      final store = on();
      final facts = _facts(_prize);
      final tags = registry.classify(facts, store);
      final section = registry.sectionOf(facts, tags, store)!;
      expect(section.id, 'spam');
      final look = registry.look(section, facts, tags, store)!;
      expect(look.value, isNull);
      expect(look.caption, 'Looks like spam: a link, prize wording');
      expect(look.word!.label, 'Not spam');
      expect(look.tap, isNull, reason: 'a tap opens the conversation, as anywhere');
      // One moved here by hand, whose words the rules would not call spam.
      expect(registry.look(section, _facts('Hi, is this Anna?'), TagSet.none, store)!.caption, 'Moved here by you');
    });

    test('a conversation\'s menu has "Not spam" in Spam, and "Move to Spam" elsewhere unless it is a contact\'s', () {
      final store = on();
      List<String> menu(MessageFacts facts, {String? section}) => [for (final b in registry.actions(Slots.conversationMenu, ConversationPlace(facts, registry.classify(facts, store), section: section), store)) b.action.label];
      expect(menu(_facts(_prize), section: 'spam'), ['Not spam']);
      expect(menu(_facts('Hi, is this Anna?')), ['Move to Spam']);
      expect(menu(_facts('Hi, is this Anna?', contact: true)), isEmpty);
    });

    test('a conversation in Spam is muted as its text is seen, unless that is switched off', () {
      final store = on();
      final facts = _facts(_prize);
      final tags = registry.classify(facts, store);
      expect(registry.incoming(facts, tags, store).map((b) => b.action), [isA<MuteNotification>()]);
      expect(registry.incoming(_facts('See you at 7'), TagSet.none, store), isEmpty);
      store.write('plugin_spam_mute', 'off');
      expect(registry.incoming(facts, tags, store), isEmpty);
    });

    test('another list of rules stands in for the app\'s own', () {
      const mine = SpamPlugin(rules: [
        SpamRule(id: 'fruit', name: 'Fruit', says: 'fruit', about: 'It names a fruit.', words: r'pineapple'),
        SpamRule(id: 'short', name: 'A short number', says: 'a short number', about: 'It came from a five-digit number.', sender: r'^\d{5}$'),
      ]);
      final other = PluginRegistry(const [mine]);
      final store = on();
      expect(other.classify(_facts('Fresh pineapple today', from: ['70220']), store).detail('spam'), 'fruit, a short number');
      expect(other.classify(_facts(_prize), store).isEmpty, isTrue);
      expect(other.settingsOf(mine).map((s) => s.label), containsAll(['Fruit', 'A short number']));
    });

    test('a text that is both a sign-in code and spam is in Codes: Codes is asked first', () {
      final both = PluginRegistry(shippedPlugins);
      final store = on();
      expect(both.plugins.first, isA<CodesPlugin>());
      const text = 'URGENT: your account is locked. Use code 482913 to verify your identity at https://bank.example/unlock and claim your prize';
      final facts = _facts(text);
      final tags = both.classify(facts, store);
      expect(tags.names, containsAll(['code', 'spam']));
      expect(both.sectionOf(facts, tags, store)!.id, 'codes');
    });
  });

  group('in the list', () {
    List<Map<String, Object?>> phone() => [
          ListPhone.conversation(1, '+15551230001', 'Sounds good, see you at 7', name: 'Maya Chen', minutes: 4),
          ListPhone.conversation(2, '+15559870002', _prize, minutes: 9, unread: true),
          ListPhone.conversation(3, '+15551230005', 'Call me when you land', name: 'Dad', minutes: 50),
          ListPhone.conversation(4, '+15559870004', _parcel, minutes: 120),
          ListPhone.conversation(5, '+15559870005', 'Hi, is this Anna?', minutes: 300),
          ListPhone.conversation(6, '+15551230006', _locked, name: 'Priya Natarajan', minutes: 400),
        ];

    testWidgets('off, as the app ships: nothing is hidden and nothing is asked of the phone', (tester) async {
      final listed = ListPhone(phone())..install();
      final sheet = await loadSheet(tester);
      await pumpScreen(tester, sheet, const ConversationsScreen(), AppState());
      expect(find.byType(SectionTabs), findsNothing);
      expect(find.byType(ConversationRow), findsNWidgets(6));
      expect(listed.asked, isEmpty);
    });

    testWidgets('on: spam leaves the main list for its section, which says why, and "Not spam" puts one back for good', (tester) async {
      final listed = ListPhone(phone())..install();
      final sheet = await loadSheet(tester);
      final state = AppState()..setFlag('plugin_spam', true);
      await pumpScreen(tester, sheet, const ConversationsScreen(), state);

      // Two look like spam and are from numbers; Priya's, a contact's, stays where it is.
      expect(_chip('Spam'), findsOneWidget);
      expect(_chip('2'), findsOneWidget);
      expect(find.byType(ConversationRow), findsNWidgets(4));
      expect(find.text(_prize), findsNothing);
      expect(find.text(_locked), findsOneWidget);
      // The unread one was muted as it was seen.
      expect(listed.asked, ['muted 2 true']);

      await tester.tap(_chip('Spam'));
      await settle(tester);
      expect(find.byType(PluginRow), findsNWidgets(2));
      expect(find.text('Looks like spam: a link, prize wording'), findsOneWidget);
      expect(find.text('Looks like spam: a link, a delivery problem'), findsOneWidget);
      expect(find.textContaining('Nothing here is deleted or blocked'), findsOneWidget);

      // "Not spam" on the row: back in the main list, said, kept, and its notifications back on.
      await tester.tap(find.text('Not spam').first);
      await settle(tester);
      expect(find.text('Moved to Messages'), findsOneWidget);
      expect(find.byType(PluginRow), findsOneWidget);
      expect(listed.prefs[Filing.key], '2:');
      expect(listed.asked, ['muted 2 true', 'muted 2 false']);
      expect(listed.prefs[ListPlugins.mutedKey], '');

      // Another spam text comes in that conversation: it stays in the main list, and is not muted again.
      listed.conversations[1]['snippet'] = 'FINAL NOTICE: claim your prize now at http://prize.example/last';
      listed.conversations[1]['date'] = DateTime.now().millisecondsSinceEpoch;
      listed.conversations[1]['unread'] = true;
      Sms.instance.changes.add(2);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(_chip('1'), findsOneWidget);
      expect(listed.asked, ['muted 2 true', 'muted 2 false']);
      await tester.tap(_chip('Messages'));
      await settle(tester);
      expect(find.textContaining('FINAL NOTICE'), findsOneWidget);

      // One the rules missed is moved to Spam from its long press.
      await tester.longPress(find.text('Hi, is this Anna?'));
      await settle(tester);
      await tester.tap(find.text('Move to Spam'));
      await settle(tester);
      expect(find.text('Moved to Spam'), findsOneWidget);
      expect(find.text('Hi, is this Anna?'), findsNothing);
      expect(_chip('2'), findsOneWidget);
      expect(listed.prefs[Filing.key], '2:,5:spam');
      await tester.tap(_chip('Spam'));
      await settle(tester);
      expect(find.text('Moved here by you'), findsOneWidget);
      // A contact's conversation is not offered it.
      await tester.tap(_chip('Messages'));
      await settle(tester);
      await tester.longPress(find.text('Call me when you land'));
      await settle(tester);
      expect(find.text('Move to Spam'), findsNothing);
    });

    testWidgets('what was marked "Not spam" is still not spam when the app is opened again', (tester) async {
      final listed = ListPhone(phone())..install();
      listed.prefs.addAll({'plugin_spam': 'on', Filing.key: '2:'});
      final sheet = await loadSheet(tester);
      // The person's choices as Android kept them.
      final state = AppState();
      await tester.runAsync(state.load);
      await pumpScreen(tester, sheet, const ConversationsScreen(), state);
      expect(_chip('1'), findsOneWidget);
      expect(find.text(_prize), findsOneWidget);
      expect(listed.asked, isEmpty, reason: 'it is in the main list: nothing mutes it');
    });
  });
}
