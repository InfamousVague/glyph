/// The app from its first frame: the launch screen at once, and the app itself under it as soon as what it is made
/// over has opened.
///
/// The app's start waited for the library's core before it drew anything: the core's own isolate started, its
/// library loaded and its folder opened, about 0.3 s on a phone during which the window was the system's blank
/// one, though the first thing the app draws is a launch screen whose first line is "Opening your notes". Here
/// that screen is up from the first frame, over nothing, and says so while the core opens; the root is put under
/// it the moment it can be made, and the screen goes on from where it was: one screen, begun once, with the timers
/// and the ghost it began with (lib/launch/launch_screen.dart is not changed, and neither is what it waits for:
/// the notes read, the update check answered, and long enough to be read).
///
/// What is the root's to say, it says through a [LaunchSeat]: whether the notes are read and how many there are,
/// where the account's sync stands, and whether a meeting is being recorded. Until there is a root the notes are
/// being opened, there are none to count, and nothing syncs or records, which is what the root itself says in its
/// own first frame.
///
/// A root that is given no seat draws its own launch screen, as it always has: a test's, a gallery's.
library;

import 'package:flutter/widgets.dart';

import '../core/updates.dart';
import '../launch/launch_screen.dart';
import 'selected.dart';
import 'update_wiring.dart';

/// What the root says of itself to the launch screen over it.
typedef LaunchFacts = ({bool loading, int notes, SyncPhase sync, bool Function() recording});

/// Where the root says it ([sit]), for whoever draws the launch screen over the root to read ([facts]) and be told
/// by.
class LaunchSeat extends ChangeNotifier {
  LaunchFacts Function()? _read;
  Listenable? _by;

  /// What the root says now; null while there is no root.
  LaunchFacts? get facts => _read?.call();

  /// The root is up: [read] is asked whenever [told] says something of the root's changed.
  void sit(LaunchFacts Function() read, Listenable told) {
    _by?.removeListener(notifyListeners);
    _read = read;
    _by = told..addListener(notifyListeners);
  }

  /// The root that sat with [read] is gone. A root started over sits before the one before it has gone, so only the
  /// one sitting leaves the seat empty.
  void rise(LaunchFacts Function() read) {
    if (_read != read) return;
    _by?.removeListener(notifyListeners);
    _by = null;
    _read = null;
  }

  @override
  void dispose() {
    _by?.removeListener(notifyListeners);
    super.dispose();
  }
}

/// The launch screen from the first frame, and under it what [builder] makes of [opened] once it has: the app's
/// root, handed the [LaunchSeat] it says its facts through and the way to start over (Developer's resets,
/// lib/core/reset.dart: what `window.location.reload()` was to the page; the launch screen is up again for the
/// root made anew, as it is for a page loaded again).
///
/// [updates] is the app's own, made before anything opened, since the launch screen asks it to look as it comes up
/// and has its line from its first frame only where the build looks at all.
class GhostOpening<T> extends StatefulWidget {
  const GhostOpening({super.key, required this.opened, this.updates, required this.builder, this.onStep});

  /// What the app is made over: it must complete, with what there is where something would not open.
  final Future<T> opened;
  final Updates? updates;
  final Widget Function(BuildContext context, T opened, LaunchSeat seat, VoidCallback restart) builder;

  /// Told as the start passes each of its moments here, for a build that times its start (lib/perf): `screen` as
  /// the launch screen is first made, `root` as the app is put under it.
  final void Function(String step)? onStep;

  @override
  State<GhostOpening<T>> createState() => _GhostOpeningState<T>();
}

class _GhostOpeningState<T> extends State<GhostOpening<T>> {
  final LaunchSeat _seat = LaunchSeat();
  late final Listenable _told = Listenable.merge([_seat, widget.updates]);
  ({T it})? _opened;
  bool _launching = true;
  int _run = 0;

  /// The app as it was made for this run: made once, so the launch screen going builds nothing of it again.
  Widget? _app;

  @override
  void initState() {
    super.initState();
    widget.onStep?.call('screen');
    widget.opened.then((opened) {
      if (!mounted) return;
      widget.onStep?.call('root');
      setState(() => _opened = (it: opened));
    });
  }

  @override
  void dispose() {
    _seat.dispose();
    super.dispose();
  }

  void _restart() => setState(() {
        _run += 1;
        _app = null;
        _launching = true;
      });

  /// What the launch screen draws from, each a value: it is built again when one is another.
  ({bool loading, int notes, bool checking, String? apk, String? error, SyncPhase sync}) _facts() {
    final said = _seat.facts;
    final updates = widget.updates;
    final apk = updates?.apk;
    return (
      loading: said?.loading ?? true,
      notes: said?.notes ?? 0,
      checking: updates?.checking ?? false,
      apk: apk is ApkPhaseAvailable ? apk.info.version : null,
      error: updates?.lastError,
      sync: said?.sync ?? SyncPhase.off,
    );
  }

  bool _recording() => _seat.facts?.recording() ?? false;

  @override
  Widget build(BuildContext context) {
    final opened = _opened;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The app, made anew each time it is started over; nothing, until what it is made over has opened.
        if (opened == null) const SizedBox.shrink() else _app ??= KeyedSubtree(key: ValueKey<int>(_run), child: widget.builder(context, opened.it, _seat, _restart)),
        if (_launching)
          KeyedSubtree(
            key: ValueKey<String>('launch:$_run'),
            child: Selected(
              listenable: _told,
              select: _facts,
              builder: (context, facts) => LaunchScreen(
                loading: facts.loading,
                notes: facts.notes,
                updates: launchUpdatesOf(widget.updates),
                sync: facts.sync,
                recording: _recording,
                onDone: () => setState(() => _launching = false),
              ),
            ),
          ),
      ],
    );
  }
}
