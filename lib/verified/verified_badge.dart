/// A verified page's badge, and Verify… in its More sheet (lib/verified/verified.dart says what a verified page is;
/// Matt, 2026-10-30: "add all 12").
///
/// - **The badge** sits at the top of the page, under its title's place in the header, where the byline is
///   (lib/note/byline.dart): a shield and "Verified by Matt · until Dec 1" in green, the same in amber within a week
///   of its last day, and "Needs review" in the grey of the third ink once it has run out. A page edited since it was
///   verified says "edited since verified" after it, in the third ink, until someone verifies it again. Pressed, it
///   opens the More sheet, where Verify… is (behind More… in simple mode).
/// - **Verify…** sets who vouches for it - you unless you pick another of the team - and for how long, 30, 90 or 180
///   days, and writes the front matter through the editor as one step; Verify again and Take it off are there once it
///   is verified.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../core/days.dart' show isoDay, isoDayAfter;
import '../sheet/css.dart';
import '../sheet/kit.dart';
import 'verified.dart';

/// The badge's ink for where a page stands: green, amber, or the third ink.
String verifiedInk(VerifiedStanding standing) => switch (standing) {
      VerifiedStanding.fresh => 'glacier-green-11',
      VerifiedStanding.soon => 'glacier-amber-11',
      VerifiedStanding.expired => 'app-ink-3',
    };

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.verified, required this.edited, required this.today, this.start, this.onPress});

  final Verified verified;

  /// Whether the words have changed since it was verified.
  final bool edited;
  final DateTime today;

  /// The column's own left edge, where it is not the page's gutter (a page to read, from 600px), as the byline's.
  final double? start;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final standing = verifiedStanding(verified, today);
    final ink = t.color(verifiedInk(standing));
    final words = verifiedWords(verified, today);
    final label = edited ? '$words, edited since verified' : words;
    final badge = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 0.4 * sm,
      children: [
        AppIcon(standing == VerifiedStanding.expired ? Lucide.circleAlert : Lucide.shieldCheck, size: sm * 1.1, strokeWidth: 2.2, color: ink),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: words, style: pageText(t, sm, weight: 'medium', color: ink)),
                if (edited) TextSpan(text: ' · edited since verified', style: pageText(t, sm, color: t.color('app-ink-3'))),
              ],
            ),
            maxLines: 2,
          ),
        ),
      ],
    );
    return Padding(
      key: const ValueKey('verified-badge'),
      padding: EdgeInsets.only(left: start ?? t.len('app-gutter'), right: t.len('app-gutter'), top: t.space(2)),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          button: onPress != null,
          label: label,
          child: ExcludeSemantics(
            child: onPress == null
                ? badge
                : GlacierPressable(
                    onPressed: onPress,
                    builder: (context, state) => Opacity(opacity: state.pressed ? 0.6 : 1, child: badge),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Verify…'s row on the More sheet: what it says under its name.
String verifyHint(Verified? verified, bool edited, DateTime today) {
  if (verified == null) return 'Mark it as the team’s current truth, for a while.';
  final words = verifiedWords(verified, today);
  return edited ? '$words · edited since verified' : words;
}

/// Verify…'s page: who vouches for it, for how long, and the press that writes it.
class VerifyPage extends StatefulWidget {
  const VerifyPage({super.key, required this.owners, required this.me, required this.verified, required this.edited, required this.today, required this.onVerify, required this.onRemove, required this.close});

  /// Who can vouch for it: you first, then the organization's members in a team's note.
  final List<String> owners;
  final String me;
  final Verified? verified;
  final bool edited;
  final DateTime today;
  final void Function(String by, int days) onVerify;
  final VoidCallback onRemove;

  /// The sheet closed, after a press.
  final VoidCallback close;

  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  late String _by = widget.verified?.by ?? widget.me;
  int _days = 90;

  @override
  Widget build(BuildContext context) {
    final verified = widget.verified;
    final owners = <String>[widget.me, for (final owner in widget.owners) if (owner.toLowerCase() != widget.me.toLowerCase()) owner];
    if (!owners.any((owner) => owner.toLowerCase() == _by.toLowerCase())) owners.add(_by);
    final day = isoDay(widget.today);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetNote(verified == null
            ? 'A verified page is the team’s current truth: its owner vouches for it until a day, and is told when that day has passed.'
            : verifyHint(verified, widget.edited, widget.today)),
        const SheetHeading('Owner'),
        SheetGroup(
          children: [
            for (final owner in owners)
              SheetRow(
                key: ValueKey('verify-owner-$owner'),
                icon: const AppIcon(Lucide.userRound, size: 18, strokeWidth: 2),
                label: owner.toLowerCase() == widget.me.toLowerCase() ? '${ownerShown(owner)} (you)' : ownerShown(owner),
                chosen: owner.toLowerCase() == _by.toLowerCase(),
                onPress: () => setState(() => _by = owner),
              ),
          ],
        ),
        const SheetHeading('For'),
        SheetGroup(
          children: [
            for (final days in verifyPeriods)
              SheetRow(
                key: ValueKey('verify-days-$days'),
                icon: const AppIcon(Lucide.calendarDays, size: 18, strokeWidth: 2),
                label: '$days days',
                hint: 'Until ${untilShown(isoDayAfter(day, days)!, widget.today)}',
                chosen: days == _days,
                onPress: () => setState(() => _days = days),
              ),
          ],
        ),
        SheetGroup(
          children: [
            SheetRow(
              key: const ValueKey('verify-now'),
              icon: const AppIcon(Lucide.shieldCheck, size: 18, strokeWidth: 2),
              label: verified == null ? 'Verify' : 'Verify again',
              hint: 'By ${ownerShown(_by)}, until ${untilShown(isoDayAfter(day, _days)!, widget.today)}.',
              onPress: () {
                widget.onVerify(_by, _days);
                widget.close();
              },
            ),
          ],
        ),
        if (verified != null)
          SheetGroup(
            children: [
              SheetRow(
                key: const ValueKey('verify-remove'),
                label: 'Take the verification off',
                danger: true,
                onPress: () {
                  widget.onRemove();
                  widget.close();
                },
              ),
            ],
          ),
      ],
    );
  }
}
