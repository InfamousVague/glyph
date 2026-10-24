import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../settings/kit/settings_kit.dart';
import '../mail_in.dart';

/// Email to a note (lib/mail/mail_in.dart, docs/MAIL.md): a private address, shown with Copy, a new one in its place,
/// and off.
///
/// The address is also the one Ghost is invited to a meeting by (docs/MEET.md), so where the account's service has
/// Ghost in meetings the card is on Settings › Meetings, after the meetings, and the address itself is drawn once, on
/// the invite card above it with Copy and a new one (lib/meet/ui/meet_card.dart): [addressAbove], and this card is
/// what mail to the address becomes, what the server sees of it, and off (Matt, 2026-10-24: "move all google meet
/// related stuff to under the meet section"). Account then has only a line pointing there. Before there is an address
/// it is this card that turns one on, on Meetings as it was on Account. A service with no Ghost in meetings has the
/// whole card on Account, as before.
///
/// This is the one setting where the server reads words of the person's in the clear, so the card says so in plain
/// words before it is turned on, and again under it once it is: the server reads each mail as it arrives, as any
/// mail server must, seals it to the account's key at once, and keeps only the sealed copy.
///
/// Drawn only where the service takes mail ([mailCardShown]): an older service, or one not set up for mail, has
/// nothing here to offer, and an address already on is still shown so it can be turned off.
bool mailCardShown(MailIn mail) {
  final address = mail.address;
  return address != null && (address.available || address.address != null);
}

/// What the card says under itself: what happens to a mail, in a person's words.
const String mailCardFooter =
    'Anyone with the address can send to it, so give it only where you mean to. The server reads each mail as it arrives, as any mail server must, then seals it to your account’s key at once and keeps only the sealed copy, until your next sync files it. Pictures come with it; other files are named in the note but not kept yet.';

/// The card.
class MailCard extends StatefulWidget {
  const MailCard({super.key, required this.services, this.addressAbove = false});

  final AccountServices services;

  /// The address, with Copy and a new one, is on the invite card above (Settings › Meetings), so it is not drawn here.
  final bool addressAbove;

  @override
  State<MailCard> createState() => _MailCardState();
}

class _MailCardState extends State<MailCard> {
  String? _said;
  bool _busy = false;

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      await work();
    } catch (failure) {
      if (mounted) setState(() => _said = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copy(String address) async {
    try {
      await Clipboard.setData(ClipboardData(text: address));
      if (mounted) setState(() => _said = 'The address is copied.');
    } catch (_) {
      if (mounted) setState(() => _said = address);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mail = widget.services.mailIn;
    if (mail == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: mail,
      builder: (context, _) {
        final address = mail.address?.address;
        final above = widget.addressAbove;
        return PaneSection(
          title: 'Email to a note',
          description: above && address != null ? const Text('Mail sent to your address becomes a note in your Inbox: its subject the title, its words and pictures the note.') : null,
          footer: Text(_said ?? mailCardFooter),
          children: [
            if (address == null)
              SettingRow(
                key: const ValueKey('mail-on'),
                icon: const AppIcon(Lucide.mail, size: 20),
                label: _busy ? 'Making an address…' : 'Turn on an address',
                hint: Text('Mail sent to a private address of yours becomes a note in your Inbox: its subject the title, its words and pictures the note.${above ? ' It is the address Ghost is invited to a meeting by, too.' : ''}'),
                disabled: _busy,
                onPress: () => unawaited(_run(() => mail.newAddress())),
              )
            else if (above)
              SettingRow(
                key: const ValueKey('mail-off'),
                icon: const AppIcon(Lucide.x, size: 20),
                label: 'Turn off',
                hint: const Text('Mail and invites to the address are turned away. Mail already sent is still filed.'),
                disabled: _busy,
                onPress: () => unawaited(_run(() => mail.turnOff())),
              )
            else ...[
              SettingRow(
                key: const ValueKey('mail-address'),
                icon: const AppIcon(Lucide.mail, size: 20),
                // Broken, where a phone's width must break it, after the @ and nowhere in a word.
                label: address.replaceFirst('@', '@\u200B'),
                hint: const Text('Mail sent here becomes a note in your Inbox.'),
                control: RowAction(onPress: () => unawaited(_copy(address)), child: const Text('Copy')),
              ),
              SettingRow(
                key: const ValueKey('mail-new'),
                icon: const AppIcon(Lucide.refreshCw, size: 20),
                label: 'Make a new address',
                hint: const Text('The old one stops taking mail at once.'),
                disabled: _busy,
                onPress: () => unawaited(_run(() async {
                  await mail.newAddress();
                  if (mounted) setState(() => _said = 'A new address. The old one takes no more mail.');
                })),
              ),
              SettingRow(
                key: const ValueKey('mail-off'),
                icon: const AppIcon(Lucide.x, size: 20),
                label: 'Turn off',
                hint: const Text('Mail to the address is turned away. Mail already sent is still filed.'),
                disabled: _busy,
                onPress: () => unawaited(_run(() => mail.turnOff())),
              ),
            ],
          ],
        );
      },
    );
  }
}
