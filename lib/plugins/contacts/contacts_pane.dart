import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/task_fields.dart' show personHandle;
import '../../integrations/contacts/contact_book.dart';
import '../../integrations/contacts/contact_card.dart' show ContactFace;
import '../../integrations/contacts/contact_match.dart' show personMatchKey;
import '../../integrations/contacts/contact_picker.dart';
import '../../integrations/contacts/contacts.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/settings_search.dart';

/// What Settings' search finds on Contacts: what the phone allows, and the people once it allows it.
List<SettingsFindable> contactsFindable(ContactsStore store) => [
  const SettingsFindable('Your contacts', 'contacts address book phone people call text email picture allow permission'),
  if (store.ready) const SettingsFindable('People in your notes', 'people person assignee match contact link unlink'),
];

/// The row's reading: off, not allowed, or how many of the people named are contacts.
String contactsSummary(ContactsStore store) {
  if (!store.on) return 'Off';
  if (store.access != null && store.access != ContactsAccess.granted) return 'Not allowed';
  final people = store.peopleNamed();
  final matched = people.where((name) => store.contactOf(name) != null).length;
  if (people.isEmpty) return 'On';
  return '$matched of ${people.length} matched';
}

/// The Contacts plugin's page, Settings › Contacts (docs/INTEGRATIONS.md §2; the port's own, 2026-10-17,
/// and a page of its own behind Plugins until it was a plugin): the phone's contacts for the people named on to-dos.
///
/// - **Your contacts**: what the phone allows. The plugin's switch on its card is the page's switch: switched on, the
///   phone asks. Refused, the page says so and asks again with Allow; refused for good, it offers the phone's own
///   settings, where it can be allowed. Drawn by itself (as a test does) where it is off, it offers to turn it on.
/// - **People in your notes**, once it is on: everyone a note names (`@sam`), with the contact each is, matched by
///   name ("Matched by name"), set by hand ("Chosen by you") or none. Choose picks another from the contacts; Unlink
///   says this person is no contact; By name takes back what was set by hand. Kept on this device only.
///
/// Then a footnote on what leaves the device, which is nothing.
class ContactsPane extends StatefulWidget {
  const ContactsPane({super.key, this.store});

  /// The contacts it shows and changes; the app's own when left out.
  final ContactsStore? store;

  static Widget hosted(BuildContext context) => const ContactsPane();

  @override
  State<ContactsPane> createState() => _ContactsPaneState();
}

class _ContactsPaneState extends State<ContactsPane> {
  ContactsStore get _store => widget.store ?? phoneContacts;

  @override
  void initState() {
    super.initState();
    // Read again as the page opens, so a contact just added is matched.
    unawaited(_store.read());
  }

  Future<void> _choose(String name) async {
    final contact = await pickContact(context, store: _store, title: 'Contact for @${personHandle(name) ?? name}');
    if (contact != null) _store.link(name, contact);
  }

  Widget _person(ContactsStore store, String name) {
    final match = store.matchOf(name);
    final contact = match.contact;
    final shown = '@${personHandle(name) ?? name}';
    final hint = contact != null ? '${contact.name.isNotEmpty ? contact.name : shown} · ${match.byHand ? 'Chosen by you' : 'Matched by name'}' : (match.byHand ? 'No contact · Chosen by you' : 'No contact by this name');
    return SettingRow(
      key: ValueKey<String>('contacts-person:${personMatchKey(name)}'),
      icon: contact != null ? ContactFace(contact: contact, photo: store.photoOf(contact), size: 20) : const AppIcon(Lucide.userRound, size: 16),
      label: shown,
      hint: Text(hint),
      control: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RowAction(key: ValueKey<String>('contacts-choose:${personMatchKey(name)}'), onPress: () => unawaited(_choose(name)), child: const Text('Choose')),
          if (match.byHand)
            RowAction(key: ValueKey<String>('contacts-by-name:${personMatchKey(name)}'), onPress: () => store.matchByName(name), child: const Text('By name'))
          else if (contact != null)
            RowAction(key: ValueKey<String>('contacts-unlink:${personMatchKey(name)}'), onPress: () => store.unlink(name), child: const Text('Unlink')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final store = _store;
        final access = store.access;
        final unavailable = access == ContactsAccess.unavailable;
        final refused = access == ContactsAccess.denied || access == ContactsAccess.blocked;
        final people = store.ready ? store.peopleNamed() : const <String>[];
        final String said;
        if (store.busy && !store.ready) {
          said = 'Asking…';
        } else if (!store.on) {
          said = 'Off. Turning it on asks to read your contacts.';
        } else if (store.ready) {
          said = 'Read on this device only.';
        } else if (unavailable) {
          said = 'This device has none Ghost.md can read.';
        } else if (refused) {
          said = 'Not allowed.';
        } else {
          said = 'Not read yet.';
        }
        return PaneBody(
          children: [
            PaneSection(
              title: 'Contacts',
              description: const Text('See the picture of a person named on a to-do, and call, text or email them from their chip. Write @sam on a to-do, or pick someone with A person.'),
              children: [
                SettingRow(
                  key: const ValueKey<String>('contacts-access'),
                  icon: const AppIcon(Lucide.contactRound, size: 16),
                  label: 'Your contacts',
                  hint: Text(said),
                  // Off, as where the page is drawn by itself: the way on, which asks. The plugin's card is the switch.
                  control: store.on || unavailable ? null : RowAction(onPress: () => unawaited(store.turnOn()), child: const Text('Turn on')),
                ),
              ],
            ),
            if (unavailable) const SettingsCallout(child: Text('This device has no contacts Ghost.md can read.')),
            if (store.on && refused && !store.busy)
              SettingsCallout(
                action: access == ContactsAccess.blocked
                    ? RowAction(onPress: () => unawaited(store.book.openSettings()), child: const Text('Open settings'))
                    : RowAction(onPress: () => unawaited(store.turnOn()), child: const Text('Allow')),
                child: Text(
                  access == ContactsAccess.blocked
                      ? 'Ghost.md is not allowed to read your contacts. Allow it in your device’s settings, then come back here.'
                      : 'Ghost.md was not allowed to read your contacts. Allow asks again.',
                ),
              ),
            if (store.ready)
              PaneSection(
                title: 'People in your notes',
                description: const Text('Each person named on a to-do and the contact they are. Choose another, or Unlink, and it is kept on this device.'),
                children: [
                  if (people.isEmpty) const SettingRow(label: 'No one yet', hint: Text('Write @sam on a to-do and Sam appears here.')),
                  for (final name in people) _person(store, name),
                ],
              ),
            const SettingsFootnote(child: Text('Nothing about a contact leaves this device or goes into a note, but the name you pick.')),
          ],
        );
      },
    );
  }
}

/// A person's key, for the rows' keys.
String personMatchKeyOf(String name) => (personHandle(name) ?? name).toLowerCase();
