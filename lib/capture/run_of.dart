/// The run a spoken phrasing means ("fix the spelling", "summarise it"), for the live reader to queue one said
/// mid-take for after Done (`live_route.dart` `notRoute`).
///
/// The rules are `lib/ai/instruction.dart`'s (`runOf`, a port of `src/app/ai/instruction.ts`); this file only says
/// the kind as the recorder keeps it: the web's own word (`RunKind`, `src/app/ai/kinds.ts`: 'fix', 'summarize',
/// 'format', 'enhance', 'continue', 'shape') as a `String`, which is `RunKind.id`. When the recorder carries the
/// enum itself, this file goes and `live_route.dart` imports that one.
library;

import '../ai/instruction.dart' as ai;

/// The run a phrasing means, as the web's word for it, or null. With [whole], the run and nothing more
/// (lib/ai/instruction.dart `runOf`).
String? runOf(String words, {bool whole = false}) => ai.runOf(words, whole: whole)?.id;
