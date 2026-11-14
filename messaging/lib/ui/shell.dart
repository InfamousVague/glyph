import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../kit/settings_type.dart';
import '../sms.dart';
import 'common.dart';
import 'compose.dart';
import 'conversations.dart';
import 'settings.dart';
import 'thread.dart';

/// The app's one frame, on the phone and on a computer alike (Matt, 2026-11-14: "Unify the UI experience to match on
/// desktop and mac as well the desktop app should get all featues its missing from mobile and thr mobile app should
/// gain the nav from desktop").
///
/// The list of conversations (lib/ui/conversations.dart) and, beside it, a pane for what is opened from it: a
/// conversation, a new message, Settings. In a window [wideAt] wide or wider (a computer's, a tablet's, a folding
/// phone opened out) both are on the screen, the list down the side as the Mac's first had it; the conversation
/// open is marked in the list and draws no way back, since there is nowhere to go back to. In a narrower one (a
/// phone, a folding phone's cover) the list is the screen and what is opened slides over it, with its way back.
///
/// It is the same list and the same pane either way, each kept where it is as the window changes: a conversation
/// open on a folding phone's cover, a message half written in it, is still open and half written when the phone is
/// opened out, with the list now beside it.
///
/// Both are navigators. What a page in the pane opens (a contact's page, a picture, a sheet) opens over it in the
/// pane; the Archived list opens over the list in the list's place. Android's back closes what is in the pane
/// first, then goes back in the list, then leaves the app.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.foot, this.nothing, this.settings, this.paneObservers = const []});

  /// Kept under the list: on a computer, how the phone is connected.
  final Widget? foot;

  /// What the pane says while nothing is open in it and the window is wide. "Choose a conversation" where not given.
  final WidgetBuilder? nothing;

  /// The Settings page, and one section of it where a name is given. The phone's own where not given.
  final Widget Function(BuildContext context, String? section)? settings;

  /// Told of the pages that open in the pane: the look for a newer version (lib/ui/update_banner.dart).
  final List<NavigatorObserver> paneObservers;

  /// How wide a window is, in logical pixels, before the list and the pane stand side by side. A phone held
  /// upright is 360 to 430; a folding phone opened out is 700 or more.
  static const wideAt = 640.0;

  /// How much of a wide window the list takes: as the Mac's has it, less where the window is only just wide.
  static double sideWidth(double width) => (width * 0.4).clamp(280.0, 340.0);

  /// The shell this page is in, to open things with; null on a page shown with none (a test of one screen).
  static AppShellState? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<_ShellScope>()?.shell;

  /// Whether the list and the pane are side by side. The page asking is built again when that changes.
  static bool wideOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ShellScope>()?.wide ?? false;

  /// The conversation open in the pane, or null. The page asking is built again when that changes.
  static int? threadOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ShellScope>()?.thread;

  /// What is kept under the list ([foot]), or null.
  static Widget? footOf(BuildContext context) => context.getInheritedWidgetOfExactType<_ShellScope>()?.shell.widget.foot;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  final _pane = GlobalKey<NavigatorState>();
  final _side = GlobalKey<NavigatorState>();

  /// The page open in the pane, and the conversation it is where it is one. Null: nothing is open.
  PageRouteBuilder<void>? _open;
  int? _thread;

  bool _wide = false;

  /// Whether Android's back has something to close in the pane, and something to go back from in the list.
  bool _paneBack = false;
  bool _sideBack = false;

  /// Told each time the pane's page closes or gives way to another: the list reads its conversations again, as it
  /// did on a phone whenever a conversation was come back from.
  final closed = ValueNotifier<int>(0);

  /// The conversation open in the pane, or null.
  int? get thread => _thread;

  /// Whether the list and the pane are side by side.
  bool get wide => _wide;

  @override
  void dispose() {
    closed.dispose();
    super.dispose();
  }

  PageRouteBuilder<void> _route(Widget page) => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, _, _) => _PanePage(child: page),
        // Beside the list a page takes the place of the last one, so it fades in; over the list it slides across
        // it, as a phone's pages do.
        transitionsBuilder: (context, a, _, child) => AppShell.wideOf(context)
            ? FadeTransition(opacity: CurvedAnimation(parent: a, curve: const Interval(0, 0.55)), child: child)
            : SlideTransition(
                position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
                child: child,
              ),
      );

  /// Opens [page] in the pane, in place of whatever was there. [thread] is the conversation it is, for the list to
  /// mark.
  void show(Widget page, {int? thread}) {
    final nav = _pane.currentState;
    if (nav == null) {
      // Asked for before the first frame (a notification that opened the app): once there is a pane.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pane.currentState != null) show(page, thread: thread);
      });
      return;
    }
    final route = _route(page);
    final had = _open != null;
    setState(() {
      _open = route;
      _thread = thread;
    });
    nav.pushAndRemoveUntil(route, (r) => r.isFirst);
    // The list under a page that covers it is not drawn, and is drawn again as the page starts to leave.
    route.animation?.addStatusListener((_) {
      if (mounted && _open == route) setState(() {});
    });
    route.popped.then((_) {
      if (!mounted || _open != route) return;
      setState(() {
        _open = null;
        _thread = null;
      });
      closed.value++;
    });
    if (had) closed.value++;
  }

  /// Opens a conversation. One already open is left as it is, with whatever is half written in it.
  void openThread(int thread, List<Person> people, {String? draft}) {
    if (_thread == thread && _open != null && _open!.isCurrent && draft == null) return;
    show(ThreadScreen(key: ValueKey('thread-$thread-${draft == null ? '' : draft.hashCode}'), thread: thread, people: people, draft: draft), thread: thread);
  }

  /// Opens the new-message page, [body] already written where another app sent some words to text.
  void compose({String? body}) => show(ComposeScreen(key: UniqueKey(), body: body));

  /// Opens Settings, or the one [section] of it.
  void settings([String? section]) {
    final own = widget.settings;
    show(own != null ? own(context, section) : (section == null ? const SettingsScreen() : SettingsSectionScreen(section)));
  }

  /// Closes what is open in the pane.
  void close() => _pane.currentState?.popUntil((r) => r.isFirst);

  /// Takes the list back to the conversations, from Archived.
  void home() => _side.currentState?.popUntil((r) => r.isFirst);

  Widget _sized(Widget child) => LayoutBuilder(
        // The screens measure themselves against the screen they are on: here that is their share of the window.
        builder: (context, box) => MediaQuery(data: MediaQuery.of(context).copyWith(size: Size(box.maxWidth, box.maxHeight)), child: child),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= AppShell.wideAt;
      _wide = wide;
      final side = wide ? AppShell.sideWidth(box.maxWidth) : box.maxWidth;
      // A page that has finished sliding over the list covers all of it.
      final covered = !wide && _open != null && _open!.animation?.status == AnimationStatus.completed;
      return _ShellScope(
        shell: this,
        wide: wide,
        thread: _open == null ? null : _thread,
        child: PopScope(
          canPop: !(_paneBack || _sideBack),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            // What is open closes first; then the list goes back from Archived, or stops choosing.
            (_paneBack ? _pane : _side).currentState?.maybePop();
          },
          child: ColoredBox(
            color: t.color('glacier-bg'),
            child: Stack(children: [
              Positioned(
                key: const ValueKey('shell-side'),
                left: 0,
                top: 0,
                bottom: 0,
                width: side,
                child: Offstage(
                  offstage: covered,
                  child: TickerMode(
                    enabled: !covered,
                    child: HeaderCover(
                      covered: !wide && _open != null,
                      child: _sized(NotificationListener<NavigationNotification>(
                        onNotification: (n) {
                          if (n.canHandlePop != _sideBack) setState(() => _sideBack = n.canHandlePop);
                          return false;
                        },
                        child: Navigator(
                          key: _side,
                          onGenerateRoute: (_) => PageRouteBuilder<void>(pageBuilder: (context, _, _) => const ConversationsScreen()),
                        ),
                      )),
                    ),
                  ),
                ),
              ),
              if (wide) Positioned(key: const ValueKey('shell-rule'), left: side, top: 0, bottom: 0, width: 1, child: ColoredBox(color: t.color('app-rule'))),
              Positioned(
                key: const ValueKey('shell-pane'),
                left: wide ? side + 1 : 0,
                top: 0,
                bottom: 0,
                right: 0,
                // With nothing open on a narrow screen the pane is empty air over the list: touches go through.
                child: IgnorePointer(
                  ignoring: !wide && _open == null,
                  child: _sized(NotificationListener<NavigationNotification>(
                    onNotification: (n) {
                      if (n.canHandlePop != _paneBack) setState(() => _paneBack = n.canHandlePop);
                      return false;
                    },
                    child: Navigator(
                      key: _pane,
                      observers: widget.paneObservers,
                      onGenerateRoute: (_) => PageRouteBuilder<void>(opaque: false, pageBuilder: (context, _, _) => const _Base()),
                    ),
                  )),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

class _ShellScope extends InheritedWidget {
  const _ShellScope({required this.shell, required this.wide, required this.thread, required super.child});
  final AppShellState shell;
  final bool wide;
  final int? thread;

  @override
  bool updateShouldNotify(_ShellScope old) => old.wide != wide || old.thread != thread;
}

/// A page open in the pane: it draws its way back only while the list is not beside it.
class _PanePage extends StatelessWidget {
  const _PanePage({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => PaneRoot(isBeside: AppShell.wideOf(context), child: child);
}

/// Under every page in the pane. Beside the list it is what the pane says with nothing open; over the list it is
/// nothing at all, and the list is seen through it.
class _Base extends StatelessWidget {
  const _Base();

  @override
  Widget build(BuildContext context) {
    if (!AppShell.wideOf(context)) return const SizedBox.expand();
    final own = AppShell.maybeOf(context)?.widget.nothing;
    return own != null ? own(context) : const _Nothing();
  }
}

/// The pane before a conversation is chosen.
class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(t.space(6)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GhostLogo(size: t.lenOf('3.5rem')),
            SizedBox(height: t.space(4)),
            Text('Choose a conversation', textAlign: TextAlign.center, style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: t.color('app-ink-2'))),
            SizedBox(height: t.space(1)),
            Text('Or start a new one with the button over the list.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
          ]),
        ),
      ),
    );
  }
}
