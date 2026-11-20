/// Souls, the app's points (Matt, 2026-11-19: "Build a new points system into the app called souls, right now they will
/// not have any use but I want to be able to give them out as rewards to people who submit bugs, display the points in
/// the top bar next to the feedback button with a flame icon next to them").
///
/// The relay keeps each person's souls (relay/lib/handles.dart); they are given from the admin page
/// (lib/ui/admin_page.dart) and told to the person as they are given (Me.souls, Me.gifts). Here: the count with its
/// flame in the list's top bar, and a sheet about them under it.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/semantic_colors.dart';
import '../kit/settings_type.dart';
import '../me/me.dart';
import 'common.dart';
import 'dialup/bevel.dart' show isBevelChrome;
import 'nav_bar.dart' show HoverTip;
import 'special_badges.dart';

/// The flame's colour.
const soulsFlame = Color(0xFFF2762E);

/// 1234 as "1,234", 12 500 as "12.5k".
String soulsCount(int n) {
  if (n >= 10000) {
    final k = n / 1000;
    return '${k >= 100 ? k.round() : (k * 10).round() / 10}k'.replaceAll('.0k', 'k');
  }
  final s = '$n';
  return s.length > 3 ? '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}' : s;
}

/// The count of souls with its flame, round like the top bar's other buttons, beside Share feedback. A press says
/// what souls are. Souls given while the app is open are said as they come.
class SoulsChip extends StatefulWidget {
  const SoulsChip({super.key, this.side, this.onOpen});

  /// How tall it is: the bar's buttons' height, unless a strip says less (the Mac's title strip).
  final double? side;

  /// What a press does, where the sheet must open on a navigator below the chip (the Mac's title strip).
  final VoidCallback? onOpen;

  @override
  State<SoulsChip> createState() => _SoulsChipState();
}

class _SoulsChipState extends State<SoulsChip> {
  @override
  void initState() {
    super.initState();
    Me.instance.gifts.addListener(_gift);
  }

  @override
  void dispose() {
    Me.instance.gifts.removeListener(_gift);
    super.dispose();
  }

  void _gift() {
    final g = Me.instance.gifts.value;
    if (g == null || !mounted) return;
    Me.instance.gifts.value = null;
    final badge = g.badge == null ? null : specialBadge(g.badge!);
    final words = badge != null
        ? 'You were given the ${badge.name} badge'
        : g.souls > 0
            ? 'You got ${soulsCount(g.souls)} ${g.souls == 1 ? 'soul' : 'souls'}${g.why.isEmpty ? '' : ': ${g.why}'}'
            : '${soulsCount(-g.souls)} ${g.souls == -1 ? 'soul was' : 'souls were'} taken back';
    // Above the app's pages (the Mac's title strip) there may be nothing to toast on: then the count says it alone.
    try {
      toast(context, words);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: Me.instance,
      builder: (context, _) {
        final n = Me.instance.souls;
        final label = '${soulsCount(n)} ${n == 1 ? 'soul' : 'souls'}';
        void open() => widget.onOpen != null ? widget.onOpen!() : showSouls(context);
        if (isBevelChrome(t)) {
          return IconTap(key: const ValueKey('souls'), icon: Lucide.flame, label: label, onPressed: open);
        }
        final side = widget.side ?? t.len('glacier-control-height-md');
        return HoverTip(
          message: label,
          below: true,
          end: true,
          child: GlacierPressable(
            key: const ValueKey('souls'),
            onPressed: open,
            semanticLabel: label,
            builder: (context, state) => GlacierFocusRing(
              visible: state.focused,
              radius: t.radius('full'),
              child: Container(
                height: side,
                constraints: BoxConstraints(minWidth: side),
                padding: EdgeInsets.symmetric(horizontal: t.space(3)),
                decoration: BoxDecoration(
                  color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'),
                  borderRadius: BorderRadius.circular(side / 2),
                  border: Border.all(color: t.color('app-rule')),
                ),
                alignment: Alignment.center,
                child: ExcludeSemantics(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const AppIcon(Lucide.flame, size: 16, strokeWidth: 2.2, wash: false, color: soulsFlame),
                    SizedBox(width: t.space(1)),
                    Text(soulsCount(n), style: pageText(t, t.fontSize('sm'), weight: 'bold', color: t.color('app-ink'))),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What souls are, how many this person has, and their badges.
Future<void> showSouls(BuildContext context) {
  return Navigator.of(context).push<void>(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: context.tokens.sheetScrim,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => const SoulsSheet(),
    transitionsBuilder: (context, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}

class SoulsSheet extends StatelessWidget {
  const SoulsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space(3), 0, t.space(3), pad.bottom + t.space(3)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: t.lenOf('26rem')),
          child: Container(
            key: const ValueKey('souls-sheet'),
            padding: EdgeInsets.all(t.space(5)),
            decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('xl'))),
            child: ListenableBuilder(
              listenable: Me.instance,
              builder: (context, _) {
                final n = Me.instance.souls;
                final badges = specialBadgesOf(Me.instance.special);
                return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const AppIcon(Lucide.flame, size: 30, strokeWidth: 2, wash: false, color: soulsFlame),
                    SizedBox(width: t.space(2)),
                    Text(soulsCount(n), style: pageText(t, t.fontSize('3xl'), weight: 'bold', color: t.color('app-ink'), height: 1.1)),
                    SizedBox(width: t.space(2)),
                    Text(n == 1 ? 'soul' : 'souls', style: pageText(t, t.fontSize('lg'), color: t.color('app-ink-2'))),
                  ]),
                  SizedBox(height: t.space(3)),
                  Text(
                    'Souls are Ghost Messaging\'s thank-you for helping make it better. Report a bug with Share feedback and say your username, and you may be given some.',
                    style: pageText(t, t.fontSize('md'), color: t.color('app-ink-2'), height: 1.45),
                  ),
                  SizedBox(height: t.space(2)),
                  Text('They can\'t be spent on anything yet. Keep them: they will be.', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'), height: 1.4)),
                  if (badges.isNotEmpty) ...[
                    SizedBox(height: t.space(4)),
                    Text('YOUR BADGES', style: pageText(t, t.fontSize('xs'), weight: 'bold', color: t.color('app-ink-3'))),
                    SizedBox(height: t.space(2)),
                    Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [for (final b in badges) SpecialBadgeChip(badge: b)]),
                  ],
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}
