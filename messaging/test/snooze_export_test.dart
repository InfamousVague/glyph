import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/export_chat.dart';
import 'package:ghost_messaging/snooze.dart';

/// Snoozing a conversation and exporting one (GMFB-36, from the Uplink gap review: snoozed messages were in Uplink's
/// backlog, #53, and exporting conversations in Warp's, #373).
void main() {
  group('snooze', () {
    late DateTime now;
    late List<String> told;
    setUp(() {
      now = DateTime(2026, 11, 22, 14, 0);
      told = [];
      Snoozed.now = () => now;
      Snoozed.woke = (key, title) => told.add('$key $title');
      Snoozed.instance.reset();
    });
    tearDown(() {
      Snoozed.instance.reset();
      Snoozed.now = DateTime.now;
      Snoozed.woke = (_, _) {};
    });

    test('out of Messages until its time, then back at the top with a notification, until it is opened', () {
      final app = AppState();
      Snoozed.instance.start(app);
      final key = Snoozed.text(42);
      Snoozed.instance.snooze(key, now.add(const Duration(hours: 1)), title: 'Maya');
      expect(Snoozed.instance.hides(key), isTrue);
      expect(Snoozed.instance.until(key), now.add(const Duration(hours: 1)));

      now = now.add(const Duration(minutes: 59));
      Snoozed.instance.wakeDue();
      expect(told, isEmpty);
      expect(Snoozed.instance.hides(key), isTrue);

      now = now.add(const Duration(minutes: 2));
      Snoozed.instance.wakeDue();
      expect(told, ['text:42 Maya']);
      expect(Snoozed.instance.hides(key), isFalse);
      expect(Snoozed.instance.woken(key), isTrue, reason: 'at the top until opened');
      Snoozed.instance.wakeDue();
      expect(told.length, 1, reason: 'told once');

      Snoozed.instance.opened(key);
      expect(Snoozed.instance.woken(key), isFalse);
    });

    test('kept with the app\'s choices: a snooze that came due while closed ends when the app opens', () {
      final app = AppState();
      Snoozed.instance.start(app);
      Snoozed.instance.snooze(Snoozed.text(7), now.add(const Duration(hours: 3)), title: 'Sam');
      Snoozed.instance.reset();
      now = now.add(const Duration(hours: 4));
      Snoozed.instance.start(app);
      expect(told, ['text:7 Sam']);
      expect(Snoozed.instance.woken(Snoozed.text(7)), isTrue);
    });

    test('unsnoozed: back at once, and nothing said', () {
      Snoozed.instance.start(AppState());
      Snoozed.instance.snooze(Snoozed.text(1), now.add(const Duration(days: 1)));
      Snoozed.instance.unsnooze(Snoozed.text(1));
      expect(Snoozed.instance.hides(Snoozed.text(1)), isFalse);
      expect(Snoozed.instance.woken(Snoozed.text(1)), isFalse);
    });

    test('the times offered: an hour, three, this evening while it is before five, tomorrow at nine, Monday at nine', () {
      final sunday2pm = Snoozed.choices(DateTime(2026, 11, 22, 14, 0));
      expect(sunday2pm.map((c) => c.label), ['For an hour', 'For 3 hours', 'Until this evening (6 PM)', 'Until tomorrow (9 AM)', 'Until next week (Monday, 9 AM)']);
      expect(sunday2pm[2].at, DateTime(2026, 11, 22, 18));
      expect(sunday2pm[3].at, DateTime(2026, 11, 23, 9));
      expect(sunday2pm[4].at, DateTime(2026, 11, 23, 9), reason: 'Sunday: next Monday is tomorrow');
      final wednesdayEvening = Snoozed.choices(DateTime(2026, 11, 25, 19, 30));
      expect(wednesdayEvening.length, 4, reason: 'no "this evening" after five');
      expect(wednesdayEvening.last.at, DateTime(2026, 11, 30, 9));
    });
  });

  group('export', () {
    test('Markdown: a heading, a heading a day, each message with who and when, files and quotes, oldest first', () {
      final md = chatMarkdown('Maya Chen', [
        (at: DateTime(2026, 11, 22, 9, 5), who: 'You', text: 'Coffee?\nAt 10', files: const [], replyTo: null, edited: false),
        (at: DateTime(2026, 11, 21, 18, 0), who: 'Maya Chen', text: 'Here is the *plan*', files: const ['plan.pdf'], replyTo: null, edited: true),
        (at: DateTime(2026, 11, 22, 9, 6), who: 'Maya Chen', text: 'Yes!', files: const [], replyTo: 'Replying to You: Coffee?', edited: false),
      ], now: DateTime(2026, 11, 22, 20, 0));
      expect(md, startsWith('# Maya Chen\n\nExported from Ghost Messaging on 2026-11-22 at 20:00 · 3 messages\n'));
      expect(md.indexOf('## 2026-11-21'), lessThan(md.indexOf('## 2026-11-22')));
      expect(md, contains('**Maya Chen** 18:00 (edited)\nHere is the *plan*\n- 📎 plan.pdf'));
      expect(md, contains('**You** 09:05\nCoffee?  \nAt 10'));
      expect(md, contains('**Maya Chen** 09:06\n> Replying to You: Coffee?\nYes!'));
    });

    test('a file name a file system takes, with the day', () {
      expect(exportName('Maya: plans/ideas?', now: DateTime(2026, 11, 22)), 'Maya plans ideas 2026-11-22.md');
      expect(exportName('   ', now: DateTime(2026, 11, 22)), 'Conversation 2026-11-22.md');
    });
  });
}
