/// Kinds of text: what a text from someone who is not a contact is about, sorted on the phone so the list can show
/// or hide each kind (Matt, 2026-11-14: "I'd like to have tabs for messages with a intelligent spam filter, debt
/// collectors, political messages, payment reminders, tracking information, etc ... I'm thinking a filter dropdown
/// where showing spam, political messages, and debt collectors are filtered out by default", and "also add in
/// blocking of door to door sales and other sales messages like tree trimming, gutter cleaning, buying the house,
/// etc").
///
/// Each kind is a section of the list that is a filter, not a tab ([ListSection.filter]): its conversations stay in
/// Messages while it is shown, and leave it while it is hidden; the filter menu beside the tabs says which, and can
/// show one kind alone. Political texts, debt collectors and sales are hidden until shown; payment reminders,
/// deliveries and appointments are shown. Spam is the Spam filter's (spam.dart), a kind like these.
///
/// A kind is a few patterns for a text's words, said in a line each in Settings. A text is of a kind when it shows
/// one of its strong signs, or two of its others. Nobody in your contacts is ever sorted, nor your own words; a
/// kind that is shown (a delivery, a reminder) does not take a text the Spam filter would call spam, so a fake
/// "your parcel is held, pay the fee" goes to Spam. Nothing is sent anywhere, deleted or blocked: a hidden kind is
/// one press away ("N hidden" at the list's foot), and "Not political" on a conversation puts it back in Messages
/// for good.
library;

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import 'plugin.dart';
import 'spam.dart';

/// One kind of text.
class TextKind {
  const TextKind({
    required this.id,
    required this.label,
    required this.one,
    required this.icon,
    required this.about,
    required this.strong,
    this.weak = const [],
    this.hidden = false,
    this.notSpam = false,
  });

  /// Its section's id.
  final String id;

  /// What the filter menu and its tab say: "Political".
  final String label;

  /// One conversation of it, for "Not …": "political".
  final String one;
  final LucideIcon icon;

  /// What Settings says of it.
  final String about;

  /// Patterns any one of which makes a text this kind.
  final List<String> strong;

  /// Patterns two of which make a text this kind.
  final List<String> weak;

  /// Hidden from Messages until the person shows it.
  final bool hidden;

  /// A text the Spam filter would call spam is not this kind: it is shown, so a scam dressed as it must not be.
  final bool notSpam;

  static final _patterns = <String, RegExp>{};
  static RegExp _re(String source) => _patterns[source] ??= RegExp(r'(?<![a-z0-9])(?:' + source + r')(?![a-z0-9])', caseSensitive: false);

  bool matches(String text) {
    for (final s in strong) {
      if (_re(s).hasMatch(text)) return true;
    }
    var n = 0;
    for (final w in weak) {
      if (_re(w).hasMatch(text) && ++n >= 2) return true;
    }
    return false;
  }
}

/// The kinds, in the order a text is asked about them: the first that takes it has it.
const List<TextKind> textKinds = [
  TextKind(
    id: 'debt',
    label: 'Debt collectors',
    one: 'a debt collector',
    icon: LucideMore.circleDollarSign,
    hidden: true,
    // A toll or DMV "final notice" with a link to pay is a scam: Spam's, not a collector's.
    notSpam: true,
    about: 'Collection agencies: an attempt to collect a debt, an account in collections, settling a balance.',
    strong: [
      r'(?:attempt|trying) to collect a debt',
      r'debt collector',
      r'collections? (?:agency|department|account|notice)',
      r'(?:placed|referred|sent|assigned) (?:in|into|to|for) collections?',
      r'settle (?:your|this|the) (?:debt|balance|account)',
      r'(?:resolve|settle) (?:your|this) (?:outstanding )?(?:debt|balance)',
      r'reported to (?:the )?credit bureaus?',
    ],
    weak: [r'past due', r'delinquent', r'outstanding balance', r'collections?', r'creditor', r'settlement offer', r'credit (?:report|score|bureau)'],
  ),
  TextKind(
    id: 'political',
    label: 'Political',
    one: 'political',
    icon: LucideMore.landmark,
    hidden: true,
    about: 'Campaigns, candidates and causes: a vote, a ballot, a donation, "paid for by".',
    strong: [
      r'paid for by',
      r'election day',
      r'(?:mail-?in|absentee|your) ballots?',
      r'polls? (?:open|close|are open|location)',
      r'chip in',
      // Ways to vote, not voting on where to eat.
      r'(?:vote|voting) (?:early|yes on|no on|by mail|in person)',
      r'(?:register(?:ed)?|make a plan) to vote',
      r'(?:democrats?|republicans?|gop|dnc|rnc|maga)',
      r'(?:presidential|senate|congressional|gubernatorial|midterm|primary) (?:race|election|campaign)',
      // "Surveys" and "polls" on issues, which are campaigns' (seen on Matt's phone, 2026-11-14).
      r'(?:local|important|community) issues?',
      r'issues? (?:survey|poll)',
      r'research-?polls?',
      r'gauging (?:views|opinions)',
      r'campaign updates',
      r'residents (?:across|of) (?:our|the|your)',
    ],
    weak: [r'vote', r'election', r'campaign', r'candidates?', r'donat(?:e|ion|ions)', r'congress(?:man|woman)?', r'senators?', r'governor', r'president', r'petition', r'rally', r'endorse'],
  ),
  TextKind(
    id: 'sales',
    label: 'Sales & solicitors',
    one: 'sales',
    icon: Lucide.megaphone,
    hidden: true,
    about: 'Door-to-door and other selling: tree trimming, gutters, roofs, solar, "we buy houses", offers and promo codes.',
    strong: [
      r"(?:we(?:'| a)re|we have a crew|our crew is|we will be) (?:working |out )?in your (?:area|neighbou?rhood)",
      r'tree (?:trimmings?|removals?|services?|cutting|work|projects?|care)',
      r'(?:local )?arborists?',
      r'gutters? (?:cleaning|guards?|replacement|install)',
      r'(?:buy|purchase) your (?:house|home|property|land)',
      r'(?:cash|an offer|a cash offer) (?:for|on) your (?:house|home|property|land)',
      r'(?:interested in|thought about|considering) selling (?:your )?(?:house|home|property|land)?',
      r'we buy (?:houses|homes|property)',
      r'roof(?:ing)? (?:inspections?|replacement|repairs?|estimates?)',
      r'no-?cost (?:roof |home )?(?:inspections?|estimates?|quotes?)',
      r'(?:kitchen|bathroom|shower|home) (?:& |and )?(?:bathroom )?remodels?',
      r'(?:health |life |auto |car |home )?insurance (?:quotes?|plans?)',
      r'(?:want|like|need|interested in) (?:a |some )?(?:free )?quotes?',
      r'(?:send|get) you (?:a few |some |a )?(?:free )?quotes?',
      r'pre-?approved (?:for )?\$?\d',
      r'(?:tickets are )?selling fast',
      r'eligible to add',
      r'solar (?:panels?|savings|consultation|program)',
      r'(?:pressure|power) washing',
      r'(?:lawn|landscaping|yard) (?:care|service|services|maintenance)',
      r'pest control',
      r'window (?:cleaning|replacement)',
      r'driveway (?:sealing|paving|repair)',
      r'free (?:estimate|estimates|quote|quotes|inspection|consultation)',
      r'promo code',
      r'(?:sale|offer) ends',
      r'\d+% off',
      r'shop now',
    ],
    // "Reply STOP to opt out" is one sign however many of its words a text has.
    weak: [r'neighbou?rhood', r'your (?:home|house|property)', r'special offer', r'limited time', r'discounts?', r'deals?', r'(?:reply|text|txt) stop|stop to (?:end|opt|quit|cancel|unsubscribe)|unsubscribe|opt[ -]out', r'book (?:now|today)', r'\$\d+(?:\.\d\d)?/mo', r'quotes?'],
  ),
  TextKind(
    id: 'reminders',
    label: 'Payment reminders',
    one: 'a payment reminder',
    icon: LucideMore.receipt,
    notSpam: true,
    about: 'Bills and payments: an amount due, a due date, autopay, a statement that is ready.',
    strong: [
      r'payment (?:is )?(?:due|reminder|scheduled|received|confirmation)',
      r'(?:amount|balance|minimum payment) due',
      r'due (?:on|by) (?:\d|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|mon|tue|wed|thu|fri|sat|sun|today|tomorrow)',
      r'autopay',
      r'(?:your )?(?:bill|statement) is (?:ready|available|due)',
      r'(?:rent|premium|invoice|bill) (?:is )?due',
      r'(?:past[- ]due|unpaid) (?:bill|balance|payment|amount)',
      r'(?:issues?|problems?|trouble) collecting (?:your )?payment',
      r'(?:scheduled for |service )interruption',
    ],
    weak: [r'bill', r'statement', r'payment', r'past due', r'balance', r'account ending', r'pay (?:now|online|here)'],
  ),
  TextKind(
    id: 'deliveries',
    label: 'Deliveries & tracking',
    one: 'a delivery',
    icon: LucideMore.package,
    notSpam: true,
    about: 'Orders and parcels: shipped, out for delivery, delivered, a tracking number.',
    strong: [
      r'out for delivery',
      r'(?:has been|was|is|were|should be) delivered',
      r'delivered today',
      r'(?:order|package|parcel|delivery) (?:was|has been) (?:dropped off|left)',
      r'(?:has |have )?(?:shipped|been shipped)',
      r'tracking (?:number|#|no\.?|id|info|information|link|update)',
      r'track your (?:package|order|shipment|parcel|delivery)',
      r'(?:package|parcel|order|shipment) (?:is )?(?:on its way|arriving|arrives|will arrive|delayed)',
      r'arriving (?:today|tomorrow|by)',
      r'expected (?:delivery|arrival)',
    ],
    // A carrier's name alone is not a delivery: their sign-in codes and alerts are not.
    weak: [r'order', r'package', r'parcel', r'shipment', r'delivery', r'arriv(?:e|ing|al)', r'ups|fedex|usps|dhl|amazon|ontrac|lasership|dasher'],
  ),
  TextKind(
    id: 'appointments',
    label: 'Appointments',
    one: 'an appointment',
    icon: LucideMore.calendarCheck,
    notSpam: true,
    about: 'Bookings and reminders: an appointment, a reservation, "reply C to confirm".',
    strong: [
      r'appointments? (?:reminder|confirmed|confirmation|is (?:on|at|scheduled|tomorrow|today)|on|at|for|with)',
      r'reply (?:c|y|yes|1) to confirm',
      r'(?:your )?(?:reservation|booking) (?:is )?(?:confirmed|for|on|at|reminder)',
      r'(?:check-?in|check in) (?:is )?(?:at|opens|now open)',
      r'reminder: you have',
      r'(?:your )?appt\.?',
      r'(?:service professional|technician|tech) .{0,40}(?:is )?on (?:the|their|his|her) way',
    ],
    weak: [r'appointment', r'reservation', r'booking', r'reschedule', r'clinic', r'dentist', r'doctor', r'scheduled for'],
  ),
];

class KindsPlugin extends GhostPlugin {
  const KindsPlugin({this.kinds = textKinds, this.spam = spamRules});

  final List<TextKind> kinds;

  /// What a shown kind asks before taking a text: whether the Spam filter would call it spam.
  final List<SpamRule> spam;

  /// The tag a text of a kind is given: `kind`, its detail the kind's id.
  static const tag = 'kind';

  @override
  String get id => 'kinds';

  @override
  String get name => 'Kinds of text';

  @override
  String get description => 'Texts from numbers not in your contacts are sorted by what they are about, for the filter beside the tabs.';

  @override
  LucideIcon get icon => Lucide.listFilter;

  @override
  List<Classifier> get classifiers => [
        (facts) {
          if (facts.contact || facts.outgoing == true || facts.text.trim().isEmpty) return const [];
          bool? looksSpam;
          for (final k in kinds) {
            if (!k.matches(facts.text)) continue;
            if (k.notSpam && (looksSpam ??= judgeSpam(facts, rules: spam).spam)) continue;
            return [Tag(tag, k.id)];
          }
          return const [];
        },
      ];

  static PluginAction _not(TextKind k, int thread) => PluginAction(
        label: 'Not ${k.one}',
        icon: Lucide.check,
        run: (host) {
          host.move(thread, null);
          host.say('Moved to Messages');
        },
      );

  @override
  List<ListSection> get sections => [
        for (final k in kinds)
          ListSection(
            id: k.id,
            label: k.label,
            icon: k.icon,
            filter: true,
            hidden: k.hidden,
            takes: (facts, tags, prefs) => tags.detail(tag) == k.id,
            row: (facts, tags, prefs) => RowLook(caption: tags.detail(tag) == k.id ? k.label : 'Moved here by you', word: _not(k, facts.thread)),
          ),
      ];

  @override
  List<SlotFill> get slots => [
        // A conversation's long press: out of its kind for good.
        Slots.conversationMenu.fill((place, prefs) => [
              for (final k in kinds)
                if (place.section == k.id) _not(k, place.facts.thread),
            ]),
      ];

  @override
  PluginSettingsPage? get settingsPage => PluginSettingsPage(
        hue: 'slate',
        intro: 'Texts from numbers that are not in your contacts, sorted by what they are about. The filter beside the tabs shows or hides each kind.',
        summary: (prefs) => '${kinds.length} kinds',
      );

  @override
  List<PluginSetting> get settings => [
        for (final k in kinds) PluginSetting.note(label: k.label, hint: '${k.about}${k.hidden ? ' Hidden from Messages until you show it.' : ''}', icon: k.icon),
        const PluginSetting.note(
          label: 'On this phone only',
          hint: 'Texts are looked at here and sent nowhere. Nothing is deleted or blocked, and your contacts are never sorted. "Not …" on a conversation puts it back in Messages for good.',
          icon: Lucide.lock,
        ),
      ];
}
