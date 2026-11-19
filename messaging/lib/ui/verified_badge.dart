import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide_more.dart';
import '../me/verified_numbers.dart';

/// The verified-number badge beside someone's name in a space, a circle's members or their profile card (Matt,
/// 2026-11-19: "add the verfied by number badge as a default feature"; lib/me/verified_numbers.dart): drawn where the
/// relay says they verified a phone number by a texted code ([me]: where you verified yours); nothing otherwise, and
/// nothing while it is being asked.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.id, this.username, this.me = false, this.size = 14, this.numbers});
  final String id;
  final String? username;
  final bool me;
  final double size;
  final VerifiedNumbers? numbers;

  @override
  Widget build(BuildContext context) {
    final n = numbers ?? VerifiedNumbers.instance;
    return ListenableBuilder(
      listenable: n,
      builder: (context, _) {
        final yes = me ? n.mine : n.of(id, username: username) == true;
        if (!yes) return const SizedBox.shrink();
        final t = context.tokens;
        return Padding(
          key: ValueKey('verified-$id'),
          padding: EdgeInsets.only(left: t.space(1)),
          child: Semantics(label: 'Verified phone number', child: AppIcon(LucideMore.badgeCheck, size: size, color: t.color('app-accent'))),
        );
      },
    );
  }
}
