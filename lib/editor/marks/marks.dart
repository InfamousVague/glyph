/// The marks' extensions, in the order `src/app/editor/Editor.tsx` lists them: the style looks, the smoke, the
/// effects, and a note in brackets after a mark. Hand the same list to the parser and the highlighter:
///
///     noteExtensions(formats: marks, more: <Extension>[markExtensions(marks), ...])
library;

import '../../plugins/marks.dart';
import '../state/state.dart';
import 'format_looks.dart';
import 'mark_notes.dart';
import 'text_effects.dart';
import 'wisp_format.dart';
import 'wisp_motion.dart';

export '../../plugins/marks.dart';
export 'format_looks.dart';
export 'mark_notes.dart';
export 'run_paint.dart' show MarkClock, MarkPaint, markMotion;
export 'text_effects.dart';
export 'wisp_format.dart';
export 'wisp_motion.dart';

/// The marks drawn as the web draws them. `wispTyping` is the web's prop of that name: what the person takes out
/// smokes away (`wisp_motion.dart`).
Extension markExtensions(Iterable<GlyphFormat> formats, {bool wispTyping = false}) => Extension.list(<Extension>[
  formatLooks(formats),
  wispFormat(formats),
  textEffects(formats),
  markNotes(formats),
  if (wispTyping) wispDepartures(),
]);
