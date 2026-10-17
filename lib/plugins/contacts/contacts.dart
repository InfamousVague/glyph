/// The Contacts plugin, built in and off until switched on: the phone's contacts for the people named on to-dos
/// (docs/INTEGRATIONS.md §2). Matt, 2026-10-17: "Ask Claude and other integrations should be shipped as plugins".
///
/// What it does is lib/integrations/contacts/ (the store, the address book, the match, the picker and the card) and
/// the editor's people chips: a chip of a contact shows their picture and opens their card (call, text, email), and
/// the + beside a line offers "A person" to pick from the contacts. The plugin's switch is the store's
/// ([contactsSwitch], handed it by the app's root): switched on, the phone is asked; refused, nothing is read and the
/// plugin's page says so, with the way to allow it; switched off, the book is put out of memory and no chip is a
/// contact's, while the matches set by hand are kept for next time. Its page is the one that was Settings › Contacts
/// ([ContactsPane]), without the switch it had, which is the card's now.
///
/// Nothing leaves the device: no permission here reaches past the phone, so Local only does not hold it off.
library;

import '../../integrations/contacts/contacts.dart' show ContactsSwitch, phoneContacts;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../registry.dart' show plugins;
import '../types.dart';
import 'contacts_pane.dart';

export 'contacts_pane.dart' show ContactsPane, contactsFindable, contactsSummary;

const PluginManifest contactsManifest = PluginManifest(
  id: 'contacts',
  name: 'Contacts',
  description: 'Matches the people named on your to-dos to your phone’s contacts: their picture on the chip, a tap to call, text or email them, and A person to pick someone.',
  version: '1.0.0',
  author: 'Ghost.md',
  // Off until switched on: switching it on is when the phone asks to read the address book.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Reads the people your to-dos name (@sam) to match them, and writes the name you pick into the note. Nothing else in a note changes.'),
    PluginPermission(Permission.native, 'Reads your phone’s contacts, once you allow it, on this device only. No contact’s name, number or picture is kept or sent anywhere.'),
  ],
  storage: ['glyph-contacts'],
);

/// The plugin's switch as the contacts' store holds it, or null where the app's registry has no such plugin (a
/// test's, which keeps the store's own).
ContactsSwitch? contactsSwitch() {
  final registry = plugins;
  if (registry.byId(contactsManifest.id) == null) return null;
  return ContactsSwitch(read: () => registry.isEnabled(contactsManifest.id), write: (on) => registry.setEnabled(contactsManifest.id, on), changes: registry);
}

final GlyphPlugin contactsPlugin = GlyphPlugin(manifest: contactsManifest, icon: 'contact-round', settings: _ContactsSettings());

/// The page, and what the search finds on it as it stands now: the people once the phone allows it.
class _ContactsSettings extends PluginSettings {
  _ContactsSettings() : super(pane: (context) => const ContactsPane(), summary: () => contactsSummary(phoneContacts), hue: 'graphite');

  @override
  List<SettingsFindable> get settings => contactsFindable(phoneContacts);
}
