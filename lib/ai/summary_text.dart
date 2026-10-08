/// The summary section a note carries in its body, under the AI's path. A port of `src/app/ai/summaryText.ts`.
///
/// What differs: the module itself is lib/core/summary_text.dart, since the sync merge needed its reading half before
/// there was any AI here; this library only hands it on, so the AI's files import it where the web's did.
library;

export '../core/summary_text.dart';
