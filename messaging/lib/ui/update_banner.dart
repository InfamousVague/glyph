import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import 'common.dart';

/// Over every page while a newer Ghost Messaging is waiting (Matt, 2026-11-13: "the app should auto check for
/// updates on load of any page so it pops the banner"): what version, and Update now. The look itself is asked for
/// as each page opens ([UpdateWatch]); this draws what it found. Put away with its cross, it stays away for that
/// version and comes back for the next.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key, required this.child});
  final Widget child;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  UpdateState _update = const UpdateState();
  StreamSubscription<UpdateState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Sms.instance.updates.stream.listen((u) {
      if (mounted) setState(() => _update = u);
    });
    Sms.instance.update().then((u) {
      if (mounted) setState(() => _update = u);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// What the banner says, or null where there is nothing to say: no newer version, or one being looked for.
  static String? line(UpdateState u) {
    final version = u.available;
    if (version == null || version.isEmpty) return null;
    return switch (u.phase) {
      'available' => 'Ghost Messaging $version is out',
      'ready' => 'Ghost Messaging $version is ready to install',
      'downloading' => 'Getting Ghost Messaging $version${u.progress == null ? '' : ' · ${(u.progress! * 100).round()}%'}',
      'installing' => 'Installing Ghost Messaging $version…',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.of(context);
    final words = line(_update);
    final show = words != null && app.choice('update_dismissed', '') != _update.available;
    if (!show) return widget.child;
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final busy = _update.phase == 'downloading' || _update.phase == 'installing';
    final paper = t.color('app-paper');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ColoredBox(
        color: t.color('app-ink'),
        child: Padding(
          padding: EdgeInsets.fromLTRB(t.space(4), pad.top + t.space(1), t.space(1), t.space(1)),
          child: Row(children: [
            AppIcon(Lucide.download, size: 16, color: paper, wash: false),
            SizedBox(width: t.space(2)),
            Expanded(child: Text(words, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: paper))),
            if (!busy)
              GlacierPressable(
                onPressed: () => _update.phase == 'ready' ? Sms.instance.updateInstall() : Sms.instance.updateCheck(install: true),
                semanticLabel: 'Update now',
                builder: (context, state) => Container(
                  margin: EdgeInsets.symmetric(horizontal: t.space(1)),
                  padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                  decoration: BoxDecoration(color: paper.withValues(alpha: state.pressed ? 0.75 : 1), borderRadius: BorderRadius.circular(t.lenOf('1rem'))),
                  child: Text('Update now', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink'))),
                ),
              ),
            if (!busy) IconTap(icon: Lucide.x, label: 'Not now', size: 16, box: t.lenOf('2.25rem'), color: paper, onPressed: () => app.set('update_dismissed', _update.available ?? '')),
          ]),
        ),
      ),
      // The banner has taken the status bar's room: the page under it starts at its own top.
      Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child)),
    ]);
  }
}

/// Asks for a look for a newer version each time a page opens or is come back to. Android answers no oftener than
/// every five minutes (Updater.pageCheck), so walking through the app is one question to the site, not one a page.
class UpdateWatch extends NavigatorObserver {
  void _look(Route<dynamic>? route) {
    if (route is PageRoute) Sms.instance.updateOnPage().catchError((_) {});
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _look(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _look(previousRoute);
}
