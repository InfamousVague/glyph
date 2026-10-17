// What the contacts tests share: an address book that is the test's own, so no platform is asked, and the people in
// it.
import 'dart:async';
import 'dart:typed_data';

import 'package:ghost_md/integrations/contacts/contact_book.dart';

const PhoneContact sam = PhoneContact(id: 'c-sam', name: 'Sam Ortiz', first: 'Sam', last: 'Ortiz', phones: <String>['+1 (555) 010-0100', '+1 555 0199'], emails: <String>['sam@example.com']);
const PhoneContact jose = PhoneContact(id: 'c-jose', name: 'José Núñez', first: 'José', last: 'Núñez', phones: <String>['+34 600 000 000']);
const PhoneContact ana = PhoneContact(id: 'c-ana', name: 'Ana Lima', first: 'Ana', last: 'Lima', emails: <String>['ana@example.com']);
const PhoneContact ana2 = PhoneContact(id: 'c-ana2', name: 'Ana Silva', first: 'Ana', last: 'Silva');
const PhoneContact robin = PhoneContact(id: 'c-robin', name: 'Robin');

/// An address book the test fills and answers for.
class FakeContactBook extends ContactBook {
  FakeContactBook({List<PhoneContact>? people, this.granted = ContactsAccess.denied, this.answer = ContactsAccess.granted}) : people = people ?? <PhoneContact>[sam, jose, ana, ana2, robin];

  List<PhoneContact> people;

  /// Whether it may be read now.
  ContactsAccess granted;

  /// What the phone's prompt answers when asked.
  ContactsAccess answer;

  int asked = 0;
  int read = 0;
  int settingsOpened = 0;
  final List<String> opened = <String>[];
  final Map<String, Uint8List> photos = <String, Uint8List>{};
  final List<String> photosAsked = <String>[];
  final StreamController<void> changed = StreamController<void>.broadcast();

  @override
  Future<ContactsAccess> access() async => granted;

  @override
  Future<ContactsAccess> ask() async {
    asked += 1;
    if (granted == ContactsAccess.granted) return granted;
    return granted = answer;
  }

  @override
  Future<List<PhoneContact>> everyone() async {
    read += 1;
    return granted == ContactsAccess.granted ? people : const <PhoneContact>[];
  }

  @override
  Future<Uint8List?> photoOf(String id) async {
    photosAsked.add(id);
    return photos[id];
  }

  @override
  Future<bool> open(String id) async {
    opened.add(id);
    return true;
  }

  @override
  Future<void> openSettings() async => settingsOpened += 1;

  @override
  Stream<void> get changes => changed.stream;
}

/// A picture's bytes: a 1 x 1 PNG.
final Uint8List onePixel = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0, //
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);
