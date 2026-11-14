/// Spam filter: texts that look like spam, from numbers that are not contacts, in a section of their own (Matt,
/// 2026-11-14: "filtering out spam messages").
///
/// Off until it is chosen in Settings › Plugins: a filter that takes messages out of the list should be asked for.
/// The rules are few and can be said in a line each ([spamRules]): a text shows a sign or it does not, and a
/// conversation is spam when its newest text shows two of them, or three where it also holds a sign-in code, and
/// nobody in it is a contact. Everything is looked at on the phone; nothing is sent anywhere, deleted or blocked.
/// The conversation's row in Spam says which signs it showed, and "Not spam" puts it back in the main list, where
/// it stays whatever later texts in it say. A conversation the rules missed can be moved to Spam from its long
/// press.
///
/// The rules are a list of plain values, a pattern for the words or for the sender's address, so another list can
/// stand in for them (`SpamPlugin(rules: …)`), from this app or one day from outside it.
library;

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import 'codes.dart';
import 'plugin.dart';
import 'ui.dart';

/// One sign that a text may be spam.
class SpamRule {
  const SpamRule({required this.id, required this.name, required this.says, required this.about, this.words, this.sender}) : assert(words != null || sender != null);

  final String id;

  /// What Settings calls it: "A link".
  final String name;

  /// How the row in Spam says it, after "Looks like spam:": "a link".
  final String says;

  /// What Settings says of it, in a line.
  final String about;

  /// A pattern for the text's words, letters in either case; or
  final String? words;

  /// a pattern for the address it came from.
  final String? sender;

  bool matches(MessageFacts facts) {
    final words = this.words;
    final sender = this.sender;
    if (words != null && _pattern(words).hasMatch(facts.text)) return true;
    return sender != null && facts.senders.any(_pattern(sender).hasMatch);
  }

  static final _patterns = <String, RegExp>{};
  static RegExp _pattern(String source) => _patterns[source] ??= RegExp(source, caseSensitive: false);
}

/// The signs, as the app ships them. Each phrase is a word or words of its own, never part of a longer word
/// ("locked" is not in "unlocked"), and no phrase is in two rules, so one fact about a text is one sign.
const List<SpamRule> spamRules = [
  SpamRule(
    id: 'link',
    name: 'A link',
    says: 'a link',
    about: 'The text has a web address in it.',
    words: r'(?:https?://|www\.)[^\s]+|(?<![@\w.-])[a-z0-9-]{2,}\.(?:com|net|org|info|biz|xyz|top|click|link|online|site|shop|store|vip|icu|buzz|club|win|live|ly|cc|co|io|me|app)(?:/[^\s]*)?(?![\w-]|\.[a-z])',
  ),
  SpamRule(
    id: 'email',
    name: 'Sent from an email address',
    says: 'sent from an email address',
    about: 'It came from an email address, not a phone number.',
    sender: r'@',
  ),
  SpamRule(
    id: 'prize',
    name: 'Prize wording',
    says: 'prize wording',
    about: 'It says you have won or been selected, or have a prize or a gift card to claim.',
    words: r"(?<![a-z0-9])(?:you(?:['’]ve| have)? won|winner|prize|lottery|jackpot|gift ?cards?|free gift|congratulations|been selected|claim (?:your|now|it|here))(?![a-z0-9])",
  ),
  SpamRule(
    id: 'pressure',
    name: 'Pressure to act',
    says: 'pressure to act',
    about: 'It says something is urgent, suspended, locked, unpaid or about to expire, or asks you to verify or confirm an account.',
    words: r'(?<![a-z0-9])(?:urgent|urgently|immediately|act now|final notice|last chance|expires? (?:today|tonight|soon)|within \d+ ?(?:hours|hrs|hour|h)|suspended|suspension|locked|restricted|deactivated|unusual activity|suspicious activity|(?:verify|confirm|update) your (?:account|identity|information|details|payment|billing)|unpaid|overdue|outstanding balance|late fees?|pay now)(?![a-z0-9])',
  ),
  SpamRule(
    id: 'money',
    name: 'A money offer',
    says: 'a money offer',
    about: 'It offers a loan, an investment, easy earnings or a refund that is waiting.',
    words: r'(?<![a-z0-9])(?:loans?|pre-?approved|debt relief|crypto|bitcoin|investments?|investing|earn \$?\d[\d,]*|\$\d[\d,]* (?:a|per|each|every) (?:day|week)|work from home|cash prize|refund (?:is |of \S+ is )?(?:pending|waiting|available|ready)|tax refund)(?![a-z0-9])',
  ),
  SpamRule(
    id: 'delivery',
    name: 'A delivery problem',
    says: 'a delivery problem',
    about: 'It says a package could not be delivered, is held, or needs an address or a fee.',
    words: r"(?<![a-z0-9])(?:(?:package|parcel|shipment|delivery)(?![a-z0-9]).{0,60}(?<![a-z0-9])(?:undeliverable|failed|on hold|held|rescheduled?|incomplete|incorrect|customs fees?|redelivery)|(?:could ?n[o'’]t|can ?not|can['’]t|unable to|failed to) (?:be )?deliver(?:ed)?)(?![a-z0-9])",
  ),
];

/// What the rules make of one text: the signs it shows, and whether that is enough.
class SpamVerdict {
  const SpamVerdict(this.signs, this.needed);

  /// The rules it matched, in the order they are listed.
  final List<SpamRule> signs;

  /// How many it takes: two, or three for a text with a sign-in code in it.
  final int needed;

  bool get spam => signs.length >= needed;

  /// The signs in words: "a link, prize wording".
  String get why => signs.map((s) => s.says).join(', ');
}

/// Asks [rules] about a text. Who sent it is not asked here: a contact's text is never looked at ([SpamPlugin]).
SpamVerdict judgeSpam(MessageFacts facts, {List<SpamRule> rules = spamRules}) {
  final signs = [for (final rule in rules) if (rule.matches(facts)) rule];
  // A sign-in code often comes with a link and "if this wasn't you, act immediately": it takes one sign more.
  return SpamVerdict(signs, signInCode(facts.text) == null ? 2 : 3);
}

class SpamPlugin extends GhostPlugin {
  const SpamPlugin({this.rules = spamRules});

  /// The signs it looks for. Another list stands in for the app's own.
  final List<SpamRule> rules;

  /// The tag a text that looks like spam is given; its detail is the signs it showed.
  static const tag = 'spam';

  /// The section's id.
  static const section = 'spam';

  @override
  String get id => 'spam';

  @override
  String get name => 'Spam filter';

  @override
  String get description => 'Texts that look like spam, from numbers not in your contacts, go to a Spam section.';

  @override
  LucideIcon get icon => Lucide.triangleAlert;

  /// It hides messages: it is chosen, not given.
  @override
  bool get onByDefault => false;

  static PluginAction _notSpam(int thread) => PluginAction(
        label: 'Not spam',
        icon: Lucide.check,
        run: (host) {
          host.move(thread, null);
          host.say('Moved to Messages');
        },
      );

  @override
  List<Classifier> get classifiers => [
        (facts) {
          // Never a contact's, and never the person's own words.
          if (facts.contact || facts.outgoing == true) return const [];
          final verdict = judgeSpam(facts, rules: rules);
          return verdict.spam ? [Tag(tag, verdict.why)] : const [];
        },
      ];

  @override
  List<ListSection> get sections => [
        ListSection(
          id: section,
          label: 'Spam',
          icon: Lucide.triangleAlert,
          takes: (facts, tags, prefs) => tags.has(tag),
          row: (facts, tags, prefs) {
            final why = tags.detail(tag);
            return RowLook(caption: why == null ? 'Moved here by you' : 'Looks like spam: $why', word: _notSpam(facts.thread));
          },
        ),
      ];

  @override
  List<SlotFill> get slots => [
        // Over the Spam list: what it is, and that nothing is lost.
        Slots.aboveList.fill((context, place, prefs) => [
              if (place.section == section) const PluginNote('Texts that look like spam, from numbers not in your contacts. Nothing here is deleted or blocked.'),
            ]),
        // A conversation's long press in the list: out of Spam for good, or into it by hand.
        Slots.conversationMenu.fill((place, prefs) {
          final thread = place.facts.thread;
          return [
            if (place.section == section)
              _notSpam(thread)
            else if (!place.facts.contact)
              PluginAction(
                label: 'Move to Spam',
                icon: Lucide.triangleAlert,
                run: (host) {
                  host.move(thread, section);
                  host.say('Moved to Spam');
                },
              ),
          ];
        }),
      ];

  /// A conversation in Spam is muted as its newest text is seen, so what comes in it next arrives quietly.
  @override
  List<IncomingRule> get incoming => [
        (facts, tags, at, prefs) => [if (at == section && prefs.flag('mute')) const MuteNotification()],
      ];

  /// A section of its own in Settings, while the filter is on.
  @override
  PluginSettingsPage? get settingsPage => PluginSettingsPage(
        hue: 'red',
        intro: 'What looks like spam, from numbers that are not in your contacts, in a tab of its own.',
        summary: (prefs) => prefs.flag('mute') ? 'Spam is muted' : 'Spam still notifies',
      );

  @override
  List<PluginSetting> get settings => [
        const PluginSetting.toggle(
          key: 'mute',
          label: 'Mute conversations in Spam',
          hint: 'Later texts in a conversation that is in Spam arrive without a notification. "Not spam" turns them back on.',
          icon: Lucide.bell,
        ),
        const PluginSetting.note(
          label: 'What counts as spam',
          hint: 'A text from a number that is not in your contacts that shows two of the signs below. One with a sign-in code in it needs three.',
          icon: Lucide.info,
        ),
        for (final rule in rules) PluginSetting.note(label: rule.name, hint: rule.about),
        const PluginSetting.note(
          label: 'On this phone only',
          hint: 'Texts are looked at here and sent nowhere. Nothing is deleted or blocked: a conversation in Spam opens as any other, and "Not spam" puts it back for good.',
          icon: Lucide.lock,
        ),
      ];
}
