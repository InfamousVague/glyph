// Settings › Contacts as the app holds it (lib/integrations/contacts/contacts.dart): off until turned on, which asks
// the phone; refused, it stays off; on, the book is read and the people matched; the switch and the matches set by
// hand kept on this device; nothing of a contact kept anywhere.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/integrations/contacts/contact_book.dart';
import 'package:ghost_md/integrations/contacts/contacts.dart';

import 'support.dart';

void main() {
  late MemoryStored kept;
  late FakeContactBook book;

  setUp(() {
    kept = MemoryStored();
    book = FakeContactBook();
  });

  ContactsStore store() => ContactsStore(book: book, kept: kept);

  Map<String, Object?> keptJson() => jsonDecode(kept.getItem(contactSettingsKey)!) as Map<String, Object?>;

  test('is off until turned on, and asks nothing and reads nothing while it is', () async {
    final contacts = store()..start(bodies: () => <String>['- [ ] Call @sam']);
    await pumpEventQueue();
    expect(contacts.on, isFalse);
    expect(contacts.ready, isFalse);
    expect(book.asked, 0);
    expect(book.read, 0);
    expect(contacts.contactOf('sam'), isNull);
  });

  test('turned on, asks the phone, reads the book and matches the people', () async {
    final contacts = store();
    expect(await contacts.turnOn(), ContactsAccess.granted);
    expect(book.asked, 1);
    expect(contacts.on, isTrue);
    expect(contacts.ready, isTrue);
    expect(contacts.everyone, hasLength(5));
    expect(contacts.contactOf('@sam'), sam);
    expect(contacts.contactOf('sam-ortiz'), sam);
    expect(keptJson(), <String, Object?>{'on': true, 'links': <String, Object?>{}});
  });

  test('refused, stays off and says so; refused for good, says that', () async {
    book.answer = ContactsAccess.denied;
    final contacts = store();
    expect(await contacts.turnOn(), ContactsAccess.denied);
    expect(contacts.on, isFalse);
    expect(contacts.access, ContactsAccess.denied);
    expect(contacts.everyone, isEmpty);
    expect(kept.getItem(contactSettingsKey), isNull);
    book.answer = ContactsAccess.blocked;
    expect(await contacts.turnOn(), ContactsAccess.blocked);
    expect(contacts.on, isFalse);
    expect(contacts.access, ContactsAccess.blocked);
  });

  test('on where the app starts, reads the book again; turned off, puts it out of memory', () async {
    kept.write(contactSettingsKey, <String, Object?>{'on': true, 'links': <String, String>{}});
    book.granted = ContactsAccess.granted;
    final contacts = store()..start();
    await pumpEventQueue();
    expect(contacts.ready, isTrue);
    expect(book.asked, 0);
    expect(contacts.contactOf('jose'), jose);
    contacts.turnOff();
    expect(contacts.on, isFalse);
    expect(contacts.everyone, isEmpty);
    expect(contacts.contactOf('jose'), isNull);
    expect(keptJson()['on'], isFalse);
  });

  test('on, but no longer allowed: holds no one until it is allowed again', () async {
    kept.write(contactSettingsKey, <String, Object?>{'on': true});
    book.granted = ContactsAccess.denied;
    final contacts = store()..start();
    await pumpEventQueue();
    expect(contacts.on, isTrue);
    expect(contacts.ready, isFalse);
    expect(contacts.access, ContactsAccess.denied);
    expect(contacts.contactOf('sam'), isNull);
  });

  test('keeps the matches set by hand on this device, by the person as they are compared', () async {
    final contacts = store();
    await contacts.turnOn();
    contacts.link('@Ana', ana2);
    expect(contacts.contactOf('ana'), ana2);
    expect(contacts.matchOf('ana').byHand, isTrue);
    contacts.unlink('Sam');
    expect(contacts.contactOf('@sam'), isNull);
    expect(keptJson()['links'], <String, Object?>{'ana': 'c-ana2', 'sam': ''});
    // Read again from what was kept: the same matches.
    final again = store();
    await again.read();
    expect(again.contactOf('ana'), ana2);
    expect(again.contactOf('sam'), isNull);
    again.matchByName('sam');
    expect(again.contactOf('sam'), sam);
    expect(keptJson()['links'], <String, Object?>{'ana': 'c-ana2'});
  });

  test('keeps nothing of a contact: only the switch and the ids chosen', () async {
    final contacts = store();
    await contacts.turnOn();
    contacts.link('sam', sam);
    final written = kept.getItem(contactSettingsKey)!;
    for (final said in <String>['Sam Ortiz', '555', 'example.com', 'Ortiz']) {
      expect(written, isNot(contains(said)));
    }
    expect(kept.allKeys, <String>[contactSettingsKey]);
  });

  test('lists the people the notes name, each once, then anyone set by hand whom no note names', () async {
    final contacts = store()..start(bodies: () => <String>['- [ ] Call @sam\n- [ ] Ask @Sam about @ana', 'email sam@example.com', '- [ ] Pay @José-Núñez']);
    await contacts.turnOn();
    contacts.unlink('robin');
    expect(contacts.peopleNamed(), <String>['sam', 'ana', 'José-Núñez', 'robin']);
  });

  test('asks for a matched contact’s picture once, and tells when it comes', () async {
    book.photos['c-sam'] = onePixel;
    final contacts = store();
    await contacts.turnOn();
    var told = 0;
    contacts.addListener(() => told += 1);
    expect(contacts.photoOf(sam), isNull);
    await pumpEventQueue();
    expect(contacts.photoOf(sam), onePixel);
    expect(contacts.photoOf(jose), isNull);
    await pumpEventQueue();
    expect(book.photosAsked, <String>['c-sam', 'c-jose']);
    expect(told, 1);
  });

  test('reads the book again when it changes under the app', () async {
    final contacts = store();
    await contacts.turnOn();
    book.people = <PhoneContact>[...book.people, const PhoneContact(id: 'c-matt', name: 'Matt')];
    book.changed.add(null);
    await pumpEventQueue();
    expect(contacts.contactOf('matt')?.id, 'c-matt');
    contacts.dispose();
  });

  test('a book with no one in it is unavailable, and never turns on', () async {
    final contacts = ContactsStore(book: const NoContactBook(), kept: kept);
    expect(await contacts.turnOn(), ContactsAccess.unavailable);
    expect(contacts.on, isFalse);
    contacts.start();
    expect(contacts.started, isFalse);
  });
}
