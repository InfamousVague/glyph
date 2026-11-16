import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/plugins/plugin.dart';
import 'package:ghost_messaging/plugins/registry.dart';
import 'package:ghost_messaging/plugins/replies.dart';

/// Replies (lib/plugins/replies.dart; Matt, 2026-11-14: "Needs a reply", "Smart replies", "Follow-up nudges").
void main() {
  final now = DateTime(2026, 11, 14, 10);

  test('what asks something of the reader', () {
    expect(asksSomething('Are you free Saturday?'), isTrue);
    expect(asksSomething('let me know when you land'), isTrue);
    expect(asksSomething('can you grab milk'), isTrue);
    expect(asksSomething('Sounds good, see you'), isFalse);
    expect(asksSomething('haha'), isFalse);
  });

  test('replies that fit the text', () {
    expect(repliesFor('Thanks so much!').first, 'You\'re welcome!');
    expect(repliesFor('Are you coming tonight?'), contains('Yes'));
    expect(repliesFor('Dinner Friday at 7?'), contains('Sounds good!'));
    expect(repliesFor('where are you'), contains('On my way'));
    expect(repliesFor('what time works for you?'), contains('Let me check'));
    expect(repliesFor('ok cool'), hasLength(3));
  });

  test('a promise of yours, and when to be reminded of it', () {
    final p = promiseIn('I\'ll send you the photos tonight at 8', now)!;
    expect(p.at, DateTime(2026, 11, 14, 19, 45), reason: 'a quarter of an hour before the time it said');
    expect(p.label, 'Today 8 PM');
    expect(promiseIn('will call you later', now)!.label, 'Later');
    expect(promiseIn('See you tonight at 8', now), isNull, reason: 'a plan, not a promise to do something');
    expect(promiseIn('I sent it', now), isNull);
  });

  test('Needs a reply: an unread question, from a person, stays in Messages too', () {
    final registry = PluginRegistry(const [RepliesPlugin()]);
    final store = MemoryStore();
    MessageFacts facts(String text, {bool unread = true, bool contact = true, String from = '+15551230001'}) =>
        MessageFacts(thread: 1, senders: [from], text: text, contact: contact, unread: unread);
    PluginSection? at(MessageFacts f) => registry.sectionOf(f, registry.classify(f, store), store);
    expect(at(facts('Are you free Saturday?')), isNull, reason: 'the tab is off until it is turned on (Matt, 2026-11-16)');
    store.write('plugin_replies_tab', 'on');
    expect(at(facts('Are you free Saturday?'))?.id, RepliesPlugin.section);
    expect(at(facts('Are you free Saturday?', unread: false)), isNull, reason: 'read: it has been seen to');
    expect(at(facts('Sounds good')), isNull);
    expect(at(facts('Reply YES to confirm?', contact: false, from: '28777')), isNull, reason: 'a short code asks no person to answer');
    expect(registry.sections(store).single.section.leavesMain, isFalse);
    expect(remindTimes(now).map((t) => t.label), ['In an hour', 'This evening', 'Tomorrow morning']);
    expect(shippedPlugins.whereType<RepliesPlugin>(), hasLength(1));
  });
}
