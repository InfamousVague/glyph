/// The AI's icons, from the kit's set (lucide underneath): one per phase of a run, one per kind. A port of
/// `src/app/ai/icons.ts`.
///
/// Matt chose the kit's set over the app's own drawn strokes for these, so every AI state and action reads as one
/// family with the rest of the kit. The same icon means the same thing wherever it shows: the strip, the log, a home
/// card, a chip.
///
/// What differs: no widgets here, so an icon is its NAME, the lucide name the app's own set carries
/// (lib/art/lucide.g.dart: `Lucide.wandSparkles` is `LucideIcon('wand-sparkles', …)`), and whoever draws one finds it
/// by that. The web's component for each is named beside it.
library;

import 'kinds.dart';
import 'runs.dart';

/// The icon of each phase of a run (`PHASE_ICONS`).
const Map<RunPhase, String> phaseIcons = {
  RunPhase.queued: 'hourglass', // Hourglass
  RunPhase.loading: 'loader-circle', // LoaderCircle
  RunPhase.prefill: 'book-open-text', // BookOpenText
  RunPhase.generating: 'pen-line', // PenLine
  RunPhase.done: 'circle-check', // CircleCheck
  RunPhase.stopped: 'circle-stop', // CircleStop
  RunPhase.failed: 'triangle-alert', // TriangleAlert
};

/// The icon of each kind of run (`KIND_ICONS`).
const Map<RunKind, String> kindIcons = {
  RunKind.format: 'wand-sparkles', // WandSparkles
  RunKind.summarize: 'scan-text', // ScanText
  RunKind.enhance: 'sparkles', // Sparkles
  RunKind.fix: 'spell-check', // SpellCheck
  RunKind.shape: 'list-checks', // ListChecks
  RunKind.continueWriting: 'pen-line', // PenLine
  RunKind.ask: 'bot', // Bot
  RunKind.review: 'brain', // Brain
  RunKind.fill: 'square-dashed', // SquareDashed
};

/// The phases whose icon turns: the model is at work and nothing else on the screen is moving (`spins`).
bool spins(RunPhase phase) => phase == RunPhase.loading;
