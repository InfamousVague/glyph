/// A mail-to-note address of one's own name, `matt@in.ghostmarkdown.com` (Matt, 2026-10-24: "i'd like you to add the
/// ability to create our own custom name for the email if the name is available like matt@in.ghostmarkdown.com";
/// docs/MAIL.md, server/src/mail/names.rs `chosen`).
///
/// The rules are the service's, checked here first so the field can say what is wrong with a name as it is typed,
/// without asking: 3 to 30 of a to z, 0 to 9 and single dots, dashes or underscores between them, lower-cased, nothing
/// reserved, and nothing shaped like a name the service makes. Only a name that passes is asked about
/// ([MailIn.checkName]), since only the service knows whether anyone has or had it; the service checks all of it
/// again, and its words for a refusal are the ones here, so an app and a service a version apart say the same.
library;

/// Why a name may not be anyone's, as the service says it (`reason`).
enum MailNameUnfit {
  characters('Only letters, numbers, dots, dashes and underscores'),
  short('At least 3 characters'),
  long('At most 30 characters'),
  separators('A dot, dash or underscore goes between letters or numbers, one at a time'),
  generated('That looks like a name Ghost.md makes up. Choose one of your own'),
  reserved('That name is reserved');

  const MailNameUnfit(this.words);

  /// What the field says, without a full stop: it stands alone under the field, as "Available" does.
  final String words;

  static MailNameUnfit? byCode(Object? code) => code is String ? values.where((v) => v.name == code).firstOrNull : null;
}

/// The longest a name may be, for the field's own limit.
const int mailNameMost = 30;

/// Names nobody is given (names.rs `RESERVED`), compared with their separators taken out.
const Set<String> mailNamesReserved = {
  'abuse', 'account', 'accounts', 'admin', 'administrator', 'alerts', 'all', 'api', 'app', 'billing', 'bot', 'bounce',
  'bounces', 'calendar', 'contact', 'daemon', 'dkim', 'dmarc', 'email', 'everyone', 'ftp', 'ghost', 'ghostbot', 'ghostmd',
  'ghostmarkdown', 'glyph', 'hello', 'help', 'hostmaster', 'imap', 'info', 'invite', 'invites', 'legal', 'list',
  'listserv', 'mail', 'mailer', 'mailerdaemon', 'mailgun', 'majordomo', 'meet', 'meeting', 'meetings', 'mx', 'news',
  'nobody', 'noreply', 'notifications', 'null', 'official', 'operator', 'owner', 'pop', 'postmaster', 'privacy',
  'recordings', 'reply', 'root', 'sales', 'security', 'smtp', 'spf', 'staff', 'support', 'sysadmin', 'system', 'team',
  'test', 'webmaster', 'www',
};

final RegExp _allowed = RegExp(r'^[a-z0-9._-]*$');
final RegExp _separator = RegExp(r'[._-]');
final RegExp _doubled = RegExp(r'[._-]{2}');

/// The old made addresses' shape: sixteen of the base32 alphabet. A readable made name (`sneaky_siren33`) is refused
/// by the service alone, which holds the word lists, and the field says its words ([MailNameUnfit.generated]).
final RegExp _base32 = RegExp(r'^[a-z2-7]{16}$');

/// A name as typed, as it is kept and compared: trimmed and lower-cased.
String mailNameNormal(String typed) => typed.trim().toLowerCase();

/// What is wrong with [name], [mailNameNormal] already, or null for a name the service is worth asking about.
MailNameUnfit? mailNameUnfit(String name) {
  if (!_allowed.hasMatch(name)) return MailNameUnfit.characters;
  if (name.length < 3) return MailNameUnfit.short;
  if (name.length > mailNameMost) return MailNameUnfit.long;
  if (_separator.hasMatch(name[0]) || _separator.hasMatch(name[name.length - 1]) || _doubled.hasMatch(name)) return MailNameUnfit.separators;
  if (_base32.hasMatch(name)) return MailNameUnfit.generated;
  if (mailNamesReserved.contains(name.replaceAll(_separator, ''))) return MailNameUnfit.reserved;
  return null;
}

/// What the service said of a name ([MailIn.checkName]).
class MailNameCheck {
  const MailNameCheck({required this.name, required this.available, this.reason, this.message});

  /// The name as it would be kept.
  final String name;
  final bool available;

  /// `taken`, `yours`, or a [MailNameUnfit]'s name; null when [available].
  final String? reason;

  /// The service's own words for [reason], for one this app does not know.
  final String? message;

  /// What the field says of it.
  String get words {
    if (available) return 'Available';
    if (reason == 'taken') return 'Taken';
    if (reason == 'yours') return 'That is your address already';
    final unfit = MailNameUnfit.byCode(reason);
    if (unfit != null) return unfit.words;
    final said = message?.trim() ?? '';
    return said.isEmpty ? 'That name can’t be used' : said.replaceFirst(RegExp(r'\.$'), '');
  }
}

/// The words for a refusal with no name check behind it: an older service that has no names yet.
const String mailNamesNotYet = 'This service can’t take a name of your own yet';
