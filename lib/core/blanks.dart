/// Blanks the AI fills, under the web's own name: `src/app/core/blanks.ts`.
///
/// The whole of that file reads text and is ported in `blanks_syntax.dart`, which stage 4's editor needed before
/// stage 8 had a model to ask. This is that library by the name the AI's modules import (ai/fills/**, core/fill_facts,
/// core/fill_live), so a line of the web's `import … from '../../core/blanks.ts'` ports as written. Nothing is added
/// here: a rule about a blank's text belongs in blanks_syntax.dart, once.
library;

export 'blanks_syntax.dart';
