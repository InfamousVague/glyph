import 'dart:async';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../desktop/ui/qr.dart';
import '../friends/add_link.dart';
import '../friends/buddies.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../me/me.dart';
import '../sms.dart';
import 'common.dart';

/// Profile › Your add-me link (GMFB-34: "A gogho.st/add/USERNAME link and QR code that opens a friend request"):
/// the link, copied or shared, and its QR code to show someone in person.
class AddMeSection extends StatelessWidget {
  const AddMeSection({super.key, required this.username});
  final String username;

  @override
  Widget build(BuildContext context) {
    final link = addMeLink(username);
    return PaneSection(
      title: 'Your add-me link',
      description: const Text('Anyone who opens it, or scans the code, can send you a friend request. You still choose whether to accept.'),
      children: [
        SettingRow(
          key: const ValueKey('add-me-copy'),
          icon: AppIcon(Lucide.link, size: 18),
          label: link.replaceFirst('https://', ''),
          hint: const Text('Copy'),
          onPress: () {
            unawaited(Clipboard.setData(ClipboardData(text: link)));
            toast(context, 'Copied your add-me link');
          },
        ),
        SettingRow(icon: AppIcon(Lucide.share2, size: 18), label: 'Share it', onPress: () => Sms.instance.shareText('Add me on Ghost Messaging', link)),
        SettingRow(key: const ValueKey('add-me-qr'), icon: AppIcon(LucideMore.qrCode, size: 18), label: 'Show the QR code', onPress: () => showAddMeCode(context, username)),
      ],
    );
  }
}

/// The add-me link as a QR code, big, to be scanned from this screen.
void showAddMeCode(BuildContext context, String username) {
  final t = context.tokens;
  showChoices(
    context,
    header: Padding(
      padding: EdgeInsets.all(t.space(4)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        QrView(key: const ValueKey('add-me-code'), data: addMeLink(username), size: t.lenOf('15rem'), label: 'Your add-me link, as a QR code'),
        SizedBox(height: t.space(3)),
        Text('@$username', style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('app-ink'))),
        Text('Scan to add me on Ghost Messaging', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
      ]),
    ),
    choices: const [],
  );
}

/// Someone's add-me link was opened: asked whether to send them a friend request, then sent.
void askToAdd(BuildContext context, String link) {
  final name = addLinkUsername(link);
  if (name == null) return toast(context, 'That add-me link isn\'t complete. Ask for it again.', tone: GlacierToastTone.danger);
  final me = Me.instance;
  if (me.username == name) return toast(context, 'That\'s your own add-me link.');
  final b = Buddies.instance;
  final had = b.all.where((x) => x.username == name).firstOrNull;
  if (had?.state == 'yes') return toast(context, 'You and @$name are friends already.');
  if (me.username == null) return toast(context, 'Choose a username first (Settings › Me › Profile), then open the link again.');
  showChoices(context, title: 'Send @$name a friend request?', choices: [
    Choice('Send a friend request', Lucide.userPlus, () async {
      try {
        final got = await b.add(name);
        if (context.mounted) toast(context, got.state == 'yes' ? 'You and @$name are friends' : 'Asked @$name');
      } catch (e) {
        if (context.mounted) toast(context, '$e', tone: GlacierToastTone.danger);
      }
    }),
  ]);
}
