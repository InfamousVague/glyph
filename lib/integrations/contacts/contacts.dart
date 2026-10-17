/// Settings › Contacts as the app holds it (docs/INTEGRATIONS.md §2): whether it is on, the matches set by hand, and
/// the address book read while it is on.
///
/// - **Off until the person turns it on**, which is when the phone asks ([ContactsStore.turnOn]). Refused, it stays
///   off and says so; refused for good, the page offers the phone's own settings.
/// - **This device's own.** The switch and the hand-set matches are kept in its memory under `glyph-contacts`
///   (lib/core/stored.dart), never synced: another phone has another address book. The contacts themselves are held
///   in memory only, read again when the app starts, when the book changes and when the page is opened.
/// - **Nothing leaves.** No contact's name, number, address or picture is written anywhere: a note gets the name a
///   person picks ([mentionOf]), and only when they pick it.
///
/// [phoneContacts] is the app's own store; a test hands its own [ContactBook] and [Stored] to a [ContactsStore], or
/// puts one in place with [useContacts].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/stored.dart';
import '../../core/task_fields.dart' show FieldKind, fieldsIn;
import 'contact_book.dart';
import 'contact_match.dart';

/// What the person chose, kept on this device.
@immutable
class ContactSettings {
  const ContactSettings({this.on = false, this.links = const <String, String>{}});

  /// Whether Settings › Contacts is on: off until turned on.
  final bool on;

  /// The matches set by hand: a person's key ([personMatchKey]) to a contact's id, or to '' for no contact.
  final Map<String, String> links;

  ContactSettings copyWith({bool? on, Map<String, String>? links}) => ContactSettings(on: on ?? this.on, links: links ?? this.links);

  Map<String, Object?> toJson() => <String, Object?>{'on': on, 'links': links};

  /// What was kept, each part checked; anything else is the default's.
  static ContactSettings? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final links = raw['links'];
    return ContactSettings(
      on: raw['on'] == true,
      links: links is Map ? <String, String>{for (final entry in links.entries) if (entry.key is String && entry.value is String) entry.key as String: entry.value as String} : const <String, String>{},
    );
  }

  @override
  bool operator ==(Object other) => other is ContactSettings && other.on == on && mapEquals(other.links, links);

  @override
  int get hashCode => Object.hash(on, Object.hashAll(links.entries.map((entry) => '${entry.key}=${entry.value}')));

  @override
  String toString() => 'ContactSettings(${toJson()})';
}

/// The key the choices are kept under.
const String contactSettingsKey = 'glyph-contacts';

/// Settings › Contacts: the choices, the address book's answer and the people in it.
class ContactsStore extends ChangeNotifier {
  ContactsStore({ContactBook? book, Stored? kept})
      : book = book ?? PluginContactBook.forDevice(),
        _kept = kept ?? stored {
    _settings = _kept.read<ContactSettings>(contactSettingsKey, const ContactSettings(), ContactSettings.fromJson);
  }

  final ContactBook book;
  final Stored _kept;
  late ContactSettings _settings;
  ContactsAccess? _access;
  List<PhoneContact> _everyone = const <PhoneContact>[];
  final Map<String, Uint8List?> _photos = <String, Uint8List?>{};
  final Set<String> _asked = <String>{};
  bool _reading = false;
  bool _asking = false;
  bool _gone = false;
  StreamSubscription<void>? _watch;
  List<String> Function()? _bodies;

  /// What the person chose.
  ContactSettings get settings => _settings;

  /// Whether Settings › Contacts is on.
  bool get on => _settings.on;

  /// The address book's last answer; null until it has been asked.
  ContactsAccess? get access => _access;

  /// Everyone in the book, while it is on and may be read.
  List<PhoneContact> get everyone => _everyone;

  /// Whether the book is being read or the person is being asked.
  bool get busy => _reading || _asking;

  /// Whether a contact can be picked: on, and allowed.
  bool get ready => on && _access == ContactsAccess.granted;

  /// Whether the app has started it ([start]) on a device with an address book: where Settings shows its page.
  bool get started => _started;
  bool _started = false;

  /// From the app's start: the notes' words, for the people the page lists, and the book read when it is on.
  void start({List<String> Function()? bodies}) {
    _bodies = bodies ?? _bodies;
    _started = book is! NoContactBook;
    if (on) unawaited(read());
  }

  /// Turns it on: the phone asks first, and it stays off where the answer is no. Answers how the asking went.
  Future<ContactsAccess> turnOn() async {
    if (_asking) return _access ?? ContactsAccess.denied;
    _asking = true;
    _tell();
    ContactsAccess said;
    try {
      said = await book.ask();
    } catch (_) {
      said = ContactsAccess.unavailable;
    }
    _asking = false;
    if (_gone) return said;
    _access = said;
    if (said == ContactsAccess.granted) {
      _keep(_settings.copyWith(on: true));
      await read();
    } else {
      _tell();
    }
    return said;
  }

  /// Turns it off: the book is put out of memory, the matches set by hand are kept for next time.
  void turnOff() {
    _keep(_settings.copyWith(on: false));
    _forgetBook();
    _tell();
  }

  /// Reads the book again, where it is on: its answer first, then everyone in it.
  Future<void> read() async {
    if (!on || _reading) return;
    _reading = true;
    _tell();
    try {
      _access = await book.access();
      if (_access == ContactsAccess.granted) {
        _everyone = await book.everyone();
        _photos.clear();
        _asked.clear();
        _watch ??= book.changes.listen((_) => unawaited(read()), onError: (Object _) {});
      } else {
        _forgetBook();
      }
    } catch (_) {
      _forgetBook();
    } finally {
      _reading = false;
    }
    _tell();
  }

  void _forgetBook() {
    _everyone = const <PhoneContact>[];
    _photos.clear();
    _asked.clear();
    unawaited(_watch?.cancel());
    _watch = null;
  }

  /// Which contact [name] is: none while it is off.
  ContactMatch matchOf(String name) => on ? matchContact(name, _everyone, links: _settings.links) : noMatch;

  /// The contact [name] is, or null.
  PhoneContact? contactOf(String name) => matchOf(name).contact;

  /// The contact with this id, while it is in the book.
  PhoneContact? byId(String id) {
    for (final contact in _everyone) {
      if (contact.id == id) return contact;
    }
    return null;
  }

  /// Matches [name] to [contact] by hand.
  void link(String name, PhoneContact contact) => _setLink(name, contact.id);

  /// Says [name] is no contact, by hand.
  void unlink(String name) => _setLink(name, '');

  /// Takes back what was set by hand for [name]: matched by its name again.
  void matchByName(String name) {
    final key = personMatchKey(name);
    if (!_settings.links.containsKey(key)) return;
    _keep(_settings.copyWith(links: <String, String>{..._settings.links}..remove(key)));
    _tell();
  }

  void _setLink(String name, String id) {
    final key = personMatchKey(name);
    if (key.isEmpty || _settings.links[key] == id) return;
    _keep(_settings.copyWith(links: <String, String>{..._settings.links, key: id}));
    _tell();
  }

  /// A contact's small picture, where it has been read: asked for the first time it is wanted, and told when it comes.
  Uint8List? photoOf(PhoneContact contact) {
    if (!ready) return null;
    if (_asked.add(contact.id)) {
      unawaited(
        book.photoOf(contact.id).then((bytes) {
          if (_gone || !_asked.contains(contact.id)) return;
          _photos[contact.id] = bytes;
          if (bytes != null) _tell();
        }, onError: (Object _) {}),
      );
    }
    return _photos[contact.id];
  }

  /// The people the notes name, each once, in the order they are first named; then anyone matched by hand whom no
  /// note names now, so a match can always be taken back.
  List<String> peopleNamed() {
    final seen = <String>{};
    final people = <String>[];
    for (final body in _bodies?.call() ?? const <String>[]) {
      if (!body.contains('@')) continue;
      for (final span in fieldsIn(body)) {
        if (span.kind != FieldKind.person) continue;
        if (seen.add(personMatchKey(span.value))) people.add(span.value);
      }
    }
    for (final key in _settings.links.keys) {
      if (seen.add(key)) people.add(key);
    }
    return people;
  }

  void _keep(ContactSettings next) {
    if (next == _settings) return;
    _settings = next;
    _kept.write(contactSettingsKey, next.toJson());
  }

  void _tell() {
    if (!_gone) notifyListeners();
  }

  @override
  void dispose() {
    _gone = true;
    unawaited(_watch?.cancel());
    super.dispose();
  }
}

ContactsStore? _contacts;

/// The app's own, over the device's memory as it is when first asked: after the launch has opened it.
ContactsStore get phoneContacts => _contacts ??= ContactsStore();

/// Puts [store] in the app's place, for a test; null makes the next ask a new one.
void useContacts(ContactsStore? store) => _contacts = store;
