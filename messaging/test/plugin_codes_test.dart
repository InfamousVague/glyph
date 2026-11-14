import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/plugins/codes.dart';
import 'package:ghost_messaging/plugins/plugin.dart';
import 'package:ghost_messaging/plugins/registry.dart';
import 'package:ghost_messaging/plugins/ui.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/ui/common.dart' show IconTap;
import 'package:ghost_messaging/ui/conversations.dart';

import 'support/list_harness.dart';

/// Codes (lib/plugins/codes.dart; Matt, 2026-11-14: "separating OTPs into their own section"): what reads as a
/// sign-in code, which conversations the section takes, and the section in the list.
MessageFacts _facts(String text, {bool contact = false, bool group = false, int thread = 4}) => MessageFacts(thread: thread, senders: const ['28849'], text: text, contact: contact, group: group);

Finder _chip(String label) => find.descendant(of: find.byType(SectionChips), matching: find.text(label));

void main() {
  group('what reads as a code', () {
    test('the list\'s finder answers as the notification\'s does, on the examples both are held to', () {
      // android/.../CodesTest.kt reads the same file for Notifier.otp.
      final cases = (jsonDecode(File('test/code_vectors.json').readAsStringSync()) as Map<String, dynamic>)['cases'] as List;
      expect(cases.length, greaterThanOrEqualTo(20));
      for (final c in cases) {
        expect(signInCode(c['text'] as String), c['code'], reason: c['text'] as String);
      }
    });

    test('a long text is not looked through', () {
      final filler = 'word ' * 80;
      expect(signInCode('Your code is 482913 $filler'.substring(0, 400)), '482913');
      expect(signInCode('Your code is 482913 $filler'.substring(0, 401)), isNull);
    });
  });

  group('the plugin', () {
    const plugin = CodesPlugin();
    final registry = PluginRegistry(const [plugin]);

    test('is on until switched off, and is one of the plugins the app ships with', () {
      expect(plugin.onByDefault, isTrue);
      expect(registry.isOn(plugin, MemoryStore()), isTrue);
      expect(shippedPlugins.whereType<CodesPlugin>(), hasLength(1));
    });

    test('a text with a code is tagged with it, whoever sent it', () {
      final store = MemoryStore();
      expect(registry.classify(_facts('Your verification code is 482913.'), store).detail('code'), '482913');
      expect(registry.classify(_facts('the door code is 4417', contact: true), store).detail('code'), '4417');
      expect(registry.classify(_facts('See you at 7'), store).isEmpty, isTrue);
    });

    test('the section takes a code from one number that is not a contact, and leaves a contact\'s and a group\'s where they are', () {
      final store = MemoryStore();
      String? where(MessageFacts facts) => registry.sectionOf(facts, registry.classify(facts, store), store)?.id;
      expect(where(_facts('Your verification code is 482913.')), 'codes');
      expect(where(_facts('the door code is 4417', contact: true)), isNull);
      expect(where(_facts('the door code is 4417', group: true)), isNull);
      expect(where(_facts('Your package was delivered')), isNull);
    });

    test('its row is the code, large, and a tap or the button at its end copies it and marks the conversation read', () async {
      final store = MemoryStore();
      final facts = _facts('Your verification code is 482913.');
      final tags = registry.classify(facts, store);
      final look = registry.look(registry.sections(store).single, facts, tags, store)!;
      expect(look.value, '482913');
      expect(look.tap!.label, 'Copy 482913');
      expect(look.end!.label, 'Copy 482913');
      final host = _Host(registry.prefsOf(plugin, store));
      await look.tap!.run(host);
      expect(host.did, ['copy 482913 (Copied 482913)', 'read 4']);
      // With its own setting off, copying leaves it unread.
      host.did.clear();
      host.prefs.setFlag('read', false);
      await look.tap!.run(host);
      expect(host.did, ['copy 482913 (Copied 482913)']);
      // Filed in Codes by hand with no code in its last words: drawn as the main list draws it.
      expect(registry.look(registry.sections(store).single, _facts('Thanks'), TagSet.none, store), isNull);
    });

    test('a conversation\'s menu copies its code and moves it between Codes and the main list', () {
      final store = MemoryStore();
      final code = _facts('Your verification code is 482913.');
      final tags = registry.classify(code, store);
      List<String> menu(ConversationPlace place) => [for (final b in registry.actions(Slots.conversationMenu, place, store)) b.action.label];
      expect(menu(ConversationPlace(code, tags, section: 'codes')), ['Copy 482913', 'Keep in Messages']);
      expect(menu(ConversationPlace(code, tags)), ['Copy 482913', 'Move to Codes']);
      expect(menu(ConversationPlace(_facts('Thanks'), TagSet.none, section: 'codes')), ['Keep in Messages']);
      expect(menu(ConversationPlace(_facts('Thanks'), TagSet.none)), isEmpty);
    });

    test('a message\'s menu offers to copy the code in it, if it is someone else\'s', () {
      final store = MemoryStore();
      const people = [Person(address: '28849')];
      Message message(String body, {bool outgoing = false}) => Message(id: 1, kind: 'sms', address: outgoing ? '' : '28849', body: body, date: DateTime(2026), outgoing: outgoing, state: 'received');
      List<String> menu(Message m) {
        final facts = MessageFacts.message(m, thread: 4, people: people);
        return [for (final b in registry.actions(Slots.messageMenu, MessagePlace(facts, registry.classify(facts, store)), store)) b.action.label];
      }

      expect(menu(message('Your code is 482913')), ['Copy 482913']);
      expect(menu(message('My code is 482913', outgoing: true)), isEmpty);
      expect(menu(message('See you at 7')), isEmpty);
    });
  });

  group('in the list', () {
    List<Map<String, Object?>> phone() => [
          ListPhone.conversation(1, '+15551230001', 'Sounds good, see you at 7', name: 'Maya Chen', minutes: 4),
          ListPhone.conversation(2, '28849', 'Your verification code is 482913. Don\'t share it with anyone.', minutes: 9, unread: true),
          ListPhone.conversation(3, '+15551230005', 'The door code is 4417', name: 'Dad', minutes: 50),
          ListPhone.conversation(4, '70002', '771-204 is your login code', minutes: 120),
          ListPhone.conversation(5, '+15551230007', 'Your package was delivered', minutes: 300),
        ];

    testWidgets('codes have a section of their own, the newest first, and a tap copies one', (tester) async {
      final listed = ListPhone(phone())..install();
      final sheet = await loadSheet(tester);
      await pumpScreen(tester, sheet, const ConversationsScreen(), AppState());

      // The app's own plugins, as it ships: Codes is on. The two codes from numbers have left the main list; Dad's
      // has not.
      expect(_chip('Codes'), findsOneWidget);
      expect(_chip('2'), findsOneWidget);
      expect(find.byType(ConversationRow), findsNWidgets(3));
      expect(find.textContaining('482913'), findsNothing);
      expect(find.text('The door code is 4417'), findsOneWidget);

      await tester.tap(_chip('Codes'));
      await settle(tester);
      expect(find.byType(PluginRow), findsNWidgets(2));
      expect(tester.getCenter(find.text('482913')).dy, lessThan(tester.getCenter(find.text('771204')).dy));
      expect(find.text('Your verification code is 482913. Don\'t share it with anyone.'), findsOneWidget, reason: 'the words, small, under the code');

      await tester.tap(find.text('482913'));
      await settle(tester);
      expect(listed.copied, ['482913']);
      expect(find.text('Copied 482913'), findsOneWidget);
      expect(listed.asked, ['markRead 2']);
      await tester.tap(find.byWidgetPredicate((w) => w is IconTap && w.label == 'Copy 771204'));
      await settle(tester);
      expect(listed.copied, ['482913', '771204']);

      // A contact's code can be moved to Codes from its long press, and stays.
      await tester.tap(_chip('Messages'));
      await settle(tester);
      await tester.longPress(find.text('The door code is 4417'));
      await settle(tester);
      expect(find.text('Copy 4417'), findsOneWidget);
      await tester.tap(find.text('Move to Codes'));
      await settle(tester);
      expect(_chip('3'), findsOneWidget);
      expect(listed.prefs[Filing.key], '3:codes');
    });

    testWidgets('switched off in the person\'s choices, the list has no Codes', (tester) async {
      ListPhone(phone()).install();
      final sheet = await loadSheet(tester);
      await pumpScreen(tester, sheet, const ConversationsScreen(), AppState()..setFlag('plugin_codes', false));
      expect(find.byType(SectionChips), findsNothing);
      expect(find.byType(ConversationRow), findsNWidgets(5));
    });
  });
}

/// A host that writes down what it was asked.
class _Host implements PluginHost {
  _Host(this.prefs);
  @override
  final PluginPrefs prefs;
  final did = <String>[];
  @override
  void say(String words) => did.add('say $words');
  @override
  void copy(String text, {String? say}) => did.add('copy $text${say == null ? '' : ' ($say)'}');
  @override
  void open(int thread) => did.add('open $thread');
  @override
  Future<void> markRead(int thread) async => did.add('read $thread');
  @override
  void move(int thread, String? section) => did.add('move $thread $section');
  @override
  void write(String text) => did.add('write $text');
}
