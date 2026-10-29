/// The Contacts plugin's setup (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-29: "add the voiceover onboarding
/// for the rest of the plugins"). Nothing to sign in to and no key: the one thing to set up is the phone's permission,
/// asked through the store's own [ContactsStore.turnOn], as the plugin's page asks it (contacts_pane.dart).
///
/// 1. **The people on your to-dos**: what it does, and that nothing of a contact leaves the device.
/// 2. **Allow your contacts**: the phone's own prompt. Allowed, the setup goes on by itself; refused for good, the
///    phone's settings are opened, where it can be allowed ([contactsAllow]).
/// 3. **Check it worked**: whether the store may read the book now, and how many contacts it found
///    ([contactsSetupResult]).
/// 4. **Try it**: `@sam` on a to-do, and A person on the + beside a line.
///
/// Needed until the contacts may be read, or where the device has none to read.
library;

import '../../art/lucide.g.dart';
import '../../integrations/contacts/contact_book.dart' show ContactsAccess;
import '../../integrations/contacts/contacts.dart' show ContactsStore, phoneContacts;
import '../onboarding/setup_flow.dart';

/// Asks the phone (see the header); what went wrong in a sentence, or null.
Future<String?> contactsAllow(ContactsStore store) async {
  if (store.access == ContactsAccess.blocked) {
    await store.book.openSettings();
    return 'Allow contacts for Ghost.md in your device’s settings, then come back here and check.';
  }
  return switch (await store.turnOn()) {
    ContactsAccess.granted => null,
    ContactsAccess.unavailable => 'This device has no contacts Ghost.md can read.',
    ContactsAccess.blocked => 'Ghost.md is not allowed to read your contacts. Press again to open your device’s settings, where it can be allowed.',
    _ => 'Ghost.md was not allowed to read your contacts. Press again to be asked again.',
  };
}

/// The check's answer (see the header).
Future<SetupResult> contactsSetupResult(ContactsStore store) async {
  if (store.ready) {
    await store.read();
    final count = store.everyone.length;
    return SetupResult.ok(count == 0 ? 'Allowed. Your contacts are read on this device only.' : 'Allowed: ${count == 1 ? '1 contact' : '$count contacts'}, read on this device only.');
  }
  return switch (store.access) {
    ContactsAccess.unavailable => const SetupResult.failed('This device has no contacts Ghost.md can read.'),
    ContactsAccess.blocked => const SetupResult.failed('Ghost.md is not allowed to read your contacts. Allow it in your device’s settings, then check again.', pasteAgain: true),
    _ => const SetupResult.failed('Ghost.md may not read your contacts yet. Allow them first.', pasteAgain: true),
  };
}

/// The setup (see the header). [store] is the contacts it asks for; the phone's own where null.
PluginSetup contactsSetup({ContactsStore? store}) {
  ContactsStore on() => store ?? phoneContacts;
  return PluginSetup(
    id: 'contacts',
    name: 'Contacts',
    hues: const ['rose', 'coral', 'magenta'],
    tiles: const [Lucide.contactRound, Lucide.userRound, Lucide.phone, Lucide.mail],
    ready: () => on().ready || on().access == ContactsAccess.unavailable,
    watch: (listener) {
      final watched = on()..addListener(listener);
      return () => watched.removeListener(listener);
    },
    about: 'Two short steps: allow your contacts, and a check that it worked.',
    again: 'The steps from the start: allowing your contacts, and a check that it worked.',
    steps: [
      const SetupIntro(
        id: 'intro',
        title: 'The people on your to-dos',
        icon: Lucide.contactRound,
        mark: false,
        points: [
          (Lucide.userRound, 'A contact’s picture on the chip of a person named on a to-do'),
          (Lucide.phone, 'A tap on the chip to call, text or email them'),
          (Lucide.lock, 'Read on this device only: no contact is kept or sent anywhere'),
        ],
      ),
      SetupAct(id: 'allow', title: 'Allow your contacts', icon: Lucide.contactRound, label: 'Allow contacts', again: 'Allow again', onward: true, run: () => contactsAllow(on())),
      SetupCheck(id: 'check', title: 'Check it worked', icon: Lucide.shieldCheck, checking: 'Reading your contacts…', run: () => contactsSetupResult(on())),
      const SetupDone(id: 'done', title: 'Try it', icon: Lucide.wandSparkles),
    ],
  );
}
