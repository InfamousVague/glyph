/// Replies: a tab of the conversations waiting on an answer to a question, replies to choose from over the composer,
/// and reminders to follow up (Matt, 2026-11-14, of the ideas to streamline someone's day: "Needs a reply", "Smart
/// replies", "Follow-up nudges", and "let's add all of the additional ones to a plugins, some can be grouped into the
/// same plugin").
///
/// - Needs a reply: an unread conversation whose newest text asks something ("are you free Saturday?", "let me
///   know") gets a tab of that name; it stays in Messages too, and leaves the tab once it is read or answered.
/// - Replies to choose from: over an empty composer, under a text that waits for an answer, three short replies that
///   fit it (a thank-you, a yes-or-no question, a plan, "where are you"); a press writes one in, to send or change.
/// - Follow up: a message's menu has Remind me, an hour from now, this evening or tomorrow morning; and after a text
///   of yours that promises something ("I'll send the photos tonight") the composer offers a reminder for when it
///   said. The reminder is a notification that opens the conversation.
///
/// All of it is worked out on the phone from the words alone.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import '../ui/common.dart';
import 'actions.dart' show whenIn, whenLabel;
import 'conversation.dart' show PluginThread;
import 'plugin.dart';

/// Whether [text] asks something of whoever reads it.
bool asksSomething(String text) {
  final s = text.trim().toLowerCase();
  if (s.isEmpty) return false;
  if (s.contains('?')) return true;
  return RegExp(r'^(?:are|is|can|could|will|would|do|does|did|have|has|should|shall|want|wanna|when|where|what|who|why|how)\b').hasMatch(s) ||
      RegExp(r'(?<![a-z])(?:let me know|lmk|get back to me|text me back|call me back|thoughts\b|rsvp)').hasMatch(s);
}

/// Three replies that fit [text], the shortest first.
List<String> repliesFor(String text) {
  final s = text.trim().toLowerCase();
  bool has(String pattern) => RegExp(pattern).hasMatch(s);
  if (has(r'(?<![a-z])(?:thanks|thank you|thx|ty|appreciate)(?![a-z])')) return const ['You\'re welcome!', 'Anytime 😊', 'No problem'];
  if (has(r'how (?:are|r) (?:you|u)|how\x27s it going|how have you been|what\x27s up|wyd')) return const ['Good, you?', 'Doing well!', 'Busy but good'];
  if (has(r'(?<![a-z])(?:where are you|where r u|eta|how long|how far|almost here|you close)(?![a-z])')) return const ['On my way', '5 minutes away', 'Running late, sorry!'];
  if (has(r'(?<![a-z])(?:call me|can you call|give me a call|ring me)(?![a-z])')) return const ['Calling now', 'Can\'t talk, text me?', 'Call you soon'];
  if (has(r'(?<![a-z])(?:love you|miss you|luv u|ily)(?![a-z])')) return const ['❤️', 'Love you too', 'Miss you too'];
  if (has(r'(?<![a-z])(?:happy birthday|congrats|congratulations)(?![a-z])')) return const ['Thank you! 🎉', 'Thanks so much!', '😊'];
  if (has(r'(?<![a-z])(?:sorry|my bad|apologi)')) return const ['No worries!', 'All good', 'It\'s okay'];
  if (asksSomething(text) && has(r'^(?:are|is|can|could|will|would|do|does|did|have|has|should|want|wanna)\b')) return const ['Yes', 'No', 'Let me check'];
  if (whenIn(text, DateTime.now()) != null && asksSomething(text)) return const ['Sounds good!', 'Works for me', 'Can we do later?'];
  if (asksSomething(text)) return const ['Let me check', 'Not sure', 'I\'ll get back to you'];
  if (whenIn(text, DateTime.now()) != null) return const ['Sounds good!', 'See you then', 'Perfect'];
  return const ['👍', 'Sounds good', 'Haha'];
}

/// When a text of the person's own promises something ("I'll send it tonight", "will call you tomorrow"), and the
/// time it said; null where it promises nothing.
({DateTime at, String label})? promiseIn(String text, DateTime now) {
  final s = text.toLowerCase();
  if (!RegExp(r"(?<![a-z])(?:i['’]ll|i will|will do|i can|let me|i['’]m going to|gonna)(?![a-z])|^(?:will|gonna) ").hasMatch(s.trim())) return null;
  if (!RegExp(r'(?<![a-z])(?:send|call|text|check|look|get back|email|bring|pay|book|ask|find|share|grab|pick up|drop off)').hasMatch(s)) return null;
  final when = whenIn(text, now);
  if (when != null && when.at.isAfter(now)) {
    final at = when.allDay ? DateTime(when.at.year, when.at.month, when.at.day, 9) : when.at.subtract(const Duration(minutes: 15));
    return (at: at.isAfter(now) ? at : when.at, label: whenLabel(when.at, when.allDay, now));
  }
  if (RegExp(r'(?<![a-z])(?:later|soon|in a bit|after work)(?![a-z])').hasMatch(s)) {
    final at = now.add(const Duration(hours: 3));
    return (at: at, label: 'Later');
  }
  return null;
}

/// The times a reminder can be for, from [now]: an hour from now, this evening at six (or tomorrow's, past five),
/// tomorrow morning at nine.
List<({String label, DateTime at})> remindTimes(DateTime now) {
  final evening = now.hour < 17 ? DateTime(now.year, now.month, now.day, 18) : DateTime(now.year, now.month, now.day + 1, 18);
  return [
    (label: 'In an hour', at: now.add(const Duration(hours: 1))),
    (label: now.hour < 17 ? 'This evening' : 'Tomorrow evening', at: evening),
    (label: 'Tomorrow morning', at: DateTime(now.year, now.month, now.day + 1, 9)),
  ];
}

class RepliesPlugin extends GhostPlugin {
  const RepliesPlugin({this.now});
  final DateTime Function()? now;

  static const section = 'reply';

  @override
  String get id => 'replies';

  @override
  String get name => 'Replies';

  @override
  String get description => 'A Needs a reply tab, replies to choose from over the composer, and reminders to follow up.';

  @override
  LucideIcon get icon => LucideMore.reply;

  DateTime _now() => (now ?? DateTime.now)();

  @override
  List<Classifier> get classifiers => [
        (facts) => !facts.group && facts.outgoing != true && asksSomething(facts.text) ? [const Tag('asks')] : const [],
      ];

  @override
  List<ListSection> get sections => [
        ListSection(
          id: section,
          label: 'Needs a reply',
          icon: LucideMore.reply,
          // It stays in Messages too: a tab to go through, not a place things are put away in.
          leavesMain: false,
          takes: (facts, tags, prefs) => prefs.flag('tab') && facts.unread && tags.has('asks') && (facts.contact || facts.senders.every((a) => a.replaceAll(RegExp(r'\D'), '').length >= 10)),
        ),
      ];

  static Future<void> _remind(PluginHost host, int thread, String who, String words, DateTime at, String when) async {
    final ok = await Sms.instance.remind(thread: thread, title: 'Follow up${who.isEmpty ? '' : ' with $who'}', body: words, at: at);
    host.say(ok ? 'I\'ll remind you ${when.toLowerCase()}' : 'Couldn\'t set the reminder');
  }

  @override
  List<SlotFill> get slots => [
        // Over the composer: replies to choose from, or a reminder after a promise.
        Slots.aboveComposer.fill((context, place, prefs) {
          if (place.text.isNotEmpty) return const [];
          final last = place.lastIn;
          if (last != null && prefs.flag('suggest') && last.trim().isNotEmpty) return [ReplyChips(replies: repliesFor(last))];
          final mine = place.lastOut;
          if (mine != null && prefs.flag('nudge') && !Sms.remote) {
            final promise = promiseIn(mine, _now());
            if (promise != null) return [_PromiseChip(thread: place.thread, who: place.title, words: mine, at: promise.at, label: promise.label)];
          }
          return const [];
        }),
        // A message's menu: Remind me.
        Slots.messageMenu.fill((place, prefs) => Sms.remote || !prefs.flag('nudge')
            ? const []
            : [
                for (final t in remindTimes(_now()))
                  PluginAction(
                    label: 'Remind me ${t.label.toLowerCase()}',
                    icon: Lucide.bell,
                    run: (host) => _remind(host, place.facts.thread, '', place.facts.text, t.at, t.label),
                  ),
              ]),
      ];

  @override
  PluginSettingsPage? get settingsPage => PluginSettingsPage(
        hue: 'blue',
        intro: 'Keeping up with the people waiting on you.',
        summary: (prefs) => [if (prefs.flag('tab')) 'Needs a reply', if (prefs.flag('suggest')) 'Suggestions', if (prefs.flag('nudge')) 'Reminders'].join(' · '),
      );

  @override
  List<PluginSetting> get settings => const [
        PluginSetting.toggle(key: 'tab', label: 'Needs a reply tab', hint: 'Unread conversations whose newest text asks you something.', icon: LucideMore.reply),
        PluginSetting.toggle(key: 'suggest', label: 'Replies to choose from', hint: 'Three short replies over the composer, under a text that waits for an answer.', icon: Lucide.messageSquare),
        PluginSetting.toggle(key: 'nudge', label: 'Reminders to follow up', hint: 'Remind me in a message\'s menu, and an offer after a text of yours that promises something.', icon: Lucide.bell),
        PluginSetting.note(label: 'On this phone only', hint: 'Worked out from the words, on the phone. Nothing is sent anywhere.', icon: Lucide.lock),
      ];
}

/// Replies to choose from: a press writes one into the composer.
class ReplyChips extends StatelessWidget {
  const ReplyChips({super.key, required this.replies});
  final List<String> replies;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final thread = PluginThread.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final r in replies) ...[
            GlacierPressable(
              onPressed: thread == null ? null : () => thread.write(r),
              semanticLabel: 'Reply: $r',
              builder: (context, state) => Container(
                padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1) + 3),
                decoration: BoxDecoration(
                  color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'),
                  borderRadius: BorderRadius.circular(t.radius('full')),
                  border: Border.all(color: t.color('app-rule')),
                ),
                child: Text(r, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink'))),
              ),
            ),
            SizedBox(width: t.space(2)),
          ],
        ]),
      ),
    );
  }
}

/// After a text of the person's that promises something: a reminder for when it said.
class _PromiseChip extends StatelessWidget {
  const _PromiseChip({required this.thread, required this.who, required this.words, required this.at, required this.label});
  final int thread;
  final String who;
  final String words;
  final DateTime at;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GlacierPressable(
          onPressed: () async {
            final ok = await Sms.instance.remind(thread: thread, title: 'Follow up${who.isEmpty ? '' : ' with $who'}', body: words, at: at);
            if (context.mounted) toast(context, ok ? 'I\'ll remind you' : 'Couldn\'t set the reminder');
          },
          builder: (context, state) => Container(
            padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1) + 3),
            decoration: BoxDecoration(
              color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'),
              borderRadius: BorderRadius.circular(t.radius('full')),
              border: Border.all(color: t.color('app-rule')),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(Lucide.bell, size: 14, strokeWidth: 2.2, wash: false, color: t.color('app-ink-2')),
              SizedBox(width: t.space(1) + 2),
              Text('You promised something · remind me ${label == 'Later' ? 'later' : label}', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink'))),
            ]),
          ),
        ),
      ),
    );
  }
}
