/// Which lane a blank is in, decided by code before any model is asked (docs/DESIGN.md §145, 2.1): worked out by the
/// app, recognised and not finished by it, live (looked up on the web once pressed, or paused, or refused), or waiting
/// for the model. A port of `src/app/ai/fills/lane.ts`. The editor draws by it and the queue runs by it, so the two
/// never disagree. Pure.
///
/// What differs: a [Lane] is a sealed class, one subclass a lane, with the web's word as its [Lane.lane]; [Lookups]
/// and [LiveCan] are enums whose [Lookups.id] and [LiveCan.id] are the web's words, since `local-only` is not a name
/// Dart allows.
library;

import '../../core/blanks.dart';
import '../../core/fill_facts.dart';
import '../../core/fill_live.dart';
import 'shape.dart';
import 'web.dart';

/// Whether this device may look a live blank up: on, held by Local only, or switched off in Settings (`Lookups`).
enum Lookups {
  on('on'),
  localOnly('local-only'),
  off('off');

  const Lookups(this.id);

  /// The page's word for it.
  final String id;
}

/// What a press may do with a live blank: `look`, a press looks it up; `local-only`, Local only keeps it paused;
/// `off`, Look up blanks online is off; `none`, no public source answers it.
enum LiveCan {
  look('look'),
  localOnly('local-only'),
  off('off'),
  none('none');

  const LiveCan(this.id);

  /// The page's word for it.
  final String id;
}

/// A blank's lane (`Lane`).
sealed class Lane {
  const Lane();

  /// The page's word for the lane: `worked`, `cannot`, `live` or `model`.
  String get lane;
}

/// Worked out by the app.
final class WorkedLane extends Lane {
  const WorkedLane({required this.worked});

  final WorkedAnswer worked;

  @override
  String get lane => 'worked';

  @override
  bool operator ==(Object other) => other is WorkedLane && other.worked == worked;

  @override
  int get hashCode => Object.hash('worked', worked);

  @override
  String toString() => 'WorkedLane($worked)';
}

/// Recognised by the app, and not finished by it.
final class CannotLane extends Lane {
  const CannotLane({required this.cannot});

  final CannotWork cannot;

  @override
  String get lane => 'cannot';

  @override
  bool operator ==(Object other) => other is CannotLane && other.cannot == cannot;

  @override
  int get hashCode => Object.hash('cannot', cannot);

  @override
  String toString() => 'CannotLane($cannot)';
}

/// Live: looked up on the web once pressed, or paused, or refused.
final class LiveLane extends Lane {
  const LiveLane({required this.live, required this.plan, required this.can, required this.info});

  final Live live;
  final LookupPlan plan;

  /// `look`, a press looks it up; `local-only`, Local only keeps it paused; `off`, Look up blanks online is off;
  /// `none`, no public source answers it.
  final LiveCan can;
  final ShapeInfo info;

  @override
  String get lane => 'live';

  @override
  bool operator ==(Object other) => other is LiveLane && other.live == live && other.plan == plan && other.can == can && other.info == info;

  @override
  int get hashCode => Object.hash('live', live, plan, can, info);

  @override
  String toString() => 'LiveLane($live, $plan, ${can.id}, $info)';
}

/// Waiting for the model.
final class ModelLane extends Lane {
  const ModelLane({required this.info});

  final ShapeInfo info;

  @override
  String get lane => 'model';

  @override
  bool operator ==(Object other) => other is ModelLane && other.info == info;

  @override
  int get hashCode => Object.hash('model', info);

  @override
  String toString() => 'ModelLane($info)';
}

/// What a lane is decided with (`LaneOptions`).
class LaneOptions {
  const LaneOptions({required this.clock, required this.learntUntil, required this.lookups});

  final FactClock clock;

  /// The chosen model's horizon (ai/backend.dart `learntUntil`).
  final int learntUntil;
  final Lookups lookups;
}

/// A blank's lane.
Lane laneOf(Blank blank, String text, LaneOptions options) {
  // A translation is read first: `- Is the museum open on Sundays? {?in German}` asks for German words, not the hours,
  // and `- How many days until Christmas? {?in French}` for French ones, not the count.
  final shaped = shapeOf(blank, text);
  if (shaped.shape == Shape.language) return ModelLane(info: shaped);
  final worked = workOut(blank, text, options.clock);
  if (worked is WorkedAnswer) return WorkedLane(worked: worked);
  if (worked is CannotWork) return CannotLane(cannot: worked);
  final asking = askingWords(blank, text);
  final live = screen(asking, options.learntUntil);
  final info = shaped;
  if (live != null) {
    final plan = lookupPlan(live.kind, asking, options.clock.now);
    final can = plan.kind == LookupKind.none
        ? LiveCan.none
        : switch (options.lookups) {
            Lookups.on => LiveCan.look,
            Lookups.localOnly => LiveCan.localOnly,
            Lookups.off => LiveCan.off,
          };
    return LiveLane(live: live, plan: plan, can: can, info: info);
  }
  return ModelLane(info: info);
}

/// Whether a press of Fill takes the blank: the model's, and a live one this device may look up.
bool fillable(Lane lane) => lane is ModelLane || (lane is LiveLane && lane.can == LiveCan.look);
