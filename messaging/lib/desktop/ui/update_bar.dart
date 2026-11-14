import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../kit/settings_type.dart';
import '../desk.dart';
import '../updates.dart';

/// What the Mac app says of its own updates in a line (lib/desktop/updates.dart), for Settings and for the bar.
String updateLine(MacUpdates u) {
  final version = u.release?.version ?? '';
  return switch (u.phase) {
    MacUpdatePhase.idle => u.checked == null ? 'Not looked for yet' : 'Up to date',
    MacUpdatePhase.checking => 'Looking for a newer version…',
    MacUpdatePhase.downloading => u.progress >= 1 ? 'Putting Ghost Messaging $version in place…' : 'Getting Ghost Messaging $version · ${(u.progress * 100).round()}%',
    MacUpdatePhase.ready => 'Ghost Messaging $version is ready',
    MacUpdatePhase.restarting => 'Restarting as Ghost Messaging $version…',
    MacUpdatePhase.manual => 'Ghost Messaging $version is out, and this copy can\'t update itself. ${u.problem ?? ''}'.trim(),
    MacUpdatePhase.failed => 'The update didn\'t come: ${u.problem ?? 'no reason given'}. It is tried again later.',
  };
}

/// Over every page of the Mac app while a newer version is in place: what it is, and Restart to update. Quitting
/// the app swaps it in as well, so the bar is an offer, not a chore.
class DeskUpdateBar extends StatelessWidget {
  const DeskUpdateBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final updates = DeskScope.of(context).updates;
    if (updates == null) return child;
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final phase = updates.phase;
        if (phase != MacUpdatePhase.ready && phase != MacUpdatePhase.restarting && phase != MacUpdatePhase.manual) return child;
        final t = context.tokens;
        final paper = t.color('app-paper');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ColoredBox(
            color: t.color('app-ink'),
            child: Padding(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(1), t.space(2), t.space(1)),
              child: Row(children: [
                AppIcon(Lucide.download, size: 16, color: paper, wash: false),
                SizedBox(width: t.space(2)),
                Expanded(child: Text(updateLine(updates), maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: paper))),
                if (phase == MacUpdatePhase.ready)
                  GlacierPressable(
                    onPressed: updates.restart,
                    semanticLabel: 'Restart to update',
                    builder: (context, state) => Container(
                      margin: EdgeInsets.symmetric(vertical: t.space(1)),
                      padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                      decoration: BoxDecoration(color: paper.withValues(alpha: state.pressed ? 0.75 : 1), borderRadius: BorderRadius.circular(t.lenOf('1rem'))),
                      child: Text('Restart to update', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink'))),
                    ),
                  )
                else
                  SizedBox(height: t.lenOf('2.75rem')),
              ]),
            ),
          ),
          Expanded(child: child),
        ]);
      },
    );
  }
}
