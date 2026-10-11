/// What a build made to be measured (`--dart-define=GHOST_PERF=true`, lib/perf) says of the editor beside its frames:
/// where each update's time went, by the field, the computed facet and the plugin it went to, and how long the
/// view's own parts took (taking the new state, reading the decorations, finding what changed, telling the lines).
/// Read with each stretch of the walk as `editor.<name>=<times>(<ms>)` (lib/perf/frame_log.dart `Perf`).
///
/// The profile of a walk says the same in shares of the samples it caught, a few hundred to a stretch; this is the
/// clock itself, every time. A letter's transaction is done before its frame begins, so no frame's build has it:
/// `editor.update.doc` is what a letter cost before anything was drawn.
///
/// Each time is its own alone: what one field's update spent inside another's (a field asked for while a field is
/// worked out) is taken off the outer one. Every call site asks [ghostPerf] first, a constant, so a build that
/// does not measure has none of this.
library;

import '../../perf/frame_log.dart';
import '../state/state.dart' show StateProbe;

abstract final class Measured {
  static final List<int> _inside = <int>[];
  static bool _installed = false;

  /// Hears the state's own fields and computed facets too. Asked twice, listens once.
  static void install() {
    if (_installed || !ghostPerf) return;
    _installed = true;
    StateProbe.enter = enter;
    StateProbe.leave = leave;
  }

  /// Something begins: hand what this answers to [leave].
  static int enter() {
    _inside.add(0);
    return Perf.now();
  }

  /// It ended. Its own time, what began and ended inside it left out, is added to `editor.<name>`.
  static void leave(String name, int began) {
    final whole = Perf.now() - began;
    final inside = _inside.removeLast();
    // The name as the report has it, made once for each: a hundred of these end in every update, and a name made
    // for each was the measuring's own weight on what it measured.
    Perf.add(_names[name] ??= 'editor.$name', Perf.now() - (whole - inside));
    if (_inside.isNotEmpty) _inside[_inside.length - 1] += whole;
  }

  static final Map<String, String> _names = <String, String>{};
}
