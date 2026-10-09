/// One icon a step, from the kit's set (lucide, lib/art/lucide.g.dart), the same family as the strip's
/// (ai/icons.dart): drawn small in the step list and large on the phone's screen (scene/hot_phone.dart), so the mark
/// on the phone and the mark in the list are one thing. A port of `src/app/scene/icons.ts`.
///
/// What differs: nothing. `STEP_ICONS` is [stepIcons].
library;

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import 'steps.dart';

/// `STEP_ICONS`.
const Map<StepId, LucideIcon> stepIcons = <StepId, LucideIcon>{
  StepId.listen: Lucide.ear,
  StepId.load: Lucide.loaderCircle,
  StepId.read: Lucide.bookOpenText,
  StepId.think: Lucide.brain,
  StepId.write: Lucide.penLine,
  StepId.done: Lucide.circleCheck,
};
