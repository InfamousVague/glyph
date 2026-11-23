import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../friends/buddies.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import 'common.dart';

// Vouches on screen (GMFB-33; lib/friends/vouches.dart): how many of the viewer's own friends vouch for someone, with
// their names on a tap; vouching for a friend and taking it back; and hiding the vouches one holds.

Widget _icon(LucideIcon icon) => AppIcon(icon, size: 18);

/// What a profile says of vouches: by how many of the viewer's own friends, or none.
String vouchedWords(int n, {bool mine = false}) => n == 0
    ? (mine ? 'No friends vouch for you yet' : 'None of your friends vouch for them yet')
    : 'Vouched for by $n of your friends';

/// Who the names are: "Maya, Sam and Theo".
String namesOf(List<Buddy> who) {
  final names = [for (final b in who) b.shown];
  if (names.length <= 1) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// What Vouch for says under it.
const vouchHint = 'Say this account is really them. Only your friends who are theirs too will see it.';

/// The choices on [b]'s card (a friend's): Vouch for them, or take it back.
List<Choice> vouchChoices(BuildContext context, Buddy b, {Buddies? buddies}) {
  final all = buddies ?? Buddies.instance;
  if (!all.vouchesHere || b.state != 'yes') return const [];
  final name = '@${b.username}';
  Future<void> go(bool on) async {
    try {
      await all.vouch(b, on: on);
      if (context.mounted) toast(context, on ? 'You vouched for $name' : 'You took back your vouch for $name');
    } catch (e) {
      if (context.mounted) toast(context, '$e', tone: GlacierToastTone.danger);
    }
  }

  return [
    all.vouchedFor(b)
        ? Choice('Take back your vouch for $name', Lucide.undo2, () => unawaited(go(false)), hint: 'They and your friends stop counting it')
        : Choice('Vouch for $name', Lucide.userCheck, () => unawaited(go(true)), hint: vouchHint),
  ];
}

/// The card's Vouches: the count of the viewer's friends who vouch for [b] (or for this account, where [b] is null),
/// their names shown on a tap, and whether the viewer does.
class VouchesLine extends StatefulWidget {
  const VouchesLine({super.key, this.buddy, this.buddies, required this.section});
  final Buddy? buddy;
  final Buddies? buddies;
  final Widget Function(String title, Widget child, {Key? key}) section;

  @override
  State<VouchesLine> createState() => _VouchesLineState();
}

class _VouchesLineState extends State<VouchesLine> {
  bool _names = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.buddies ?? Buddies.instance;
    return ListenableBuilder(
      listenable: all,
      builder: (context, _) {
        final t = context.tokens;
        final b = widget.buddy;
        final who = all.vouchersOf(b);
        final mine = b != null && all.vouchedFor(b);
        if (who.isEmpty && !mine) return const SizedBox.shrink();
        final ink = pageText(t, t.fontSize('sm'), color: t.color('app-ink'), height: 1.4);
        return widget.section(
          'Vouches',
          key: const ValueKey('profile-vouches'),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (who.isNotEmpty)
              GestureDetector(
                key: const ValueKey('profile-vouches-count'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _names = !_names),
                child: Text(vouchedWords(who.length, mine: b == null), style: ink.copyWith(fontWeight: FontWeight.w600)),
              ),
            if (_names && who.isNotEmpty) Text(namesOf(who), key: const ValueKey('profile-vouches-names'), style: ink.copyWith(color: t.color('app-ink-2'))),
            if (mine) Text('You vouch for them', key: const ValueKey('profile-vouches-mine'), style: ink.copyWith(color: t.color('app-ink-2'))),
          ]),
        );
      },
    );
  }
}

/// Profile › Vouches: how many of this person's friends vouch for them, and whether friends are shown them.
class VouchesSection extends StatelessWidget {
  const VouchesSection({super.key, this.buddies});
  final Buddies? buddies;

  @override
  Widget build(BuildContext context) {
    final b = buddies ?? Buddies.instance;
    return ListenableBuilder(
      listenable: b,
      builder: (context, _) {
        final who = b.vouchersOf(null);
        return PaneSection(
          title: 'Vouches',
          description: const Text('A friend can vouch that this account is really you. Each of your friends sees how many of their own friends vouch for you, never a count of everyone.'),
          children: [
            SettingRow(
              key: const ValueKey('vouches-mine'),
              icon: _icon(Lucide.userCheck),
              label: vouchedWords(who.length, mine: true),
              hint: who.isEmpty ? null : Text(namesOf(who)),
            ),
            SettingRow(
              icon: _icon(Lucide.eyeOff),
              label: 'Show friends who vouches for me',
              hint: const Text('Off, your friends see no vouches on your profile.'),
              control: GlacierSwitch(
                key: const ValueKey('vouches-show'),
                checked: !b.vouches.hidden,
                onCheckedChange: (on) => unawaited(b.hideVouches(!on)),
                ariaLabel: 'Show friends who vouches for me',
              ),
            ),
          ],
        );
      },
    );
  }
}
