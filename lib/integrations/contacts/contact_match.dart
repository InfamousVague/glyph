/// Which contact a person named on a to-do is (docs/INTEGRATIONS.md §2): `@sam` and `@sam-ortiz` against the names
/// in the phone's address book, and the matches the person set by hand in Settings › Contacts.
///
///     @sam          the one contact whose first name is Sam; nobody where two are, or none
///     @sam-ortiz    the contact shown as "Sam Ortiz", or whose first and last names are Sam and Ortiz
///     @José, @jose  the same person: the case and the accents are not compared, nor `-`, `_` and `.` told apart
///
/// A match set by hand wins over all of these, and so does "no contact" set by hand: the key is the person as two
/// mentions of them are compared (core/task_fields.dart `personKey`), folded as here, so `@Sam` and `@sam` share one.
/// A contact set by hand that is no longer in the book is matched as though nothing were set.
///
/// What a contact picked writes ([mentionOf]) is the other way round: their first and last names as a handle,
/// `@Sam-Ortiz`, the way a spoken "for Sam Ortiz" and the note's own person picker write one.
library;

import '../../core/task_fields.dart' show personHandle, personKey;
import 'contact_book.dart';

/// The Latin letters with marks, each as the letters it is compared as.
const Map<String, String> _plain = <String, String>{
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a', 'ǎ': 'a', //
  'æ': 'ae', 'ç': 'c', 'ć': 'c', 'ĉ': 'c', 'ċ': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd', 'ð': 'd', //
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e', //
  'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g', 'ĥ': 'h', 'ħ': 'h', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ĩ': 'i', 'ī': 'i', 'ĭ': 'i', 'į': 'i', 'ı': 'i', 'ǐ': 'i', //
  'ĵ': 'j', 'ķ': 'k', 'ĺ': 'l', 'ļ': 'l', 'ľ': 'l', 'ŀ': 'l', 'ł': 'l', //
  'ñ': 'n', 'ń': 'n', 'ņ': 'n', 'ň': 'n', //
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ŏ': 'o', 'ő': 'o', 'ǒ': 'o', 'œ': 'oe', //
  'ŕ': 'r', 'ŗ': 'r', 'ř': 'r', 'ś': 's', 'ŝ': 's', 'ş': 's', 'š': 's', 'ș': 's', 'ß': 'ss', //
  'ţ': 't', 'ť': 't', 'ŧ': 't', 'ț': 't', 'þ': 'th', //
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ũ': 'u', 'ū': 'u', 'ŭ': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u', 'ǔ': 'u', //
  'ŵ': 'w', 'ý': 'y', 'ÿ': 'y', 'ŷ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z',
};

/// The marks a letter may be written with after it, apart (U+0300 to U+036F).
final RegExp _combining = RegExp('[̀-ͯ]');
final RegExp _joins = RegExp(r'[\s._-]+');
final RegExp _endJoins = RegExp(r'^-+|-+$');

/// A name as it is compared: lower case, without its accents, its words joined by one `-`.
String foldName(String name) {
  final lower = name.toLowerCase().replaceAll(_combining, '');
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final letter = String.fromCharCode(rune);
    out.write(_plain[letter] ?? letter);
  }
  return out.toString().replaceAll(_joins, '-').replaceAll(_endJoins, '');
}

/// A person named in a note, as a hand-set match is kept by: `@Sam`, "sam" and "Sam" are `sam`.
String personMatchKey(String name) => foldName(personKey(name));

String _handleKey(String words) => foldName(personHandle(words) ?? '');

/// The names a contact answers to, folded: the one the phone shows, their first and last together, and their
/// first alone (the shown name's first word where the phone has no first name apart).
({String shown, String full, String first}) contactKeys(PhoneContact contact) {
  final both = '${contact.first} ${contact.last}'.trim();
  final firstWord = contact.first.trim().isNotEmpty ? contact.first : contact.name.trim().split(RegExp(r'\s+')).first;
  return (shown: _handleKey(contact.name), full: both.isEmpty ? '' : _handleKey(both), first: _handleKey(firstWord));
}

/// Which contact [name] is, and whether that was set by hand.
typedef ContactMatch = ({PhoneContact? contact, bool byHand});

/// No contact, not set by hand.
const ContactMatch noMatch = (contact: null, byHand: false);

/// The contact a person named as [name] is, among [everyone], with the matches set by hand ([links]: a person's key,
/// [personMatchKey], to a contact's id, or to '' for no contact).
ContactMatch matchContact(String name, List<PhoneContact> everyone, {Map<String, String> links = const <String, String>{}}) {
  final key = personMatchKey(name);
  if (key.isEmpty) return noMatch;
  final set = links[key];
  if (set != null) {
    if (set.isEmpty) return (contact: null, byHand: true);
    for (final contact in everyone) {
      if (contact.id == set) return (contact: contact, byHand: true);
    }
  }
  final keys = <PhoneContact, ({String shown, String full, String first})>{for (final contact in everyone) contact: contactKeys(contact)};
  // A whole name first: one contact by it, or nobody where two share it.
  final whole = <PhoneContact>[for (final contact in everyone) if (keys[contact]!.shown == key || keys[contact]!.full == key) contact];
  if (whole.length == 1) return (contact: whole.single, byHand: false);
  if (whole.length > 1) return noMatch;
  // A first name alone, where it is the only one by it.
  if (key.contains('-')) return noMatch;
  final firsts = <PhoneContact>[for (final contact in everyone) if (keys[contact]!.first == key) contact];
  return firsts.length == 1 ? (contact: firsts.single, byHand: false) : noMatch;
}

/// What picking [contact] writes after the at sign: their first and last names as a handle (`Sam-Ortiz`), else the
/// name the phone shows; null where nothing of it makes one.
String? mentionOf(PhoneContact contact) {
  final both = '${contact.first} ${contact.last}'.trim();
  return personHandle(both.isNotEmpty ? both : contact.name);
}

/// The contacts whose names hold what is typed, accents and case aside, in the book's order; all of them for nothing
/// typed.
List<PhoneContact> contactsLike(List<PhoneContact> everyone, String typed) {
  final looking = foldName(typed.replaceFirst(RegExp('^@+'), ''));
  if (looking.isEmpty) return everyone;
  return <PhoneContact>[
    for (final contact in everyone)
      if (foldName(contact.name).contains(looking) || foldName('${contact.first} ${contact.last}').contains(looking)) contact,
  ];
}
