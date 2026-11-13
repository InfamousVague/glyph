import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/lucide.g.dart';
import '../sms.dart';
import 'common.dart';

/// What can be done about encryption with one person, by where it stands (android/.../E2e.kt): offered from a
/// conversation's header and from Settings › Encryption. [onChanged] is called after anything changes.
void showEncryptionChoices(BuildContext context, Person person, E2eState state, VoidCallback onChanged) {
  final name = person.label;
  Future<void> offer() async {
    try {
      await Sms.instance.e2eOffer(person.address);
      if (context.mounted) toast(context, state.state == 'pending' ? 'Encryption is on with $name' : 'Key sent. Encryption starts when $name accepts.');
    } catch (e) {
      if (context.mounted) toast(context, 'Couldn\'t send the key: $e', tone: GlacierToastTone.danger);
    }
    onChanged();
  }

  Future<void> off() async {
    await Sms.instance.e2eOff(person.address);
    if (context.mounted) toast(context, 'Encryption is off with $name');
    onChanged();
  }

  switch (state.state) {
    case 'on':
      showChoices(context, title: 'Texts with $name are encrypted${state.verified ? ' and verified' : ''}. Only your two phones can read them.', choices: [
        Choice(state.verified ? 'Safety number (verified)' : 'Verify safety number', Lucide.shieldCheck, () => showSafetyNumber(context, person, state, onChanged)),
        Choice('Turn off encryption', Lucide.x, off, danger: true),
      ]);
    case 'pending':
      showChoices(
        context,
        title: state.changed
            ? '$name sent a NEW encryption key. That happens when they reinstall the app or change phones, and it is also what someone reading in the middle would do. Ask them before accepting.'
            : '$name sent their encryption key. Accepting sends yours back, and from then on your texts with them are encrypted.',
        choices: [
          Choice(state.changed ? 'Accept the new key' : 'Accept and turn on', Lucide.lock, offer),
          Choice('Decline', Lucide.x, off, danger: true),
        ],
      );
    case 'offered':
      showChoices(context, title: 'Your key was sent. Encryption starts when $name accepts in Ghost Messaging.', choices: [
        Choice('Send the key again', Lucide.send, offer),
        Choice('Cancel', Lucide.x, off, danger: true),
      ]);
    default:
      showChoices(
        context,
        title: 'Encrypt your texts with $name so only your two phones can read them. They need Ghost Messaging too. This sends them one text with your key.',
        choices: [Choice('Send my key', Lucide.lock, offer)],
      );
  }
}

/// The thirty digits both phones show when nobody is in the middle, and the tick that says they were compared.
void showSafetyNumber(BuildContext context, Person person, E2eState state, VoidCallback onChanged) {
  showChoices(
    context,
    title: 'Safety number with ${person.label}\n\n${state.safety ?? ''}\n\nCompare it with theirs in person or on a call (Settings › Encryption on their phone, or this conversation\'s header). The same digits on both phones mean nobody swapped a key on the way.',
    choices: [
      Choice(state.verified ? 'Mark as not verified' : 'They match: mark as verified', state.verified ? Lucide.x : Lucide.shieldCheck, () async {
        await Sms.instance.e2eVerify(person.address, !state.verified);
        onChanged();
      }),
    ],
  );
}
