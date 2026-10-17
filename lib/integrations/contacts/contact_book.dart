/// The phone's own address book, as Settings › Contacts reads it (docs/INTEGRATIONS.md §2): who is in it, whether
/// the app may look, and the Contacts app opened at one of them. Read on this device and held in its memory only:
/// nothing of a contact is kept, synced or written into a note but the name a person picks.
///
/// [ContactBook] is what the rest of lib/integrations/contacts asks, so a test hands its own and no platform is
/// needed. [PluginContactBook] is the device's, over `flutter_contacts` (Android, the iPhone and the Mac); anywhere
/// else, and in a test that hands none, the book says [ContactsAccess.unavailable] and holds no one.
///
/// What is read of a contact is what the card and the matching need: the name the phone shows, the first and last
/// names, the phone numbers and the email addresses, the one marked primary first. Not the photo: that is asked for
/// one contact at a time ([ContactBook.photoOf]), and only for the people a note names, so a book of thousands is not
/// read as pictures.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException, MissingPluginException;
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Whether the app may read the contacts.
enum ContactsAccess {
  /// Allowed: all of them, or (an iPhone's limited access) the ones the person chose.
  granted,

  /// Not allowed yet: asking again shows the phone's prompt.
  denied,

  /// Refused for good, or held by a policy: only the phone's own settings can allow it now.
  blocked,

  /// No address book here: a platform `flutter_contacts` does not reach (Windows, Linux), or a test.
  unavailable,
}

/// One person in the address book, as far as the app reads them.
@immutable
class PhoneContact {
  const PhoneContact({required this.id, required this.name, this.first = '', this.last = '', this.phones = const <String>[], this.emails = const <String>[]});

  /// The phone's own id for them: what a hand-set match is kept by, and what opens them in Contacts.
  final String id;

  /// The name the phone shows them by ("Sam Ortiz", "Dr Sam Ortiz Jr").
  final String name;

  /// Their first and last names, where the phone has them apart; empty where it does not.
  final String first;
  final String last;

  /// Their numbers and addresses, the primary one first.
  final List<String> phones;
  final List<String> emails;

  /// Their initials, at most two: the first and last names', else the shown name's first two words'.
  String get initials {
    final words = <String>[if (first.trim().isNotEmpty) first.trim(), if (last.trim().isNotEmpty) last.trim()];
    final from = words.isNotEmpty ? words : name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (from.isEmpty) return '?';
    final letters = <String>[for (final word in from.length > 1 ? <String>[from.first, from.last] : from) String.fromCharCode(word.runes.first).toUpperCase()];
    return letters.join();
  }

  @override
  bool operator ==(Object other) => other is PhoneContact && other.id == id && other.name == name && other.first == first && other.last == last && listEquals(other.phones, phones) && listEquals(other.emails, emails);

  @override
  int get hashCode => Object.hash(id, name, first, last, Object.hashAll(phones), Object.hashAll(emails));

  @override
  String toString() => 'PhoneContact($id, $name)';
}

/// What the app asks of the address book.
abstract class ContactBook {
  const ContactBook();

  /// Whether the app may read it now, asking nothing.
  Future<ContactsAccess> access();

  /// Asks the person, with the phone's own prompt where it can still be shown; answers how that went.
  Future<ContactsAccess> ask();

  /// Everyone in it, by the shown name; nobody where it may not be read.
  Future<List<PhoneContact>> everyone();

  /// One contact's small picture, or null where they have none.
  Future<Uint8List?> photoOf(String id);

  /// Opens the phone's own Contacts app at them; false where it could not.
  Future<bool> open(String id);

  /// The phone's settings for this app, where contacts refused for good are allowed again.
  Future<void> openSettings();

  /// Told whenever the address book changes under the app.
  Stream<void> get changes;
}

/// A book with nothing in it and no way to ask: a platform with no address book, and a test that hands none.
class NoContactBook extends ContactBook {
  const NoContactBook();

  @override
  Future<ContactsAccess> access() async => ContactsAccess.unavailable;

  @override
  Future<ContactsAccess> ask() async => ContactsAccess.unavailable;

  @override
  Future<List<PhoneContact>> everyone() async => const <PhoneContact>[];

  @override
  Future<Uint8List?> photoOf(String id) async => null;

  @override
  Future<bool> open(String id) async => false;

  @override
  Future<void> openSettings() async {}

  @override
  Stream<void> get changes => const Stream<void>.empty();
}

/// Whether this platform has an address book `flutter_contacts` reads.
bool get contactsOnPlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

/// The device's address book, over `flutter_contacts`.
class PluginContactBook extends ContactBook {
  const PluginContactBook();

  /// The book for this device: the plugin's where it reaches, else one with no one in it.
  static ContactBook forDevice() => contactsOnPlatform ? const PluginContactBook() : const NoContactBook();

  static ContactsAccess _said(fc.PermissionStatus status) => switch (status) {
    fc.PermissionStatus.granted || fc.PermissionStatus.limited => ContactsAccess.granted,
    fc.PermissionStatus.denied || fc.PermissionStatus.notDetermined => ContactsAccess.denied,
    fc.PermissionStatus.permanentlyDenied || fc.PermissionStatus.restricted => ContactsAccess.blocked,
  };

  @override
  Future<ContactsAccess> access() async {
    try {
      return _said(await fc.FlutterContacts.permissions.check(fc.PermissionType.read));
    } on MissingPluginException {
      return ContactsAccess.unavailable;
    } on PlatformException {
      return ContactsAccess.unavailable;
    }
  }

  @override
  Future<ContactsAccess> ask() async {
    try {
      return _said(await fc.FlutterContacts.permissions.request(fc.PermissionType.read));
    } on MissingPluginException {
      return ContactsAccess.unavailable;
    } on PlatformException {
      // Another prompt is already up (`CONCURRENT_REQUEST`): as it stands.
      return access();
    }
  }

  /// The primary one first, then the rest as the phone lists them, each once.
  static List<String> _primaryFirst<T>(List<T> all, String Function(T each) said, bool? Function(T each) primary) {
    final out = <String>[];
    for (final each in <T>[...all.where((each) => primary(each) == true), ...all.where((each) => primary(each) != true)]) {
      final words = said(each).trim();
      if (words.isNotEmpty && !out.contains(words)) out.add(words);
    }
    return out;
  }

  @override
  Future<List<PhoneContact>> everyone() async {
    try {
      final all = await fc.FlutterContacts.getAll(properties: <fc.ContactProperty>{fc.ContactProperty.name, fc.ContactProperty.phone, fc.ContactProperty.email});
      return <PhoneContact>[
        for (final each in all)
          if (each.id case final id? when id.isNotEmpty)
            PhoneContact(
              id: id,
              name: (each.displayName ?? '').trim(),
              first: (each.name?.first ?? '').trim(),
              last: (each.name?.last ?? '').trim(),
              phones: _primaryFirst<fc.Phone>(each.phones, (phone) => phone.number, (phone) => phone.isPrimary),
              emails: _primaryFirst<fc.Email>(each.emails, (email) => email.address, (email) => email.isPrimary),
            ),
      ];
    } on MissingPluginException {
      return const <PhoneContact>[];
    } on PlatformException {
      return const <PhoneContact>[];
    }
  }

  @override
  Future<Uint8List?> photoOf(String id) async {
    try {
      final contact = await fc.FlutterContacts.get(id, properties: <fc.ContactProperty>{fc.ContactProperty.photoThumbnail});
      final bytes = contact?.photo?.thumbnail;
      return bytes == null || bytes.isEmpty ? null : bytes;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> open(String id) async {
    try {
      if (Platform.isMacOS) {
        // The Mac's Contacts answers its own address for a card: the contact's identifier after `addressbook://`.
        return await launcher.launchUrl(Uri.parse('addressbook://${Uri.encodeComponent(id)}'));
      }
      await fc.FlutterContacts.native.showViewer(id);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await fc.FlutterContacts.permissions.openSettings();
    } on MissingPluginException {
      // Nowhere to go.
    } on PlatformException {
      // Nowhere to go.
    }
  }

  @override
  Stream<void> get changes => fc.FlutterContacts.onDatabaseChange;
}
