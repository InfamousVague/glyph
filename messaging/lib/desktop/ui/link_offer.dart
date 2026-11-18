import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/lucide_more.dart';
import '../../kit/settings_type.dart';
import '../../ui/common.dart';
import '../../ui/computers.dart' show PairButton;
import '../platform.dart';

/// The step after a username on a computer of its own (Matt, 2026-11-18: "make setting up SMS and such and linking to
/// a phone an optional step all other processes should work without linking a phone"): texts from an Android phone,
/// offered once, with "Not now" as plain as "Link my phone". Settings › Your phone offers it again any time.
class LinkOffer extends StatelessWidget {
  const LinkOffer({super.key, required this.onLink, required this.onSkip});
  final VoidCallback onLink;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(t.space(6), t.space(8), t.space(6), t.space(6)),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: t.lenOf('4rem'),
                  height: t.lenOf('4rem'),
                  decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.lenOf('1rem')), border: Border.all(color: t.color('app-rule'))),
                  alignment: Alignment.center,
                  child: AppIcon(LucideMore.smartphone, size: 28, color: t.color('app-ink-2')),
                ),
              ),
              SizedBox(height: t.space(5)),
              Text('Texts from your phone? (optional)', style: pageText(t, t.fontSize('2xl'), weight: 'bold', color: t.color('app-ink'), height: 1.2)),
              SizedBox(height: t.space(2)),
              Text(
                'If you text from an Android phone with Ghost Messaging on it, this $computerWord can show those texts and send through it. Everything else, friends, circles, Telegram and Signal, works without a phone. You can link one any time in Settings › Your phone.',
                style: pageText(t, t.fontSize('md'), color: t.color('app-ink-2'), height: 1.45),
              ),
              SizedBox(height: t.space(8)),
              PairButton(key: const ValueKey('link-offer-link'), label: 'Link my Android phone', icon: LucideMore.qrCode, onPressed: onLink),
              SizedBox(height: t.space(3)),
              PairButton(key: const ValueKey('link-offer-skip'), label: 'Not now', icon: Lucide.arrowRight, quiet: true, onPressed: onSkip),
            ],
          ),
        ),
      ),
    );
  }
}

/// A phone has just been linked to a computer that was on its own: said for the moment before the app opens again on
/// it (restartApp).
class LinkRestarting extends StatelessWidget {
  const LinkRestarting({super.key, required this.phone});
  final String phone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const GhostSpinner(size: 24),
          SizedBox(height: t.space(4)),
          Text('Linked with $phone', style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: t.color('app-ink'))),
          SizedBox(height: t.space(1)),
          Text('Opening Ghost Messaging again with your texts…', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
        ]),
      ),
    );
  }
}
