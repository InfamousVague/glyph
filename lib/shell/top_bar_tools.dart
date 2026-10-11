import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Where a screen's own controls go when the app's top bar is there to hold them: the web app's
/// core/topBarTools.ts. A note's tools - the view toggle, the bookmark, the mic, the three dots - belong to the
/// note's screen and hold the editor's state, so the bar offers a slot and the screen keeps owning its buttons.
///
/// One slot and one tail, because there is one bar: [tools] is drawn in the bar's slot, pushed to its far end, and
/// [tail] is the bar's last place, after Organizations and the bell, for the one control that ends the row (a
/// screen's More).
///
/// Differs from the web: the bar said where its slot was and React put the screen's buttons into the bar's DOM with
/// a portal, so they stayed the screen's own elements. A widget cannot be drawn in two places, so the screen hands
/// the widgets over ([TopBarFill]) and the bar builds them: they live in the bar's part of the tree, and reach the
/// screen's state through whatever they close over or listen to. A change of widgets reaches the bar a frame after
/// the screen builds it, so what changes often should listen for itself rather than be handed over anew.
class TopBarTools extends ChangeNotifier {
  Object? _owner;
  Widget? _tools;
  Widget? _tail;

  /// The bar is gone. A screen under it goes in the same frame and gives its controls back a frame later
  /// ([_TopBarFillState._later]), to a bar that has nobody left to tell: without this the notifier threw in that
  /// frame's callbacks, which under a test is the NEXT test's first frame.
  bool _gone = false;

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }

  /// The screen's own controls, or null where no screen has any.
  Widget? get tools => _tools;

  /// The screen's last control, its More.
  Widget? get tail => _tail;

  void _set(Object owner, Widget? tools, Widget? tail) {
    if (_gone) return;
    if (identical(_owner, owner) && identical(_tools, tools) && identical(_tail, tail)) return;
    _owner = owner;
    _tools = tools;
    _tail = tail;
    notifyListeners();
  }

  void _clear(Object owner) {
    if (_gone || !identical(_owner, owner)) return;
    _owner = null;
    _tools = null;
    _tail = null;
    notifyListeners();
  }

  /// The bar's slot above [context], or null where there is no bar: a screen then draws its controls where it
  /// always did (`useTopBarTools`).
  static TopBarTools? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TopBarToolsScope>()?.notifier;
}

/// The bar's slot, offered to the screens under it.
class TopBarToolsScope extends InheritedNotifier<TopBarTools> {
  const TopBarToolsScope({super.key, required TopBarTools super.notifier, required super.child});
}

/// A screen putting its own controls in the top bar while it is on screen (`useTopBarTools`, `useTopBarTail`): [tools]
/// in the slot, [tail] at the row's end. Taken out again as the screen goes.
class TopBarFill extends StatefulWidget {
  const TopBarFill({super.key, this.tools, this.tail, required this.child});

  final Widget? tools;
  final Widget? tail;
  final Widget child;

  @override
  State<TopBarFill> createState() => _TopBarFillState();
}

class _TopBarFillState extends State<TopBarFill> {
  TopBarTools? _bar;

  /// After the frame: the bar may not be told to build while the tree is building.
  void _later(VoidCallback run) {
    SchedulerBinding.instance.addPostFrameCallback((_) => run());
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bar = TopBarTools.maybeOf(context);
    final was = _bar;
    if (!identical(bar, was)) {
      if (was != null) _later(() => was._clear(this));
      _bar = bar;
    }
    _hand();
  }

  @override
  void didUpdateWidget(TopBarFill old) {
    super.didUpdateWidget(old);
    if (!identical(old.tools, widget.tools) || !identical(old.tail, widget.tail)) _hand();
  }

  void _hand() {
    final bar = _bar;
    if (bar == null) return;
    _later(() {
      if (mounted) bar._set(this, widget.tools, widget.tail);
    });
  }

  @override
  void dispose() {
    final bar = _bar;
    if (bar != null) _later(() => bar._clear(this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
