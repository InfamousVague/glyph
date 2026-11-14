import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import 'common.dart';

/// Over every page's content, under its header, while a newer Ghost Messaging is waiting (Matt, 2026-11-13: "the
/// app should auto check for updates on load of any page so it pops the banner"): what version, Update, and a cross. The look itself is asked for
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
    HeaderEnd.changed.addListener(_place);
  }

  @override
  void dispose() {
    HeaderEnd.changed.removeListener(_place);
    _sub?.cancel();
    super.dispose();
  }

  /// Where the header of the page in front ends (HeaderEnd), and how wide that page is: looked for whenever a page
  /// says its header has moved.
  Rect? _under;

  void _place() {
    if (!mounted) return;
    final at = HeaderEnd.lowestRect();
    if (at != _under) setState(() => _under = at);
  }

  /// What the banner says, or null where there is nothing to say: no newer version, or one being looked for.
  /// [short] leaves the app's name out, for a banner no wider than the list's column.
  static String? line(UpdateState u, {bool short = false}) {
    final version = u.available;
    if (version == null || version.isEmpty) return null;
    final what = short ? version : 'Ghost Messaging $version';
    return switch (u.phase) {
      'available' => '$what is out',
      'ready' => '$what is ready to install',
      'downloading' => 'Getting $what${u.progress == null ? '' : ' · ${(u.progress! * 100).round()}%'}',
      'installing' => 'Installing $what…',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.of(context);
    final words = line(_update);
    final show = words != null && app.choice('update_dismissed', '') != _update.available;
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final busy = _update.phase == 'downloading' || _update.phase == 'installing';
    const white = Color(0xFFFFFFFF);
    // As wide as the page whose header it hangs under. Where the list stands beside a pane (a computer, a folding
    // phone opened out) that is the list's column (Matt, 2026-11-14, of the Mac: "the banner shows up in the middle
    // of the page instead of in the sidebar"): it had been laid across the whole window, half over each.
    final left = _under?.left ?? 0;
    final column = _under?.width ?? double.infinity;
    final across = column.isFinite ? column : MediaQuery.sizeOf(context).width;
    // In a column that narrow the app's name is left out, so the words and the button still fit.
    final narrow = across < t.lenOf('24rem');
    final said = line(_update, short: narrow);
    // Over the page's content and under its header (Matt, 2026-11-14: "Redo the update banner to show over the
    // content but not over the header, make it have an x button and be more colorful"): each page marks where its
    // header ends (HeaderEnd: under the title, and on the list under the search too), the banner hangs just below
    // that, and the page keeps its place. It was a bar across the very top, in the status bar's room, that pushed
    // every page down.
    return Stack(children: [
      widget.child,
      Positioned(
        top: (_under?.top ?? pad.top + t.lenOf('3.5rem')) + t.space(1),
        left: left + t.space(narrow ? 2 : 3),
        width: across - t.space(narrow ? 2 : 3) * 2,
        child: IgnorePointer(
          ignoring: !show,
          child: AnimatedSlide(
            offset: show ? Offset.zero : const Offset(0, -0.35),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: t.lenOf('34rem')),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // Indigo to violet to pink: the one thing on the page that is not the page's own colours.
                      gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFF4F5BD5), Color(0xFF8B5CF6), Color(0xFFEC4899)]),
                      borderRadius: BorderRadius.circular(t.radius('xl')),
                      boxShadow: t.shadowOf('0 8px 24px rgba(79,91,213,0.35)'),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(t.radius('xl')),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(1), t.space(2)),
                          child: Row(children: [
                            Container(
                              width: t.lenOf('2rem'),
                              height: t.lenOf('2rem'),
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x33FFFFFF)),
                              alignment: Alignment.center,
                              child: AppIcon(busy ? Lucide.download : Lucide.sparkles, size: 16, color: white, wash: false),
                            ),
                            SizedBox(width: t.space(2)),
                            Expanded(child: Text(said ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: white, height: 1.25))),
                            if (!busy)
                              GlacierPressable(
                                onPressed: () => _update.phase == 'ready' ? Sms.instance.updateInstall() : Sms.instance.updateCheck(install: true),
                                semanticLabel: 'Update now',
                                builder: (context, state) => Container(
                                  margin: EdgeInsets.only(left: t.space(2)),
                                  padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
                                  decoration: BoxDecoration(color: white.withValues(alpha: state.pressed ? 0.8 : 1), borderRadius: BorderRadius.circular(t.lenOf('1rem'))),
                                  child: Text('Update now', style: pageText(t, t.fontSize('sm'), weight: 'bold', color: const Color(0xFF4F3FC4))),
                                ),
                              ),
                            // Put away at any time, a download going on behind it or not: it stays away for this
                            // version and comes back for the next.
                            IconTap(icon: Lucide.x, label: 'Not now', size: 18, box: t.lenOf('2.5rem'), color: white, onPressed: () => app.set('update_dismissed', _update.available ?? '')),
                          ]),
                        ),
                        if (_update.phase == 'downloading')
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(widthFactor: (_update.progress ?? 0.04).clamp(0.04, 1.0), child: Container(height: 3, color: white)),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
