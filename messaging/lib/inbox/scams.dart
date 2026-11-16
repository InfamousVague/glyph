import 'inbox.dart';

/// Spam and scams in chats on Telegram and the other networks (Matt, 2026-11-15: "i also want spam filters on them to
/// work and cut out fake romance scams and other telegram scams").
///
/// A chat is taken out of the list, into Spam, when:
///
/// - the network itself marks the account a scam or a fake (Telegram's own labels, `verification_status`); or
/// - an account names itself Telegram without being Telegram's own; or
/// - someone who is not a contact wrote first (Telegram shows its "Report spam" bar for such a chat) and the newest
///   message shows a sign of one of [scamSigns]: the come-on and the flirty emoji, the romance opener ("hello dear",
///   "sorry, wrong number"), the
///   "investment" pitch (crypto, forex, trading mentors), the fake Telegram support or giveaway, the money ask (gift
///   cards, sugar daddies, loans), or the too-good job.
///
/// A contact's chat, or a group, is never taken out; "Not spam" puts a chat back for good. Everything is looked at on
/// the device; nothing is reported, blocked or deleted.
class ScamSign {
  const ScamSign(this.id, this.says, this.pattern, {this.coldOnly = false});
  final String id;

  /// A sign that counts only where a stranger wrote and was never answered ([InboxChat.cold]): a friend not saved as a
  /// contact may send a 😍.
  final bool coldOnly;

  /// How the row in Spam says it, after "Looks like a scam:".
  final String says;
  final String pattern;

  bool matches(String text) => (_compiled[pattern] ??= RegExp(pattern, caseSensitive: false)).hasMatch(text);
  static final _compiled = <String, RegExp>{};
}

const _b = r'(?<![a-z0-9])';
const _e = r'(?![a-z0-9])';

const List<ScamSign> scamSigns = [
  ScamSign(
    'romance',
    'a romance opener',
    '$_b(?:(?:hello|hi|hey|good (?:morning|evening))[ ,]+(?:my )?(?:dear|darling|handsome|beautiful|sweetheart)|how are you (?:my )?dear|nice to meet you dear|are you single|'
        'looking for (?:a )?(?:serious |long[- ]term )?(?:relationship|partner)|sorry,? (?:wrong (?:number|person)|i (?:added|messaged) the wrong)|'
        'my (?:friend|cousin) gave me your (?:number|contact)|i saw your profile|can we be friends)$_e',
  ),
  // The cold come-on that gets past Telegram's own filter: one message from a stranger, romantic or sexual, often with a
  // flirty emoji (Matt, 2026-11-15, three of them: "I want to see your face. Are you free? I have a surprise.", "Hiya! ✨
  // What a pleasant 😍 surprise!", "Want to meet someone close to you?").
  ScamSign(
    'flirt',
    'a come-on from a stranger',
    '$_b(?:see your face|are you free(?: tonight| now)?|i have a surprise|(?:what a )?pleasant surprise|meet (?:someone|a girl|girls|women|singles) (?:close|near) (?:to )?you|'
        'someone (?:close|near) (?:to )?you|want to (?:see|meet|chat with|talk to) you|hiya|hey (?:cutie|handsome|sexy|babe|baby|stranger)|cutie|sexy|naughty|horny|kisses|'
        'hot (?:pics|photos|girls|singles)|send (?:me )?(?:a |your )?(?:pic|photo|selfie)s?|come over|bored (?:tonight|at home|and alone)|hook ?up|nudes?|lonely tonight|'
        'looking for (?:fun|a friend|company)|can i (?:get to )?know you)$_e',
    coldOnly: true,
  ),
  ScamSign('flirt-emoji', 'a flirty emoji', '(?:😍|😘|🥰|💋|🫦|🍑|🍒|🍆|💦|😈|😏|💕|💖|💗|💓|❤️‍🔥|🌹|😻|🫕)', coldOnly: true),
  ScamSign(
    'invest',
    'an investment pitch',
    '$_b(?:invest(?:ment|ing)?|usdt|bitcoin|btc|ethereum|crypto(?:currency)?|forex|trading (?:signals?|mentor|platform|account)|guaranteed (?:profit|returns?)|'
        'daily (?:profit|returns?)|airdrop|mining pool|liquidity pool|withdraw(?:al)?|double your)$_e',
  ),
  ScamSign(
    'support',
    'a fake support or giveaway message',
    '$_b(?:telegram (?:support|team|security|administration)|your account (?:will be|has been|is) (?:banned|deleted|suspended|restricted|locked)|'
        'verify your (?:account|identity)|premium (?:gift|giveaway)|claim your (?:prize|gift|reward)|you(?:\'ve| have) won)$_e',
  ),
  ScamSign(
    'money',
    'a money ask',
    '$_b(?:gift ?cards?|steam card|cash ?app|paypal flip|western union|moneygram|send me (?:money|\\\$)|loan offer|instant loan|sugar (?:daddy|mommy|baby)|weekly allowance)$_e',
  ),
  ScamSign(
    'job',
    'a too-good job',
    '$_b(?:work from home|earn \\\$?\\d+[k]? (?:a|per) (?:day|hour|week)|part[- ]time (?:job|work) (?:offer|available)|remote job offer|no experience (?:needed|required)|easy money)$_e',
  ),
];

/// A private chat whose name is Telegram's own, which only Telegram's real account (777000, [InboxChat.service]) may
/// have: two of Matt's three came from accounts calling themselves "Telegram".
final _pretends = RegExp(r'^\W*(?:telegram|telegram (?:support|team|security|premium|notifications?|official)|support team|security team)\W*$', caseSensitive: false);

/// Why [chat] looks like spam or a scam, in words for its row; null where it does not.
String? scamOf(InboxChat chat) {
  if (chat.group || chat.lastFromMe && chat.flag == null) return null;
  final flag = chat.flag;
  if (flag != null) return flag;
  if (!chat.service && chat.network == 'telegram' && _pretends.hasMatch(chat.title)) return 'Pretends to be Telegram';
  if (!chat.stranger) return null;
  final signs = [for (final s in scamSigns) if ((!s.coldOnly || chat.cold) && s.matches(chat.snippet)) s.says];
  return signs.isEmpty ? null : 'Looks like a scam: ${signs.join(', ')}';
}
