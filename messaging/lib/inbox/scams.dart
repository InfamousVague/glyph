import 'inbox.dart';

/// Spam and scams in chats on Telegram and the other networks (Matt, 2026-11-15: "i also want spam filters on them to
/// work and cut out fake romance scams and other telegram scams").
///
/// A chat is taken out of the list, into Spam, when:
///
/// - the network itself marks the account a scam or a fake (Telegram's own labels, `verification_status`); or
/// - someone who is not a contact wrote first (Telegram shows its "Report spam" bar for such a chat) and the newest
///   message shows a sign of one of [scamSigns]: the romance opener ("hello dear", "sorry, wrong number"), the
///   "investment" pitch (crypto, forex, trading mentors), the fake Telegram support or giveaway, the money ask (gift
///   cards, sugar daddies, loans), or the too-good job.
///
/// A contact's chat, or a group, is never taken out; "Not spam" puts a chat back for good. Everything is looked at on
/// the device; nothing is reported, blocked or deleted.
class ScamSign {
  const ScamSign(this.id, this.says, this.pattern);
  final String id;

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

/// Why [chat] looks like spam or a scam, in words for its row; null where it does not.
String? scamOf(InboxChat chat) {
  if (chat.group || chat.lastFromMe && chat.flag == null) return null;
  final flag = chat.flag;
  if (flag != null) return flag;
  if (!chat.stranger) return null;
  final signs = [for (final s in scamSigns) if (s.matches(chat.snippet)) s.says];
  return signs.isEmpty ? null : 'Looks like a scam: ${signs.join(', ')}';
}
