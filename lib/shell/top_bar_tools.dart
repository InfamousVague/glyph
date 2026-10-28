import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../note/note_tools.dart' show NoteToolsModel;

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
///
/// **The tools as words too** ([model]): the header toolbar's other versions (lib/shell/header_toolbar.dart; Matt,
/// 2026-10-28: "right now it's just a huge list of icons and is quite hard to work with") do not draw the note's
/// widgets as they come but sort the note's actions into pills, tiles and menus of their own, so a screen that has
/// its tools as a model hands that over beside the widgets. Version 1, today's bar, draws [tools] and [tail] as
/// ever; a screen with no model is drawn from its widgets in every version.
class TopBarTools extends ChangeNotifier {
  Object? _owner;
  Widget? _tools;
  Widget? _tail;
  ValueListenable<NoteToolsModel>? _model;

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

  /// What the screen's [tools] are, as the actions they draw: the view switch, the spare actions and More. Null for
  /// a screen that handed widgets alone.
  ValueListenable<NoteToolsModel>? get model => _model;

  void _set(Object owner, Widget? tools, Widget? tail, ValueListenable<NoteToolsModel>? model) {
    if (_gone) return;
    if (identical(_owner, owner) && identical(_tools, tools) && identical(_tail, tail) && identical(_model, model)) return;
    _owner = owner;
    _tools = tools;
    _tail = tail;
    _model = model;
    notifyListeners();
  }

  void _clear(Object owner) {
    if (_gone || !identical(_owner, owner)) return;
    _owner = null;
    _tools = null;
    _tail = null;
    _model = null;
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
/// in the slot, [tail] at the row's end, and [model], what they are, for the bar's other versions. Taken out again as
/// the screen goes.
class TopBarFill extends StatefulWidget {
  const TopBarFill({super.key, this.tools, this.tail, this.model, required this.child});

  final Widget? tools;
  final Widget? tail;
  final ValueListenable<NoteToolsModel>? model;
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
    if (!identical(old.tools, widget.tools) || !identical(old.tail, widget.tail) || !identical(old.model, widget.model)) _hand();
  }

  void _hand() {
    final bar = _bar;
    if (bar == null) return;
    _later(() {
      if (mounted) bar._set(this, widget.tools, widget.tail, widget.model);
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
