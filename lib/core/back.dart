import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A handler on the back stack: true if it took the gesture.
typedef BackCallback = bool Function();

/// The phone's back gesture, answered by the app: the stack of closers of the web app's core/back.ts.
///
/// An open note, Settings, a pane inside it, a menu: each puts a handler on the stack while it is up ([onBack], or
/// the [OnBack] widget), and a back gesture is a walk down the stack, newest first, the first handler to take it
/// winning ([goBack]). Handlers stack in the order they register, which is opening order, so the newest thing on
/// screen is the first thing a back gesture dismisses.
///
/// [tookBack] is what the system is told (`tookBack` there): the gesture is stepped back through the stack and
/// always counts as used, so a back gesture never puts the app behind the home screen (Matt: "don't leave the app
/// with a back swipe ever"); the home gesture is the way out. A gesture that lands within half a second of
/// [markSteppedBack] is the same swipe the page has already stepped back on, and is answered without stepping again.
///
/// Differs from the web: the stack is an object rather than a module's own list, so a test can make one; the app's
/// is [backStack]. It tells its listeners when a handler comes or goes, which [BackScope] needs to say whether the
/// system may take a gesture itself.
class BackStack extends ChangeNotifier {
  BackStack({int Function()? now}) : _now = now ?? _clock;

  static int _clock() => DateTime.now().millisecondsSinceEpoch;

  final int Function() _now;
  final List<BackCallback> _handlers = [];

  /// `SAME_SWIPE_MS`.
  static const int sameSwipeMs = 500;
  int? _steppedAt;

  /// How many handlers are up.
  int get depth => _handlers.length;

  /// Puts a handler on top of the stack; returns its unregister.
  VoidCallback onBack(BackCallback handler) {
    _handlers.add(handler);
    notifyListeners();
    return () {
      if (_handlers.remove(handler)) notifyListeners();
    };
  }

  /// Runs the newest handler that wants the gesture. True if one took it.
  bool goBack() {
    for (var i = _handlers.length - 1; i >= 0; i--) {
      if (i < _handlers.length && _handlers[i]()) return true;
    }
    return false;
  }

  /// A swipe the app has just stepped back on itself: the system's gesture that follows it is the same one.
  void markSteppedBack() => _steppedAt = _now();

  /// What the system is told: the gesture is stepped back through the stack, and always counts as used.
  bool tookBack() {
    final stepped = _steppedAt;
    if (stepped != null && _now() - stepped < sameSwipeMs) return true;
    goBack();
    return true;
  }
}

/// The app's one back stack.
final BackStack backStack = BackStack();

/// Installs the app's answer to the system's back gesture and to Escape, over [child] (`installBack`, core/back.ts).
/// Put it once, under the app's navigator and over every screen.
///
/// The web app's activity asked the page through `window.__glyph.back`; here the route this is in is told it may
/// not pop (a [PopEntry], as [PopScope] is one), so Android hands the gesture to the app, and the gesture walks
/// [stack]. Escape walks it too, and keeps the honest answer: a key nothing took is left to whatever else listens.
///
/// Overlays close before screens change in two ways. A sheet or a menu of the app's registers on the stack after the
/// screen under it, so it is the first to be asked. And something that answers back for itself - the kit's menu,
/// popover and palette each hold a [PopScope] of their own while open - is left to it: when another entry of the
/// route refuses the pop, this one stands down for that gesture, where both would otherwise step back at once.
///
/// [leavesAtRoot] false is the web app's rule: with nothing on the stack the gesture is still used, and the app
/// stays. True lets the system take a gesture the stack has nothing for, which puts the app behind the home screen.
///
/// Differs from the web: in a tree with no navigator the binding's own `didPopRoute` is answered instead.
class BackScope extends StatefulWidget {
  const BackScope({super.key, this.stack, this.leavesAtRoot = false, required this.child});

  /// The stack to walk; the app's own ([backStack]) unless a test brings one.
  final BackStack? stack;
  final bool leavesAtRoot;
  final Widget child;

  /// The stack in force at [context]: the nearest [BackScope]'s, or the app's.
  static BackStack of(BuildContext context) => context.getInheritedWidgetOfExactType<_BackStackScope>()?.stack ?? backStack;

  @override
  State<BackScope> createState() => _BackScopeState();
}

class _BackScopeState extends State<BackScope> with WidgetsBindingObserver implements PopEntry<Object?> {
  final _CanPop _canPop = _CanPop();
  ModalRoute<Object?>? _route;
  BackStack? _listening;

  BackStack get _stack => widget.stack ?? backStack;

  @override
  ValueListenable<bool> get canPopNotifier => _canPop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addLateKeyEventHandler(_onKey);
    _listen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    _route?.unregisterPopEntry(this);
    _route = route;
    route?.registerPopEntry(this);
  }

  @override
  void didUpdateWidget(BackScope old) {
    super.didUpdateWidget(old);
    _listen();
  }

  void _listen() {
    final stack = _stack;
    if (!identical(stack, _listening)) {
      _listening?.removeListener(_sync);
      _listening = stack..addListener(_sync);
    }
    _sync();
  }

  /// Whether the system may take a gesture itself: only where the app may be left, with nothing up to close.
  void _sync() => _canPop.set(widget.leavesAtRoot && _stack.depth == 0);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeLateKeyEventHandler(_onKey);
    _listening?.removeListener(_sync);
    _route?.unregisterPopEntry(this);
    _canPop.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    return _stack.goBack() ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop) return;
    // Asked of the route with this entry standing aside: something else that refuses the pop has the gesture.
    final route = _route;
    if (route != null) {
      _canPop.aside = true;
      final others = route.popDisposition == RoutePopDisposition.doNotPop;
      _canPop.aside = false;
      if (others) return;
    }
    _stack.tookBack();
  }

  @override
  // ignore: deprecated_member_use
  void onPopInvoked(bool didPop) {}

  /// Back where there is no route to ask: a tree with no navigator.
  @override
  Future<bool> didPopRoute() async {
    if (_route != null) return false;
    if (widget.leavesAtRoot && _stack.depth == 0) return false;
    return _stack.tookBack();
  }

  @override
  Widget build(BuildContext context) => _BackStackScope(stack: _stack, child: widget.child);
}

/// Whether the route may pop, as this scope says it; `aside` answers yes without telling anyone, for the one
/// question [_BackScopeState.onPopInvokedWithResult] asks of the route.
class _CanPop extends ChangeNotifier implements ValueListenable<bool> {
  bool _value = false;
  bool aside = false;

  @override
  bool get value => aside || _value;

  void set(bool next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }
}

class _BackStackScope extends InheritedWidget {
  const _BackStackScope({required this.stack, required super.child});
  final BackStack stack;

  @override
  bool updateShouldNotify(_BackStackScope old) => !identical(old.stack, stack);
}

/// While [active], a back gesture runs [onBack] and is taken (`useBack(active, close)`, core/back.ts): the screen
/// case in one widget, saying whether it is showing and what leaving it means.
class OnBack extends StatefulWidget {
  const OnBack({super.key, this.active = true, required this.onBack, required this.child});

  final bool active;
  final VoidCallback onBack;
  final Widget child;

  @override
  State<OnBack> createState() => _OnBackState();
}

class _OnBackState extends State<OnBack> {
  BackStack? _stack;
  VoidCallback? _off;

  bool _run() {
    widget.onBack();
    return true;
  }

  /// On the stack while active, in the order this was mounted, which is the order things open in.
  void _sync() {
    final stack = BackScope.of(context);
    final want = widget.active;
    if (_off != null && (!want || !identical(stack, _stack))) {
      _off!();
      _off = null;
    }
    _stack = stack;
    if (want && _off == null) _off = stack.onBack(_run);
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(OnBack old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _off?.call();
    _off = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
