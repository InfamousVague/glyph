/// A part of the app that is built again only when what it shows changed.
///
/// The root was one builder over everything it listens to (the notes, the workspaces, the trash, the preferences,
/// the account, voice, presence): a change to any of them built the whole app again, the home page or the open
/// note under Settings, every sheet that was shut. Measured on a library of 354 notes (tool/perf.sh, 2026-10-10)
/// that was a frame of 60 ms on the home page and 230 to 310 ms with Settings open, more than once a second, for a
/// runner that had nothing to say.
///
/// Here each part says what it reads ([Selected.select]: a record of the values and the objects its builder draws
/// from) and is built again when that record is another, and at no other time: the widget it built last is handed
/// back as the object it was, which is where the framework stops walking. What the root is told by, it tells all of
/// them by ([RootTick]); each asks its own question, which is a handful of comparisons.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../perf/frame_log.dart';

/// Something the root holds changed. It says nothing of what: every [Selected] part asks whether what it reads did.
class RootTick extends ChangeNotifier {
  bool _gone = false;

  /// Tells every part to look.
  void tell() {
    if (_gone) return;
    if (ghostPerf) Perf.count('root.tick');
    notifyListeners();
  }

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }
}

/// Builds [builder] with what [select] answers, and again only when it answers another value: when [listenable]
/// says something changed, when whatever holds this part is built again, and when something inherited that the
/// builder leans on (the window's size, the tokens) is another.
///
/// [select] is asked often and must cost nearly nothing: a record of fields, each a number, a word, or an object
/// compared by which object it is (a list the library keeps while nothing in it changed, a note). Two records are
/// the same when every field is.
class Selected<T> extends StatefulWidget {
  const Selected({super.key, required this.listenable, required this.select, required this.builder, this.name});

  final Listenable listenable;
  final T Function() select;
  final Widget Function(BuildContext context, T value) builder;

  /// What a measured build counts this part's builds as (`built.<name>`, lib/perf/frame_log.dart).
  final String? name;

  @override
  State<Selected<T>> createState() => _SelectedState<T>();
}

class _SelectedState<T> extends State<Selected<T>> {
  late T _drew;
  Widget? _child;

  /// Something inherited changed since the child was built: it is built again whatever is selected.
  bool _stale = false;
  bool _waiting = false;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_heard);
  }

  @override
  void didUpdateWidget(Selected<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.listenable, widget.listenable)) {
      oldWidget.listenable.removeListener(_heard);
      widget.listenable.addListener(_heard);
    }
  }

  /// What the builder read through its context is another: it is asked again whatever [Selected.select] says.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stale = true;
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_heard);
    super.dispose();
  }

  void _heard() {
    // Not yet built, or about to be built again whatever is asked: nothing to mark.
    if (!mounted || _child == null || _stale) return;
    if (widget.select() == _drew) return;
    // Told while a frame is being laid out or painted (a desk let go as the tree is taken down says its note was
    // left): drawn after that frame, as the root's own listeners waited.
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) return setState(() {});
    if (_waiting) return;
    _waiting = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _waiting = false;
      if (mounted && _child != null && !_stale && widget.select() != _drew) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final had = _child;
    final now = widget.select();
    if (had != null && !_stale && now == _drew) return had;
    _stale = false;
    _drew = now;
    if (!ghostPerf || widget.name == null) return _child = widget.builder(context, now);
    // How many times each part was built in a stretch, and how long making its widget took (not building what is
    // under it, which is the frame's).
    final began = Perf.now();
    final built = _child = widget.builder(context, now);
    Perf.add('built.${widget.name}', began);
    return built;
  }
}
