// Which contact a person named on a to-do is (lib/integrations/contacts/contact_match.dart): `@first` and
// `@first-last` against the address book, case and accents aside, and the matches set by hand winning over them.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/integrations/contacts/contact_book.dart';
import 'package:ghost_md/integrations/contacts/contact_match.dart';

import 'support.dart';

const List<PhoneContact> book = <PhoneContact>[sam, jose, ana, ana2, robin];

PhoneContact? of(String name, {Map<String, String> links = const <String, String>{}, List<PhoneContact> among = book}) => matchContact(name, among, links: links).contact;

void main() {
  group('a name folded', () {
    test('is lower case, without its accents, its words joined by one dash', () {
      expect(foldName('José Núñez'), 'jose-nunez');
      expect(foldName('ZOË_o.Brien'), 'zoe-o-brien');
      expect(foldName('  Straße  '), 'strasse');
      // Written apart: the letter, then its mark.
      expect(foldName('José'), 'jose');
    });

    test('keys a person as two mentions of them are compared', () {
      expect(personMatchKey('@Sam'), 'sam');
      expect(personMatchKey('Sam Ortiz'), 'sam-ortiz');
      expect(personMatchKey('@sam-ortiz'), personMatchKey('Sam Ortiz'));
    });
  });

  group('matched by name', () {
    test('a first name alone is the one contact by it', () {
      expect(of('sam'), sam);
      expect(of('Sam'), sam);
      expect(of('@robin'), robin);
    });

    test('a first name two contacts share is nobody', () {
      expect(of('ana'), isNull);
    });

    test('first and last is the contact by both, shown that way or kept apart', () {
      expect(of('sam-ortiz'), sam);
      expect(of('Sam-Ortiz'), sam);
      expect(of('ana-silva'), ana2);
      expect(of('ana-lima'), ana);
      // The phone shows a name its first and last do not say: either one finds them.
      const doctor = PhoneContact(id: 'c-doc', name: 'Dr Lee Park', first: 'Lee', last: 'Park');
      expect(of('lee-park', among: <PhoneContact>[doctor]), doctor);
      expect(of('dr-lee-park', among: <PhoneContact>[doctor]), doctor);
    });

    test('case and accents are not compared', () {
      expect(of('jose'), jose);
      expect(of('JOSÉ'), jose);
      expect(of('jose-nunez'), jose);
      expect(of('José-Núñez'), jose);
    });

    test('a name nobody in the book has is nobody, and a first name with a dash is not a first name', () {
      expect(of('matt'), isNull);
      expect(of('sam-smith'), isNull);
      expect(of(''), isNull);
    });

    test('two contacts by one whole name are nobody', () {
      const twin = PhoneContact(id: 'c-twin', name: 'Sam Ortiz', first: 'Sam', last: 'Ortiz');
      expect(of('sam-ortiz', among: <PhoneContact>[sam, twin]), isNull);
    });
  });

  group('matched by hand', () {
    test('a contact chosen wins over the name, and is said to be chosen', () {
      final match = matchContact('sam', book, links: <String, String>{'sam': 'c-jose'});
      expect(match.contact, jose);
      expect(match.byHand, isTrue);
      expect(matchContact('sam', book).byHand, isFalse);
    });

    test('no contact chosen wins too', () {
      final match = matchContact('@Sam', book, links: <String, String>{'sam': ''});
      expect(match.contact, isNull);
      expect(match.byHand, isTrue);
    });

    test('lets two contacts by one name be told apart', () {
      expect(of('ana', links: <String, String>{'ana': 'c-ana2'}), ana2);
    });

    test('a contact chosen who has left the book is matched by name again', () {
      final match = matchContact('sam', book, links: <String, String>{'sam': 'c-gone'});
      expect(match.contact, sam);
      expect(match.byHand, isFalse);
    });
  });

  group('a contact picked', () {
    test('writes their first and last names as a handle', () {
      expect(mentionOf(sam), 'Sam-Ortiz');
      expect(mentionOf(jose), 'José-Núñez');
      expect(mentionOf(robin), 'Robin');
      expect(mentionOf(const PhoneContact(id: 'x', name: '')), isNull);
    });

    test('is matched by what it writes', () {
      for (final contact in book.where((each) => each != ana && each != ana2)) {
        expect(of(mentionOf(contact)!), contact, reason: contact.name);
      }
      expect(of(mentionOf(ana)!), ana);
    });

    test('is found by the names that hold what is typed, accents and case aside', () {
      expect(contactsLike(book, ''), book);
      expect(contactsLike(book, 'an'), <PhoneContact>[ana, ana2]);
      expect(contactsLike(book, '@NUNEZ'), <PhoneContact>[jose]);
      expect(contactsLike(book, 'sam ort'), <PhoneContact>[sam]);
    });

    test('has initials from their first and last names, else their shown name', () {
      expect(sam.initials, 'SO');
      expect(jose.initials, 'JN');
      expect(robin.initials, 'R');
      expect(const PhoneContact(id: 'x', name: 'mary jane watson').initials, 'MW');
      expect(const PhoneContact(id: 'x', name: '').initials, '?');
    });
  });
}
